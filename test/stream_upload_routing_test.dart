import 'dart:convert';
import 'dart:io';

import 'package:aicycle_on_device/src/config/aicycle_config.dart';
import 'package:aicycle_on_device/src/config/config_holder.dart';
import 'package:aicycle_on_device/src/core/upload/photo_upload_queue.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stream_routing_test_');
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
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('VBI org: anchor photo upload to VBI API with isCallEngine=true', () async {
    AICycleConfigHolder.init(
      AICycleConfig(
        generalConfig: GeneralConfig(
          apiToken: 'aic_token',
          documentId: 'vbi_session_123',
          documentName: 'vbi_doc',
          organization: AiCycleOrg.vbi,
          aicBaseUrl: 'https://claim-api.aicycle.ai',
        ),
        vbiConfig: VBIConfig(
          apiVersionCode: 'v1',
          apiUploadBaseUrl: 'https://vbi-upload.vn',
          authorityId: 'auth_123',
          signatureKey: 'sig_123',
          externalSessionId: 'ext_vbi_999',
          jobId: 'job_1',
          maHangMuc: 'hm_1',
          tenHangMuc: 'thm_1',
          departmentId: 'dept_1',
          userId: 'user_1',
          maTVV: 'tvv_1',
          source: 'src_1',
          btxKhoangCach: '1m',
          diaChi: 'Hanoi',
          sdk: 'sdk_vbi',
        ),
        carInformation: CarInformation(
          companyName: 'toyota',
          modelName: 'vios',
        ),
        modelConfig: ModelConfig(),
      ),
    );

    final anchorFile = File('${tempDir.path}/anchor_photo.jpg')
      ..writeAsStringSync('anchor_bytes');

    await PhotoUploadQueue.instance.enqueuePhoto(
      sessionId: 'vbi_session_123',
      angleId: 0,
      photoIndex: 0,
      filePath: anchorFile.path,
      imageOrder: 1,
      isCallEngine: true,
    );

    final queueFile =
        File('${tempDir.path}/aicycle_photo_cache/upload_queue.json');
    expect(queueFile.existsSync(), isTrue);

    final data = jsonDecode(queueFile.readAsStringSync()) as Map<String, dynamic>;
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    final anchorItem = items.first;

    expect(anchorItem['isCallEngine'], isTrue);
    expect(anchorItem['url'], 'https://vbi-upload.vn/api/v1/vbi4sales/Upload/upload-ai');
    expect(anchorItem['fileName'], '0_0.jpg');
    expect(anchorItem['fields']['so_id_hs'], 'vbi_session_123');
    expect(anchorItem['fields']['isCallEngine'], 'true');
  });

  test('AICycle org: anchor photo upload to AICycle API with isCallEngine=true', () async {
    AICycleConfigHolder.init(
      AICycleConfig(
        generalConfig: GeneralConfig(
          apiToken: 'aic_token',
          documentId: 'aic_session_456',
          documentName: 'doc',
          organization: AiCycleOrg.aicycle,
          aicBaseUrl: 'https://claim-api.aicycle.ai',
        ),
        carInformation: CarInformation(
          companyName: 'honda',
          modelName: 'city',
        ),
        modelConfig: ModelConfig(),
      ),
    );

    final anchorFile = File('${tempDir.path}/anchor_aic.jpg')
      ..writeAsStringSync('anchor_bytes_aic');

    await PhotoUploadQueue.instance.enqueuePhoto(
      sessionId: 'aic_session_456',
      angleId: 1,
      photoIndex: 0,
      filePath: anchorFile.path,
      imageOrder: 1,
      isCallEngine: true,
    );

    final queueFile =
        File('${tempDir.path}/aicycle_photo_cache/upload_queue.json');
    expect(queueFile.existsSync(), isTrue);

    final data = jsonDecode(queueFile.readAsStringSync()) as Map<String, dynamic>;
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    final anchorItem = items.first;

    expect(anchorItem['isCallEngine'], isTrue);
    expect(anchorItem['url'], 'https://claim-api.aicycle.ai/insurance/v2/claim-me/upload');
    expect(anchorItem['fileName'], '1_0.jpg');
    expect(anchorItem['fields']['claimFolderId'], 'aic_session_456');
    expect(anchorItem['fields']['isCallEngine'], 'true');
  });

  test('enqueueExistingPhotos always sets isCallEngine to true', () async {
    AICycleConfigHolder.init(
      AICycleConfig(
        generalConfig: GeneralConfig(
          apiToken: 'aic_token',
          documentId: 'aic_session_456',
          documentName: 'doc',
          organization: AiCycleOrg.aicycle,
        ),
        carInformation: CarInformation(
          companyName: 'honda',
          modelName: 'city',
        ),
        modelConfig: ModelConfig(),
      ),
    );

    final photo1 = File('${tempDir.path}/p1.jpg')..writeAsStringSync('img1');
    final photo2 = File('${tempDir.path}/p2.jpg')..writeAsStringSync('img2');

    await PhotoUploadQueue.instance.enqueueExistingPhotos('aic_session_456', {
      0: [photo1.path],
      1: [photo2.path],
    });

    final queueFile =
        File('${tempDir.path}/aicycle_photo_cache/upload_queue.json');
    final data = jsonDecode(queueFile.readAsStringSync()) as Map<String, dynamic>;
    final items = (data['items'] as List).cast<Map<String, dynamic>>();

    expect(items.length, 2);
    for (final item in items) {
      expect(item['isCallEngine'], isTrue);
      expect(item['fileName'].toString().startsWith('stream_'), isFalse);
      expect(item['fields']['isCallEngine'], 'true');
    }
  });
}
