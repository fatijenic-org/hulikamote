import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/scene_primitive.dart';
import 'package:hulikamote_dashboard/features/docs/domain/palette/doc_palette.dart';
import 'package:hulikamote_dashboard/features/docs/presentation/widgets/scene_painter.dart';

class TestRecordingCanvas implements Canvas {
  final List<String> calls = [];

  @override
  void drawRRect(RRect rrect, Paint paint) {
    calls.add('drawRRect: $rrect with color ${paint.color}');
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    calls.add('drawLine: $p1 -> $p2 with color ${paint.color}');
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    calls.add('drawCircle: $c (r=$radius) with color ${paint.color}');
  }

  @override
  void drawPath(Path path, Paint paint) {
    calls.add('drawPath: with color ${paint.color}');
  }

  @override
  void save() {
    calls.add('save');
  }

  @override
  void restore() {
    calls.add('restore');
  }

  @override
  void scale(double sx, [double? sy]) {
    calls.add('scale: $sx, $sy');
  }

  @override
  void translate(double dx, double dy) {
    calls.add('translate: $dx, $dy');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('DocScenePainter', () {
    test('paints all primitive types in correct order on recording canvas', () {
      final scene = DocScene(
        w: 330.0,
        h: 170.0,
        aria: 'Test Scene',
        primitives: [
          const RectPrimitive(x: 6.0, y: 6.0, w: 318.0, h: 158.0, rx: 10.0, role: 'road', dash: false),
          const LinePrimitive(x1: 50.0, y1: 55.0, x2: 270.0, y2: 55.0, role: 'a-ok', arrow: true, dash: false, width: 3.2),
          const CirclePrimitive(cx: 160.0, cy: 50.0, r: 5.0, role: 'per', fillSurface: false),
          const PolygonPrimitive(points: [Offset(24.0, 26.0), Offset(306.0, 26.0), Offset(306.0, 144.0)], role: 'zone'),
          const PolylinePrimitive(points: [Offset(30.0, 85.0), Offset(38.0, 97.0)], role: 'path', dash: true),
          const PathPrimitive(d: 'M165 150 Q165 96 85 86', role: 'path', dash: false, width: 2.4),
          const TextPrimitive(x: 160.0, y: 46.0, text: 'legal direction', role: 'sk', anchor: 'middle'),
        ],
      );

      final canvas = TestRecordingCanvas();
      final painter = DocScenePainter(scene: scene, palette: DocPalette.dark);

      painter.paint(canvas, const Size(330, 170));

      expect(canvas.calls, contains('save'));
      expect(canvas.calls, contains('restore'));

      // Check that rect (road) was drawn first
      final firstDrawIndex = canvas.calls.indexWhere((c) => c.startsWith('drawRRect'));
      expect(firstDrawIndex, greaterThan(0));

      // Check line with arrow drawn
      final lineDrawIndex = canvas.calls.indexWhere((c) => c.startsWith('drawLine'));
      expect(lineDrawIndex, greaterThan(firstDrawIndex));

      // Check circle drawn
      final circleDrawIndex = canvas.calls.indexWhere((c) => c.startsWith('drawCircle'));
      expect(circleDrawIndex, greaterThan(lineDrawIndex));

      // Check multiple paths were drawn (arrowhead, polygon, polyline, path)
      final pathCalls = canvas.calls.where((c) => c.startsWith('drawPath')).toList();
      expect(pathCalls.length, greaterThanOrEqualTo(3));
    });

    test('shouldRepaint returns true when scene or palette changes', () {
      final scene1 = const DocScene(w: 100, h: 100, aria: '', primitives: []);
      final scene2 = const DocScene(w: 200, h: 200, aria: '', primitives: []);

      final p1 = DocScenePainter(scene: scene1, palette: DocPalette.light);
      final p2 = DocScenePainter(scene: scene1, palette: DocPalette.dark);
      final p3 = DocScenePainter(scene: scene2, palette: DocPalette.light);
      final p4 = DocScenePainter(scene: scene1, palette: DocPalette.light);

      expect(p1.shouldRepaint(p4), isFalse);
      expect(p1.shouldRepaint(p2), isTrue);
      expect(p1.shouldRepaint(p3), isTrue);
    });
  });
}
