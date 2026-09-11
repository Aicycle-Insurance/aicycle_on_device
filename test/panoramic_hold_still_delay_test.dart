import 'dart:io';

import 'package:aicycle_on_device/src/core/constants/string_sheet.dart';
import 'package:aicycle_on_device/src/features/camera/presentation/controller/camera_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ảnh toàn cảnh chỉ được chụp sau khi tooltip "Hãy giữ yên điện thoại…" đã
/// HIỂN THỊ đủ 3s. Mốc đếm phải là lúc tooltip thật sự hiện, không phải lúc căn
/// đủ bộ phận — vì tooltip có thể còn đang xếp hàng chờ tooltip trước đó hiển
/// thị đủ tối thiểu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('aicycle_panoramic_test');
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

  // Test chạy trên đồng hồ thật: mốc "tooltip đã hiện" chỉ quan sát được ở nhịp
  // bơm frame kế tiếp nên luôn trễ hơn mốc thật vài chục ms. Cận dưới trừ đi sai
  // số đó — vẫn cách rất xa hành vi lỗi cũ (~0.6s).
  const samplingSlack = Duration(milliseconds: 150);
  final atLeastHoldStill = greaterThanOrEqualTo(
      const Duration(seconds: 3) - samplingSlack);

  const box = {'left': 0.4, 'top': 0.4, 'right': 0.6, 'bottom': 0.6};

  Map<String, dynamic> classifyFrame(String top1) => {
        'type': 'classify',
        'fps': 10.0,
        'cameraFps': 30.0,
        'processingTimeMs': 10.0,
        'classification': {
          'top1': top1,
          'top1Confidence': 0.9,
          'top5': <Map<String, dynamic>>[],
        },
      };

  Map<String, dynamic> carPartFrame(List<String> classes) => {
        'type': 'detect',
        'modelId': 'detect2',
        'fps': 6.7,
        'cameraFps': 30.0,
        'processingTimeMs': 10.0,
        'detections': [
          for (final c in classes)
            {'className': c, 'confidence': 0.9, 'normalizedBox': box},
        ],
      };

  const allParts = ['Biển số xe', 'Cánh cửa', 'Ba đờ sốc trước'];

  test(
    'không chụp cho tới khi tooltip "giữ yên" đã hiển thị đủ 3s',
    () async {
      final controller = CameraController(sessionId: 'test-session');
      addTearDown(controller.dispose);
      controller.startCapture();

      // Góc 0 (phải trước).
      controller.onStreamingData(classifyFrame('phai_truoc_toan_canh'));

      // Mới thấy biển, chưa thấy cửa → tooltip "Lùi camera ra xa…". Tooltip
      // hướng dẫn góc đang hiển thị phải giữ đủ tối thiểu nên phải bơm frame
      // vài nhịp mới tới lượt nó.
      DateTime? moveBackShownAt;
      final moveBackDeadline = DateTime.now().add(const Duration(seconds: 8));
      while (moveBackShownAt == null &&
          DateTime.now().isBefore(moveBackDeadline)) {
        controller.onStreamingData(carPartFrame(['Biển số xe']));
        if (controller.message?.message == StringSheet.moveBackGuide) {
          moveBackShownAt = DateTime.now();
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(moveBackShownAt, isNotNull,
          reason: 'tooltip "Lùi camera ra xa…" phải được hiển thị');

      // Chờ một nhịp NGẮN hơn thời gian giữ tooltip tối thiểu (3s), rồi căn đủ
      // bộ phận. Đây là kịch bản khiến bug xuất hiện:
      // holdStill bị hoãn vì "Lùi camera ra xa…" chưa hiển thị đủ tối thiểu.
      await Future<void>.delayed(const Duration(milliseconds: 600));

      DateTime? holdStillShownAt;
      DateTime? capturedAt;

      // Bơm frame liên tục như stream thật cho tới khi có lệnh chụp.
      final deadline = DateTime.now().add(const Duration(seconds: 16));
      while (capturedAt == null && DateTime.now().isBefore(deadline)) {
        controller.onStreamingData(carPartFrame(allParts));

        if (holdStillShownAt == null &&
            controller.message?.message == StringSheet.holdStillGuide) {
          holdStillShownAt = DateTime.now();
        }
        if (controller.captureFlashTick > 0) capturedAt = DateTime.now();

        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(holdStillShownAt, isNotNull,
          reason: 'tooltip "Hãy giữ yên điện thoại…" phải được hiển thị');
      expect(capturedAt, isNotNull, reason: 'phải tự động chụp ảnh toàn cảnh');

      // Tooltip "Lùi camera ra xa…" giữ đủ tối thiểu → holdStill hiện muộn.
      expect(
        holdStillShownAt!.difference(moveBackShownAt!),
        greaterThanOrEqualTo(const Duration(milliseconds: 2500)),
        reason: 'holdStill bị hoãn tới khi tooltip trước hiển thị đủ tối thiểu',
      );

      // Điểm mấu chốt: 3s được tính TỪ LÚC TOOLTIP HIỆN.
      expect(
        capturedAt!.difference(holdStillShownAt),
        atLeastHoldStill,
        reason: 'phải chờ đủ 3s kể từ khi user nhìn thấy "Hãy giữ yên…"',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'đã hiện "giữ yên" thì vẫn chụp sau 3s dù bộ phận rời khung',
    () async {
      final controller = CameraController(sessionId: 'test-session-2');
      addTearDown(controller.dispose);
      controller.startCapture();
      controller.onStreamingData(classifyFrame('phai_truoc_toan_canh'));

      // Bơm frame đủ bộ phận cho tới khi tooltip "Hãy giữ yên…" thật sự hiện.
      DateTime? holdStillShownAt;
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (holdStillShownAt == null && DateTime.now().isBefore(deadline)) {
        controller.onStreamingData(carPartFrame(allParts));
        if (controller.message?.message == StringSheet.holdStillGuide) {
          holdStillShownAt = DateTime.now();
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(holdStillShownAt, isNotNull);
      expect(controller.captureFlashTick, 0);

      // Từ đây user lia máy đi: KHÔNG còn bộ phận nào. Lời hứa "3s nữa chụp" vẫn phải được giữ.
      DateTime? capturedAt;
      final captureDeadline = DateTime.now().add(const Duration(seconds: 12));
      while (capturedAt == null && DateTime.now().isBefore(captureDeadline)) {
        controller.onStreamingData(carPartFrame(const []));
        if (controller.captureFlashTick > 0) capturedAt = DateTime.now();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(capturedAt, isNotNull,
          reason: 'phải chụp dù bộ phận đã rời khung');
      final waited = capturedAt!.difference(holdStillShownAt!);
      expect(waited, atLeastHoldStill);
      expect(waited, lessThan(const Duration(milliseconds: 3600)),
          reason: 'chụp ngay khi hết 3s, không chờ thêm');

      // Tooltip không bị hướng dẫn khác chen ngang trong lúc chờ.
      expect(controller.message?.message,
          anyOf(StringSheet.holdStillGuide, StringSheet.captureSuccess));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'vẫn chụp sau 3s kể cả khi stream ngừng bắn frame',
    () async {
      final controller = CameraController(sessionId: 'test-session-3');
      addTearDown(controller.dispose);
      controller.startCapture();
      controller.onStreamingData(classifyFrame('phai_truoc_toan_canh'));

      DateTime? holdStillShownAt;
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (holdStillShownAt == null && DateTime.now().isBefore(deadline)) {
        controller.onStreamingData(carPartFrame(allParts));
        if (controller.message?.message == StringSheet.holdStillGuide) {
          holdStillShownAt = DateTime.now();
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(holdStillShownAt, isNotNull);

      // Không bơm thêm frame nào nữa — chụp phải do timer tự kích hoạt.
      await Future<void>.delayed(const Duration(milliseconds: 3400));
      expect(controller.captureFlashTick, greaterThan(0),
          reason: 'timer phải tự chụp kể cả khi không còn frame nào tới');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
