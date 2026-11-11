import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/crosswalk_overlay.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/zone_geometry.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/crosswalk_editor.dart';

import 'support/test_support.dart';

/// "Pedestrian lane": an overlay crosswalk placed on the picture IS a crosswalk zone, for testing the rule where there is none.
const _rule = 'pedestrian_lane';

AnalysisDraft _draft() {
  final d = AnalysisDraft();
  d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
  d.toggle(_rule);
  return d;
}

Future<void> _pump(WidgetTester tester, AnalysisDraft d) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: d,
          builder: (_, _) => PedestrianLaneEditor(draft: d, violationKey: _rule, frame: MemoryImage(kTinyPng)),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _overlayMode(WidgetTester tester) async {
  await tester.tap(find.text('Crosswalk overlay (test)'));
  await tester.pump(const Duration(milliseconds: 50));
}

Offset _at(WidgetTester tester, double fx, double fy) {
  final r = tester.getRect(find.byKey(const ValueKey('cw-canvas')));
  return Offset(r.left + fx * r.width, r.top + fy * r.height);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f); // the side panel scrolls on its own
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

Future<void> _place(WidgetTester tester, double fx, double fy) async {
  await _tapKey(tester, 'cw-place');
  await tester.tapAt(_at(tester, fx, fy));
  await tester.pump();
}

Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await g.moveTo(Offset.lerp(from, to, 0.5)!);
  await g.moveTo(to);
  await g.up();
  await tester.pump();
}

Future<void> _slide(WidgetTester tester, String field, double value) async {
  final f = find.byKey(ValueKey('cw-slider-$field'));
  await tester.ensureVisible(f);
  await tester.pump();
  tester.widget<Slider>(f).onChanged!(value);
  await tester.pump();
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data ?? '';

void main() {
  group('the numbers match the backend (engine/crosswalk_overlay.py)', () {
    void expectCorners(Map c, List<(double, double)> want) {
      final got = CrosswalkOverlay.corners(c);
      for (var i = 0; i < 4; i++) {
        expect(got[i].dx, closeTo(want[i].$1, 0.05), reason: 'corner $i x');
        expect(got[i].dy, closeTo(want[i].$2, 0.05), reason: 'corner $i y');
      }
    }

    test('the normal look', () {
      expectCorners({}, [(-153.12, -62.198), (153.12, -62.198), (211.2, 62.198), (-211.2, 62.198)]);
    });

    test('a big, deep, turned, slanted one', () {
      expectCorners(
        {'scale': 2.0, 'depth': 1.5, 'angle': 20, 'slant': 60},
        [(-157.609, -213.733), (258.12, -62.42), (346.67, 282.546), (-447.182, -6.393)],
      );
    });

    test('numbers outside the limits are kept inside them', () {
      final c = {'scale': 99, 'depth': -3, 'angle': 400, 'slant': 900, 'stripes': 99, 'wear': 7};
      expect(CrosswalkOverlay.scaleOf(c), CrosswalkOverlay.maxScale);
      expect(CrosswalkOverlay.depthOf(c), CrosswalkOverlay.minDepth);
      expect(CrosswalkOverlay.angleOf(c), CrosswalkOverlay.maxAngle);
      expect(CrosswalkOverlay.slantOf(c), CrosswalkOverlay.maxSlant);
      expect(CrosswalkOverlay.stripesOf(c), CrosswalkOverlay.maxStripes);
      expect(CrosswalkOverlay.wearOf(c), 1.0);
      expect(CrosswalkOverlay.stripesOf({'stripes': 1}), CrosswalkOverlay.minStripes);
    });

    test('the bars are as many as asked and cover the paint share of the band', () {
      final quad = [const Offset(0, 0), const Offset(0.4, 0), const Offset(0.4, 0.1), const Offset(0, 0.1)];
      for (final n in [3, 8, 16]) {
        final bars = CrosswalkOverlay.bars(quad, n);
        expect(bars.length, n);
        final covered = bars.fold<double>(0, (sum, b) => sum + (b[1].dx - b[0].dx));
        expect(covered, closeTo(0.4 * CrosswalkOverlay.fill, 1e-9));
      }
    });
  });

  group('placing and shaping', () {
    testWidgets('the editor starts on the zone and the overlay tab shows the crosswalk card', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      expect(find.byKey(const ValueKey('crosswalk-card')), findsNothing);
      await _overlayMode(tester);
      expect(find.byKey(const ValueKey('crosswalk-card')), findsOneWidget);
      expect(_text(tester, 'cw-summary'), contains('No overlay crosswalk yet'));
    });

    testWidgets('a click places nothing until “Place a crosswalk” is pressed', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _overlayMode(tester);
      await tester.tapAt(_at(tester, 0.5, 0.7));
      await tester.pump();
      expect(d.crosswalks(_rule), isEmpty);
      expect(d.zonesReady(_rule), isFalse);
    });

    testWidgets('placing one makes the rule ready, at the click, with the normal look', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _overlayMode(tester);
      await _place(tester, 0.5, 0.7);
      final list = d.crosswalks(_rule);
      expect(list.length, 1);
      expect(list[0]['x'], closeTo(0.5 * ZoneGeometry.refWidth, 1));
      expect(list[0]['y'], closeTo(0.7 * ZoneGeometry.refHeight, 1));
      expect(list[0]['stripes'], CrosswalkOverlay.defaultStripes);
      expect(list[0]['slant'], CrosswalkOverlay.defaultSlant);
      expect(d.zonesReady(_rule), isTrue);
      expect(d.crosswalkCount(_rule), 1);
      expect(_text(tester, 'cw-summary'), contains('1 overlay crosswalk'));
    });

    testWidgets('dragging a crosswalk moves it by how far the pointer moved', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _overlayMode(tester);
      await _place(tester, 0.5, 0.7);
      await _drag(tester, _at(tester, 0.5, 0.7), _at(tester, 0.3, 0.5));
      final c = d.crosswalks(_rule)[0];
      expect(c['x'], closeTo(0.3 * ZoneGeometry.refWidth, 6));
      expect(c['y'], closeTo(0.5 * ZoneGeometry.refHeight, 6));
    });

    testWidgets('the sliders set size, depth, rotation, perspective, stripes and wear', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _overlayMode(tester);
      await _place(tester, 0.5, 0.7);
      await _slide(tester, 'scale', 2.0);
      await _slide(tester, 'depth', 1.5);
      await _slide(tester, 'angle', -25);
      await _slide(tester, 'slant', 55);
      await _slide(tester, 'stripes', 12);
      await _slide(tester, 'wear', 0.6);
      final c = d.crosswalks(_rule)[0];
      expect(c['scale'], 2.0);
      expect(c['depth'], 1.5);
      expect(c['angle'], -25);
      expect(c['slant'], 55);
      expect(c['stripes'], 12);
      expect(c['stripes'], isA<int>()); // a whole number of bars
      expect(c['wear'], 0.6);
    });

    testWidgets('Reset its look brings the normal look back and keeps the spot', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _overlayMode(tester);
      await _place(tester, 0.4, 0.6);
      await _slide(tester, 'scale', 2.5);
      await _slide(tester, 'stripes', 14);
      await _tapKey(tester, 'cw-reset');
      final c = d.crosswalks(_rule)[0];
      expect(c['scale'], CrosswalkOverlay.defaultScale);
      expect(c['stripes'], CrosswalkOverlay.defaultStripes);
      expect(c['x'], closeTo(0.4 * ZoneGeometry.refWidth, 1));
    });

    testWidgets('several crosswalks can be placed, picked, removed and cleared', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _overlayMode(tester);
      await _place(tester, 0.2, 0.8);
      await tester.tapAt(_at(tester, 0.8, 0.3)); // still placing
      await tester.pump();
      expect(d.crosswalks(_rule).length, 2);
      await _tapKey(tester, 'cw-item-0');
      await _slide(tester, 'stripes', 5);
      expect(d.crosswalks(_rule)[0]['stripes'], 5);
      expect(d.crosswalks(_rule)[1]['stripes'], CrosswalkOverlay.defaultStripes);
      await _tapKey(tester, 'cw-remove-0');
      expect(d.crosswalks(_rule).length, 1);
      expect(d.crosswalks(_rule)[0]['x'], closeTo(0.8 * ZoneGeometry.refWidth, 1));
      await _tapKey(tester, 'cw-clear');
      expect(d.crosswalks(_rule), isEmpty);
      expect(d.zonesReady(_rule), isFalse);
    });

    testWidgets('a right-click on a crosswalk removes it', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _overlayMode(tester);
      await _place(tester, 0.5, 0.7);
      await tester.tapAt(_at(tester, 0.5, 0.7), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(d.crosswalks(_rule), isEmpty);
    });

    testWidgets('the realistic look is on until it is switched off', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _overlayMode(tester);
      expect(tester.widget<Switch>(find.byKey(const ValueKey('cw-realistic'))).value, isTrue);
      await _tapKey(tester, 'cw-realistic');
      expect(d.config(_rule)['crosswalks_realistic'], isFalse);
    });

    testWidgets('the overlay crosswalks and the look reach the backend config', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _overlayMode(tester);
      await _place(tester, 0.5, 0.7);
      await _slide(tester, 'stripes', 10);
      await _tapKey(tester, 'cw-realistic');
      final per = d.buildConfig(activePlateModel: 'p.onnx')['per_violation_configs'] as Map;
      final sent = per[_rule] as Map;
      expect((sent['crosswalks'] as List).length, 1);
      expect(((sent['crosswalks'] as List)[0] as Map)['stripes'], 10);
      expect(sent['crosswalks_realistic'], false);
      expect(sent['time_limit'], 3.0);
    });

    testWidgets('going back to the zone tab keeps the placed crosswalks', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _overlayMode(tester);
      await _place(tester, 0.5, 0.7);
      await tester.tap(find.text('Draw a zone'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('crosswalk-card')), findsNothing);
      expect(d.crosswalks(_rule).length, 1);
    });
  });
}
