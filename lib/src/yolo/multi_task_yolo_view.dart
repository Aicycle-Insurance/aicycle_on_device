// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'core/yolo_model_resolver.dart';

/// Callback fired on the main thread for each inference result from one of the
/// active YOLO tasks.
///
/// [data] contains:
/// - `"type"`: `"detect"` | `"classify"` | `"ocr"` | `"thermal"` — the task kind
/// - `"modelId"`: which configured model produced this result. Use this (not `"type"`)
///   to route results, since two detection models both report `"type": "detect"`:
///   `"detect"` (primary detect model), `"detect2"` (second detect model),
///   `"classify"` (classify model)
/// - `"fps"`: per-model FPS
/// - `"cameraFps"`: raw camera feed FPS
/// - `"processingTimeMs"`: inference time in ms
/// - `"detections"`: list of detection maps (detect models)
/// - `"classification"`: map with `top1`, `top1Confidence`, `top5` (classify model)
/// - `"readable"` (bool), `"plate"` (String), `"score"` (double): OCR result
///   (`type == "ocr"`) — emitted only when an OCR model is configured and a
///   license-plate box was found in a carPart frame.
/// - `"level"` (int 0–3), `"state"` (String), `"throttled"` (bool): device
///   thermal tier (`type == "thermal"`) — emitted once when the camera starts
///   and again whenever the tier changes. Native throttles each model's
///   inference rate as the tier rises; this event only reports that it is
///   happening.
typedef MultiTaskStreamCallback = void Function(Map<String, dynamic> data);

/// Controller for [MultiTaskYOLOView]. Pass to the widget and call [capturePhoto]
/// to take a still JPEG from the live camera stream.
class MultiTaskYOLOController {
  MethodChannel? _channel;
  bool _torchEnabled = false;

  void _attach(MethodChannel channel) => _channel = channel;
  void _detach() => _channel = null;

  bool get isTorchEnabled => _torchEnabled;

  /// Capture a JPEG still from the current camera frame.
  /// Returns the JPEG bytes, or throws if the camera is not ready.
  ///
  /// The preview is rendered aspect-fill (cover) inside the platform view, while
  /// the still capture comes from the full camera frame — so by default the
  /// saved photo contains more than what is visible on screen. Pass the visible
  /// viewport (normalized [0,1] rect in *preview* coordinates) to have native
  /// crop the still to exactly what the user sees. `(0,0,1,1)` = no crop.
  Future<Uint8List> capturePhoto({
    double cropLeft = 0,
    double cropTop = 0,
    double cropRight = 1,
    double cropBottom = 1,
  }) async {
    final ch = _channel;
    if (ch == null) throw StateError('MultiTaskYOLOView is not attached');
    final bool fullFrame =
        cropLeft <= 0 && cropTop <= 0 && cropRight >= 1 && cropBottom >= 1;
    final result = await ch.invokeMethod<Uint8List>(
      'capturePhoto',
      fullFrame
          ? null
          : {
              'cropLeft': cropLeft,
              'cropTop': cropTop,
              'cropRight': cropRight,
              'cropBottom': cropBottom,
            },
    );
    if (result == null) throw StateError('capturePhoto returned null');
    return result;
  }

  /// Capture a JPEG still and let the native side write it directly to [filePath].
  /// This avoids moving the full JPEG through the platform channel just so Dart
  /// can write it back to disk.
  Future<String> capturePhotoToFile({
    required String filePath,
    String? thumbnailPath,
    double cropLeft = 0,
    double cropTop = 0,
    double cropRight = 1,
    double cropBottom = 1,
    int quality = 80,
    int thumbnailMaxSize = 160,
  }) async {
    final ch = _channel;
    if (ch == null) throw StateError('MultiTaskYOLOView is not attached');
    final result = await ch.invokeMethod<String>(
      'capturePhotoToFile',
      {
        'path': filePath,
        if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
        'quality': quality,
        'thumbnailMaxSize': thumbnailMaxSize,
        'cropLeft': cropLeft,
        'cropTop': cropTop,
        'cropRight': cropRight,
        'cropBottom': cropBottom,
      },
    );
    if (result == null) throw StateError('capturePhotoToFile returned null');
    return result;
  }

  /// Turn the camera torch on ([enable] = true) or off ([enable] = false).
  /// Returns the actual torch state after the call — `false` when the device
  /// has no torch or the call is made before the view is attached.
  Future<bool> setTorch(bool enable) async {
    final ch = _channel;
    if (ch == null) return false;
    final result = await ch.invokeMethod<bool>('setTorch', {'enable': enable});
    _torchEnabled = result ?? false;
    return _torchEnabled;
  }

  Future<bool> toggleTorch() => setTorch(!_torchEnabled);

  /// Forwards the visible viewport (preview-space vertical band, normalized
  /// [0,1]) so native can gate license-plate OCR to plates fully inside what the
  /// user sees. Returns `false` if the view isn't attached yet (caller should
  /// retry once it is). Fire-and-forget on the native side.
  bool setViewport(double top, double bottom) {
    final ch = _channel;
    if (ch == null) return false;
    ch.invokeMethod<void>('setViewport', {'top': top, 'bottom': bottom});
    return true;
  }

  /// Phase-based model gating to cut inference load. `active == true` (inspection)
  /// runs carDamage and stops license-plate OCR; `active == false`
  /// (framing/panorama) runs OCR and stops carDamage. carCorner/carPart always
  /// run. Returns `false` if the view isn't attached yet.
  bool setInspectionActive(bool active) {
    final ch = _channel;
    if (ch == null) return false;
    ch.invokeMethod<void>('setInspectionActive', {'active': active});
    return true;
  }

  /// Stops the camera and releases all CoreML model predictors from memory.
  /// Call this before removing [MultiTaskYOLOView] from the tree so GPU/ANE
  /// memory is freed immediately rather than waiting for a potentially-delayed deinit.
  Future<void> stop() async {
    final ch = _channel;
    if (ch == null) return;
    await ch.invokeMethod<void>('stop');
  }
}

/// A Flutter widget that runs two detection models plus a classification model
/// simultaneously on a single camera stream — no JPEG round-trip, no MethodChannel
/// per frame. Each model runs concurrently on its own queue.
///
/// Pass [secondDetectModelPath] to enable a second detection model running in parallel
/// with the primary detect + classify models. The [onStreamingData] callback fires for
/// every result; route on `data["modelId"]` (`"detect"`, `"detect2"`, `"classify"`)
/// since both detection models report `data["type"] == "detect"`.
class MultiTaskYOLOView extends StatefulWidget {
  const MultiTaskYOLOView({
    super.key,
    required this.detectModelPath,
    required this.classifyModelPath,
    required this.secondDetectModelPath,
    this.ocrModelPath,
    this.ocrConfidenceThreshold = 0.85,
    this.controller,
    this.onStreamingData,
    this.lensFacing = 'back',
    this.useGpu = true,
    this.confidenceThreshold = 0.25,
    this.iouThreshold = 0.7,
    this.detectConfidenceThreshold,
    this.detectIouThreshold,
    this.classifyConfidenceThreshold,
    this.secondDetectConfidenceThreshold,
    this.secondDetectIouThreshold,
  });

  /// Primary detection model. Results arrive with `data["modelId"] == "detect"`.
  final String detectModelPath;
  final String classifyModelPath;

  /// Second detection model. When non-null, runs in parallel with the primary
  /// detect + classify models; pass null to run only detect + classify. Results arrive
  /// via [onStreamingData] with `data["type"] == "detect"` and `data["modelId"] == "detect2"`.
  final String? secondDetectModelPath;

  /// License-plate OCR model (CoreML/TFLite recognizer, not a YOLO model). When
  /// non-null, native runs it on carPart frames containing a license-plate box and
  /// streams a `data["type"] == "ocr"` event with `readable`/`plate`/`score`. Used
  /// purely as a framing signal — a readable plate marks a good panoramic frame.
  final String? ocrModelPath;

  /// Minimum mean digit-confidence for an OCR read to count as `readable`.
  final double ocrConfidenceThreshold;

  final MultiTaskYOLOController? controller;
  final MultiTaskStreamCallback? onStreamingData;
  final String lensFacing;
  final bool useGpu;

  /// Default confidence threshold, applied to any model without a per-model override.
  final double confidenceThreshold;

  /// Default IoU (NMS) threshold, applied to any model without a per-model override.
  final double iouThreshold;

  /// Per-model overrides. When null, the corresponding model falls back to the
  /// global [confidenceThreshold] / [iouThreshold]. Classification only uses a
  /// confidence threshold (IoU does not apply to it).
  final double? detectConfidenceThreshold;
  final double? detectIouThreshold;
  final double? classifyConfidenceThreshold;
  final double? secondDetectConfidenceThreshold;
  final double? secondDetectIouThreshold;

  @override
  State<MultiTaskYOLOView> createState() => _MultiTaskYOLOViewState();
}

class _MultiTaskYOLOViewState extends State<MultiTaskYOLOView> {
  static int _nextId = 0;
  late final String _viewId;
  EventChannel? _eventChannel;
  MethodChannel? _methodChannel;
  StreamSubscription<dynamic>? _eventSubscription;

  // Resolved absolute paths (null = still resolving)
  String? _detectResolved;
  String? _classifyResolved;
  String? _secondDetectResolved;
  String? _ocrResolved;
  String? _resolutionError;

  @override
  void initState() {
    super.initState();
    _viewId = 'multi_task_${_nextId++}';
    _resolveModels();
  }

  Future<void> _resolveModels() async {
    try {
      // Start OCR path resolution at the same time as the three required YOLO
      // models. It remains optional, but no longer adds a second serial path
      // preparation pass before the native camera view can be created.
      final ocrFuture = () async {
        final ocrPath = widget.ocrModelPath;
        if (ocrPath == null) return null;
        try {
          return await YOLOModelResolver.preparePath(ocrPath);
        } catch (_) {
          return null;
        }
      }();
      final futures = [
        YOLOModelResolver.preparePath(widget.detectModelPath),
        YOLOModelResolver.preparePath(widget.classifyModelPath),
        YOLOModelResolver.preparePath(widget.secondDetectModelPath!),
      ];
      final results = await Future.wait(futures);
      final ocrResolved = await ocrFuture;
      if (!mounted) return;
      setState(() {
        _detectResolved = results[0];
        _classifyResolved = results[1];
        _secondDetectResolved = results[2];
        _ocrResolved = ocrResolved;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolutionError = e.toString());
    }
  }

  void _onPlatformViewCreated(int id) {
    _eventChannel = EventChannel(
      'com.aicycle.yolo/multiTaskResults_$_viewId',
    );
    _methodChannel = MethodChannel(
      'com.aicycle.yolo/multiTaskControl_$_viewId',
    );

    widget.controller?._attach(_methodChannel!);

    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel!.receiveBroadcastStream().listen(
      (event) {
        if (event is Map && widget.onStreamingData != null) {
          widget.onStreamingData!(Map<String, dynamic>.from(event));
        }
      },
      onError: (Object error) {
        // ignore stream errors to prevent unhandled exceptions
      },
      cancelOnError: false,
    );
  }

  Map<String, dynamic> get _creationParams {
    final params = <String, dynamic>{
      'viewId': _viewId,
      'detectModel': _detectResolved!,
      'classifyModel': _classifyResolved!,
      'lensFacing': widget.lensFacing,
      'useGpu': widget.useGpu,
      'confidenceThreshold': widget.confidenceThreshold,
      'iouThreshold': widget.iouThreshold,
      'detectConfidenceThreshold':
          widget.detectConfidenceThreshold ?? widget.confidenceThreshold,
      'detectIouThreshold': widget.detectIouThreshold ?? widget.iouThreshold,
      'classifyConfidenceThreshold':
          widget.classifyConfidenceThreshold ?? widget.confidenceThreshold,
    };
    params['secondDetectModel'] = _secondDetectResolved!;
    params['secondDetectConfidenceThreshold'] =
        widget.secondDetectConfidenceThreshold ?? widget.confidenceThreshold;
    params['secondDetectIouThreshold'] =
        widget.secondDetectIouThreshold ?? widget.iouThreshold;
    // OCR is optional; only forward it if the (optional) model resolved.
    if (_ocrResolved != null) {
      params['ocrModel'] = _ocrResolved!;
      params['ocrConfidenceThreshold'] = widget.ocrConfidenceThreshold;
    }
    return params;
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return const ColoredBox(color: Color(0xFF000000));
    }

    if (_resolutionError != null) {
      return ColoredBox(
        color: const Color(0xFF000000),
        child: Center(
          child: Text(
            'Model error: $_resolutionError',
            style: const TextStyle(color: Color(0xFFFF4444), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final secondDetectPending =
        widget.secondDetectModelPath != null && _secondDetectResolved == null;
    if (_detectResolved == null ||
        _classifyResolved == null ||
        secondDetectPending) {
      // Still resolving model paths
      return const ColoredBox(color: Color(0xFF000000));
    }

    if (Platform.isIOS) {
      return UiKitView(
        viewType: 'com.aicycle.yolo/YOLOMultiTaskPlatformView',
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: _creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      );
    }

    // Android
    return AndroidView(
      viewType: 'com.aicycle.yolo/YOLOMultiTaskPlatformView',
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: _creationParams,
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    widget.controller?._detach();
    // Native PlatformView.dispose owns resource release. Sending another stop
    // from here races the route/widget transition and can stall the first upload
    // frame when heavy camera/model cleanup starts immediately.
    super.dispose();
  }
}
