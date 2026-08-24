import 'package:aicycle_on_device/src/features/camera/presentation/controller/camera_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Các nhánh async trong luồng inspection chờ tới 10 s bằng `Future.delayed`
/// (không huỷ được). Nếu user rời màn camera giữa lúc chờ mà nhánh đó vẫn chạy
/// tiếp, nó sẽ gọi `notifyListeners()` VÀ mở Timer mới trên controller đã
/// dispose → `FlutterError: A CameraController was used after being disposed`.
///
/// Dùng [testWidgets] chứ không phải [test]: cần tua thời gian ảo cho hết nhịp
/// chờ, và testWidgets còn tự báo lỗi nếu còn Timer treo lúc kết thúc — chính
/// là triệu chứng thứ hai của lỗi này.
void main() {
  Map<String, dynamic> detectFrame() => {
        'type': 'detect',
        'modelId': 'detect',
        'fps': 10.0,
        'cameraFps': 30.0,
        'processingTimeMs': 12.0,
        'detections': [
          {
            'className': 'Móp/bẹp',
            'confidence': 0.9,
            'normalizedBox': {
              'left': 0.45,
              'top': 0.4,
              'right': 0.55,
              'bottom': 0.6,
            },
          },
        ],
      };

  CameraController scanningController() {
    return CameraController(sessionId: 's')
      ..startCapture()
      ..startDamageScanning();
  }

  testWidgets('dispose giữa nhịp chờ 10 s của "Thiếu tổn thất"',
      (tester) async {
    final controller = scanningController();
    // Đủ 5 frame liên tiếp để mở màn xác nhận.
    for (var i = 0; i < 6; i++) {
      controller.onStreamingData(detectFrame());
    }
    // Bấm "Thiếu tổn thất" → vào nhánh chờ 10 s không huỷ được.
    controller.rejectDamage();

    // User thoát màn camera ngay sau đó.
    controller.stopCamera();
    controller.dispose();

    // Tua hết nhịp chờ. Không được ném, và không được để lại Timer treo.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('dispose giữa nhịp chờ sau khi xác nhận tổn thất',
      (tester) async {
    final controller = scanningController();
    for (var i = 0; i < 6; i++) {
      controller.onStreamingData(detectFrame());
    }
    // Không await: confirmDamage tự chờ bên trong, ta cần dispose xen vào giữa.
    controller.confirmDamage();

    controller.stopCamera();
    controller.dispose();

    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('dispose ngay sau completeCurrentAngle', (tester) async {
    final controller = scanningController();
    controller.onStreamingData(detectFrame());
    controller.completeCurrentAngle();
    controller.stopCamera();
    controller.dispose();

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('frame tới sau dispose bị bỏ qua', (tester) async {
    final controller = scanningController();
    controller.stopCamera();
    controller.dispose();

    controller.onStreamingData(detectFrame());
    await tester.pump(const Duration(seconds: 11));
  });
}
