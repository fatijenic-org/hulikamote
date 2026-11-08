/// Draws the officer pages to PNGs so the design can be looked at without launching the app. It only runs when
/// SHOTS_DIR is set:
///   SHOTS_DIR=some/folder flutter test test/visual/officer_screenshots_test.dart
/// The images are never part of the repository.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hulikamote_dashboard/core/services/api_service.dart';
import 'package:hulikamote_dashboard/core/shell/app_shell.dart';
import 'package:hulikamote_dashboard/core/shell/officer_mode.dart';
import 'package:hulikamote_dashboard/features/auth/presentation/screens/login_screen.dart';
import 'package:hulikamote_dashboard/features/overview/presentation/screens/overview_screen.dart';
import 'package:hulikamote_dashboard/features/violations/presentation/screens/inbox_screen.dart';
import 'package:hulikamote_dashboard/features/violations/presentation/screens/violations_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/officer/fake_backend.dart';
import '../support/screenshot.dart';

final _out = Platform.environment['SHOTS_DIR'];

/// The app's dark theme with Roboto, because the app's own font (Lexend, from Google Fonts) cannot be fetched in a test.
/// Lexend is a little wider than Roboto, so leave some room when judging tight spots.
ThemeData _theme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF3B82F6),
      scaffoldBackgroundColor: const Color(0xFF0B0F17),
      fontFamily: 'Roboto',
    );

FakeBackend _backend() => FakeBackend(
      sessions: {
        'forensic': {},
        'live': {
          'ab12cd34-aaaa': [
            pendingTicket('t1', plate: 'ANA 777'),
            pendingTicket('t2', cls: 'red_light'),
            pendingTicket('t3', cls: 'counterflow', plate: 'LP14LJA'),
          ],
        },
        'video_analysis': {
          'ef56ab78-bbbb': [pendingTicket('t4', cls: 'no_helmet', plate: 'DEF 5678')],
        },
      },
      violations: [
        record('v1', cls: 'counterflow', plate: 'ANA 777', at: DateTime.now().subtract(const Duration(minutes: 9))),
        record('v2', cls: 'no_helmet', plate: 'LP14LJA', at: DateTime.now().subtract(const Duration(hours: 3))),
        record('v3', cls: 'red_light', plate: null, at: DateTime.now().subtract(const Duration(days: 1))),
        record('v4', cls: 'illegal_parking', plate: 'ABC 1234', at: DateTime.now().subtract(const Duration(days: 4))),
        record('v5', cls: 'no_helmet', plate: 'DEF 5678', at: DateTime.now().subtract(const Duration(days: 9))),
      ],
      plates: [
        {'plate': 'ANA 777', 'points': 3, 'by_class': {'counterflow': 2, 'no_helmet': 1}, 'last_at': null},
        {'plate': 'LP14LJA', 'points': 1, 'by_class': {'no_helmet': 1}, 'last_at': null},
      ],
    );

/// The real menu with the real page in it for the entries that have one, and a plain page for the rest.
Future<GoRouter> _shell(WidgetTester tester, FakeBackend backend, {String start = '/'}) async {
  final pages = <int, Widget>{
    AppShell.overviewIndex: OverviewScreen(api: backend.overview, onOpen: (_, _) {}),
    4: InboxScreen(client: backend.client),
    5: ViolationsScreen(api: ApiService(client: backend.client)),
  };
  final router = GoRouter(initialLocation: start, routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(navigationShell: shell),
      branches: [
        for (var i = 0; i < AppShell.navCount; i++)
          StatefulShellBranch(routes: [
            GoRoute(path: i == 0 ? '/' : '/p$i', builder: (_, _) => pages[i] ?? Center(child: Text('page $i'))),
          ]),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await showForScreenshot(tester, MaterialApp.router(theme: _theme(), routerConfig: router, debugShowCheckedModeBanner: false));
  await tester.pump(const Duration(milliseconds: 500));
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  final skip = _out == null ? 'set SHOTS_DIR to draw the screens' : null;

  setUpAll(loadScreenshotFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfficerMode.enabled.value = true;
  });

  testWidgets('sign in', (tester) async {
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const LoginScreen())]);
    addTearDown(router.dispose);
    await showForScreenshot(tester, MaterialApp.router(theme: _theme(), routerConfig: router, debugShowCheckedModeBanner: false));
    await saveScreenshot(tester, '$_out/d01_sign_in.png');
  }, skip: skip != null);

  testWidgets('overview', (tester) async {
    await _shell(tester, _backend(), start: '/p${AppShell.overviewIndex}');
    await _settle(tester);
    await saveScreenshot(tester, '$_out/d02_overview.png');
  }, skip: skip != null);

  testWidgets('overview, backend off', (tester) async {
    await _shell(tester, _backend()..down = true, start: '/p${AppShell.overviewIndex}');
    await _settle(tester);
    await saveScreenshot(tester, '$_out/d03_overview_down.png');
  }, skip: skip != null);

  testWidgets('overview, one source failing', (tester) async {
    await _shell(tester, _backend()..sessions = null, start: '/p${AppShell.overviewIndex}');
    await _settle(tester);
    await saveScreenshot(tester, '$_out/d04_overview_partial.png');
  }, skip: skip != null);

  testWidgets('violations', (tester) async {
    await _shell(tester, _backend(), start: '/p5');
    await _settle(tester);
    await saveScreenshot(tester, '$_out/d05_violations.png');
  }, skip: skip != null);

  testWidgets('inbox', (tester) async {
    await _shell(tester, _backend(), start: '/p4');
    await _settle(tester);
    await saveScreenshot(tester, '$_out/d06_inbox.png');
  }, skip: skip != null);

  testWidgets('review a ticket', (tester) async {
    final backend = _backend();
    final tickets = backend.sessions!['live']!['ab12cd34-aaaa']!;
    tickets[0]['evidence_paths'] = '["a.jpg","b.jpg","c.jpg"]';
    await _shell(tester, backend, start: '/p4');
    await _settle(tester);
    await tester.tap(find.text('Batch ab12cd34'));
    await tester.pumpAndSettle();
    await saveScreenshot(tester, '$_out/d07_review.png');
  }, skip: skip != null);

  testWidgets('menu collapsed', (tester) async {
    await _shell(tester, _backend(), start: '/p${AppShell.overviewIndex}');
    await _settle(tester);
    await tester.tap(find.byTooltip('Collapse the menu'));
    await tester.pump(const Duration(milliseconds: 400));
    await saveScreenshot(tester, '$_out/d08_menu_collapsed.png');
  }, skip: skip != null);
}
