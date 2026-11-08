import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hulikamote_dashboard/core/shell/app_shell.dart';
import 'package:hulikamote_dashboard/core/shell/officer_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/forensic/support/test_support.dart';

const officerPages = ['Overview', 'Live Monitor', 'Video Analysis', 'Forensic Analyzer', 'Inbox', 'Violations', 'Demerit Points', 'Motorists'];
const developerPages = [
  'Benchmark', 'Models', 'Settings', 'Utilities', 'Wiki', 'Code Reference', 'Docs', 'Progress Report', 'Visualizer', 'Datasets',
];

/// The real menu in front of a router with one plain page per menu entry.
Future<GoRouter> pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          for (var i = 0; i < AppShell.navCount; i++)
            StatefulShellBranch(routes: [GoRoute(path: i == 0 ? '/' : '/p$i', builder: (_, _) => Center(child: Text('page $i')))]),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
  return router;
}

void main() {
  setUpAll(loadRoboto);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfficerMode.enabled.value = false;
  });

  testWidgets('the full menu is shown by default', (tester) async {
    await pumpShell(tester);
    for (final label in [...officerPages, ...developerPages]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('officer view keeps only the pages an officer needs', (tester) async {
    await pumpShell(tester);
    await OfficerMode.set(true);
    await tester.pump();
    for (final label in officerPages) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final label in developerPages) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });

  testWidgets('the switch at the bottom of the menu turns it on and off', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('Utilities'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('Utilities'), findsOneWidget);
  });

  testWidgets('a page still opens the right screen when the menu is shortened', (tester) async {
    await pumpShell(tester);
    await OfficerMode.set(true);
    await tester.pump();
    await tester.tap(find.text('Violations'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('page 5'), findsOneWidget);                 // Violations is entry 5 in the full menu
    await tester.tap(find.text('Motorists'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('page 7'), findsOneWidget);
  });

  testWidgets('turning it on while on a developer page moves to the Overview', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Utilities'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('page 10'), findsOneWidget);
    await OfficerMode.set(true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('page ${AppShell.overviewIndex}'), findsOneWidget);
    expect(find.text('page 10'), findsNothing);
  });

  testWidgets('officer view lists the Overview first, with a heading over each group', (tester) async {
    await pumpShell(tester);
    await OfficerMode.set(true);
    await tester.pump();
    final top = {for (final label in ['Overview', 'Live Monitor', 'Inbox', 'Motorists']) label: tester.getTopLeft(find.text(label)).dy};
    expect(top['Overview']!, lessThan(top['Live Monitor']!));
    expect(top['Live Monitor']!, lessThan(top['Inbox']!));
    expect(top['Inbox']!, lessThan(top['Motorists']!));
    for (final group in ['MONITOR', 'REVIEW', 'RECORDS']) {
      expect(find.text(group), findsOneWidget, reason: group);
    }
  });

  testWidgets('the Overview opens the right screen', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Overview'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('page ${AppShell.overviewIndex}'), findsOneWidget);
  });

  test('the choice is remembered between runs', () async {
    await OfficerMode.set(true);
    OfficerMode.enabled.value = false;                           // as if the app had just been started
    await OfficerMode.load();
    expect(OfficerMode.enabled.value, isTrue);
    await OfficerMode.set(false);
    await OfficerMode.load();
    expect(OfficerMode.enabled.value, isFalse);
  });
}
