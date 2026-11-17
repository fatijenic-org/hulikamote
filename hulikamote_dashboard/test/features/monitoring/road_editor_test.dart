import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/monitoring/domain/models/detection.dart';
import 'package:hulikamote_dashboard/features/monitoring/domain/models/road_detect.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/road_zone_editor.dart';

/// The road editor after "Detect road": shapes of any number of points (so a curve is possible), lines, directions.
const _size = Size(1280, 720);

final _road = RoadArea(
  id: 'road-1',
  kind: 'road',
  polygon: const [Offset(300, 100), Offset(900, 100), Offset(900, 700), Offset(300, 700)],
  flow: 'in',
  arrow: const [Offset(600, 200), Offset(600, 500)],
);
const _solid = RoadArea(id: 'solid-1', kind: 'solid_line', polygon: [Offset(100, 600), Offset(250, 400), Offset(300, 150)]);

late List<RoadArea> _areas;

Future<void> _pump(WidgetTester tester, List<RoadArea> initial) async {
  _areas = initial;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1100,
        height: 760,
        child: StatefulBuilder(
          builder: (context, setState) => RoadZoneEditor(
            frame: null,
            size: _size,
            areas: _areas,
            onChanged: (a) => setState(() => _areas = a),
            onReset: () {},
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Where a point of the picture is on the screen.
Offset _at(WidgetTester tester, Offset frame) {
  final box = tester.getRect(find.byKey(const ValueKey('road-canvas')));
  return box.topLeft + frame * (box.width / _size.width);
}

Future<void> _tap(WidgetTester tester, Offset frame, {int buttons = kPrimaryButton}) async {
  await tester.tapAt(_at(tester, frame), buttons: buttons);
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _press(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _chooseDraw(WidgetTester tester, String item) async {
  await _press(tester, 'road-draw');
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.byKey(ValueKey(item)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100)); // the menu closes first, the tool starts a frame later
}

void main() {
  group('the shapes', () {
    test('a line is read from "line", an area from "polygon", and written back the same way', () {
      final line = RoadArea.fromJson({
        'id': 'solid-1',
        'kind': 'solid_line',
        'line': [[1, 2], [3, 4], [5, 6]],
        'style': 'double_yellow',
        'rule': true,
      });
      expect(line.isLine && line.polygon.length == 3 && line.style == 'double_yellow' && line.rule, true);
      expect(line.toJson()['line'], [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]]);
      expect(line.toJson().containsKey('polygon'), false);
      final stop = RoadArea.fromJson({'id': 's', 'kind': 'stop_line', 'line': [[0, 0], [9, 9]]});
      expect(stop.toJson().containsKey('style') || stop.toJson().containsKey('rule'), false);
      final side = RoadArea.fromJson({
        'id': 'road-1',
        'kind': 'road',
        'polygon': [[0, 0], [9, 0], [9, 9]],
        'flow': 'out',
        'arrow': [[4, 8], [4, 1]],
      });
      expect(side.flow, 'out');
      expect(side.toJson()['arrow'], [[4.0, 8.0], [4.0, 1.0]]);
      expect(side.copyWith(kind: 'sidewalk', clearFlow: true).toJson().containsKey('flow'), false);
    });

    test('the directions of the road are put into words, left to right', () {
      RoadArea side(String id, double x, String flow) =>
          RoadArea(id: id, kind: 'road', flow: flow, polygon: [Offset(x, 0), Offset(x + 10, 0), Offset(x + 10, 10)]);
      expect(roadDirectionsText([side('a', 700, 'out'), side('b', 100, 'in')]), 'Traffic: incoming on the left, outgoing on the right.');
      expect(roadDirectionsText([side('a', 100, 'in')]), contains('Only incoming traffic was seen'));
      expect(roadDirectionsText([const RoadArea(id: 'r', kind: 'road', polygon: [Offset.zero, Offset(1, 0), Offset(1, 1)])]), '');
    });

    test('the status says what the traffic showed', () {
      expect(RoadDetectStatus.fromJson({'state': 'done', 'flow': {'state': 'two_way', 'bands': 2}}).flowState, 'two_way');
      expect(RoadDetectStatus.fromJson({'state': 'done'}).flowState, 'none');
    });

    test('smoothing rounds the corners: an area doubles its points, a line keeps its ends', () {
      final area = RoadZoneEditor.smooth(_road.polygon, closed: true);
      expect(area.length, 8);
      expect(area.first, const Offset(300 * 0.75 + 900 * 0.25, 100));
      final line = RoadZoneEditor.smooth(_solid.polygon, closed: false);
      expect(line.length, 6);
      expect(line.first, _solid.polygon.first);
      expect(line.last, _solid.polygon.last);
    });

    test('a road area with a direction is drawn as the incoming or outgoing road', () {
      final incoming = RoadZone.fromJson({'violation': 'road', 'polygon': [[0, 0], [9, 0], [9, 9]], 'flow': 'in', 'arrow': [[4, 1], [4, 8]]});
      expect(incoming.flow, 'in');
      expect(incoming.arrow, [[4.0, 1.0], [4.0, 8.0]]);
      expect(incoming.label, 'Incoming road');
      expect(RoadZone.fromJson({'violation': 'road', 'polygon': [[0, 0], [9, 0], [9, 9]], 'flow': 'out'}).label, 'Outgoing road');
      expect(RoadZone.fromJson({'violation': 'road', 'polygon': [[0, 0], [9, 0], [9, 9]]}).label, 'Road');
    });
  });

  group('editing points', () {
    testWidgets('tap an edge of the selected shape to add a point there, then remove the point again', (tester) async {
      await _pump(tester, [_road]);
      await _tap(tester, const Offset(600, 400));                             // select it
      expect(find.byKey(const ValueKey('road-kind')), findsOneWidget);
      await _tap(tester, const Offset(600, 100));                             // on the top edge
      expect(_areas.single.polygon.length, 5);
      expect(_areas.single.polygon[1].dx, closeTo(600, 3));
      expect(_areas.single.polygon[1].dy, closeTo(100, 3));
      await _press(tester, 'road-remove-point');                               // the new point is the selected one
      expect(_areas.single.polygon, _road.polygon);
    });

    testWidgets('a shape keeps at least its least points, and right-click removes the point under the pointer', (tester) async {
      await _pump(tester, [_road]);
      await _tap(tester, const Offset(600, 400));
      await _tap(tester, const Offset(600, 100));                             // 5 points
      await _tap(tester, const Offset(600, 100), buttons: kSecondaryButton);   // right-click on that point
      expect(_areas.single.polygon.length, 4);
      var area = _areas.single;
      for (final p in [area.polygon[3], area.polygon[2]]) {                    // down to the 3 an area needs
        await _tap(tester, p, buttons: kSecondaryButton);
      }
      expect(_areas.single.polygon.length, 3);
      await _tap(tester, _areas.single.polygon[0], buttons: kSecondaryButton);
      expect(_areas.single.polygon.length, 3, reason: 'an area needs 3 points');
      area = _areas.single;
      expect(area.minPoints, 3);
    });

    testWidgets('drag a point to move it', (tester) async {
      await _pump(tester, [_road]);
      await _tap(tester, const Offset(600, 400));
      final from = _at(tester, const Offset(900, 100));
      await tester.dragFrom(from, const Offset(-80, 60));
      await tester.pump(const Duration(milliseconds: 50));
      final moved = _areas.single.polygon[1];
      expect(moved.dx, lessThan(900));
      expect(moved.dy, greaterThan(100));
      expect(_areas.single.polygon.length, 4);
    });

    testWidgets('Smooth turns a shape into a curve of more points', (tester) async {
      await _pump(tester, [_road]);
      await _tap(tester, const Offset(600, 400));
      await _press(tester, 'road-smooth');
      expect(_areas.single.polygon.length, 8);
    });
  });

  group('drawing', () {
    testWidgets('a solid line is drawn point by point (a bend is just another point) and starts as a rule', (tester) async {
      await _pump(tester, [_road]);
      await _chooseDraw(tester, 'draw-solid');
      expect(find.byKey(const ValueKey('road-drawing')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('road-finish'))).onPressed, isNull, reason: 'a line needs 2 points');
      for (final p in const [Offset(100, 600), Offset(200, 400), Offset(260, 300), Offset(400, 200)]) {
        await _tap(tester, p);
      }
      await _press(tester, 'road-finish');
      final line = _areas.last;
      expect(line.kind, 'solid_line');
      expect(line.polygon.length, 4);
      expect(line.rule, true);
      expect(find.byKey(const ValueKey('line-rule')), findsOneWidget);       // selected: the switch for "flag crossings"
      await _press(tester, 'line-rule');
      expect(_areas.last.rule, false);
    });

    testWidgets('an incoming road is drawn with its arrow, and the direction can be turned around', (tester) async {
      await _pump(tester, []);
      await _chooseDraw(tester, 'draw-in');
      for (final p in const [Offset(300, 100), Offset(600, 100), Offset(600, 700), Offset(300, 700)]) {
        await _tap(tester, p);
      }
      await _tap(tester, const Offset(300, 100));                              // tapping the first point closes the area
      final side = _areas.single;
      expect(side.kind == 'road' && side.flow == 'in' && side.arrow.length == 2, true);
      expect(side.arrow.first.dy, lessThan(side.arrow.last.dy), reason: 'incoming points down, toward the camera');
      await tester.tap(find.text('Outgoing'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_areas.single.flow, 'out');
      expect(_areas.single.arrow.first.dy, greaterThan(_areas.single.arrow.last.dy));
      await tester.tap(find.text('No direction'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_areas.single.flow, isNull);
      expect(_areas.single.arrow, isEmpty);
    });

    testWidgets('Cancel throws a half-drawn shape away', (tester) async {
      await _pump(tester, [_road]);
      await _chooseDraw(tester, 'draw-stop');
      await _tap(tester, const Offset(100, 100));
      await _press(tester, 'road-draw-cancel');
      expect(_areas, [_road]);
      expect(find.byKey(const ValueKey('road-drawing')), findsNothing);
    });

    testWidgets('a line is selected by tapping near it', (tester) async {
      await _pump(tester, [_road, _solid]);
      await _tap(tester, const Offset(175, 500));                              // on the first segment of the line
      expect(find.byKey(const ValueKey('line-style')), findsOneWidget);
      expect(find.byKey(const ValueKey('road-kind')), findsNothing, reason: 'a line has no area kind');
    });
  });
}
