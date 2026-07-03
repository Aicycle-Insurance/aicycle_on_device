import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';
import '../../camera/data/model/car_angle.dart';
import '../../folder_result/domain/entity/inspection_result.dart';
import 'add_damage_view.dart';
import 'controller/result_controller.dart';
import 'models/damage_annotation_draft.dart';
import 'models/mask_tap_result.dart';
import 'widgets/result_bottom_bar.dart';
import 'widgets/result_thumbnail_strip.dart';
import 'widgets/scaled_result_image.dart';

class ResultView extends StatefulWidget {
  const ResultView({
    super.key,
    required this.sessionId,
    required this.capturedPhotos,
    this.onAngleUploaded,
    this.onComplete,
    this.onAddPhoto,
  });

  final String sessionId;

  /// Reference to CameraController's capturedPhotos map.
  final Map<int, List<Uint8List>> capturedPhotos;

  /// Called after each angle is fully uploaded — camera strips those photos
  /// so a repeated "next" press won't re-upload them.
  final void Function(int angleId)? onAngleUploaded;
  final Function(dynamic result)? onComplete;

  /// Hành vi nút "Thêm ảnh tổn thất". Mặc định (null) là pop về màn trước
  /// (camera). Bootstrap có thể truyền hành vi khác (vd push lại camera khi
  /// folder đã có sẵn kết quả).
  final void Function(BuildContext context)? onAddPhoto;

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  late final ResultController _controller;

  int _selectedAngle = 0;
  int _selectedImageIndex = 0;
  bool _initialAngleSynced = false;

  /// Tap đang active — hiện nút "Thêm tổn thất" tại vị trí chạm.
  MaskTapResult? _activeTap;

  /// Các tổn thất đã xác nhận — chờ gửi BE (imageId, tọa độ, loại tổn thất).
  final List<DamageAnnotationDraft> _pendingDamageAnnotations = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller = ResultController(
      sessionId: widget.sessionId,
      capturedPhotos: widget.capturedPhotos,
      repository: sl.resultRepository,
      onAngleUploaded: widget.onAngleUploaded,
    )..start();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller.dispose();
    super.dispose();
  }

  void _selectAngle(int angle) {
    setState(() {
      _selectedAngle = angle;
      _selectedImageIndex = 0;
      _activeTap = null;
    });
  }

  void _selectImage(int index) {
    setState(() {
      _selectedImageIndex = index;
      _activeTap = null;
    });
  }

  /// Tap trúng mask → lưu state + hiện nút. Tap trượt → ẩn nút.
  void _handleMaskTap(MaskTapResult? result) {
    setState(() => _activeTap = result);
  }

  /// Mở màn chọn loại tổn thất; lưu draft khi user bấm "Lưu thay đổi".
  Future<void> _openAddDamageScreen(
    BuildContext context,
    ResultImage image,
  ) async {
    final tap = _activeTap;
    if (tap == null) return;

    final draft = await Navigator.of(context).push<DamageAnnotationDraft>(
      MaterialPageRoute(
        builder: (_) => AddDamageView(
          tapResult: tap,
          imageUrl: image.imageUrl,
        ),
      ),
    );

    if (!mounted) return;
    if (draft != null) {
      setState(() {
        _pendingDamageAnnotations.add(draft);
        _activeTap = null;
      });
    }
  }

  void _onBack(BuildContext context) {
    if (widget.onAddPhoto != null) {
      widget.onAddPhoto!(context);
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _syncInitialAngle(Map<int, List<ResultImage>> grouped) {
    if (_initialAngleSynced) return;
    _initialAngleSynced = true;
    if ((grouped[_selectedAngle] ?? []).isNotEmpty) return;
    for (var i = 0; i < CarAngle.segmentLabels.length; i++) {
      if ((grouped[i] ?? []).isNotEmpty) {
        setState(() {
          _selectedAngle = i;
          _selectedImageIndex = 0;
        });
        return;
      }
    }
  }

  String _angleLabel(int angle) {
    if (angle < StringSheet.resultAngleLabels.length) {
      return StringSheet.resultAngleLabels[angle];
    }
    return CarAngle.segmentLabels[angle];
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final landscapeMq = mq.copyWith(
      size: Size(mq.size.height, mq.size.width),
      padding: EdgeInsets.fromLTRB(
        mq.padding.bottom,
        mq.padding.left,
        mq.padding.top,
        mq.padding.right,
      ),
      viewPadding: EdgeInsets.fromLTRB(
        mq.viewPadding.bottom,
        mq.viewPadding.left,
        mq.viewPadding.top,
        mq.viewPadding.right,
      ),
      viewInsets: EdgeInsets.fromLTRB(
        mq.viewInsets.bottom,
        mq.viewInsets.left,
        mq.viewInsets.top,
        mq.viewInsets.right,
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: AppColors.black,
          body: MediaQuery(
            data: landscapeMq,
            child: RotatedBox(
              quarterTurns: 1,
              child: Builder(
                builder: (innerCtx) {
                  ScreenUtil.init(
                    innerCtx,
                    designSize: ScreenUtil.landscapeDesignSize,
                  );
                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      switch (_controller.status) {
                        case ResultStatus.uploading:
                          return _buildUploading();
                        case ResultStatus.fetchingResult:
                          return _buildFetchingResult();
                        case ResultStatus.success:
                          return _buildResult();
                        case ResultStatus.error:
                          return _buildError();
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploading() {
    final uploaded = _controller.uploadedCount;
    final total = _controller.totalCount;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 56.w,
            height: 56.w,
            child: CircularProgressIndicator(
              value: _controller.uploadProgress,
              strokeWidth: 4,
              color: AppColors.primaryA600,
              backgroundColor: AppColors.primaryA200,
            ),
          ),
          20.verticalSpace,
          Text(
            StringSheet.uploadingPhotos(uploaded, total),
            style: AppTextStyles.base.s14.ink400Color,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFetchingResult() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            color: AppColors.primaryA500,
            backgroundColor: AppColors.primaryA200,
          ),
          16.verticalSpace,
          Text(
            StringSheet.fetchingResult,
            style: AppTextStyles.base.s14.ink400Color,
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final grouped = _controller.groupedImages;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncInitialAngle(grouped);
    });
    final images = grouped[_selectedAngle] ?? [];
    final clampedIndex =
        images.isEmpty ? 0 : _selectedImageIndex.clamp(0, images.length - 1);

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: images.isEmpty
                    ? _buildEmpty()
                    : _buildMainImage(
                        context,
                        images[clampedIndex],
                      ),
              ),
              if (images.isNotEmpty)
                ResultThumbnailStrip(
                  images: images,
                  selectedIndex: clampedIndex,
                  onSelected: _selectImage,
                ),
            ],
          ),
        ),
        ResultBottomBar(
          selectedAngle: _selectedAngle,
          angleLabel: _angleLabel(_selectedAngle),
          grouped: grouped,
          onAngleSelected: _selectAngle,
          onEstimate: () {
            final result =
                _controller.result?.map((e) => e.toJson()).toList() ?? [];
            widget.onComplete?.call(result);
          },
        ),
      ],
    );
  }

  Widget _buildMainImage(BuildContext outerCtx, ResultImage image) {
    return Builder(
      builder: (context) {
        final inset = MediaQuery.paddingOf(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            ScaledResultImage(
              image: image,
              activeTap: _activeTap,
              onMaskTap: _handleMaskTap,
              onAddDamage: () => _openAddDamageScreen(outerCtx, image),
            ),
            Positioned(
              top: inset.top + 8.h,
              left: inset.left + 8.w,
              child: _BackButton(onTap: () => _onBack(outerCtx)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48.r,
            color: AppColors.greenA500,
          ),
          12.verticalSpace,
          Text(
            StringSheet.noDamageFound,
            style: AppTextStyles.base.s16.w600().copyWith(
                  color: AppColors.white,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.r),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 40.r, color: AppColors.redA400),
            12.verticalSpace,
            Text(
              _controller.errorMessage ?? StringSheet.unknownError,
              style: AppTextStyles.base.s14.ink400Color,
              textAlign: TextAlign.center,
            ),
            20.verticalSpace,
            FilledButton(
              onPressed: _controller.retry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryA500,
              ),
              child: Text(
                StringSheet.retry,
                style: AppTextStyles.baseWhite.s14.w600(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40.r,
        height: 40.r,
        decoration: BoxDecoration(
          color: AppColors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(12.r),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: AppColors.white,
          size: 20.r,
        ),
      ),
    );
  }
}
