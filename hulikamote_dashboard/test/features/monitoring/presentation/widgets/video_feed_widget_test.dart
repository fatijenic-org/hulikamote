import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/video_feed_widget.dart';

void main() {
  testWidgets('Shows disconnected view when stream is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VideoFeedWidget())),
    );
    expect(find.byIcon(Icons.videocam_off), findsOneWidget);
  });

  testWidgets('Shows MOCK badge and detection on frame arrival', (tester) async {
    final controller = StreamController<String>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VideoFeedWidget(stream: controller.stream)),
    ));

    final frameJson = jsonEncode({
      'type': 'frame',
      'mock': true,
      'frame_width': 200, // boxes are only drawn once the picture size is known
      'frame_height': 100,
      'detections': [
        {'class': 'no_helmet', 'confidence': 0.91, 'bbox': [10, 10, 50, 50]}
      ],
      'timestamp': '2026-01-01T00:00:00Z',
    });
    controller.add(frameJson);
    await tester.pump();

    expect(find.text('MOCK'), findsOneWidget);
    // box labels are painted on a canvas (not Text widgets): check that the box painter is on screen
    expect(find.byWidgetPredicate((w) => w is CustomPaint && '${w.painter.runtimeType}' == 'BoundingBoxPainter'),
        findsOneWidget);
    await controller.close();
  });

  testWidgets('No detections shows no badge', (tester) async {
    final controller = StreamController<String>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VideoFeedWidget(stream: controller.stream)),
    ));

    final frameJson = jsonEncode({
      'type': 'frame',
      'mock': true,
      'detections': [],
      'timestamp': '2026-01-01T00:00:00Z',
    });
    controller.add(frameJson);
    await tester.pump();

    expect(find.textContaining('NO HELMET'), findsNothing);
    await controller.close();
  });

  testWidgets('A camera status message is ignored, not shown as an error', (tester) async {
    final controller = StreamController<String>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VideoFeedWidget(stream: controller.stream)),
    ));
    controller.add(jsonEncode({'type': 'status', 'camera': {'state': 'offline'}}));
    await tester.pump();
    expect(find.textContaining('Error parsing frame'), findsNothing);
    await controller.close();
  });

  String frame(int w, int h, {bool box = false, String transport = 'hls'}) => jsonEncode({
        'type': 'frame',
        'transport': transport,
        'frame_width': w,
        'frame_height': h,
        'detections': box
            ? [
                {'class': 'car', 'confidence': 0.9, 'bbox': [10, 10, 50, 50]}
              ]
            : [],
        'timestamp': '2026-01-01T00:00:00Z',
      });

  bool hasBoxes(WidgetTester tester) =>
      tester.any(find.byWidgetPredicate((w) => w is CustomPaint && '${w.painter.runtimeType}' == 'BoundingBoxPainter'));

  group('the picture keeps its own shape', () {
    for (final (name, w, h, box) in [
      ('4:3 in a wide, flat space', 640, 480, const Size(1000, 300)),
      ('16:9 in a tall space', 1280, 720, const Size(500, 900)),
      ('a square picture', 720, 720, const Size(1000, 600)),
    ]) {
      testWidgets(name, (tester) async {
        final controller = StreamController<String>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: box.width, height: box.height, child: VideoFeedWidget(stream: controller.stream))),
          ),
        ));
        controller.add(frame(w, h));
        await tester.pump();
        final shown = tester.getSize(find.byType(AspectRatio));
        expect(shown.width / shown.height, closeTo(w / h, 0.01));          // never stretched to fit the space
        await controller.close();
      });
    }
  });

  group('the boxes wait for the picture', () {
    testWidgets('with a delay, boxes appear only after it has passed', (tester) async {
      final controller = StreamController<String>();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: VideoFeedWidget(stream: controller.stream, boxDelayMs: 300))));
      controller.add(frame(200, 100, box: true));
      await tester.pump();
      expect(hasBoxes(tester), isFalse);                                    // arrived, but the picture is not there yet
      await tester.pump(const Duration(milliseconds: 150));
      expect(hasBoxes(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 250));
      expect(hasBoxes(tester), isTrue);                                     // now the picture has caught up
      await tester.pumpWidget(const SizedBox());                            // leaving stops the timer
      await controller.close();
    });

    testWidgets('a picture sent with the boxes needs no delay, whatever the setting', (tester) async {
      final controller = StreamController<String>();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: VideoFeedWidget(stream: controller.stream, boxDelayMs: 2000))));
      controller.add(frame(200, 100, box: true, transport: 'jpeg'));
      await tester.pump();
      expect(hasBoxes(tester), isTrue);
      await controller.close();
    });

    testWidgets('without a delay, boxes show at once (the other screens are unchanged)', (tester) async {
      final controller = StreamController<String>();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: VideoFeedWidget(stream: controller.stream))));
      controller.add(frame(200, 100, box: true));
      await tester.pump();
      expect(hasBoxes(tester), isTrue);
      await controller.close();
    });
  });
}
