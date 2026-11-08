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
}
