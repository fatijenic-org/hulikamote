import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_app/core/config/app_config.dart';
import 'package:hulikamote_app/core/services/portal_api.dart';
import 'package:hulikamote_app/features/home/screens/violation_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

/// The ticket page opened from a list, so that "back" has somewhere to go and brings the answer back.
Future<List<bool?>> openTicket(WidgetTester tester, FakePortal portal, {String? status}) async {
  final results = <bool?>[];
  await pumpPage(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => results.add(await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => ViolationDetailScreen(violation: ticket('ab12cd34-0000'), appealStatus: status, api: portal),
            ))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
  return results;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(signedInPrefs);
    await AppConfig.load();
  });

  group('a ticket', () {
    testWidgets('shows the facts and the story so far, and offers an appeal while one is allowed', (tester) async {
      await openTicket(tester, FakePortal());
      expect(find.text('No Helmet'), findsWidgets);
      expect(find.text('Plate'), findsOneWidget);
      expect(find.text('ANA 777'), findsOneWidget);
      expect(find.text('AB12CD34'), findsOneWidget);                                  // the case number
      expect(find.text('Seen by the camera'), findsOneWidget);
      expect(find.text('Confirmed by a reviewer'), findsOneWidget);
      expect(find.text('Appeal this ticket'), findsOneWidget);
    });

    testWidgets('a ticket that was appealed shows how the appeal stands instead of the button', (tester) async {
      await openTicket(tester, FakePortal(), status: 'pending');
      expect(find.text('Appeal this ticket'), findsNothing);
      expect(find.text('Appeal sent'), findsWidgets);
      expect(find.text('A reviewer has not decided yet.'), findsWidgets);
    });

    testWidgets('a rejected appeal says so plainly', (tester) async {
      await openTicket(tester, FakePortal(), status: 'rejected');
      expect(find.text('Appeal rejected'), findsWidgets);
      expect(find.text('Appeal this ticket'), findsNothing);
    });
  });

  group('appealing', () {
    testWidgets('a reason can be started from a suggestion, is sent, and the ticket then shows the appeal', (tester) async {
      final portal = FakePortal();
      final results = await openTicket(tester, portal);
      await tester.tap(find.text('Appeal this ticket'));
      await settle(tester);

      await tester.tap(find.text('I was not the one driving.'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Your reason'), 'I was not the one driving. My brother had the car.');
      await tester.tap(find.text('Send appeal'));
      await settle(tester);

      expect(portal.appealsFiled.single, {'violation': 'ab12cd34-0000', 'user': 'user_9', 'reason': 'I was not the one driving. My brother had the car.'});
      expect(find.text('Appeal sent'), findsOneWidget);
      expect(find.textContaining('You will see the result on this ticket'), findsOneWidget);

      await tester.tap(find.text('Back to the ticket'));
      await settle(tester);
      expect(find.text('Appeal this ticket'), findsNothing);                          // the ticket page already shows the new state
      expect(find.text('Appeal sent'), findsWidgets);

      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(results, [true]);                                                        // and the list is told to refresh
    });

    testWidgets('an empty reason is not sent, and the motorist is told what to do', (tester) async {
      final portal = FakePortal();
      await openTicket(tester, portal);
      await tester.tap(find.text('Appeal this ticket'));
      await settle(tester);
      await tester.tap(find.text('Send appeal'));
      await settle(tester);
      expect(find.text('Tell the reviewer why you think this ticket is wrong.'), findsOneWidget);
      expect(portal.appealsFiled, isEmpty);
    });

    testWidgets('when sending fails, the reason stays and the problem is explained', (tester) async {
      final portal = FakePortal()..failure = PortalException('You already appealed this ticket.');
      await openTicket(tester, portal);
      await tester.tap(find.text('Appeal this ticket'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Your reason'), 'It was not me.');
      await tester.tap(find.text('Send appeal'));
      await settle(tester);
      expect(find.text('You already appealed this ticket.'), findsOneWidget);
      expect(find.text('It was not me.'), findsOneWidget);                            // nothing typed is lost
      expect(find.text('Appeal sent'), findsNothing);
    });
  });
}
