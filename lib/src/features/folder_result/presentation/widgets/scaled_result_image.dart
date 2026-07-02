import 'package:flutter/material.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/utils/image_fit_utils.dart';
import '../../../../core/utils/screen_utils.dart';
import '../../domain/entity/inspection_result.dart';

/// Opacity cố định cho mask overlay bộ phận xe.
const double _partMaskOpacity = 0.3;

/// Ảnh kết quả: contain (không méo) + pinch zoom qua [InteractiveViewer].
///
/// Ảnh và mask (sau này) nằm trong cùng [Stack] bên trong viewer — zoom
/// transform toàn layer, không cần tính lại mask.
class ScaledResultImage extends StatefulWidget {
  const ScaledResultImage({
    super.key,
    required this.image,
    this.maxScale = 3.5,
  });

  final ResultImage image;
  final double maxScale;

  @override
  State<ScaledResultImage> createState() => _ScaledResultImageState();
}

class _ScaledResultImageState extends State<ScaledResultImage> {
  Size? _logicalSize;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  @override
  void initState() {
    super.initState();
    _resolveLogicalSize();
  }

  @override
  void didUpdateWidget(covariant ScaledResultImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.imageUrl != widget.image.imageUrl ||
        oldWidget.image.resolution != widget.image.resolution) {
      _clearImageStream();
      _logicalSize = null;
      _resolveLogicalSize();
    }
  }

  @override
  void dispose() {
    _clearImageStream();
    super.dispose();
  }

  void _resolveLogicalSize() {
    final fromBe = logicalSizeFromResolution(widget.image.resolution);
    if (fromBe != null) {
      setState(() => _logicalSize = fromBe);
      return;
    }

    final url = widget.image.imageUrl;
    if (url == null || url.isEmpty) return;

    final provider = NetworkImage(url);
    _imageStream = provider.resolve(const ImageConfiguration());
    _imageListener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _logicalSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
      });
      _clearImageStream();
    });
    _imageStream!.addListener(_imageListener!);
  }

  void _clearImageStream() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.image.imageUrl;

    return ColoredBox(
      color: AppColors.black,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: _buildViewportContent(url),
      ),
    );
  }

  Widget _buildViewportContent(String? url) {
    if (url == null || url.isEmpty) {
      return const _ImagePlaceholder(icon: Icons.broken_image_outlined);
    }

    if (_logicalSize == null) {
      return const _ImagePlaceholder(loading: true);
    }

    final logicalSize = _logicalSize!;

    return InteractiveViewer(
      maxScale: widget.maxScale,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final displaySize = fitImageContain(
            logicalSize: logicalSize,
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
          );
          if (displaySize == Size.zero) {
            return const SizedBox.shrink();
          }

          final imWidth = displaySize.width;
          final imHeight = displaySize.height;
          final masks = _buildPartMasks(
            widget.image.partsMasks,
            imWidth,
            imHeight,
          );

          return Center(
            child: SizedBox(
              width: imWidth,
              height: imHeight,
              child: Image.network(
                url,
                width: imWidth,
                height: imHeight,
                fit: BoxFit.fill,
                gaplessPlayback: true,
                // frame != null = ảnh đã decode xong và sẵn sàng vẽ frame đầu tiên.
                // Chặt hơn loadingBuilder (progress==null chỉ báo tải xong bytes).
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  final mainReady = frame != null;
                  return Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: mainReady
                            ? child
                            : const _ImagePlaceholder(loading: true),
                      ),
                      if (mainReady) ...masks,
                    ],
                  );
                },
                errorBuilder: (_, __, ___) {
                  return const _ImagePlaceholder(
                    icon: Icons.broken_image_outlined,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// Vẽ overlay mask bộ phận (isPart=true) và bounding box damage (isPart=false).
  /// Cả hai nằm trong cùng [Stack]/[InteractiveViewer] — zoom áp dụng đồng nhất.
  List<Widget> _buildPartMasks(
    List<PartMask> masks,
    double imWidth,
    double imHeight,
  ) {
    final seenUrls = <String>{};
    final widgets = <Widget>[];

    // Render part masks trước (nằm dưới) rồi damage bbox lên trên.
    final partMasks = masks.where((m) => m.isPart == true);
    final damageMasks = masks.where((m) => m.isPart != true);

    for (final mask in partMasks) {
      final url = mask.maskUrl;
      if (url == null || url.isEmpty || !seenUrls.add(url)) continue;

      final boxes = (mask.boxes != null && mask.boxes!.length >= 4)
          ? mask.boxes!
          : const [0.0, 0.0, 1.0, 1.0];
      final rect = maskDisplayRect(boxes, imWidth, imHeight);

      widgets.add(
        Positioned.fromRect(
          rect: rect,
          child: Image.network(
            url,
            key: ValueKey(url),
            fit: BoxFit.fill,
            gaplessPlayback: true,
            color: hexToColor(mask.vehicleColor).withValues(
              alpha: _partMaskOpacity,
            ),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    }

    for (final mask in damageMasks) {
      if (mask.boxes == null || mask.boxes!.length < 4) continue;
      final rect = maskDisplayRect(mask.boxes!, imWidth, imHeight);
      final color = hexToColor(mask.vehicleColor);
      if (color == Colors.transparent) continue;

      widgets.add(
        Positioned.fromRect(
          rect: rect,
          child: _DamageBoundingBox(
            label: mask.vehiclePartName ?? '',
            color: color,
          ),
        ),
      );
    }

    return widgets;
  }
}

/// Bounding box tổn thất: viền bo tròn + fill mờ + label tab góc trên-trái.
class _DamageBoundingBox extends StatelessWidget {
  const _DamageBoundingBox({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  static const double _fillOpacity = 0.14;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: _fillOpacity),
            borderRadius: BorderRadius.circular(3.r),
            border: Border.all(color: color, width: 0.7.w),
          ),
        ),
        if (label.isNotEmpty)
          Positioned(
            left: 6.w,
            top: 0,
            child: FractionalTranslation(
              translation: const Offset(0, -1),
              child: _DamageLabel(text: label, color: color),
            ),
          ),
      ],
    );
  }
}

class _DamageLabel extends StatelessWidget {
  const _DamageLabel({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.inkA500,
            fontSize: 8.sp,
            fontWeight: FontWeight.w500,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.loading = false, this.icon});

  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.black,
      child: Center(
        child: loading
            ? CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryA300,
              )
            : Icon(
                icon ?? Icons.image_not_supported_outlined,
                size: 48.r,
                color: AppColors.inkA300,
              ),
      ),
    );
  }
}
