import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/utils/image_fit_utils.dart';
import '../../../../core/utils/screen_utils.dart';
import '../../domain/entity/inspection_result.dart';
import '../../domain/utils/damage_box_merger.dart';
import '../models/damage_annotation_draft.dart';
import '../models/mask_tap_result.dart';
import 'add_damage_tap_button.dart';
import 'mask_hit_tester.dart';
import 'saved_damage_marker.dart';

/// Opacity cố định cho mask overlay bộ phận xe.
const double _partMaskOpacity = 0.3;


class ScaledResultImage extends StatefulWidget {
  const ScaledResultImage({
    super.key,
    required this.image,
    this.maxScale = 3.5,
    this.activeTap,
    this.savedAnnotations = const [],
    this.onMaskTap,
    this.onAddDamage,
    this.onSavedAnnotationTap,
  });

  final ResultImage image;
  final double maxScale;

  final MaskTapResult? activeTap;

  final List<DamageAnnotationDraft> savedAnnotations;

  final void Function(MaskTapResult?)? onMaskTap;

  final VoidCallback? onAddDamage;

  final void Function(DamageAnnotationDraft)? onSavedAnnotationTap;

  @override
  State<ScaledResultImage> createState() => _ScaledResultImageState();
}

class _ScaledResultImageState extends State<ScaledResultImage> {
  final _tc = TransformationController();
  final _hitTester = MaskHitTester();

  Size? _logicalSize;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  Size _displaySize = Size.zero;

  Size _containerSize = Size.zero;

  /// Vị trí pointer khi bắt đầu chạm — dùng để phân biệt tap vs pan.
  Offset? _pointerDownPos;

  @override
  void initState() {
    super.initState();
    _resolveLogicalSize();
    _hitTester.preload(widget.image.partsMasks);
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
    if (oldWidget.image != widget.image) {
      _hitTester.preload(widget.image.partsMasks);
    }
  }

  @override
  void dispose() {
    _clearImageStream();
    _tc.dispose();
    _hitTester.dispose();
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


  /// Xử lý tap tại [localInViewer] (local coords của InteractiveViewer).
  ///
  /// Convert sang image-space rồi delegate cho [MaskHitTester].
  /// Luôn gọi [onMaskTap] — trả về `null` nếu không trúng mask nào.
  void _handleTap(Offset localInViewer) {
    if (widget.onMaskTap == null) return;
    if (_displaySize == Size.zero || _containerSize == Size.zero) return;

    // Viewer local → scene (LayoutBuilder) coords.
    final scenePos = _tc.toScene(localInViewer);

    // SizedBox (imWidth x imHeight) được căn giữa bởi Center trong LayoutBuilder.
    final offsetX = (_containerSize.width - _displaySize.width) / 2;
    final offsetY = (_containerSize.height - _displaySize.height) / 2;
    final imagePos = scenePos - Offset(offsetX, offsetY);

    if (_isTapOnSavedMarker(imagePos) || _isTapOnActiveButton(imagePos)) {
      return;
    }

    final partMasks =
        widget.image.partsMasks.where((m) => m.isPart == true).toList();

    final hit = _hitTester.hitTest(
      scenePos: imagePos,
      masks: partMasks,
      imWidth: _displaySize.width,
      imHeight: _displaySize.height,
    );

    if (hit == null) {
      widget.onMaskTap?.call(null);
      return;
    }

    final imageId = widget.image.imageId;
    if (imageId == null) return;

    final normalized = displayPositionToNormalized(
      imagePos,
      _displaySize.width,
      _displaySize.height,
    );
    final logical = normalizedToLogicalPixel(
      normalized,
      widget.image.resolution,
    );

    widget.onMaskTap?.call(
      MaskTapResult(
        imageId: imageId,
        mask: hit,
        normalizedPosition: normalized,
        displayPosition: imagePos,
        logicalPixelPosition: logical,
      ),
    );
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

    return Listener(
      onPointerDown: (e) => _pointerDownPos = e.localPosition,
      onPointerUp: (e) {
        final down = _pointerDownPos;
        _pointerDownPos = null;
        if (down == null) return;
        final delta = (e.localPosition - down).distance;
        if (delta < kTouchSlop) _handleTap(e.localPosition);
      },
      child: InteractiveViewer(
        transformationController: _tc,
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

            // Cập nhật cache tọa độ — không cần setState vì chỉ dùng ở hit-test.
            _displaySize = displaySize;
            _containerSize = Size(constraints.maxWidth, constraints.maxHeight);

            final imWidth = displaySize.width;
            final imHeight = displaySize.height;
            final masks = _buildPartMasks(
              widget.image.partsMasks,
              imWidth,
              imHeight,
            );

            final activeTap = widget.activeTap;
            final showTapButton = activeTap != null &&
                activeTap.imageId == widget.image.imageId;

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
                        if (mainReady)
                          ..._buildSavedAnnotationOverlays(
                            widget.savedAnnotations,
                            imWidth,
                            imHeight,
                          ),
                        if (mainReady && showTapButton)
                          _buildTapButtonOverlay(activeTap),
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
      ),
    );
  }

  List<Widget> _buildSavedAnnotationOverlays(
    List<DamageAnnotationDraft> annotations,
    double imWidth,
    double imHeight,
  ) {
    final iconSize = 22.r;
    return [
      for (final draft in annotations)
        _buildSavedMarkerOverlay(draft, imWidth, imHeight, iconSize),
    ];
  }

  Widget _buildSavedMarkerOverlay(
    DamageAnnotationDraft draft,
    double imWidth,
    double imHeight,
    double iconSize,
  ) {
    final displayPos = normalizedToDisplayPosition(
      draft.normalizedPosition,
      imWidth,
      imHeight,
    );

    return Positioned(
      left: displayPos.dx - iconSize / 2,
      top: displayPos.dy - iconSize / 2,
      child: SavedDamageMarker(
        damageTypeName: draft.damageTypeName,
        onTap: () => widget.onSavedAnnotationTap?.call(draft),
      ),
    );
  }

  bool _isTapOnSavedMarker(Offset imagePos) {
    final iconSize = 22.r;
    for (final draft in widget.savedAnnotations) {
      final displayPos = normalizedToDisplayPosition(
        draft.normalizedPosition,
        _displaySize.width,
        _displaySize.height,
      );
      final origin = displayPos - Offset(iconSize / 2, iconSize / 2);
      final markerRect = Rect.fromLTWH(
        origin.dx,
        origin.dy - 2.h,
        148.w,
        40.h,
      );
      if (markerRect.contains(imagePos)) {
        return true;
      }
    }
    return false;
  }

  /// Nút "Thêm tổn thất" — icon tròn căn tại [tap.displayPosition], chữ nằm bên phải.
  Widget _buildTapButtonOverlay(MaskTapResult tap) {
    final iconSize = 22.r;
    return Positioned(
      left: tap.displayPosition.dx - iconSize / 2,
      top: tap.displayPosition.dy - iconSize / 2,
      child: AddDamageTapButton(onTap: () => widget.onAddDamage?.call()),
    );
  }

  bool _isTapOnActiveButton(Offset imagePos) {
    final tap = widget.activeTap;
    if (tap == null) return false;

    final iconRadius = 11.r;
    final origin = tap.displayPosition - Offset(iconRadius, iconRadius);
    final btnRect = Rect.fromLTWH(
      origin.dx,
      origin.dy - 2.h,
      148.w,
      34.h,
    );
    return btnRect.contains(imagePos);
  }

  /// Vẽ overlay mask bộ phận (isPart=true) và bounding box damage (isPart=false).
  List<Widget> _buildPartMasks(
    List<PartMask> masks,
    double imWidth,
    double imHeight,
  ) {
    final seenUrls = <String>{};
    final widgets = <Widget>[];

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

    final mergedDamages = DamageBoxMerger.merge(damageMasks.toList());
    for (final damage in mergedDamages) {
      final rect = maskDisplayRect(damage.boxes, imWidth, imHeight);
      final color = hexToColor(damage.color);
      if (color == Colors.transparent) continue;

      widgets.add(
        Positioned.fromRect(
          rect: rect,
          child: _DamageBoundingBox(
            label: damage.label,
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
