import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/replay_boxes.dart';

/// The replay's boxes: read from boxes.json, found by video time, painted thin at any zoom and kept inside the picture.
Map<String, dynamic> _json() => {
  'w': 1920,
  'h': 1080,
  'fps': 10,
  'frames': [
    [
      {'box': [100, 100, 200, 120], 'color': [0, 255, 0], 'lines': ['ABC 1234 - CAR']},
    ],
    [
      {'box': [1800, -40, 300, 200], 'color': [255, 0, 0], 'lines': ['WRONG LANE', 'VEHICLE'], 'plate': [1850, 100, 60, 20]},
      {'note': '3 RIDERS (max 2)', 'at': [1800, 160], 'color': [255, 0, 0]},
    ],
  ],
};

void main() {
  timerTests();
  test('is read from the file and found by time', () {
    final b = ReplayBoxes.fromJson(_json())!;
    expect(b.frames.length, 2);
    expect(b.at(0.0).single.lines, ['ABC 1234 - CAR']);
    expect(b.at(0.1).length, 2); // frame 1 starts at 0.1 s at 10 fps
    expect(b.at(0.1).first.color, const Color(0xFFFF0000));
    expect(b.at(5), isEmpty); // past the end
    expect(b.at(-1), isEmpty);
    expect(ReplayBoxes.fromJson({'w': 0}), isNull);
    expect(ReplayBoxes.fromJson('nope'), isNull);
  });

  test('paints a vehicle that is half outside the picture, at zoom 1 and zoomed in, without failing', () {
    final b = ReplayBoxes.fromJson(_json())!;
    final zoom = TransformationController();
    final seconds = ValueNotifier<double>(0.1);
    final painter = ReplayBoxesPainter(boxes: b, seconds: seconds, zoom: zoom);
    for (final z in [1.0, 6.0]) {
      zoom.value = Matrix4.diagonal3Values(z, z, 1);
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(960, 540));
      recorder.endRecording();
    }
  });
}

/// The parking stopwatch: a chip on the bottom edge of the vehicle's box, next to the normal label (it does not replace it).
void timerTests() {
  test('a stopwatch spec is read and painted without touching the vehicle label', () {
    final b = ReplayBoxes.fromJson({
      'w': 1920,
      'h': 1080,
      'fps': 10,
      'frames': [
        [
          {'box': [100, 100, 200, 120], 'color': [255, 0, 0], 'lines': ['ILLEGAL PARKING', 'ABC 1234 - CAR']},
          {'timer': 'PARKED 0:07 / 0:10', 'box': [100, 100, 200, 120], 'color': [255, 165, 0], 'lines': <String>[]},
        ],
      ],
    })!;
    final specs = b.at(0.0);
    expect(specs[0].lines, ['ILLEGAL PARKING', 'ABC 1234 - CAR']);
    expect(specs[0].timer, isNull);
    expect(specs[1].timer, 'PARKED 0:07 / 0:10');
    final painter = ReplayBoxesPainter(boxes: b, seconds: ValueNotifier<double>(0.0), zoom: TransformationController());
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(960, 540));
    recorder.endRecording();
  });
}
