// DEV ONLY — nút chọn ảnh từ thư viện để test upload, không cần chụp camera.
// Chỉ hiện khi kDebugMode. Xóa file này (và hook ở CameraScreen) trước release.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/utils/screen_utils.dart';
import '../controller/camera_controller.dart';

/// Overlay góc trên phải màn camera: bấm → chọn ảnh gallery → inject vào
/// [CameraController] như ảnh vừa chụp.
class DevGalleryPickButton extends StatelessWidget {
  const DevGalleryPickButton({
    super.key,
    required this.controller,
  });

  final CameraController controller;

  static final _picker = ImagePicker();

  Future<void> _pickFromGallery(BuildContext context) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final segment = controller.activeSegmentIndex ?? 0;
    controller.addDevPhoto(segment: segment, bytes: bytes);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('DEV: đã thêm ảnh vào góc $segment'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return Positioned(
      right: 12.w,
      top: 88.h,
      child: Material(
        color: AppColors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10.r),
        child: InkWell(
          onTap: () => _pickFromGallery(context),
          borderRadius: BorderRadius.circular(10.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined,
                    color: AppColors.white, size: 18.r),
                6.horizontalSpace,
                Text(
                  'DEV',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
