part of 'camera_controller.dart';

/// Phân loại từng frame streaming từ YOLO và đẩy vào đúng luồng xử lý.
mixin _StreamMixin on _CameraControllerBase {
  // ── Capture gate ──────────────────────────────────────────────────────────

  /// Gọi khi user bấm "Bắt đầu chụp ảnh xe" ở guide sheet — mở cổng cho phép
  /// [onStreamingData] bắt đầu xử lý frame. An toàn khi gọi nhiều lần.
  void startCapture() => _captureStarted = true;

  // ── Streaming data ────────────────────────────────────────────────────────

  // [data] đã là Map<String, dynamic> do MultiTaskYOLOView cấp — dùng trực tiếp,
  // không copy lại (mỗi frame chạy trên UI thread). Mỗi nhánh chỉ
  // notifyListeners() đúng một lần và chỉ khi có thay đổi nhìn thấy được, để
  // tránh rebuild thừa khi stream bắn nhiều frame/giây.
  void onStreamingData(Map<String, dynamic> data) {
    // User chưa bấm "Bắt đầu chụp ảnh xe" → bỏ qua toàn bộ frame streaming.
    if (!_captureStarted) return;

    final type = data['type'];
    // Hai model detect đều trả type=='detect'; phân biệt bằng modelId:
    //   'detect'  -> car damage (model chính)
    //   'detect2' -> car part   (model thứ 2)
    final modelId = data['modelId'];
    if (type == 'classify') {
      _handleClassify(data);
      return;
    }

    if (type == 'ocr') {
      _handleOcr(data);
      return;
    }

    if (type == 'detect' && modelId == 'detect2') {
      _handleCarPart(data);
      return;
    }

    if (type == 'detect') {
      _handleCarDamage(data);
    }
  }

  /// carCorner — phân loại góc xe.
  void _handleClassify(Map<String, dynamic> data) {
    final output = ClassifyOutput.fromJson(data);
    final segment = CarAngle.segmentOf(output.classification.top1);
    if (segment == null) return;
    // Luôn highlight góc đang nhận diện được, kể cả khi flow đã khoá.
    final highlightChanged = segment != _detectedSegmentIndex;
    if (highlightChanged) _detectedSegmentIndex = segment;

    if (_classificationLocked && segment != _activeSegmentIndex) {
      _autoSwitchToDetectedSegment(segment);
      if (highlightChanged) notifyListeners();
      return;
    }

    // Cập nhật luồng (chỉ khi chưa khoá và góc đổi). Các hàm bên trong
    // (startDamageScanning/updateMessage) tự notify khi message đổi.
    if (!_classificationLocked && segment != _activeSegmentIndex) {
      _activateDetectedSegment(segment);
    }
    if (highlightChanged) notifyListeners();
  }

  void _activateDetectedSegment(int segment) {
    _resetPanoramicFramingState(clearCarParts: true);
    _activeSegmentIndex = segment;
    // Vào thẳng scanning (bỏ qua chụp toàn cảnh) khi:
    //  - góc này đã có ảnh toàn cảnh rồi, HOẶC
    //  - config 4 góc TẮT và đã chụp xong ảnh toàn cảnh đầu tiên (các góc
    //    sau chỉ ghi nhận tổn thất, không yêu cầu chụp toàn cảnh).
    final skipPanoramic = _panoramicCapturedSegments.contains(segment) ||
        (!_require4Angles && _firstPanoramicCaptured);
    if (skipPanoramic) {
      _classificationLocked = true;
      startDamageScanning();
    } else {
      updateMessage();
    }
  }

  /// OCR (native) — tín hiệu canh khung. Đọc được biển ⇒ frame đủ tốt để
  /// làm ảnh toàn cảnh; cập nhật cờ rồi re-evaluate để có thể kích hoạt chụp.
  void _handleOcr(Map<String, dynamic> data) {
    final readable = data['readable'] == true;
    if (readable) {
      _latestPlateReadable = readable;
      _latestPlateReadableAt = DateTime.now();
      updateMessage(); // tự notify khi message đổi / tự chụp nếu đủ điều kiện
    } else if (_latestPlateReadable) {
      _clearPlateRead();
      updateMessage();
    }
  }

  /// carPart — model detect bộ phận, dùng để căn ảnh toàn cảnh.
  void _handleCarPart(Map<String, dynamic> data) {
    final output = DetectionOutput.fromJson(data);
    final wasEmpty = _latestCarPartDetections.isEmpty;
    // Chỉ giữ bộ phận nằm trong vùng user thực sự nhìn thấy (giữa top/bottom
    // bar) — model xử lý cả phần bị che nên phải lọc lại.
    final visible = _filterToViewport(output.detections);
    _latestCarPartClasses = visible.map((d) => d.className).toSet();
    _latestCarPartDetections = visible;
    // Biển không còn trong khung → cờ "đọc được" cũ không còn hiệu lực.
    if (!_latestCarPartClasses.contains(_licensePlateClass)) {
      _clearPlateRead();
    }
    updateMessage(); // tự notify khi message đổi
    // Bỏ qua redraw nếu không có nhãn bộ phận nào để vẽ (trước & sau đều rỗng).
    if (!(wasEmpty && visible.isEmpty)) notifyListeners();
  }

  /// carDamage — model detect tổn thất (model chính).
  void _handleCarDamage(Map<String, dynamic> data) {
    final output = DetectionOutput.fromJson(data);
    // Bỏ qua tổn thất nằm ngoài khung nhìn (bị top/bottom bar che).
    _latestDetections = _filterToViewport(output.detections);
    // Phát hiện tổn thất → hiển thị xác nhận ngay, không chờ timer auto-capture.
    _maybeShowDetectionReady(); // tự notify khi chuyển pha
    // Bounding box chỉ vẽ khi đang trong pha inspection; ngoài ra việc đổi
    // _latestDetections không ảnh hưởng UI → khỏi rebuild.
    if (showBoundingBoxes) notifyListeners();
  }
}
