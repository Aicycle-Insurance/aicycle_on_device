import 'package:flutter/material.dart';

import '../../../../../aicycle_on_device.dart';
import '../../../../config/config_holder.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';
import '../../domain/entity/inspection_result.dart';

/// Thẻ kết quả của một bộ phận xe: tiêu đề + ảnh đã vẽ box nhận diện tổn thất,
/// kèm hàng thumbnail để chuyển ảnh và nút thêm ảnh.
class ResultCard extends StatefulWidget {
  const ResultCard({super.key, required this.item, this.onAddPhoto});

  final VehiclePart item;

  /// Bấm nút "thêm ảnh" (ô nét đứt đầu hàng). Null thì nút vẫn hiển thị.
  final VoidCallback? onAddPhoto;

  @override
  State<ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<ResultCard> {
  int _selected = 0;

  List<ResultImage> get _images => widget.item.images;

  /// Ảnh đã vẽ box; fallback về ảnh gốc nếu chưa có bản vẽ.
  String? _urlOf(ResultImage img) =>
      AICycleConfigHolder.config.generalConfig.organization == AiCycleOrg.vbi
          ? img.imageDrawUrl ?? img.imageUrl
          : img.imageUrl;

  String get _title => widget.item.vehiclePartName ?? '';

  @override
  Widget build(BuildContext context) {
    final selectedUrl = _images.isEmpty
        ? null
        : _urlOf(_images[_selected.clamp(0, _images.length - 1)]);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tiêu đề bộ phận ────────────────────────────────────────────
          Text(
            _title,
            style: AppTextStyles.base.s18.w700().copyWith(
                  color: AppColors.inkA500,
                ),
          ),
          12.verticalSpace,
          Divider(height: 1, thickness: 1, color: AppColors.divider),
          12.verticalSpace,

          // ── Ảnh chính (đã vẽ box) ──────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: _NetworkImage(
              url: selectedUrl,
              height: 195.h,
              fit: BoxFit.cover,
            ),
          ),
          16.verticalSpace,

          // ── Hàng thumbnail + nút thêm ảnh ──────────────────────────────
          SizedBox(
            height: 72.r,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length + 1,
              separatorBuilder: (_, __) => 16.horizontalSpace,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _AddPhotoButton(onTap: widget.onAddPhoto);
                }
                final imgIndex = index - 1;
                return _Thumbnail(
                  url: _urlOf(_images[imgIndex]),
                  selected: imgIndex == _selected,
                  onTap: () => setState(() => _selected = imgIndex),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Ô nét đứt với icon camera — thêm/chụp lại ảnh.
class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: AppColors.inkA300,
          radius: 8.r,
        ),
        child: SizedBox(
          width: 68.r,
          height: 68.r,
          child: Icon(
            Icons.photo_camera_outlined,
            size: 32.r,
            color: AppColors.inkA500,
          ),
        ),
      ),
    );
  }
}

/// Thumbnail ảnh; viền xanh khi đang được chọn.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.url,
    required this.selected,
    required this.onTap,
  });

  final String? url;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68.r,
        height: 68.r,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: selected ? AppColors.primaryA500 : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6.r),
          child: _NetworkImage(url: url, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// Ảnh network với placeholder lúc tải và lúc lỗi.
class _NetworkImage extends StatelessWidget {
  const _NetworkImage({required this.url, this.height, this.fit});

  final String? url;
  final double? height;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return _placeholder();
    return Image.network(
      url!,
      width: double.infinity,
      height: height,
      fit: fit ?? BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder(
          child: Center(
            child: SizedBox(
              width: 20.r,
              height: 20.r,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryA300,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, _, __) => _placeholder(
        child: Icon(
          Icons.broken_image_outlined,
          size: 24.r,
          color: AppColors.inkA300,
        ),
      ),
    );
  }

  Widget _placeholder({Widget? child}) {
    return Container(
      width: double.infinity,
      height: height,
      color: AppColors.placeholder,
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Vẽ viền nét đứt bo góc cho nút thêm ảnh.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double dashWidth = 4;
  static const double dashGap = 4;
  static const double strokeWidth = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
