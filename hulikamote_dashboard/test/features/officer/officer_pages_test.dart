import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hulikamote_dashboard/core/services/api_service.dart';
import 'package:hulikamote_dashboard/core/shell/officer_mode.dart';
import 'package:hulikamote_dashboard/core/theme/app_theme.dart';
import 'package:hulikamote_dashboard/core/ui/page_parts.dart';
import 'package:hulikamote_dashboard/features/auth/presentation/screens/login_screen.dart';
import 'package:hulikamote_dashboard/features/overview/presentation/screens/overview_screen.dart';
import 'package:hulikamote_dashboard/features/violations/presentation/screens/inbox_screen.dart';
import 'package:hulikamote_dashboard/features/violations/presentation/screens/violations_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../forensic/support/test_support.dart';
import 'fake_backend.dart';

Future<void> show(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: page));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

FakeBackend busyBackend() => FakeBackend(
      sessions: {
        'forensic': {},
        'live': {
          'ab12cd34-aaaa': [pendingTicket('t1', plate: 'ANA 777'), pendingTicket('t2', cls: 'red_light')],
        },
        'video_analysis': {
          'ef56ab78-bbbb': [pendingTicket('t3', cls: 'counterflow', plate: 'LP14LJA')],
        },
      },
      violations: [record('v1'), record('v2', cls: 'no_helmet', plate: null), record('v3', cls: 'no_helmet', status: 'pending')],
      plates: [
        {'plate': 'ABC 1234', 'points': 3, 'by_class': {'no_helmet': 3}, 'last_at': null},
        {'plate': 'XYZ 999', 'points': 1, 'by_class': {'red_light': 1}, 'last_at': null},
      ],
    );

void main() {
  setUpAll(loadRoboto);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfficerMode.enabled.value = false;
  });

  group('Overview', () {
    testWidgets('shows the four numbers, the steps and the latest confirmed tickets', (tester) async {
      final backend = busyBackend();
      await show(tester, OverviewScreen(api: backend.overview, onOpen: (_, _) {}));
      expect(find.text('To review'), findsOneWidget);
      expect(find.text('3'), findsWidgets);                       // three tickets wait in the Inbox
      expect(find.text('Confirmed violations'), findsOneWidget);
      expect(find.text('Plates with points'), findsOneWidget);
      expect(find.text('4 points in total'), findsOneWidget);
      expect(find.text('Motorists'), findsWidgets);
      for (final step in ['Analyse a video', 'Review what it found', 'Check the points', 'Notify the driver']) {
        expect(find.text(step), findsOneWidget, reason: step);
      }
      expect(find.text('Latest confirmed'.toUpperCase()), findsOneWidget);
      expect(find.text('ABC 1234'), findsOneWidget);
      expect(find.text('Plate not read'), findsOneWidget);
    });

    testWidgets('a tile and a step open the page behind them', (tester) async {
      final opened = <String>[];
      await show(tester, OverviewScreen(api: busyBackend().overview, onOpen: (_, path) => opened.add(path)));
      await tester.tap(find.text('Confirmed violations'));
      await tester.tap(find.text('Check the points'));
      expect(opened, ['/violations', '/demerit']);
    });

    testWidgets('one failing source shows a dash and a plain sentence, the rest stay right', (tester) async {
      final backend = busyBackend()..sessions = null;
      await show(tester, OverviewScreen(api: backend.overview, onOpen: (_, _) {}));
      expect(find.textContaining('Could not load the Inbox.'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('4 points in total'), findsOneWidget);
    });

    testWidgets('with the backend off it says so and recovers on Try again', (tester) async {
      final backend = busyBackend()..down = true;
      await show(tester, OverviewScreen(api: backend.overview, onOpen: (_, _) {}));
      expect(find.text('The system is not answering'), findsOneWidget);
      backend.down = false;
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('The system is not answering'), findsNothing);
      expect(find.text('Confirmed violations'), findsOneWidget);
    });

    testWidgets('nothing confirmed yet explains how to get something here', (tester) async {
      final backend = FakeBackend(sessions: {'forensic': {}, 'live': {}, 'video_analysis': {}});
      await show(tester, OverviewScreen(api: backend.overview, onOpen: (_, _) {}));
      expect(find.text('Nothing confirmed yet'), findsOneWidget);
      expect(find.text('0'), findsWidgets);                       // a real zero, not a dash
    });
  });

  group('Violations', () {
    testWidgets('lists confirmed tickets first and the filter widens it', (tester) async {
      final backend = busyBackend();
      await show(tester, ViolationsScreen(api: ApiService(client: backend.client)));
      expect(find.text('Confirmed'), findsWidgets);
      expect(find.text('2 tickets'), findsOneWidget);
    });

    testWidgets('choosing a filter asks the backend for that status', (tester) async {
      final backend = busyBackend();
      await show(tester, ViolationsScreen(api: ApiService(client: backend.client)));
      await tester.tap(find.text('To review'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      expect(backend.asked.last.queryParameters['status'], 'pending');
      expect(find.text('1 ticket'), findsOneWidget);
      await tester.tap(find.text('All'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      expect(backend.asked.last.queryParameters.containsKey('status'), isFalse);
      expect(find.text('3 tickets'), findsOneWidget);
    });

    testWidgets('an empty filter explains itself', (tester) async {
      final backend = FakeBackend(violations: []);
      await show(tester, ViolationsScreen(api: ApiService(client: backend.client)));
      expect(find.text('No confirmed tickets yet'), findsOneWidget);
    });

    testWidgets('a dead backend gives a page with a way to retry', (tester) async {
      final backend = busyBackend()..down = true;
      await show(tester, ViolationsScreen(api: ApiService(client: backend.client)));
      expect(find.text('Could not load this page'), findsOneWidget);
      backend.down = false;
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Could not load this page'), findsNothing);
      expect(find.text('2 tickets'), findsOneWidget);
    });
  });

  group('Inbox', () {
    testWidgets('opens on the first tab that has tickets and counts each tab', (tester) async {
      await show(tester, InboxScreen(client: busyBackend().client));
      expect(find.textContaining('Forensic · 0'), findsOneWidget);
      expect(find.textContaining('Live stream · 2'), findsOneWidget);
      expect(find.textContaining('Video analysis · 1'), findsOneWidget);
      expect(find.text('Batch ab12cd34'), findsOneWidget);          // the live tab is open
      expect(find.text('3 waiting'), findsOneWidget);
    });

    testWidgets('an empty inbox says everything is done', (tester) async {
      final backend = FakeBackend(sessions: {'forensic': {}, 'live': {}, 'video_analysis': {}});
      await show(tester, InboxScreen(client: backend.client));
      expect(find.text('All caught up'), findsOneWidget);
      expect(find.text('Nothing waiting'), findsOneWidget);
    });

    testWidgets('a dead backend shows how to start it, and Try again works', (tester) async {
      final backend = busyBackend()..down = true;
      await show(tester, InboxScreen(client: backend.client));
      expect(find.textContaining('run_demo_backend.bat'), findsOneWidget);
      backend.down = false;
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Batch ab12cd34'), findsOneWidget);
    });

    testWidgets('confirming a ticket saves "approved" and moves to the next one', (tester) async {
      final backend = busyBackend();
      await show(tester, InboxScreen(client: backend.client));
      await tester.tap(find.text('Batch ab12cd34'));
      await tester.pumpAndSettle();
      expect(find.text('2 left'), findsOneWidget);
      await tester.tap(find.text('Confirm violation'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(backend.decisions, {'t1': 'approved'});
      expect(find.text('1 left'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));               // the "saved" toast goes away
    });

    testWidgets('a false alarm saves "rejected"; a failed save keeps the ticket and says why', (tester) async {
      final backend = busyBackend();
      await show(tester, InboxScreen(client: backend.client));
      await tester.tap(find.text('Batch ab12cd34'));
      await tester.pumpAndSettle();
      backend.failDecisions = true;
      await tester.tap(find.text('False alarm'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('The decision was not saved'), findsOneWidget);
      expect(find.text('2 left'), findsOneWidget);
      backend.failDecisions = false;
      await tester.tap(find.text('False alarm'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(backend.decisions, {'t1': 'rejected'});
      expect(find.text('1 left'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('typing a plate turns Confirm into "Confirm with this plate" and blocks False alarm', (tester) async {
      await show(tester, InboxScreen(client: busyBackend().client));
      await tester.tap(find.text('Batch ab12cd34'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'ZZZ 123');
      await tester.pump();
      expect(find.text('Confirm with this plate'), findsOneWidget);
      expect(find.textContaining('can only be confirmed'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byWidgetPredicate((w) => w is OutlinedButton)).onPressed, isNull);
    });
  });

  group('Login', () {
    Future<GoRouter> pumpLogin(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final router = GoRouter(initialLocation: '/login', routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/overview', builder: (_, _) => const Text('overview page')),
        GoRoute(path: '/offline-video', builder: (_, _) => const Text('video page')),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router));
      await tester.pump(const Duration(milliseconds: 100));
      return router;
    }

    testWidgets('an officer lands on the Overview', (tester) async {
      OfficerMode.enabled.value = true;
      await pumpLogin(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('overview page'), findsOneWidget);
    });

    testWidgets('the full view keeps going to Video Analysis, and Enter signs in', (tester) async {
      await pumpLogin(tester);
      await tester.enterText(find.byType(TextField).last, 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('video page'), findsOneWidget);
    });

    testWidgets('the password can be shown', (tester) async {
      await pumpLogin(tester);
      expect(tester.widget<TextField>(find.byType(TextField).last).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField).last).obscureText, isFalse);
    });
  });

  group('ago', () {
    final now = DateTime(2026, 11, 2, 12);
    test('says it the way an officer scans it', () {
      expect(ago(null), 'unknown time');
      expect(ago(now, now: now), 'just now');
      expect(ago(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
      expect(ago(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
      expect(ago(now.subtract(const Duration(days: 1, hours: 1)), now: now), 'yesterday');
      expect(ago(now.subtract(const Duration(days: 3)), now: now), '3 days ago');
      expect(ago(now.subtract(const Duration(days: 30)), now: now), '2026-10-03');
    });
  });
}
