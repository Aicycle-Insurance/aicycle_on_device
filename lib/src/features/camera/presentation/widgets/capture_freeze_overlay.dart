import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/utils/screen_utils.dart';
import 'camera_bottom_bar.dart';

/// Ảnh vừa chụp được vẽ đè lên preview ("đóng băng" khung hình) một nhịp, rồi
/// co nhỏ dần về thumbnail góc dưới trái. Auto-capture xảy ra rất nhanh nên nếu
/// chỉ nháy trắng thì user không kịp nhận ra máy đã chụp ảnh nào.
///
/// Hiệu ứng chạy lại mỗi khi [tick] đổi; [photoPath] là ảnh của lượt chụp đó.
/// Ảnh lưu xuống disk theo chiều landscape (đúng chiều user đang cầm máy) nên
/// vẽ qua `RotatedBox` giống thumbnail để khớp hệt preview đang thấy.
class CaptureFreezeOverlay extends StatefulWidget {
  const CaptureFreezeOverlay({
    super.key,
    required this.tick,
    required this.photoPath,
    required this.startedAt,
    required this.holdDuration,
    required this.shrinkDuration,
    required this.topBarHeight,
    required this.bottomBarHeight,
  });

  final int tick;
  final String? photoPath;

  /// Mốc controller bật lượt hiệu ứng hiện tại — dùng để chạy tiếp từ đúng thời
  /// điểm đã trôi nếu widget bị dựng lại giữa lượt (cây widget đổi cấu trúc).
  final DateTime? startedAt;

  /// Giữ nguyên ảnh full-screen (dừng hình) trước khi bắt đầu co nhỏ.
  final Duration holdDuration;

  /// Thời gian ảnh co nhỏ + bay về thumbnail.
  final Duration shrinkDuration;

  /// Vùng preview user thực sự thấy nằm giữa top bar và bottom bar — ảnh đóng
  /// băng phủ đúng vùng này (ảnh đã được native crop về đúng khung đó).
  final double topBarHeight;
  final double bottomBarHeight;

  @override
  State<CaptureFreezeOverlay> createState() => _CaptureFreezeOverlayState();
}

class _CaptureFreezeOverlayState extends State<CaptureFreezeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _shrink;

  /// Ảnh của lượt chụp đang chạy hiệu ứng. Giữ local để animation chạy hết dù
  /// controller đã đổi trạng thái; null = không có gì để vẽ.
  String? _path;

  @override
  void initState() {
    super.initState();
    final total = widget.holdDuration + widget.shrinkDuration;
    _controller = AnimationController(vsync: this, duration: total);
    // Pha 1 (dừng hình) giữ nguyên rect đầu; pha 2 mới co về thumbnail.
    final holdFraction =
        widget.holdDuration.inMilliseconds / total.inMilliseconds;
    _shrink = CurvedAnimation(
      parent: _controller,
      curve: Interval(holdFraction, 1, curve: Curves.easeInOutCubic),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        // Ảnh đã trùng khít thumbnail thật ở bottom bar → ẩn overlay là liền mạch.
        setState(() => _showPhoto(null));
      }
    });
    // Widget có thể được dựng lại ngay giữa một lượt hiệu ứng (cây widget đổi
    // cấu trúc → element bị tạo lại, [didUpdateWidget] không được gọi). Chạy
    // tiếp từ đúng thời điểm đã trôi thay vì mất hẳn hiệu ứng.
    final startedAt = widget.startedAt;
    if (startedAt != null && widget.photoPath != null) {
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < total) {
        _showPhoto(widget.photoPath);
        _controller.forward(
          from: elapsed.inMicroseconds / total.inMicroseconds,
        );
      }
    }
  }

  @override
  void didUpdateWidget(CaptureFreezeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tick != oldWidget.tick && widget.photoPath != null) {
      setState(() => _showPhoto(widget.photoPath));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _showPhoto(null);
    _controller.dispose();
    super.dispose();
  }

  /// Đổi ảnh đang vẽ và **đẩy ảnh cũ ra khỏi image cache của Flutter**.
  ///
  /// Ảnh chụp là JPEG cỡ FullHD; decode ra bitmap ~6–8 MB. Mỗi tấm chỉ được
  /// hiển thị đúng một lượt (~1.15 s) rồi không bao giờ dùng lại — thanh dưới
  /// đã có thumbnail 160px riêng. Nếu không evict, chúng nằm lại trong
  /// `PaintingBinding.imageCache` tới trần 100 MB; cộng với 3 model GPU và
  /// buffer camera là nguyên nhân OOM sau phiên chụp dài.
  ///
  /// Không dùng `cacheWidth`: ở pha "dừng hình" ảnh phủ gần kín màn hình nên
  /// vẫn cần gần đúng độ phân giải gốc — giảm kích thước decode sẽ làm mờ mà
  /// tiết kiệm không đáng kể. Vấn đề là TÍCH LUỸ, và evict giải quyết đúng nó.
  void _showPhoto(String? path) {
    final previous = _path;
    if (previous != null && previous != path) {
      unawaited(FileImage(File(previous)).evict());
    }
    _path = path;
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final begin = Rect.fromLTRB(
            0,
            widget.topBarHeight,
            constraints.maxWidth,
            constraints.maxHeight - widget.bottomBarHeight,
          );
          final thumbSize = CameraBottomBar.thumbnailSize.w;
          final end = Rect.fromLTWH(
            CameraBottomBar.thumbnailMargin.w,
            constraints.maxHeight - widget.bottomBarHeight / 2 - thumbSize / 2,
            thumbSize,
            thumbSize,
          );
          final image = RotatedBox(
            quarterTurns: 1,
            child: Image.file(File(path), fit: BoxFit.cover),
          );
          return AnimatedBuilder(
            animation: _shrink,
            builder: (context, _) {
              final t = _shrink.value;
              final radius =
                  BorderRadius.circular(CameraBottomBar.thumbnailRadius.r * t);
              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: Rect.lerp(begin, end, t)!,
                    child: Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(borderRadius: radius),
                      // Viền trắng hiện dần để khi hạ cánh khớp thumbnail thật.
                      foregroundDecoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: AppColors.white.withValues(alpha: t),
                          width: CameraBottomBar.thumbnailBorderWidth,
                        ),
                      ),
                      child: image,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
