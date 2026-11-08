import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_app/core/models/notice.dart';
import 'package:hulikamote_app/core/services/demo_accounts.dart';
import 'package:hulikamote_app/core/services/dev_mode.dart';
import 'package:hulikamote_app/core/services/friendly_error.dart';
import 'package:hulikamote_app/core/services/local_cache.dart';
import 'package:hulikamote_app/core/services/portal_api.dart';
import 'package:hulikamote_app/core/ui/app_theme.dart';
import 'package:hulikamote_app/core/ui/format.dart';
import 'package:hulikamote_app/core/ui/widgets.dart';
import 'package:hulikamote_app/core/utils/plate.dart';
import 'package:hulikamote_app/features/home/models/appeal_state.dart';
import 'package:hulikamote_app/features/home/models/violation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the building blocks', () {
    testWidgets('a button that is working shows a spinner, and ignores taps', (tester) async {
      var taps = 0;
      await pumpPage(tester, Scaffold(body: Center(child: AppButton(label: 'Send', loading: true, onPressed: () => taps++))));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('a button without an action is disabled, and one with an action fires', (tester) async {
      var taps = 0;
      await pumpPage(tester, Scaffold(body: Column(children: [const AppButton(label: 'Off', onPressed: null), AppButton(label: 'On', onPressed: () => taps++)])));
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Off')).onPressed, isNull);
      await tester.tap(find.text('On'));
      expect(taps, 1);
    });

    testWidgets('a status chip carries words and an icon, not only a colour', (tester) async {
      await pumpPage(tester, const Scaffold(body: Center(child: StatusChip(label: 'Appeal sent', tone: Tone.warning, icon: Icons.hourglass_top_rounded))));
      expect(find.text('Appeal sent'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    });

    testWidgets('the password box hides what is typed and can show it on request', (tester) async {
      final controller = TextEditingController(text: 'secret1');
      await pumpPage(tester, Scaffold(body: AppField(controller: controller, label: 'Password', password: true)));
      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(field().obscureText, isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(field().obscureText, isTrue);
    });

    testWidgets('an error state offers to try again, and the banner can carry an action', (tester) async {
      var retried = 0, acted = 0;
      await pumpPage(tester, Scaffold(body: Column(children: [
        Expanded(child: ErrorState(message: 'Cannot reach the cloud.', onRetry: () => retried++)),
        InfoBanner(message: 'Offline', actionLabel: 'Retry', onAction: () => acted++),
      ])));
      await tester.tap(find.text('Try again'));
      await tester.tap(find.text('Retry'));
      expect((retried, acted), (1, 1));
    });

    testWidgets('it also looks right in the dark', (tester) async {
      await pumpPage(tester, const Scaffold(body: Column(children: [StatusChip(label: 'Appeal accepted', tone: Tone.success), InfoBanner(message: 'Hello', tone: Tone.danger)])), theme: AppTheme.dark());
      expect(find.text('Appeal accepted'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
    });
  });

  group('words and numbers', () {
    test('dates and times read plainly', () {
      final t = DateTime(2026, 10, 29, 15, 7);
      expect(dateOf(t), 'Oct 29, 2026');
      expect(timeOf(t), '3:07 PM');
      expect(timeOf(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
      expect(timeOf(DateTime(2026, 1, 1, 12, 0)), '12:00 PM');
      expect(dateTimeOf(t), 'Oct 29, 2026 · 3:07 PM');
      expect(dateTimeOf(null, 'unknown'), 'unknown');
    });

    test('days are named Today, Yesterday or by date, and recent times as "ago"', () {
      final now = DateTime(2026, 10, 29, 12);
      expect(dayHeader(DateTime(2026, 10, 29, 8), now), 'Today');
      expect(dayHeader(DateTime(2026, 10, 28, 23), now), 'Yesterday');
      expect(dayHeader(DateTime(2026, 10, 20), now), 'Tue, Oct 20');
      expect(dayHeader(DateTime(2025, 12, 31), now), 'Wed, Dec 31, 2025');
      expect(ago(now.subtract(const Duration(seconds: 20)), now), 'just now');
      expect(ago(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
      expect(ago(now.subtract(const Duration(hours: 3)), now), '3 h ago');
      expect(ago(DateTime(2026, 10, 1), now), 'Oct 1, 2026');
    });

    test('initials come from the first and last name', () {
      expect(InitialsAvatar.initials('Ana Cruz'), 'AC');
      expect(InitialsAvatar.initials('  juan   de la   Cruz '), 'JC');
      expect(InitialsAvatar.initials('Maria'), 'M');
      expect(InitialsAvatar.initials(''), '?');
    });

    test('a notice has a short title and a ticket a case number and a plate that is blank when unknown', () {
      expect(notice('n', 'Traffic violation recorded: No Helmet (ABC 1234)', DateTime.now()).title, 'No Helmet · ABC 1234');
      expect(const Notice(id: 'n', subject: 'Something else', body: '', createdAt: '').title, 'Something else');
      expect(ticket('ab12cd34-0000').caseNo, 'AB12CD34');
      expect(Violation.fromJson({'id': 'x', 'cls': 'c', 'confidence': 1, 'timestamp': 't', 'plate_text': 'unidentified'}).plate, '');
      expect(Violation.fromJson({'id': 'x', 'cls': 'c', 'confidence': 1, 'timestamp': 't', 'plate_text': 'ABC 1234'}).plate, 'ABC 1234');
    });

    test('a ticket saved on the phone comes back the same, photo paths included', () {
      final saved = ticket('t1', cls: 'counterflow', frames: ['u-1/t1/a.jpg', 'u-1/t1/b.jpg']);
      final back = Violation.fromCache(saved.toJson());
      expect((back.id, back.cls, back.plate), ('t1', 'counterflow', 'ANA 777'));
      expect(back.evidencePaths, ['u-1/t1/a.jpg', 'u-1/t1/b.jpg']);
    });

    test('each appeal state has words, a tone and whether another appeal is allowed', () {
      expect(AppealState.of(null).open, isTrue);
      for (final s in ['pending', 'accepted', 'rejected']) {
        expect(AppealState.of(s).open, isFalse, reason: s);
      }
      expect(AppealState.of('accepted').tone, Tone.success);
      expect(AppealState.of('rejected').tone, Tone.danger);
      expect(iconForViolation('counterflow, illegal_parking'), iconForViolation('counterflow'));
      expect(iconForViolation('something_new'), Icons.report_problem_outlined);
    });

    test('sign-up errors are per field, and the password hint follows the typing', () {
      final errors = signUpErrors(name: '', plate: '---', password: '123', repeat: '124', email: 'nope');
      expect(errors.keys.toSet(), {'name', 'plate', 'email', 'password', 'repeat'});
      expect(signUpErrors(name: 'A', plate: 'ABC 1', password: 'secret1', repeat: 'secret1'), isEmpty);
      expect(passwordHint(''), 'At least 6 characters.');
      expect(passwordHint('abc'), '3 more to go.');
      expect(passwordHint('abcdef'), 'Good. A longer one is stronger.');
      expect(passwordHint('abcdefghij'), 'Strong.');
    });

    test('errors reach the motorist in plain words', () {
      expect(friendlyMessage(PortalException('Wrong plate number or password.')), 'Wrong plate number or password.');
      expect(friendlyMessage(StateError('boom')), 'Something went wrong. Please try again.');
      expect(isConnectionProblem(PortalException('Cannot reach the cloud. Is the phone online?')), isTrue);
      expect(isConnectionProblem(PortalException('That ticket is not yours.')), isFalse);
    });
  });

  group('what the phone keeps', () {
    test('a saved copy remembers when it was saved, belongs to one motorist, and can be cleared', () async {
      await LocalCache.save('tickets', 'u1', [1, 2, 3]);
      await LocalCache.save('tickets', 'u2', [9]);
      final mine = await LocalCache.load('tickets', 'u1');
      expect(mine!.data, [1, 2, 3]);
      expect(DateTime.now().difference(mine.at).inSeconds, lessThan(5));
      expect((await LocalCache.load('tickets', 'u2'))!.data, [9]);
      expect(await LocalCache.load('notices', 'u1'), isNull);
      await LocalCache.clear('u1');
      expect(await LocalCache.load('tickets', 'u1'), isNull);
      expect(await LocalCache.load('tickets', 'u2'), isNotNull);
    });

    test('a damaged saved copy is ignored instead of crashing', () async {
      SharedPreferences.setMockInitialValues({'cache_tickets_u1': 'not json'});
      expect(await LocalCache.load('tickets', 'u1'), isNull);
    });

    test('the demo accounts start as the three motorists and can be added to, changed, removed and reset', () async {
      expect((await DemoAccounts.load()).map((a) => a.name), ['Juan', 'Maria', 'Pedro']);
      await DemoAccounts.upsert(const DemoAccount('Ana', 'ana 777', 'secret1'));
      expect((await DemoAccounts.load()).map((a) => a.name), ['Juan', 'Maria', 'Pedro', 'Ana']);
      await DemoAccounts.upsert(const DemoAccount('Ana C.', 'ANA-777', 'newpass1'));              // same plate: replaced, not added
      final all = await DemoAccounts.load();
      expect(all.length, 4);
      expect((all.last.name, all.last.password), ('Ana C.', 'newpass1'));
      await DemoAccounts.remove('abc 1234');
      expect((await DemoAccounts.load()).map((a) => a.name), ['Maria', 'Pedro', 'Ana C.']);
      await DemoAccounts.reset();
      expect((await DemoAccounts.load()).length, 3);
    });

    test('developer mode is off until it is switched on, and the choice is kept', () async {
      await DevMode.load();
      expect(DevMode.enabled.value, isFalse);
      await DevMode.set(true);
      DevMode.enabled.value = false;
      await DevMode.load();
      expect(DevMode.enabled.value, isTrue);
      await DevMode.set(false);
    });
  });
}
