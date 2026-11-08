import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/monitoring/domain/models/detection.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/road_learning_chip.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/video_feed_widget.dart';

/// The Live Monitor learns the road paint by itself: the feed message carries the learner's status and the learned
/// zones, the picture draws them, and a chip says what is going on.
Map<String, dynamic> _frame({Map<String, dynamic>? road, List<Map<String, dynamic>>? zones}) => {
  'type': 'frame',
  'mock': false,
  'detections': <dynamic>[],
  'timestamp': '2026-11-07T00:00:00Z',
  'road': ?road,
  'road_zones': ?zones,
};

const _crosswalk = {
  'violation': 'pedestrian_lane',
  'polygon': [
    [200, 300],
    [600, 300],
    [600, 400],
    [200, 400],
  ],
  'line': null,
  'best_effort': false,
};

Future<ui.Image> _render(List<RoadZone> zones) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  BoundingBoxPainter(const [], roadZones: zones).paint(canvas, const Size(1280, 720));
  return recorder.endRecording().toImage(1280, 720);
}

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

Widget _chip(Map<String, dynamic> road, {VoidCallback? onRelearn, VoidCallback? onForget}) => MaterialApp(
  home: Scaffold(body: RoadLearningChip(road: road, onRelearn: onRelearn, onForget: onForget)),
);

void main() {
  group('the feed message', () {
    test('carries the road status and the learned zones', () {
      final f = VideoFrame.fromJson(_frame(
        road: {'state': 'learning', 'message': 'Learning the road 23/40 s', 'progress_s': 23.0, 'need_s': 40.0},
        zones: [
          _crosswalk,
          {
            'violation': 'red_light',
            'polygon': [
              [0, 600],
              [1280, 600],
              [1280, 640],
            ],
            'line': [
              [0, 620],
              [1280, 620],
            ],
            'best_effort': true,
            'hint': true,
          },
        ],
      ));
      expect(f.road!['message'], 'Learning the road 23/40 s');
      expect(f.roadZones.length, 2);
      expect(f.roadZones.first.polygon.first, [200.0, 300.0]);
      expect(f.roadZones.first.bestEffort, false);
      expect(f.roadZones.first.label, 'Crosswalk (learned)');
      expect(f.roadZones.last.bestEffort, true);
      expect(f.roadZones.last.hint, true);
      expect(f.roadZones.last.line.length, 2);
      expect(f.roadZones.last.label, 'Stop line (hint only)');
      expect(RoadZone.fromJson({'violation': 'red_light', 'polygon': [], 'best_effort': true}).label,
          'Stop line (learned, best effort)');
    });

    test('an older backend without those fields still parses', () {
      final f = VideoFrame.fromJson(_frame());
      expect(f.road, isNull);
      expect(f.roadZones, isEmpty);
    });
  });

  group('the picture', () {
    test('tints a learned crosswalk and leaves the rest of the road alone', () async {
      final image = await _render([RoadZone.fromJson(Map<String, dynamic>.from(_crosswalk))]);
      final inside = await _pixel(image, 400, 350);
      final outside = await _pixel(image, 900, 150);
      expect(inside.a, greaterThan(0));
      expect(outside.a, 0);
    });

    test('draws nothing without learned zones', () async {
      final image = await _render(const []);
      expect((await _pixel(image, 400, 350)).a, 0);
    });
  });

  group('the status chip', () {
    testWidgets('shows the learning progress', (tester) async {
      await tester.pumpWidget(_chip({
        'state': 'learning',
        'message': 'Learning the road 23/40 s',
        'progress_s': 23.0,
        'need_s': 40.0,
      }));
      expect(find.text('Learning the road 23/40 s'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('road-progress')));
      expect(bar.value, closeTo(23 / 40, 0.001));
    });

    testWidgets('says what was learned, and that lines are best effort', (tester) async {
      await tester.pumpWidget(_chip({
        'state': 'ready',
        'message': 'Road learned: 1 crosswalk, 1 stop line',
        'best_effort': ['red_light'],
      }));
      expect(find.textContaining('Road learned: 1 crosswalk, 1 stop line'), findsOneWidget);
      expect(find.textContaining('best effort'), findsOneWidget);
      expect(find.byKey(const ValueKey('road-progress')), findsNothing);
    });

    testWidgets('shows the reason when the road could not be read', (tester) async {
      await tester.pumpWidget(_chip({
        'state': 'refused',
        'message': 'Not enough traffic movement to find the road direction. Press Re-learn to try again.',
      }));
      expect(find.textContaining('Not enough traffic movement'), findsOneWidget);
    });

    testWidgets('Re-learn and Forget call back', (tester) async {
      var relearn = 0, forget = 0;
      await tester.pumpWidget(_chip(
        {'state': 'ready', 'message': 'Road learned: 1 crosswalk'},
        onRelearn: () => relearn++,
        onForget: () => forget++,
      ));
      await tester.tap(find.byKey(const ValueKey('road-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Re-learn the road'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('road-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget what was learned'));
      await tester.pumpAndSettle();
      expect((relearn, forget), (1, 1));
    });
  });
}
