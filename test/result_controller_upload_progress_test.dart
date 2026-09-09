import 'dart:io';

import 'package:aicycle_on_device/src/config/aicycle_config.dart';
import 'package:aicycle_on_device/src/config/config_holder.dart';
import 'package:aicycle_on_device/src/features/folder_result/domain/entity/inspection_result.dart';
import 'package:aicycle_on_device/src/features/folder_result/domain/repository/result_repository.dart';
import 'package:aicycle_on_device/src/features/folder_result/presentation/controller/result_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeResultRepository implements ResultRepository {
  @override
  Future<Map<String, dynamic>?> uploadAnglePhoto({
    required int angleId,
    required Uint8List photoBytes,
    required int photoIndex,
    int? imageOrder,
  }) async =>
      null;

  @override
  Future<List<VehiclePart>> fetchResult() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final repository = _FakeResultRepository();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('result_controller_test_');
    AICycleConfigHolder.init(
      AICycleConfig(
        generalConfig: GeneralConfig(
          apiToken: 'test_token',
          documentId: 'test_session',
          documentName: 'test',
          organization: AiCycleOrg.aicycle,
        ),
        carInformation: CarInformation(
          companyName: 'toyota',
          modelName: 'vios',
        ),
        modelConfig: ModelConfig(),
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('yolo_single_image_channel'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        return tempDir.path;
      },
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('tất cả ảnh anchor đã upload xong từ trước -> hoàn thành tức thì',
      () async {
    // Giả lập 2 ảnh nhưng file trên disk đã bị worker xoá sau khi upload thành công
    final photo1 = '${tempDir.path}/p1.jpg';
    final photo2 = '${tempDir.path}/p2.jpg';

    final controller = ResultController(
      sessionId: 'test_session',
      capturedPhotos: {
        0: [photo1, photo2],
      },
      repository: repository,
      fetchResultAfterUpload: false,
    );

    expect(controller.totalCount, 0);
    expect(controller.uploadedCount, 0);

    await controller.start();

    expect(controller.totalCount, 2);
    expect(controller.uploadedCount, 2);
    expect(controller.uploadProgress, 1.0);
    expect(controller.status, ResultStatus.success);

    controller.dispose();
  });

  test('ảnh đang upload dở -> cập nhật đúng k/N và hoàn tất khi file được xoá',
      () async {
    // 3 ảnh: 1 ảnh đã upload (file không tồn tại), 2 ảnh còn tồn tại trên disk
    final file1 = File('${tempDir.path}/p1.jpg'); // đã xoá (không tạo)
    final file2 = File('${tempDir.path}/p2.jpg')..writeAsStringSync('dummy2');
    final file3 = File('${tempDir.path}/p3.jpg')..writeAsStringSync('dummy3');

    final controller = ResultController(
      sessionId: 'test_session',
      capturedPhotos: {
        0: [file1.path, file2.path],
        1: [file3.path],
      },
      repository: repository,
      fetchResultAfterUpload: false,
    );

    final recordedProgress = <int>[];
    controller.addListener(() {
      recordedProgress.add(controller.uploadedCount);
    });

    final startFuture = controller.start();

    // Ban đầu: tổng 3 ảnh, 1 ảnh đã xong -> uploadedCount = 1
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.totalCount, 3);
    expect(controller.uploadedCount, 1);
    expect(controller.status, ResultStatus.uploading);

    // Giả lập worker upload xong file2 và xoá file
    file2.deleteSync();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(controller.uploadedCount, 2);

    // Giả lập worker upload xong file3 và xoá file
    file3.deleteSync();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await startFuture;

    expect(controller.uploadedCount, 3);
    expect(controller.totalCount, 3);
    expect(controller.status, ResultStatus.success);

    controller.dispose();
  });
}
