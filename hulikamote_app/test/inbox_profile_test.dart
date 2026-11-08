import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_app/core/config/app_config.dart';
import 'package:hulikamote_app/core/services/dev_mode.dart';
import 'package:hulikamote_app/core/services/portal_api.dart';
import 'package:hulikamote_app/core/services/session.dart';
import 'package:hulikamote_app/features/notifications/screens/notifications_screen.dart';
import 'package:hulikamote_app/features/profile/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(signedInPrefs);
    await AppConfig.load();
    DevMode.enabled.value = false;
  });

  group('Inbox', () {
    final now = DateTime.now();
    List<FakePortal> portals() => [
          FakePortal(notices: [
            notice('n1', 'Traffic violation recorded: No Helmet (ANA 777)', now),
            notice('n2', 'Traffic violation recorded: Counterflow (ANA 777)', now.subtract(const Duration(days: 1))),
            notice('n3', 'Traffic violation recorded: Red Light (ANA 777)', now.subtract(const Duration(days: 9))),
          ]),
        ];

    testWidgets('groups notices by day under plain headers and shortens the long subject', (tester) async {
      await pumpPage(tester, NotificationsScreen(api: portals().first));
      await settle(tester);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('No Helmet · ANA 777'), findsOneWidget);
      expect(find.textContaining('Traffic violation recorded'), findsNothing);
    });

    testWidgets('opening a notice shows its text, and it is remembered as read', (tester) async {
      await pumpPage(tester, NotificationsScreen(api: portals().first));
      await settle(tester);

      await tester.tap(find.text('No Helmet · ANA 777'));
      await settle(tester);
      expect(find.textContaining('A traffic violation was recorded for plate ANA 777.'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('inbox_read_user_9'), ['n1']);
    });

    testWidgets('with no notices it explains when one will come', (tester) async {
      await pumpPage(tester, NotificationsScreen(api: FakePortal()));
      await settle(tester);
      expect(find.text('No notices yet'), findsOneWidget);
      expect(find.textContaining('when a ticket is confirmed'), findsOneWidget);
    });

    testWidgets('offline, the saved notices are shown with a note and a retry', (tester) async {
      await pumpPage(tester, NotificationsScreen(api: portals().first));
      await settle(tester);                                                          // saves a copy
      await tester.pumpWidget(const SizedBox());
      final offline = FakePortal()..failure = PortalException('Cannot reach the cloud. Is the phone online?');
      await tester.pumpWidget(MaterialApp(home: NotificationsScreen(key: UniqueKey(), api: offline)));
      await settle(tester);
      expect(find.textContaining('Showing what was saved'), findsOneWidget);
      expect(find.text('No Helmet · ANA 777'), findsOneWidget);
    });

    testWidgets('offline with nothing saved, the problem is explained and can be retried', (tester) async {
      final portal = FakePortal(notices: [notice('n1', 'Traffic violation recorded: No Helmet (ANA 777)', now)])
        ..failure = PortalException('Cannot reach the laptop at 192.168.68.109:8000.');
      await pumpPage(tester, NotificationsScreen(api: portal));
      await settle(tester);
      expect(find.textContaining('Cannot reach the laptop'), findsOneWidget);
      portal.failure = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('No Helmet · ANA 777'), findsOneWidget);
    });
  });

  group('Profile', () {
    testWidgets('shows who is signed in, how the phone connects and how to check notifications', (tester) async {
      await pumpPage(tester, const ProfileScreen());
      await settle(tester);
      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.text('Plate ANA 777'), findsOneWidget);
      expect(find.text('ana@example.test'), findsOneWidget);
      expect(find.text('Same Wi-Fi'), findsOneWidget);
      expect(find.text('Send a test notification'), findsOneWidget);
    });

    testWidgets('signing out asks first, and then forgets the sign-in and goes to the sign-in page', (tester) async {
      await pumpPage(tester, const ProfileScreen(), routes: {'/login': (_) => const Scaffold(body: Text('the sign-in page'))});
      await settle(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await settle(tester);
      expect(find.text('Sign out?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect((await Session.current())?.userId, 'user_9');                           // cancelling changes nothing

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await settle(tester);
      expect(find.text('the sign-in page'), findsOneWidget);
      expect(await Session.current(), isNull);
      expect(AppConfig.hasServer, isTrue);                                           // the connection is kept
    });

    testWidgets('seven taps on the version line switch on developer mode (and a hint shows near the end)', (tester) async {
      await pumpPage(tester, const ProfileScreen());
      await settle(tester);
      final version = find.textContaining('version 1.0.0');
      for (var i = 0; i < 4; i++) {
        await tester.tap(version);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(DevMode.enabled.value, isFalse);
      expect(find.text('3 more taps for developer mode.'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(version);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);
      expect(DevMode.enabled.value, isTrue);
      expect(find.text('Developer tools'), findsOneWidget);
    });
  });
}
