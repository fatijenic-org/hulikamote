import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/violation_params.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/zone_editor.dart';

import 'support/test_support.dart';

/// "Illegal turn": one zone can ban several turns (several prohibited-turn arrows). Tricycle ban: no vehicle-type list.
const _rule = 'illegal_turn';

Offset _at(WidgetTester tester, double fx, double fy) {
  final r = tester.getRect(find.byKey(const ValueKey('zone-canvas')));
  return Offset(r.left + r.width * fx, r.top + r.height * fy);
}

Future<AnalysisDraft> _pump(WidgetTester tester, String rule) async {
  final d = AnalysisDraft();
  d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
  d.toggle(rule);
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: d,
          builder: (_, _) => ZoneEditor(draft: d, violationKey: rule, frame: MemoryImage(kTinyPng)),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  return d;
}

Future<void> _tap(WidgetTester tester, double fx, double fy) async {
  await tester.tapAt(_at(tester, fx, fy));
  await tester.pump();
}

void main() {
  testWidgets('a zone keeps every arrow drawn in it, the first one still as "vector"', (tester) async {
    final d = await _pump(tester, _rule);
    for (final p in [(0.1, 0.1), (0.9, 0.1), (0.9, 0.9)]) {
      await _tap(tester, p.$1, p.$2);
    }
    await tester.tap(find.text('Prohibited-turn arrow'));
    await tester.pump();
    for (final p in [(0.5, 0.5), (0.3, 0.5), (0.5, 0.7), (0.7, 0.7)]) { // arrow one (left), then arrow two (right)
      await _tap(tester, p.$1, p.$2);
    }
    expect(find.textContaining('2 drawn'), findsOneWidget);
    await tester.tap(find.text('Save this zone'));
    await tester.pump();
    final zone = d.zones(_rule).single as Map<String, dynamic>;
    final vectors = zone['vectors'] as List;
    expect(vectors.length, 2);
    expect((vectors[0] as Map)['x_dir'], lessThan(0)); // left
    expect((vectors[1] as Map)['x_dir'], greaterThan(0)); // right
    expect((zone['vector'] as Map)['x_dir'], (vectors[0] as Map)['x_dir']);
    expect((zone['ui_vectors'] as List).length, 2);
  });

  testWidgets('one arrow saves as before, with no list', (tester) async {
    final d = await _pump(tester, _rule);
    for (final p in [(0.1, 0.1), (0.9, 0.1), (0.9, 0.9)]) {
      await _tap(tester, p.$1, p.$2);
    }
    await tester.tap(find.text('Prohibited-turn arrow'));
    await tester.pump();
    await _tap(tester, 0.5, 0.5);
    await _tap(tester, 0.3, 0.5);
    await tester.tap(find.text('Save this zone'));
    await tester.pump();
    final zone = d.zones(_rule).single as Map<String, dynamic>;
    expect(zone.containsKey('vectors'), isFalse);
    expect(zone['vector'], isNotNull);
  });

  testWidgets('the tricycle rule shows no vehicle-type list; the truck ban still does', (tester) async {
    Future<void> show(String rule) async {
      final d = AnalysisDraft()..toggle(rule);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ViolationParams(draft: d, violationKey: rule, onChanged: () {}))),
      ));
    }

    await show('tricycle_on_highway');
    expect(find.text('Vehicle types NOT allowed here'), findsNothing);
    await show('truck_ban');
    expect(find.text('Vehicle types NOT allowed here'), findsOneWidget);
  });
}
