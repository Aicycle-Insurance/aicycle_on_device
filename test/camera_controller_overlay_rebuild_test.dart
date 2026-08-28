import 'dart:io';

import 'package:aicycle_on_device/src/features/camera/presentation/controller/camera_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Overlay tần số cao (box tổn thất, nhãn bộ phận) phải đi qua ValueNotifier
/// riêng, KHÔNG qua notifyListeners — nếu không thì mỗi frame inference sẽ dựng
/// lại cả thanh trên, thanh dưới, vòng tròn góc và tooltip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Vào pha inspection sẽ mở context stream (upload ngầm 1 frame/giây), và nó
  // hỏi path_provider chỗ ghi file. Trong unit test không có plugin thật nên
  // trả về thư mục tạm — chỉ để đường đó không ném, test này không quan tâm
  // tới upload.
  late Directory tempDir;
  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('aicycle_overlay_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Map<String, dynamic> detectFrame(
    List<(String, double)> boxes, {
    required String modelId,
  }) {
    return {
      'type': 'detect',
      'modelId': modelId,
      'fps': 10.0,
      'cameraFps': 30.0,
      'processingTimeMs': 12.0,
      'detections': [
        for (final (name, centerX) in boxes)
          {
            'className': name,
            'confidence': 0.9,
            'normalizedBox': {
              'left': centerX - 0.05,
              'top': 0.4,
              'right': centerX + 0.05,
              'bottom': 0.6,
            },
          },
      ],
    };
  }

  late CameraController controller;
  late int notifyCount;

  setUp(() {
    controller = CameraController(sessionId: 'test-session')
      ..startCapture()
      // Vào pha inspection để box tổn thất được phép vẽ.
      ..startDamageScanning();
    notifyCount = 0;
    controller.addListener(() => notifyCount++);
  });

  tearDown(() => controller.dispose());

  test('frame carDamage cập nhật damageBoxes mà không notifyListeners', () {
    controller.onStreamingData(
      detectFrame([('Móp/bẹp', 0.5)], modelId: 'detect'),
    );

    expect(controller.damageBoxes.value, hasLength(1));
    expect(notifyCount, 0);
  });

  test('frame carPart cập nhật carPartBoxes mà không notifyListeners', () {
    controller.onStreamingData(
      detectFrame([('Cánh cửa', 0.5)], modelId: 'detect2'),
    );

    expect(controller.carPartBoxes.value, hasLength(1));
    expect(notifyCount, 0);
  });

  test('hai frame rỗng liên tiếp chỉ bắn đúng một sự kiện cho lớp vẽ', () {
    var boxTicks = 0;
    controller.damageBoxes.addListener(() => boxTicks++);

    // Frame đầu có box → 1 sự kiện.
    controller.onStreamingData(
      detectFrame([('Móp/bẹp', 0.5)], modelId: 'detect'),
    );
    // Rồi hai frame rỗng liên tiếp → chỉ sự kiện "về rỗng" đầu tiên được bắn.
    controller.onStreamingData(detectFrame([], modelId: 'detect'));
    controller.onStreamingData(detectFrame([], modelId: 'detect'));

    expect(controller.damageBoxes.value, isEmpty);
    expect(boxTicks, 2);
  });

  test('rời pha inspection thì box tổn thất được dọn ngay', () {
    controller.onStreamingData(
      detectFrame([('Móp/bẹp', 0.5)], modelId: 'detect'),
    );
    expect(controller.damageBoxes.value, hasLength(1));

    // Đổi góc → thoát inspection; native tắt hẳn carDamage nên sẽ không có
    // frame nào tới để tự dọn.
    controller.completeCurrentAngle();

    expect(controller.damageBoxes.value, isEmpty);
  });

  test('đổi pha inspection vẫn notify để vòng tròn góc / nút kết quả kịp cập nhật',
      () {
    // Trước refactor, thay đổi _completedSegments được làm mới nhờ
    // notifyListeners() bắn theo từng frame. Nay frame đi đường riêng nên chính
    // lần đổi pha phải notify.
    controller.completeCurrentAngle();

    expect(notifyCount, greaterThan(0));
  });

  test('stopCamera dọn cả hai lớp vẽ', () {
    controller.onStreamingData(
      detectFrame([('Móp/bẹp', 0.5)], modelId: 'detect'),
    );
    controller.onStreamingData(
      detectFrame([('Cánh cửa', 0.5)], modelId: 'detect2'),
    );

    controller.stopCamera();

    expect(controller.damageBoxes.value, isEmpty);
    expect(controller.carPartBoxes.value, isEmpty);
  });

  test('frame đến sau stopCamera không ghi vào notifier đã dừng', () {
    controller.stopCamera();

    controller.onStreamingData(
      detectFrame([('Móp/bẹp', 0.5)], modelId: 'detect'),
    );

    expect(controller.damageBoxes.value, isEmpty);
  });
}
