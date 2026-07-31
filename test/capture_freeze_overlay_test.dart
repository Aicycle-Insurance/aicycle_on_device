import 'dart:io';
import 'dart:typed_data';

import 'package:aicycle_on_device/src/core/utils/screen_utils.dart';
import 'package:aicycle_on_device/src/features/camera/presentation/widgets/capture_freeze_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1x1 JPEG đủ để `Image.file` decode được trong test.
const _jpeg1x1 = <int>[
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
  0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
  0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
  0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
  0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
  0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00,
  0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x08, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x37, 0xFF,
  0xD9,
];

const _hold = Duration(milliseconds: 700);
const _shrink = Duration(milliseconds: 450);

void main() {
  late Directory tempDir;
  late String photoPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('freeze_overlay_test');
    photoPath = '${tempDir.path}/photo.jpg';
    File(photoPath).writeAsBytesSync(Uint8List.fromList(_jpeg1x1));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Dựng overlay trong một Stack full-screen như ở CameraScreen.
  Widget host({
    required int tick,
    required String? photoPath,
    required DateTime? startedAt,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          ScreenUtil.init(context, forcePortrait: true);
          return Stack(
            children: [
              Positioned.fill(
                child: CaptureFreezeOverlay(
                  tick: tick,
                  photoPath: photoPath,
                  startedAt: startedAt,
                  holdDuration: _hold,
                  shrinkDuration: _shrink,
                  topBarHeight: 83,
                  bottomBarHeight: 115,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Rect imageRect(WidgetTester tester) =>
      tester.getRect(find.byType(RotatedBox).first);

  testWidgets('không vẽ gì khi chưa có lượt chụp nào', (tester) async {
    await tester.pumpWidget(
      host(tick: 0, photoPath: null, startedAt: null),
    );
    expect(find.byType(RotatedBox), findsNothing);
  });

  testWidgets('tick đổi → dừng hình full-screen rồi co về góc dưới trái',
      (tester) async {
    await tester.pumpWidget(host(tick: 0, photoPath: null, startedAt: null));
    await tester.pumpWidget(
      host(tick: 1, photoPath: photoPath, startedAt: DateTime.now()),
    );
    await tester.pump();

    final screen = tester.getSize(find.byType(MaterialApp));

    // Pha 1: ảnh phủ đúng vùng preview (giữa top bar 83 và bottom bar 115).
    final start = imageRect(tester);
    expect(start.left, 0);
    expect(start.width, screen.width);
    expect(start.top, 83);
    expect(start.bottom, screen.height - 115);

    // Vẫn đang dừng hình ở giữa pha 1 — chưa co.
    await tester.pump(_hold - const Duration(milliseconds: 50));
    expect(imageRect(tester), start);

    // Pha 2: đang co nhỏ dần.
    await tester.pump(const Duration(milliseconds: 250));
    final mid = imageRect(tester);
    expect(mid.width, lessThan(start.width));
    expect(mid.height, lessThan(start.height));

    // Kết thúc: hạ cánh đúng ô thumbnail (48.w vuông, lề 16.w, giữa bottom bar).
    await tester.pump(const Duration(milliseconds: 249));
    final end = imageRect(tester);
    expect(end.width, closeTo(48.w, 0.5));
    expect(end.height, closeTo(48.w, 0.5));
    expect(end.left, closeTo(16.w, 0.5));
    expect(end.center.dy, closeTo(screen.height - 115 / 2, 0.5));

    // Hết hiệu ứng → overlay tự ẩn, nhường lại thumbnail thật.
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(RotatedBox), findsNothing);
  });

  testWidgets('bị dựng lại giữa lượt → chạy tiếp từ thời điểm đã trôi',
      (tester) async {
    // startedAt đã trôi hết pha dừng hình ⇒ mount xong là đang co nhỏ.
    final startedAt = DateTime.now().subtract(_hold);
    await tester.pumpWidget(
      host(tick: 7, photoPath: photoPath, startedAt: startedAt),
    );
    await tester.pump();

    final screen = tester.getSize(find.byType(MaterialApp));
    final rect = imageRect(tester);
    expect(find.byType(RotatedBox), findsOneWidget);
    expect(rect.width, lessThan(screen.width));

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RotatedBox), findsNothing);
  });

  testWidgets('lượt đã kết thúc từ trước → không chạy lại khi dựng lại',
      (tester) async {
    await tester.pumpWidget(host(
      tick: 3,
      photoPath: photoPath,
      startedAt: DateTime.now().subtract(const Duration(seconds: 5)),
    ));
    expect(find.byType(RotatedBox), findsNothing);
  });
}
