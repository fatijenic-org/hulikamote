import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/violation_catalog.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/zone_editor.dart';

import 'support/test_support.dart';

/// "Tricycle on a national highway": a zone is optional. Ticking the rule says the whole view is a road where the ban applies;
/// a drawn zone still limits it. (The video cannot show whether a road is a national highway: the operator states it.)
const _rule = 'tricycle_on_highway';

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

void main() {
  group('the tricycle ban needs no drawn zone', () {
    test('with nothing drawn the rule is ready, and the payload says which types are banned', () {
      final d = _draft();
      expect(d.zonesReady(_rule), isTrue);
      expect(d.missingZones, isEmpty);
      expect(d.canStart, isTrue);
      expect(d.zones(_rule), isEmpty);
      expect((d.buildConfig()['per_violation_configs'] as Map)[_rule]['banned_classes'], ['tricycle']);
    });

    test('the rule is a whole-picture rule, and the picker says the zone is optional', () {
      expect(AnalysisDraft.wholeFrameKeys, contains(_rule));
      expect(ViolationCatalog.of(_rule).zoneHint, contains('A zone is optional'));
    });

    test('the truck ban needs no zone either, the sidewalk rule still does', () {
      expect(_draft('truck_ban').zonesReady('truck_ban'), isTrue);
      expect(_draft('sidewalk_driving').zonesReady('sidewalk_driving'), isFalse);
    });

    testWidgets('the zone editor says the whole picture counts as a banned road, not "save a zone to continue"', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      final note = tester.widget<Text>(find.byKey(const ValueKey('lane-no-zone'))).data ?? '';
      expect(note, contains('the whole picture is a road where the ban applies'));
      expect(find.text('Save at least one zone to continue.'), findsNothing);
      expect(find.textContaining('Optional: click the corners'), findsOneWidget);
      expect(find.byKey(const ValueKey('lane-signs')), findsNothing); // the signs card belongs to the restricted lane only
    });

    testWidgets('a rule that needs its zone still says so', (tester) async {
      final d = _draft('sidewalk_driving');
      await _pump(tester, d, rule: 'sidewalk_driving');
      expect(find.text('Save at least one zone to continue.'), findsOneWidget);
    });
  });
}
