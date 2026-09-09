import 'dart:io';

import 'package:aicycle_on_device/src/config/aicycle_config.dart';
import 'package:aicycle_on_device/src/config/config_holder.dart';
import 'package:aicycle_on_device/src/core/constants/string_sheet.dart';
import 'package:aicycle_on_device/src/features/camera/presentation/controller/camera_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gallery_inject_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('yolo_single_image_channel'),
      (call) async => null,
    );

    AICycleConfigHolder.init(
      AICycleConfig(
        generalConfig: GeneralConfig(
          apiToken: 'test_token',
          documentId: 'debug_session_123',
          organization: AiCycleOrg.aicycle,
          debugMode: true,
        ),
        modelConfig: ModelConfig(),
        carInformation: CarInformation(
          companyName: 'toyota',
          modelName: 'vios',
        ),
      ),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('When debugMode is false, injectGalleryPhotoAsAutoCapture does nothing',
      () async {
    final controller = CameraController(
      sessionId: 'debug_session_123',
      debugMode: false,
    );

    final dummyFile = File('${tempDir.path}/sample.jpg');
    await dummyFile.writeAsBytes([1, 2, 3, 4]);

    await controller.injectGalleryPhotoAsAutoCapture(dummyFile.path);

    expect(controller.capturedPhotos.isEmpty, isTrue);
    expect(controller.completedSegments.isEmpty, isTrue);
    controller.dispose();
  });

  test(
      'When debugMode is true, injectGalleryPhotoAsAutoCapture copies photo and progresses session',
      () async {
    final controller = CameraController(
      sessionId: 'debug_session_123',
      debugMode: true,
    );

    final dummyFile = File('${tempDir.path}/sample.jpg');
    await dummyFile.writeAsBytes([1, 2, 3, 4]);

    final future = controller.injectGalleryPhotoAsAutoCapture(dummyFile.path);
    await future;

    // Ảnh đã được lưu vào góc active (mặc định 0)
    expect(controller.capturedPhotos.containsKey(0), isTrue);
    expect(controller.capturedPhotos[0]!.length, equals(1));
    expect(File(controller.capturedPhotos[0]!.first).existsSync(), isTrue);

    // Góc 0 đã được đánh dấu hoàn thành
    expect(controller.completedSegments.contains(0), isTrue);

    // Message và phase đã chuyển sang hướng dẫn soi tổn thất (sau 3s thông báo thành công)
    expect(controller.inspectionPhase, equals(InspectionPhase.panoramicGuide));
    expect(controller.message?.message, equals(StringSheet.inspectDamageGuide));

    controller.dispose();
  });

  test(
      'When in inspection phase, injectGalleryPhoto behaves as damage photo capture',
      () async {
    final controller = CameraController(
      sessionId: 'debug_session_123',
      debugMode: true,
    );

    final dummyFile1 = File('${tempDir.path}/damage1.jpg');
    await dummyFile1.writeAsBytes([1, 2, 3, 4]);

    final dummyFile2 = File('${tempDir.path}/damage2.jpg');
    await dummyFile2.writeAsBytes([5, 6, 7, 8]);

    // Bắt đầu bằng việc vào phase inspection (ví dụ sau khi quét tổn thất)
    controller.startDamageScanning();
    expect(controller.inspectionPhase, equals(InspectionPhase.scanning));

    // Lần 1: Inject ảnh tổng quan tổn thất
    await controller.injectGalleryPhoto(dummyFile1.path);

    expect(controller.capturedPhotos[0]!.length, equals(1));
    expect(controller.inspectionPhase, equals(InspectionPhase.detailGuide));
    // Sau khi tooltip "Chụp thành công" hiển thị đủ 3s, message chuyển sang detailPhotoGuide
    await Future.delayed(const Duration(seconds: 3));
    expect(controller.message?.message, equals(StringSheet.detailPhotoGuide));

    // Lần 2: Inject ảnh chi tiết tổn thất
    await controller.injectGalleryPhoto(dummyFile2.path);

    expect(controller.capturedPhotos[0]!.length, equals(2));
    // Sau khi chụp chi tiết, phase chuyển sang continueOrChange
    expect(controller.inspectionPhase, equals(InspectionPhase.continueOrChange));
    // Sau khi tooltip "Chụp thành công" hiển thị đủ 3s, message chuyển sang continueToNextDamage
    await Future.delayed(const Duration(seconds: 3));
    expect(
        controller.message?.message, equals(StringSheet.continueToNextDamage));

    controller.dispose();
  });
}
