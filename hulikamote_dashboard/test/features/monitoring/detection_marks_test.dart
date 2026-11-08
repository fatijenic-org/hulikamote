import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/monitoring/domain/models/detection.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/video_feed_widget.dart';

/// The live overlay shows WHY a vehicle was flagged: the backend sends boxes in `marks`, the painter draws them red.
Map<String, dynamic> _json({List<Map<String, dynamic>>? marks}) => {
  'class': 'no_helmet',
  'is_violator': true,
  'confidence': 0.9,
  'track_id': 7,
  'bbox': [100, 100, 200, 200],
  'marks': ?marks,
};

Future<ui.Image> _render(List<Detection> detections) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // A 1280 x 720 stream drawn on a 1280 x 720 canvas: one stream pixel = one canvas pixel.
  BoundingBoxPainter(detections).paint(canvas, const Size(1280, 720));
  return recorder.endRecording().toImage(1280, 720);
}

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

void main() {
  test('marks are read from the stream and a missing field means none', () {
    final withMarks = Detection.fromJson(_json(marks: [
      {'bbox': [120, 110, 40, 40], 'label': 'NO HELMET'},
      {'bbox': [160, 150, 30, 30]},
    ]));
    expect(withMarks.marks.length, 2);
    expect(withMarks.marks.first.bbox, [120, 110, 40, 40]);
    expect(withMarks.marks.first.label, 'NO HELMET');
    expect(withMarks.marks.last.label, '');
    expect(Detection.fromJson(_json()).marks, isEmpty);
  });

  testWidgets('the painter draws a flagged vehicle\'s marks in red, and nothing extra without them', (tester) async {
    await tester.runAsync(() async {
      final plain = Detection.fromJson(_json());
      final marked = Detection.fromJson(_json(marks: [
        {'bbox': [400, 300, 80, 80], 'label': ''},
      ]));
      // The mark's top edge is at y = 300 (3 px stroke): a pixel on it is red only when the mark was drawn.
      final without = await _pixel(await _render([plain]), 440, 300);
      final with_ = await _pixel(await _render([marked]), 440, 300);
      expect(with_.r > 0.9 && with_.g < 0.45 && with_.b < 0.45, isTrue, reason: 'mark edge should be red, got $with_');
      expect(without.a, 0.0, reason: 'no mark, nothing drawn there');
    });
  });
}
