import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/lane_signs.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/zone_geometry.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/zone_editor.dart';

import 'support/test_support.dart';

/// "Restricted lane": a zone is optional (nothing drawn = the whole picture is the lane), and overlay signs can be placed on the roads.
const _rule = 'restricted_lane';

AnalysisDraft _draft([String rule = _rule]) {
  final d = AnalysisDraft();
  d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
  d.toggle(rule);
  return d;
}

Future<void> _pump(WidgetTester tester, AnalysisDraft d, {String rule = _rule}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: d,
          builder: (_, _) => ZoneEditor(draft: d, violationKey: rule, frame: MemoryImage(kTinyPng)),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Offset _at(WidgetTester tester, double fx, double fy) {
  final r = tester.getRect(find.byKey(const ValueKey('zone-canvas')));
  return Offset(r.left + fx * r.width, r.top + fy * r.height);
}

Future<void> _click(WidgetTester tester, double fx, double fy) async {
  await tester.tapAt(_at(tester, fx, fy));
  await tester.pump();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f); // the side panel scrolls on its own
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await g.moveTo(Offset.lerp(from, to, 0.5)!);
  await g.moveTo(to);
  await g.up();
  await tester.pump();
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data ?? '';

Future<void> _drawZone(WidgetTester tester) async {
  for (final p in const [Offset(0.1, 0.1), Offset(0.6, 0.1), Offset(0.6, 0.9), Offset(0.1, 0.9)]) {
    await _click(tester, p.dx, p.dy);
  }
  await _tapKey(tester, 'zone-save');
}

void main() {
  group('a zone is optional', () {
    testWidgets('with nothing drawn the rule is ready and says the whole picture is the lane', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      expect(d.zonesReady(_rule), isTrue);
      expect(d.canStart, isTrue);
      expect(d.zones(_rule), isEmpty);
      expect(_text(tester, 'lane-no-zone'), contains('the whole picture is the lane'));
      expect(_text(tester, 'lane-summary'), startsWith('No zone and no sign: the whole picture is the lane'));
    });

    testWidgets('other rules still need their zone and have no signs card', (tester) async {
      expect(_draft('pedestrian_lane').zonesReady('pedestrian_lane'), isFalse);
      final d = _draft('counterflow');
      await _pump(tester, d, rule: 'counterflow');
      expect(find.byKey(const ValueKey('lane-signs')), findsNothing);
    });

    testWidgets('a drawn zone is still kept, and then limits the rule', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _drawZone(tester);
      expect(d.zones(_rule), hasLength(1));
      expect(_text(tester, 'lane-summary'), startsWith('Only the 1 zone are checked'));
    });
  });

  group('signs', () {
    testWidgets('the signs on offer are the backend list, each saying who may use the road', (tester) async {
      expect([for (final s in LaneSigns.all) s.key], ['bus_only', 'puv_only', 'motorcycle_only', 'bicycle_only', 'no_trucks', 'no_tricycles', 'no_motorcycles']);
      expect(LaneSigns.of('bus_only')!.allowed, ['bus']);
      expect(LaneSigns.of('no_trucks')!.allowed, isNot(contains('truck')));
      expect(LaneSigns.of('no_trucks')!.allowed, contains('car'));
      expect(LaneSigns.of('nope'), isNull);
    });

    testWidgets('a picked sign is placed where the picture is clicked, in reference pixels', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-type-no_trucks');
      expect(_text(tester, 'sign-allowed'), contains('car'));
      expect(_text(tester, 'sign-allowed'), isNot(contains('truck')));
      await _tapKey(tester, 'sign-place');
      expect(find.byKey(const ValueKey('sign-help')), findsOneWidget);
      await _click(tester, 0.3, 0.6);

      final signs = d.signs(_rule);
      expect(signs, hasLength(1));
      expect(signs.single['type'], 'no_trucks');
      expect(signs.single['x'], closeTo(0.3 * 1920, 8));
      expect(signs.single['y'], closeTo(0.6 * 1080, 8));
      await tester.ensureVisible(find.byKey(const ValueKey('sign-row-0')));
      expect(find.textContaining('NO TRUCKS'), findsWidgets);
      expect(find.textContaining('covers the road around it'), findsOneWidget);
      expect(_text(tester, 'lane-summary'), contains('the sign says who may use it'));
      expect(d.zonesReady(_rule), isTrue);

      final sent = d.buildConfig()['per_violation_configs'] as Map;
      expect(((sent[_rule] as Map)['signs'] as List).single['type'], 'no_trucks');
    });

    testWidgets('with several signs and no zone each vehicle follows the nearest one', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.2, 0.5);
      await _tapKey(tester, 'sign-type-motorcycle_only');
      await _click(tester, 0.8, 0.5);
      expect([for (final s in d.signs(_rule)) s['type']], ['bus_only', 'motorcycle_only']);
      expect(_text(tester, 'lane-summary'), contains('nearest'));
    });

    testWidgets('a sign can be dragged, and removed by right-click or by the bin', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.3, 0.5);
      await _click(tester, 0.7, 0.5);
      await _drag(tester, _at(tester, 0.3, 0.5), _at(tester, 0.3, 0.25));
      expect(d.signs(_rule)[0]['y'], closeTo(0.25 * 1080, 8));
      expect(d.signs(_rule)[1]['y'], closeTo(0.5 * 1080, 8), reason: 'the other sign stayed');
      expect(d.signs(_rule), hasLength(2), reason: 'a drag does not place another sign');

      await tester.tapAt(_at(tester, 0.7, 0.5), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(d.signs(_rule), hasLength(1));
      await _tapKey(tester, 'sign-delete-0');
      expect(d.signs(_rule), isEmpty);
      expect(_text(tester, 'lane-summary'), startsWith('No zone and no sign'));
    });

    testWidgets('clicking on a sign does not place another one on top of it', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.4, 0.4);
      await _click(tester, 0.4, 0.4);
      expect(d.signs(_rule), hasLength(1));
    });

    testWidgets('with zones, a sign inside one sets that zone, a sign outside every zone is said not to be used', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _drawZone(tester);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.3, 0.5); // inside the zone
      await _click(tester, 0.85, 0.5); // outside it
      await tester.ensureVisible(find.byKey(const ValueKey('sign-row-1')));
      await tester.pump();
      expect(find.textContaining('sets Zone 1'), findsOneWidget);
      expect(find.textContaining('outside every zone: not used'), findsOneWidget);
    });

    testWidgets('Done placing goes back to drawing a zone, so a click draws a corner again', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _tapKey(tester, 'sign-place'); // "Done placing signs"
      await _click(tester, 0.3, 0.3);
      expect(d.signs(_rule), isEmpty);
    });
  });

  group('size, angle and look of a sign', () {
    Future<AnalysisDraft> withSign(WidgetTester tester, {double fx = 0.5, double fy = 0.5}) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, fx, fy);
      return d;
    }

    void slide(WidgetTester tester, String key, double value) =>
        tester.widget<Slider>(find.byKey(ValueKey(key))).onChanged!(value);

    testWidgets('a placed sign is plain (full size, upright) and is the selected one', (tester) async {
      final d = await withSign(tester);
      final s = d.signs(_rule).single;
      expect([s['scale'], s['angle'], s['tilt']], [1.0, 0.0, 0.0]);
      await tester.ensureVisible(find.byKey(const ValueKey('sign-scale')));
      expect(_text(tester, 'sign-scale-value'), '100%');
      expect(_text(tester, 'sign-angle-value'), '0°');
    });

    testWidgets('the sliders set the size, the angle and the turn of the selected sign, and Reset puts them back', (tester) async {
      final d = await withSign(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('sign-scale')));
      slide(tester, 'sign-scale', 1.5);
      slide(tester, 'sign-angle', -12);
      slide(tester, 'sign-tilt', 30);
      await tester.pump();
      final s = d.signs(_rule).single;
      expect([s['scale'], s['angle'], s['tilt']], [1.5, -12.0, 30.0]);
      expect(_text(tester, 'sign-scale-value'), '150%');
      expect(_text(tester, 'sign-angle-value'), '-12°');
      expect(_text(tester, 'sign-tilt-value'), '30°');
      final sent = ((d.buildConfig()['per_violation_configs'] as Map)[_rule] as Map)['signs'] as List;
      expect(sent.single['scale'], 1.5);

      await _tapKey(tester, 'sign-reset');
      expect([s['scale'], s['angle'], s['tilt']], [1.0, 0.0, 0.0]);
    });

    testWidgets('each sign keeps its own look, and tapping a row or the sign on the picture selects it', (tester) async {
      final d = await withSign(tester, fx: 0.3);
      await _click(tester, 0.7, 0.5); // a second sign, now the selected one
      await tester.ensureVisible(find.byKey(const ValueKey('sign-scale')));
      slide(tester, 'sign-scale', 2.0);
      await tester.pump();
      expect([for (final s in d.signs(_rule)) s['scale']], [1.0, 2.0]);

      await _click(tester, 0.3, 0.5); // a tap on the first sign selects it, it does not place another
      expect(d.signs(_rule), hasLength(2));
      await tester.ensureVisible(find.byKey(const ValueKey('sign-scale')));
      expect(_text(tester, 'sign-scale-value'), '100%');

      await _tapKey(tester, 'sign-row-1'); // the row selects the other one
      expect(_text(tester, 'sign-scale-value'), '200%');
    });

    testWidgets('dragging the corner of the selected sign resizes it', (tester) async {
      final d = await withSign(tester);
      final canvas = tester.getSize(find.byKey(const ValueKey('zone-canvas')));
      final centre = _at(tester, 0.5, 0.5);
      final w = SignGeometry.width(canvas, 1.0), h = SignGeometry.height(canvas, 1.0);
      final corner = SignGeometry.resizeHandle(centre, w, h, 0);
      await _drag(tester, corner, centre + (corner - centre) * 2); // twice as far from the middle = twice the size
      expect(d.signs(_rule).single['scale'] as double, closeTo(2.0, 0.05));
      await _drag(tester, SignGeometry.resizeHandle(centre, w * 2, h * 2, 0), centre + const Offset(5, 3)); // far too small: kept at the smallest size
      expect(d.signs(_rule).single['scale'] as double, SignGeometry.minScale);
      expect(d.signs(_rule), hasLength(1));
      expect(d.signs(_rule).single['x'] as double, closeTo(0.5 * 1920, 8), reason: 'resizing does not move the sign');
    });

    testWidgets('dragging the knob above the selected sign turns it', (tester) async {
      final d = await withSign(tester);
      final canvas = tester.getSize(find.byKey(const ValueKey('zone-canvas')));
      final centre = _at(tester, 0.5, 0.5);
      final w = SignGeometry.width(canvas, 1.0), h = SignGeometry.height(canvas, 1.0);
      final knob = SignGeometry.rotateKnob(centre, w, h, 0);
      await _drag(tester, knob, centre + const Offset(120, -120)); // up and to the right: 45 degrees clockwise
      expect(d.signs(_rule).single['angle'] as double, closeTo(45, 1));
      await _drag(tester, SignGeometry.rotateKnob(centre, w, h, 45), centre + const Offset(-300, 0)); // straight left: as far as it may go
      expect(d.signs(_rule).single['angle'] as double, -SignGeometry.maxAngle);
    });

    testWidgets('the realistic look is on by default and can be turned off', (tester) async {
      final d = await withSign(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('sign-realistic')));
      expect(tester.widget<Switch>(find.byKey(const ValueKey('sign-realistic'))).value, isTrue);
      await tester.tap(find.byKey(const ValueKey('sign-realistic')));
      await tester.pump();
      expect(d.config(_rule)['signs_realistic'], isFalse);
      expect(tester.widget<Switch>(find.byKey(const ValueKey('sign-realistic'))).value, isFalse);
    });

    testWidgets('removing the selected sign leaves nothing selected and no sliders', (tester) async {
      final d = await withSign(tester);
      await _tapKey(tester, 'sign-delete-0');
      expect(d.signs(_rule), isEmpty);
      expect(find.byKey(const ValueKey('sign-scale')), findsNothing);
    });
  });

  group('SignGeometry', () {
    const canvas = Size(1000, 500);

    test('the numbers are the backend sign rule: 8.5% of the width, 0.62 tall, kept inside the limits', () {
      expect(SignGeometry.width(canvas, 1.0), closeTo(85, 1e-9));
      expect(SignGeometry.height(canvas, 2.0), closeTo(85 * 2 * 0.62, 1e-9));
      expect([SignGeometry.clampScale(99), SignGeometry.clampScale(0), SignGeometry.clampScale(double.nan)], [3.0, 0.3, 1.0]);
      expect([SignGeometry.clampAngle(500), SignGeometry.clampAngle(-500), SignGeometry.clampTilt(500), SignGeometry.clampTilt(-500)], [90.0, -90.0, 70.0, -70.0]);
    });

    test('the handles follow the sign and the pointer maps back to the size and the angle', () {
      const c = Offset(300, 200);
      final w = SignGeometry.width(canvas, 1.0), h = SignGeometry.height(canvas, 1.0);
      expect(SignGeometry.scaleFor(canvas, c, SignGeometry.resizeHandle(c, w, h, 0)), closeTo(1.0, 1e-9));
      expect(SignGeometry.scaleFor(canvas, c, SignGeometry.resizeHandle(c, w, h, 30)), closeTo(1.0, 1e-9), reason: 'the corner turns with the sign');
      expect(SignGeometry.angleFor(c, SignGeometry.rotateKnob(c, w, h, 0)), closeTo(0, 1e-9));
      expect(SignGeometry.angleFor(c, SignGeometry.rotateKnob(c, w, h, 35)), closeTo(35, 1e-9));
      expect(SignGeometry.angleFor(c, c + const Offset(50, 0)), 90.0);
      expect(SignGeometry.angleFor(c, c + const Offset(-50, 0)), -90.0);
    });

    test('a point is on the board when it is inside the turned rectangle', () {
      const c = Offset(300, 200);
      expect(SignGeometry.onBoard(c, 100, 62, 0, c + const Offset(40, 20)), isTrue);
      expect(SignGeometry.onBoard(c, 100, 62, 0, c + const Offset(90, 0)), isFalse);
      expect(SignGeometry.onBoard(c, 100, 62, 90, c + const Offset(20, 40)), isTrue, reason: 'turned a quarter, the board is tall');
      expect(SignGeometry.onBoard(c, 100, 62, 90, c + const Offset(40, 20)), isFalse);
    });
  });

  group('ZoneGeometry.inside', () {
    test('a point inside, outside and on an unusable polygon', () {
      const square = [Offset(0.1, 0.1), Offset(0.6, 0.1), Offset(0.6, 0.9), Offset(0.1, 0.9)];
      expect(ZoneGeometry.inside(square, const Offset(0.3, 0.5)), isTrue);
      expect(ZoneGeometry.inside(square, const Offset(0.85, 0.5)), isFalse);
      expect(ZoneGeometry.inside(square, const Offset(0.3, 0.95)), isFalse);
      expect(ZoneGeometry.inside(const [Offset(0, 0), Offset(1, 1)], const Offset(0.5, 0.5)), isFalse);
    });
  });
}
