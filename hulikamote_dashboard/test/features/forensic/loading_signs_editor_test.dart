import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/loading_signs.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/zone_geometry.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/zone_editor.dart';

import 'support/test_support.dart';

/// "Illegal loading / unloading": a no-loading sign can be placed anywhere on the picture, moved and resized. Its box is the area.
const _rule = 'illegal_loading';

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

Offset _atN(WidgetTester tester, Offset n) => _at(tester, n.dx, n.dy);

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

Map<String, dynamic> _sign(double fx, double fy, double w, double h) => {
  'x': fx * ZoneGeometry.refWidth,
  'y': fy * ZoneGeometry.refHeight,
  'w': w,
  'h': h,
};

void main() {
  group('a sign is a box on the picture (pure geometry)', () {
    test('a new sign is centred on the click at its default size', () {
      final s = LoadingSigns.make(const Offset(0.5, 0.5));
      expect(s['x'], closeTo(960, 0.01));
      expect(s['y'], closeTo(540, 0.01));
      expect(s['w'], LoadingSigns.defaultWidth);
      expect(s['h'], LoadingSigns.defaultHeight);
    });

    test('a sign placed at the edge of the picture is pulled inside it', () {
      final s = LoadingSigns.make(const Offset(1.0, 0.0));
      final r = LoadingSigns.rectOf(s);
      expect(r.right, closeTo(1.0, 1e-9));
      expect(r.top, closeTo(0.0, 1e-9));
      expect(r.width, closeTo(LoadingSigns.defaultWidth / 1920, 1e-9));
    });

    test('a press on a corner resizes, a press inside moves, a press outside grabs nothing', () {
      const canvas = Size(1000, 500);
      final signs = [_sign(0.5, 0.5, 400, 200)]; // box x 0.396..0.604, y 0.407..0.593
      final r = LoadingSigns.rectOf(signs.single);
      final corner = LoadingSigns.grab(signs, Offset(r.bottomRight.dx * 1000, r.bottomRight.dy * 500), canvas);
      expect(corner, isNotNull);
      expect(corner!.resize, isTrue);
      expect(corner.anchor.dx, closeTo(r.left, 1e-9)); // the opposite corner stays
      expect(corner.anchor.dy, closeTo(r.top, 1e-9));
      final body = LoadingSigns.grab(signs, const Offset(500, 250), canvas);
      expect(body, isNotNull);
      expect(body!.resize, isFalse);
      expect(LoadingSigns.grab(signs, const Offset(50, 50), canvas), isNull);
    });

    test('where boxes overlap, the sign placed last is the one grabbed', () {
      const canvas = Size(1000, 500);
      final signs = [_sign(0.5, 0.5, 400, 200), _sign(0.5, 0.5, 200, 100)];
      expect(LoadingSigns.bodyAt(signs, const Offset(500, 250), canvas), 1);
    });

    test('moving keeps the grab point under the pointer and the sign inside the picture', () {
      final s = _sign(0.5, 0.5, 400, 200);
      LoadingSigns.moveBy(s, const Offset(0.6, 0.5), const Offset(0.02, 0.0));
      expect(s['x'], closeTo(0.58 * 1920, 0.01));
      LoadingSigns.moveBy(s, const Offset(2.0, -3.0), Offset.zero);
      expect((s['x'] as double) + 200, lessThanOrEqualTo(1920));
      expect((s['y'] as double) - 100, greaterThanOrEqualTo(0));
    });

    test('resizing moves one corner and keeps the opposite one', () {
      final s = _sign(0.5, 0.5, 400, 200);
      final before = LoadingSigns.rectOf(s);
      LoadingSigns.resizeTo(s, const Offset(0.8, 0.9), before.topLeft);
      final after = LoadingSigns.rectOf(s);
      expect(after.left, closeTo(before.left, 1e-9));
      expect(after.top, closeTo(before.top, 1e-9));
      expect(after.right, closeTo(0.8, 1e-9));
      expect(after.bottom, closeTo(0.9, 1e-9));
    });

    test('a sign cannot be made smaller than the minimum, and dragging across the opposite corner flips it', () {
      final s = _sign(0.5, 0.5, 400, 200);
      final anchor = LoadingSigns.rectOf(s).topLeft;
      LoadingSigns.resizeTo(s, anchor + const Offset(0.0001, 0.0001), anchor);
      expect(s['w'], closeTo(LoadingSigns.minSide, 1e-6));
      expect(s['h'], closeTo(LoadingSigns.minSide, 1e-6));
      LoadingSigns.resizeTo(s, anchor - const Offset(0.1, 0.1), anchor);
      final r = LoadingSigns.rectOf(s);
      expect(r.right, closeTo(anchor.dx, 1e-9));
      expect(r.width, closeTo(0.1, 1e-9));
    });

    test('resizing at the edge of the picture never leaves the picture', () {
      final s = _sign(0.99, 0.99, 100, 100);
      final anchor = LoadingSigns.rectOf(s).topLeft;
      LoadingSigns.resizeTo(s, const Offset(2.0, 2.0), anchor);
      final r = LoadingSigns.rectOf(s);
      expect(r.right, lessThanOrEqualTo(1.0 + 1e-9));
      expect(r.bottom, lessThanOrEqualTo(1.0 + 1e-9));
      expect(r.width * 1920, greaterThanOrEqualTo(LoadingSigns.minSide - 1e-6));
    });

    test('resizing from a corner that is almost at the edge makes room by moving the fixed side, not by leaving the picture', () {
      final s = _sign(0.5, 0.5, 100, 100);
      LoadingSigns.resizeTo(s, const Offset(2.0, 2.0), const Offset(0.995, 0.995));
      final r = LoadingSigns.rectOf(s);
      expect(r.right, closeTo(1.0, 1e-9));
      expect(r.bottom, closeTo(1.0, 1e-9));
      expect(r.width * 1920, closeTo(LoadingSigns.minSide, 1e-6));
      expect(r.height * 1080, closeTo(LoadingSigns.minSide, 1e-6));
    });

    test('the size in words', () {
      expect(LoadingSigns.sizeText(_sign(0.5, 0.5, 960, 540)), '50% x 50% of the picture');
    });
  });

  group('in the zone editor', () {
    testWidgets('with nothing placed the whole picture is watched and the rule is ready', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      expect(d.zonesReady(_rule), isTrue);
      expect(d.canStart, isTrue);
      expect(find.byKey(const ValueKey('loading-signs')), findsOneWidget);
      expect(_text(tester, 'lane-no-zone'), contains('Place a sign or save a zone'));
      expect(_text(tester, 'loading-summary'), startsWith('Nothing marked: the whole picture is watched'));
    });

    testWidgets('other rules have no loading-signs card, and loading has no lane-signs card', (tester) async {
      final other = _draft('counterflow');
      await _pump(tester, other, rule: 'counterflow');
      expect(find.byKey(const ValueKey('loading-signs')), findsNothing);
      final lane = _draft('restricted_lane');
      await _pump(tester, lane, rule: 'restricted_lane');
      expect(find.byKey(const ValueKey('loading-signs')), findsNothing);
      await _pump(tester, _draft(), rule: _rule);
      expect(find.byKey(const ValueKey('lane-signs')), findsNothing);
    });

    testWidgets('a sign is placed where the picture is clicked, at its default size, and then the rule is ready', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      expect(find.byKey(const ValueKey('sign-help')), findsOneWidget);
      await _click(tester, 0.4, 0.5);

      final signs = d.signs(_rule);
      expect(signs, hasLength(1));
      expect(signs.single['x'], closeTo(0.4 * 1920, 8));
      expect(signs.single['y'], closeTo(0.5 * 1080, 8));
      expect(signs.single['w'], LoadingSigns.defaultWidth);
      expect(signs.single['h'], LoadingSigns.defaultHeight);
      expect(d.zonesReady(_rule), isTrue);
      expect(d.canStart, isTrue);
      expect(_text(tester, 'loading-summary'), startsWith('Loading is banned in the 1 sign.'));
      await tester.ensureVisible(find.byKey(const ValueKey('loading-sign-row-0')));
      expect(find.textContaining('22% x 21% of the picture'), findsOneWidget);

      final sent = d.buildConfig()['per_violation_configs'] as Map;
      expect(((sent[_rule] as Map)['signs'] as List).single, {'x': signs.single['x'], 'y': signs.single['y'], 'w': 420.0, 'h': 230.0});
    });

    testWidgets('dragging the sign moves it without placing another', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.3, 0.5);
      await _click(tester, 0.7, 0.5);
      await _drag(tester, _at(tester, 0.3, 0.5), _at(tester, 0.3, 0.25));
      expect(d.signs(_rule)[0]['y'], closeTo(0.25 * 1080, 8));
      expect(d.signs(_rule)[0]['x'], closeTo(0.3 * 1920, 8));
      expect(d.signs(_rule)[1]['y'], closeTo(0.5 * 1080, 8), reason: 'the other sign stayed');
      expect(d.signs(_rule), hasLength(2), reason: 'a drag does not place another sign');
    });

    testWidgets('dragging a corner resizes the sign and the opposite corner stays', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.5, 0.5);
      final before = LoadingSigns.rectOf(d.signs(_rule).single);

      await _drag(tester, _atN(tester, before.bottomRight), _at(tester, 0.8, 0.8));
      final after = LoadingSigns.rectOf(d.signs(_rule).single);
      expect(d.signs(_rule), hasLength(1));
      expect(after.left, closeTo(before.left, 0.002));
      expect(after.top, closeTo(before.top, 0.002));
      expect(after.right, closeTo(0.8, 0.005));
      expect(after.bottom, closeTo(0.8, 0.005));
    });

    testWidgets('a sign can be made bigger and then smaller again', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.5, 0.5);
      final first = LoadingSigns.rectOf(d.signs(_rule).single);
      await _drag(tester, _atN(tester, first.topLeft), _at(tester, 0.1, 0.1));
      final big = LoadingSigns.rectOf(d.signs(_rule).single);
      expect(big.width, greaterThan(first.width * 1.5));
      await _drag(tester, _atN(tester, big.topLeft), _atN(tester, first.topLeft));
      final back = LoadingSigns.rectOf(d.signs(_rule).single);
      expect(back.width, closeTo(first.width, 0.01));
    });

    testWidgets('clicking on a sign does not place another one on top of it', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.4, 0.4);
      await _click(tester, 0.4, 0.4);
      expect(d.signs(_rule), hasLength(1));
    });

    testWidgets('a sign is removed by right-click, by the bin and by undo', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.2, 0.3);
      await _click(tester, 0.7, 0.3);
      await _click(tester, 0.5, 0.8);
      expect(d.signs(_rule), hasLength(3));

      await tester.tapAt(_at(tester, 0.7, 0.3), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(d.signs(_rule), hasLength(2));
      await _tapKey(tester, 'loading-sign-delete-0');
      expect(d.signs(_rule), hasLength(1));
      await tester.ensureVisible(find.text('Undo point')); // the side panel scrolls on its own
      await tester.pump();
      await tester.tap(find.text('Undo point'));
      await tester.pump();
      expect(d.signs(_rule), isEmpty);
      expect(d.zonesReady(_rule), isTrue); // nothing placed: the whole picture is watched
      expect(d.watchesWholePicture(_rule), isTrue);
      expect(_text(tester, 'loading-summary'), startsWith('Nothing marked: the whole picture is watched'));
    });

    testWidgets('Done placing goes back to drawing a zone, so a click draws a corner again', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _tapKey(tester, 'sign-place'); // "Done placing signs"
      await _click(tester, 0.3, 0.3);
      expect(d.signs(_rule), isEmpty);
    });

    testWidgets('a drawn zone and a sign can be used together', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      for (final p in const [Offset(0.1, 0.1), Offset(0.3, 0.1), Offset(0.3, 0.3), Offset(0.1, 0.3)]) {
        await _click(tester, p.dx, p.dy);
      }
      await _tapKey(tester, 'zone-save');
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.7, 0.7);
      expect(d.zones(_rule), hasLength(1));
      expect(d.signs(_rule), hasLength(1));
      expect(_text(tester, 'loading-summary'), startsWith('Loading is banned in the 1 sign and 1 zone.'));
    });

    testWidgets('with no sign and no zone the rule is ready: the whole picture is watched', (tester) async {
      final d = _draft();
      expect(d.zonesReady(_rule), isTrue);
    });
  });
}
