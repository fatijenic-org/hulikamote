import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_app/core/config/app_config.dart';
import 'package:hulikamote_app/core/services/portal_api.dart';
import 'package:hulikamote_app/core/ui/widgets.dart';
import 'package:hulikamote_app/features/home/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(signedInPrefs);
    await AppConfig.load();
  });

  group('Records', () {
    testWidgets('greets the motorist, counts the tickets and shows where each appeal stands', (tester) async {
      final portal = FakePortal(
        tickets: [ticket('t1'), ticket('t2', cls: 'counterflow'), ticket('t3', cls: 'red_light')],
        appeals: {'t2': 'pending', 't3': 'accepted'},
      );
      await pumpPage(tester, HomeScreen(api: portal));
      await settle(tester);

      expect(find.text('Hi, Ana'), findsOneWidget);
      expect(find.textContaining('plate ANA 777'), findsOneWidget);
      expect(find.text('Can appeal'), findsNWidgets(3));              // the tile, the filter and the one open ticket's chip
      expect(find.text('Appeal sent'), findsOneWidget);
      expect(find.text('Appeal accepted'), findsOneWidget);
      expect(find.text('No Helmet'), findsOneWidget);
      expect(find.text('Counterflow'), findsOneWidget);
    });

    testWidgets('the filters narrow the list', (tester) async {
      final portal = FakePortal(tickets: [ticket('t1'), ticket('t2', cls: 'counterflow')], appeals: {'t2': 'pending'});
      await pumpPage(tester, HomeScreen(api: portal));
      await settle(tester);
      Finder segment(String label) => find.descendant(of: find.byWidgetPredicate((w) => w is SegmentedButton), matching: find.text(label));

      await tester.tap(segment('Appealed'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Counterflow'), findsOneWidget);
      expect(find.text('No Helmet'), findsNothing);

      await tester.tap(segment('Can appeal'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No Helmet'), findsOneWidget);
      expect(find.text('Counterflow'), findsNothing);
    });

    testWidgets('a filter with nothing in it says why and offers all the tickets', (tester) async {
      final portal = FakePortal(tickets: [ticket('t1')], appeals: {});
      await pumpPage(tester, HomeScreen(api: portal));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byWidgetPredicate((w) => w is SegmentedButton), matching: find.text('Appealed')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No appeals yet'), findsOneWidget);
      await tester.tap(find.text('Show all tickets'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No Helmet'), findsOneWidget);
    });

    testWidgets('a motorist with nothing on record is told so, kindly', (tester) async {
      await pumpPage(tester, HomeScreen(api: FakePortal()));
      await settle(tester);
      expect(find.text('Nothing on your record'), findsOneWidget);
      expect(find.textContaining('When a ticket is confirmed'), findsOneWidget);
    });

    testWidgets('while loading, it shows placeholders instead of a blank page', (tester) async {
      await pumpPage(tester, HomeScreen(api: FakePortal(tickets: [ticket('t1')])..delay = const Duration(milliseconds: 500)));
      expect(find.byType(SkeletonList), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.byType(SkeletonList), findsNothing);
      expect(find.text('No Helmet'), findsOneWidget);
    });

    testWidgets('when the system cannot be reached and nothing is saved, it says what happened and can try again', (tester) async {
      final portal = FakePortal(tickets: [ticket('t1')])..failure = PortalException('Cannot reach the cloud. Is the phone online?');
      await pumpPage(tester, HomeScreen(api: portal));
      await settle(tester);
      expect(find.text('Cannot reach the cloud. Is the phone online?'), findsOneWidget);

      portal.failure = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('No Helmet'), findsOneWidget);
    });

    testWidgets('when the system cannot be reached but a copy was saved, the copy is shown with a clear note', (tester) async {
      final portal = FakePortal(tickets: [ticket('t1', cls: 'counterflow')], appeals: {'t1': 'pending'});
      await pumpPage(tester, HomeScreen(api: portal));
      await settle(tester);                                              // a successful load saves a copy

      final offline = FakePortal()..failure = PortalException('Cannot reach the laptop at 192.168.68.109:8000.');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: HomeScreen(key: UniqueKey(), api: offline)));
      await settle(tester);

      expect(find.textContaining('Showing what was saved'), findsOneWidget);
      expect(find.text('Counterflow'), findsOneWidget);                   // still there
      expect(find.text('Appeal sent'), findsOneWidget);                   // with its appeal state
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
