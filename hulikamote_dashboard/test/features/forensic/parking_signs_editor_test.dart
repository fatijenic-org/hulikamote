import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/loading_signs.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/parking_reasons.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/zone_editor.dart';

import 'support/test_support.dart';

/// "Illegal parking": a no-parking sign can be placed anywhere on the picture, moved and resized. Its box is the area.
/// It is the same box sign as the no-loading sign (loading_signs_editor_test.dart); only the rule and the words differ.
const _rule = 'illegal_parking';

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

void main() {
  group('which rules take a sign as a zone', () {
    test('loading and parking do, the others do not', () {
      expect(AnalysisDraft.signZoneKeys, containsAll(['illegal_loading', 'illegal_parking']));
      expect(AnalysisDraft.signZoneKeys.contains('counterflow'), isFalse);
      expect(AnalysisDraft.signZoneKeys.contains('restricted_lane'), isFalse);
    });

    test('each rule has its own words on the sign', () {
      expect(LoadingSigns.linesFor('illegal_parking'), ['NO', 'PARKING']);
      expect(LoadingSigns.linesFor('illegal_loading'), ['NO LOADING', 'UNLOADING']);
      expect(LoadingSigns.banFor('illegal_parking'), 'no-parking');
      expect(LoadingSigns.banFor('illegal_loading'), 'no-loading');
    });

    test('a placed sign is a zone too: the rule then watches only its box, not the whole picture', () {
      final d = _draft();
      expect(d.zonesReady(_rule), isTrue);
      expect(d.watchesWholePicture(_rule), isTrue);
      d.signs(_rule).add(LoadingSigns.make(const Offset(0.5, 0.5)));
      expect(d.zonesReady(_rule), isTrue);
      expect(d.watchesWholePicture(_rule), isFalse);
      expect(d.canStart, isTrue);
    });
  });

  group('in the zone editor', () {
    testWidgets('with nothing placed the whole picture is watched and the rule is ready; the card says no-parking', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      expect(d.zonesReady(_rule), isTrue);
      expect(find.byKey(const ValueKey('loading-signs')), findsOneWidget);
      expect(find.text('NO-PARKING SIGNS (TEMPORARY)'), findsOneWidget);
      expect(find.text('Place a no-parking sign'), findsOneWidget);
      expect(_text(tester, 'lane-no-zone'), contains('Place a sign or save a zone'));
      expect(_text(tester, 'loading-summary'), startsWith('Nothing marked: the whole picture is watched'));
    });

    testWidgets('the no-loading rule keeps its own words', (tester) async {
      await _pump(tester, _draft('illegal_loading'), rule: 'illegal_loading');
      expect(find.text('NO-LOADING SIGNS (TEMPORARY)'), findsOneWidget);
      expect(find.text('Place a no-loading sign'), findsOneWidget);
    });

    testWidgets('a sign is placed where the picture is clicked, then the rule is ready and the summary says parking', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.4, 0.5);

      final signs = d.signs(_rule);
      expect(signs, hasLength(1));
      expect(signs.single['x'], closeTo(0.4 * 1920, 8));
      expect(signs.single['y'], closeTo(0.5 * 1080, 8));
      expect(signs.single['w'], LoadingSigns.defaultWidth);
      expect(d.zonesReady(_rule), isTrue);
      expect(_text(tester, 'loading-summary'), 'Parking is banned in the 1 sign. A vehicle that stands still there too long is flagged.');

      final sent = d.buildConfig()['per_violation_configs'] as Map;
      expect(((sent[_rule] as Map)['signs'] as List).single, {'x': signs.single['x'], 'y': signs.single['y'], 'w': 420.0, 'h': 230.0, 'kind': 'sign'});
    });

    testWidgets('dragging the sign moves it without placing another', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.3, 0.5);
      await _click(tester, 0.7, 0.5);
      await _drag(tester, _at(tester, 0.3, 0.5), _at(tester, 0.3, 0.25));
      expect(d.signs(_rule)[0]['y'], closeTo(0.25 * 1080, 8));
      expect(d.signs(_rule)[1]['y'], closeTo(0.5 * 1080, 8), reason: 'the other sign stayed');
      expect(d.signs(_rule), hasLength(2));
    });

    testWidgets('dragging a corner resizes the sign and the opposite corner stays', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.5, 0.5);
      final before = LoadingSigns.rectOf(d.signs(_rule).single);
      await _drag(tester, _atN(tester, before.bottomRight), _at(tester, 0.8, 0.8));
      final after = LoadingSigns.rectOf(d.signs(_rule).single);
      expect(after.left, closeTo(before.left, 0.002));
      expect(after.top, closeTo(before.top, 0.002));
      expect(after.right, closeTo(0.8, 0.005));
      expect(after.bottom, closeTo(0.8, 0.005));
    });

    testWidgets('a sign is removed by right-click and by the bin', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.2, 0.3);
      await _click(tester, 0.7, 0.3);
      await _click(tester, 0.5, 0.8);
      await tester.tapAt(_at(tester, 0.7, 0.3), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(d.signs(_rule), hasLength(2));
      await _tapKey(tester, 'loading-sign-delete-0');
      expect(d.signs(_rule), hasLength(1));
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
      expect(_text(tester, 'loading-summary'), startsWith('Parking is banned in the 1 sign and 1 zone.'));
    });

    testWidgets('other rules have no sign card', (tester) async {
      await _pump(tester, _draft('counterflow'), rule: 'counterflow');
      expect(find.byKey(const ValueKey('loading-signs')), findsNothing);
      expect(find.byKey(const ValueKey('parking-conditions')), findsNothing);
    });

    testWidgets('the no-loading rule has no list of parking places and no "what marks the area" chips', (tester) async {
      await _pump(tester, _draft('illegal_loading'), rule: 'illegal_loading');
      expect(find.byKey(const ValueKey('parking-conditions')), findsNothing);
      expect(find.byKey(const ValueKey('parking-kind-hydrant')), findsNothing);
    });
  });

  group('the look of the object in a box', () {
    Slider slider(WidgetTester tester, String key) => tester.widget<Slider>(find.byKey(ValueKey(key)));

    testWidgets('a box just placed is selected and its look can be set', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      expect(find.byKey(const ValueKey('box-look')), findsNothing);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.5, 0.5);
      expect(find.byKey(const ValueKey('box-look')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('box-look-size')));
      slider(tester, 'box-look-size').onChanged!(2.0);
      slider(tester, 'box-look-angle').onChanged!(25.0);
      slider(tester, 'box-look-tilt').onChanged!(-30.0);
      await tester.pump();
      final sign = d.signs(_rule).single;
      expect([sign['scale'], sign['angle'], sign['tilt']], [2.0, 25.0, -30.0]);
      final sent = ((d.buildConfig()['per_violation_configs'] as Map)[_rule] as Map)['signs'] as List;
      expect(sent.single, containsPair('scale', 2.0));
      expect(sent.single, containsPair('tilt', -30.0));
    });

    testWidgets('a plate can stand on the ground, a pole or a tripod; a hydrant and a painted kerb stand alone', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.3, 0.5);
      await tester.ensureVisible(find.byKey(const ValueKey('box-look-stand')));
      expect(find.text('Tripod'), findsOneWidget);
      await tester.tap(find.text('Tripod'));
      await tester.pump();
      expect(d.signs(_rule).single['stand'], 'tripod');
      expect(LoadingSigns.standOf(d.signs(_rule).single, 'sign'), 'tripod');
      await _tapKey(tester, 'parking-kind-hydrant');
      await _click(tester, 0.7, 0.5);
      expect(d.signs(_rule).last['kind'], 'hydrant');
      expect(find.byKey(const ValueKey('box-look-stand')), findsNothing, reason: 'a hydrant has no pole');
      expect(LoadingSigns.standOf(d.signs(_rule).last, 'hydrant'), 'none');
    });

    testWidgets('a click on another box selects it, a row selects it, and reset gives the plain look back', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.2, 0.4);
      await _click(tester, 0.7, 0.4);
      await tester.ensureVisible(find.byKey(const ValueKey('box-look-size')));
      slider(tester, 'box-look-size').onChanged!(2.5);
      await tester.pump();
      expect(d.signs(_rule)[1]['scale'], 2.5);
      await _click(tester, 0.2, 0.4);                                  // a click on the first box selects it, it does not place a third
      expect(d.signs(_rule), hasLength(2));
      expect(slider(tester, 'box-look-size').value, 1.0);
      await _tapKey(tester, 'loading-sign-select-1');
      expect(slider(tester, 'box-look-size').value, 2.5);
      await _tapKey(tester, 'box-look-reset');
      expect(d.signs(_rule)[1].containsKey('scale'), isFalse);
      expect(slider(tester, 'box-look-size').value, 1.0);
    });

    testWidgets('the realistic switch is saved for the analysis, and the no-loading rule has the same controls', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.5, 0.5);
      await tester.ensureVisible(find.byKey(const ValueKey('box-look-realistic')));
      expect(tester.widget<Switch>(find.byKey(const ValueKey('box-look-realistic'))).value, isTrue);
      await tester.tap(find.byKey(const ValueKey('box-look-realistic')));
      await tester.pump();
      expect(d.config(_rule)['signs_realistic'], isFalse);
      final loading = _draft('illegal_loading');
      await _pump(tester, loading, rule: 'illegal_loading');
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.5, 0.5);
      expect(find.byKey(const ValueKey('box-look')), findsOneWidget);
    });

    test('limits and defaults of the look', () {
      expect(LoadingSigns.scaleOf({'scale': 99}), LoadingSigns.maxScale);
      expect(LoadingSigns.scaleOf({}), 1.0);
      expect(LoadingSigns.angleOf({'angle': -500}), -LoadingSigns.maxAngle);
      expect(LoadingSigns.tiltOf({'tilt': double.nan}), 0.0);
      expect(LoadingSigns.standOf({'stand': 'wrong'}, 'sign'), 'post');
      expect(LoadingSigns.objectKind('illegal_loading', {}), 'no_loading');
      expect(LoadingSigns.objectKind('illegal_parking', {'kind': 'corner'}), 'corner');
      expect(LoadingSigns.objectKind('illegal_parking', {}), 'sign');
    });
  });

  group('why parking is banned there (RA 4136 Section 46)', () {
    test('the five marked places and the three judged by other rules are the eight items (a) to (h)', () {
      final items = [...ParkingReasons.all.map((r) => r.item), ...ParkingReasons.others.map((o) => o.item)]..sort();
      expect(items, ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
      expect({for (final r in ParkingReasons.all) r.key: r.meters}, {'sign': null, 'hydrant': 4, 'fire_station': 4, 'corner': 6, 'driveway': null});
      expect(ParkingReasons.others.map((o) => o.ruleKey), ['blocking_intersection', 'pedestrian_lane', 'double_parking']);
      for (final r in ParkingReasons.all) {
        expect(r.lines, hasLength(2), reason: r.key);
        expect(LoadingSigns.linesFor('illegal_parking', kind: r.key), r.lines);
      }
      expect(ParkingReasons.of(null).key, 'sign');
      expect(ParkingReasons.of('nonsense').key, 'sign');
    });

    testWidgets('the list shows all eight places with their source', (tester) async {
      await _pump(tester, _draft(), rule: _rule);
      for (final item in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) {
        await tester.ensureVisible(find.byKey(ValueKey('parking-item-$item')));
        expect(find.byKey(ValueKey('parking-item-$item')), findsOneWidget, reason: item);
      }
      expect(find.textContaining('Section 46'), findsWidgets);
      expect(_text(tester, 'parking-source-note'), contains('RA 9514'));
      expect(_text(tester, 'parking-item-e-note'), 'Marked with a box on the picture');
      expect(_text(tester, 'parking-item-b-note'), 'Judged by the rule "Pedestrian lane blocked": off');
    });

    testWidgets('choosing what marks the area decides the kind of the next sign, and the card shows it', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'parking-kind-hydrant');
      expect(_text(tester, 'parking-kind-hint'), contains('Centre the box on the hydrant'));
      expect(find.text('Place: Fire hydrant'), findsOneWidget);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.4, 0.5);
      await _tapKey(tester, 'parking-kind-corner');
      await _click(tester, 0.75, 0.5);
      expect(d.signs(_rule).map((s) => s['kind']), ['hydrant', 'corner']);
      expect(_text(tester, 'loading-sign-text-0'), contains('Fire hydrant (4 m)'));
      expect(_text(tester, 'loading-sign-text-1'), contains('Corner, curb lines meet (6 m)'));
      expect(_text(tester, 'parking-item-e-note'), '1 placed on the picture');
      expect(_text(tester, 'parking-item-c-note'), '1 placed on the picture');
      expect(_text(tester, 'parking-item-d-note'), 'Marked with a box on the picture');
      final sent = d.buildConfig()['per_violation_configs'] as Map;
      expect(((sent[_rule] as Map)['signs'] as List).map((s) => (s as Map)['kind']), ['hydrant', 'corner']);
    });

    testWidgets('the Place button of a place picks its kind and starts placing', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'parking-item-d-action'); // within 4 m of a fire station driveway
      expect(find.byKey(const ValueKey('sign-help')), findsOneWidget);
      await _click(tester, 0.3, 0.6);
      expect(d.signs(_rule).single['kind'], 'fire_station');
      expect(_text(tester, 'parking-item-d-note'), '1 placed on the picture');
    });

    testWidgets('a placed sign can be changed to another kind', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'sign-place');
      await _click(tester, 0.5, 0.5);
      expect(d.signs(_rule).single['kind'], 'sign');
      await _tapKey(tester, 'parking-sign-kind-0');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Private driveway').last);
      await tester.pump();
      expect(d.signs(_rule).single['kind'], 'driveway');
      expect(_text(tester, 'loading-sign-text-0'), contains('Private driveway'));
    });

    testWidgets('a place judged by another rule can switch that rule on', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      expect(d.isSelected('blocking_intersection'), isFalse);
      await _tapKey(tester, 'parking-item-a-action');
      expect(d.isSelected('blocking_intersection'), isTrue);
      expect(_text(tester, 'parking-item-a-note'), 'Judged by the rule "Blocking the intersection": on');
      expect(find.byKey(const ValueKey('parking-item-a-action')), findsNothing, reason: 'the button is gone once the rule is on');
      d.toggle('double_parking', on: true);
      await tester.pump();
      expect(_text(tester, 'parking-item-g-note'), 'Judged by the rule "Double parking": on');
    });
  });
}
