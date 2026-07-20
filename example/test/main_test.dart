import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('upload tab shows its empty state on a narrow phone', (
    tester,
  ) async {
    await _setPhoneViewport(tester);
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Ảnh đã tải'));
    await tester.pumpAndSettle();

    expect(find.text('Chưa có phản hồi upload'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload responses render in a maximum two-column grid', (
    tester,
  ) async {
    await _setPhoneViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: ExampleHomePage(
          initialUploadResponses: [
            {
              'response_code': '00',
              'response_message': 'SUCCESS',
              'data': {
                'status': '200',
                'typeResponse': 'SUCCESS',
                'description': 'Ảnh hợp lệ',
                'imageRoot': 'https://example.invalid/original.jpg',
                'imageAI': 'https://example.invalid/ai.jpg',
                'imageId': 128576,
              },
            },
            {
              'uploaded': true,
              'statusCode': 200,
              'rawBody':
                  '{"response_code":"00","response_message":"Dữ liệu trả về trống","data":{"status":"400","typeResponse":"ERROR","message":"Ảnh chụp qua màn hình. Vui lòng chụp lại","description":"Ảnh chụp qua màn hình","imageRoot":"https://example.invalid/rejected.jpg","imageAI":null,"imageId":128577,"carParts":[]}}',
            },
          ],
        ),
      ),
    );

    await tester.tap(find.text('Ảnh đã tải (2)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ảnh #128576'), findsOneWidget);
    expect(find.text('Upload lỗi'), findsNothing);
    expect(
      find.text('HTTP 400: Ảnh chụp qua màn hình. Vui lòng chụp lại'),
      findsOneWidget,
    );

    final imageUrls = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => (image.image as NetworkImage).url);
    expect(
      imageUrls,
      containsAll([
        'https://example.invalid/original.jpg',
        'https://example.invalid/rejected.jpg',
      ]),
    );

    final errorText = tester.widget<Text>(
      find.text('HTTP 400: Ảnh chụp qua màn hình. Vui lòng chụp lại'),
    );
    expect(errorText.style?.color, const Color(0xFFC62828));

    final rejectedImage = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is NetworkImage &&
          (widget.image as NetworkImage).url ==
              'https://example.invalid/rejected.jpg',
    );
    expect(rejectedImage, findsOneWidget);
    expect(tester.getSize(rejectedImage).height, greaterThan(80));

    final cards = find.byType(Card);
    expect(cards, findsNWidgets(2));
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    expect(first.top, second.top);
    expect(first.left, lessThan(second.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('aicycle success and error responses both render images', (
    tester,
  ) async {
    await _setPhoneViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: ExampleHomePage(
          initialUploadResponses: [
            {
              'status': 'success',
              'isPhotoValid': true,
              'errorCodeFromEngine': 0,
              'message': '',
              'imageId': 128586,
              'result': {
                'imgUrl': 'https://example.invalid/aicycle-original.jpg',
                'imgDrawUrl': 'https://example.invalid/aicycle-drawn.jpg',
                'extraInfor': {'additionalCornerInfor': '45° Trái - Trước'},
              },
              'errorLevel': 'success',
            },
            {
              'errorCodeFromEngine': 84680,
              'message': 'Ảnh chụp qua màn hình. Vui lòng chụp lại',
              'imageId': 128587,
              'result': {
                'imgUrl': 'https://example.invalid/aicycle-rejected.jpg',
              },
              'errorLevel': 'error',
            },
          ],
        ),
      ),
    );

    await tester.tap(find.text('Ảnh đã tải (2)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('45° Trái - Trước'), findsOneWidget);
    expect(
      find.text('Ảnh chụp qua màn hình. Vui lòng chụp lại'),
      findsOneWidget,
    );

    final imageUrls = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => (image.image as NetworkImage).url);
    expect(
      imageUrls,
      containsAll([
        'https://example.invalid/aicycle-original.jpg',
        'https://example.invalid/aicycle-rejected.jpg',
      ]),
    );
    expect(
      imageUrls,
      isNot(contains('https://example.invalid/aicycle-drawn.jpg')),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setPhoneViewport(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
}
