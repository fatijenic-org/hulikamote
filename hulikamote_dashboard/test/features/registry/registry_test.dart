import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/registry/data/registry_api.dart';
import 'package:hulikamote_dashboard/features/registry/domain/registry_models.dart';
import 'package:hulikamote_dashboard/features/registry/presentation/screens/registry_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../forensic/support/test_support.dart';

Map<String, dynamic> _juan({String email = '', List<String> plates = const ['ABC 1234']}) =>
    {'id': 'user_001', 'name': 'Juan Dela Cruz', 'license_no': 'N01-12-345678', 'email': email, 'plates': plates};

RegistryApi _api(Future<http.Response> Function(http.Request) handler) =>
    RegistryApi(baseUrl: 'http://test', client: MockClient(handler));

/// A backend that answers from memory and remembers what the tab asked of it.
class FakeRegistry extends RegistryApi {
  FakeRegistry() : super(baseUrl: 'http://test');

  Map<String, dynamic> juan = _juan();
  RegistryApiException? nextError;
  final calls = <String>[];

  NoticeSettings notice = const NoticeSettings(mode: 'offline', mailboxUrls: ['http://192.168.68.112:8000/mailbox']);
  TestEmailResult testResult = const TestEmailResult(status: 'sent', to: 'me@gmail.com');

  void _maybeFail() {
    final e = nextError;
    nextError = null;
    if (e != null) throw e;
  }

  @override
  Future<List<Motorist>> motorists() async => [Motorist.fromJson(juan)];

  @override
  Future<void> setEmail(String userId, String email) async {
    calls.add('email $userId $email');
    _maybeFail();
    juan = {...juan, 'email': email};
  }

  @override
  Future<void> registerPlate(String plate, String userId) async {
    calls.add('add $plate $userId');
    _maybeFail();
    juan = {...juan, 'plates': [...juan['plates'] as List, plate]};
  }

  @override
  Future<NoticeSettings> noticeSettings() async => notice;

  @override
  Future<NoticeSettings> saveNoticeSettings({
    required String mode,
    String gmail = '',
    String appPassword = '',
    String supabaseUrl = '',
    String supabaseServiceKey = '',
  }) async {
    calls.add('notice $mode ${gmail.isEmpty ? '-' : gmail} ${appPassword.isEmpty ? '-' : 'pw'}${supabaseUrl.isEmpty ? '' : ' cloud $supabaseUrl ${supabaseServiceKey.isEmpty ? '-' : 'key'}'}');
    _maybeFail();
    notice = NoticeSettings(
      mode: mode,
      gmail: gmail.isEmpty ? notice.gmail : gmail,
      cloudUrl: supabaseUrl.isEmpty ? notice.cloudUrl : supabaseUrl,
      cloudKeySet: notice.cloudKeySet || supabaseServiceKey.isNotEmpty,
      passwordSet: notice.passwordSet || appPassword.isNotEmpty,
      mailboxUrls: notice.mailboxUrls,
      notices: notice.notices,
    );
    return notice;
  }

  CloudTestResult cloudResult = const CloudTestResult(ok: true, detail: 'Connected.');

  @override
  Future<CloudTestResult> testCloud() async {
    calls.add('cloud-test');
    return cloudResult;
  }

  List<CloudAccountResult> demoResults = const [
    CloudAccountResult(plate: 'ABC 1234', status: 'created'),
    CloudAccountResult(plate: 'DEF 5678', status: 'exists'),
  ];
  PushResult pushResult = const PushResult(ready: true, detail: 'Push is ready (Firebase project demo-1).');

  @override
  Future<List<CloudAccountResult>> createCloudDemoAccounts() async {
    calls.add('demo-accounts');
    return demoResults;
  }

  @override
  Future<PushResult> pushCheck() async {
    calls.add('push-check');
    return pushResult;
  }

  @override
  Future<PushResult> sendTestPush() async {
    calls.add('push-test');
    return pushResult;
  }

  @override
  Future<TestEmailResult> sendTestEmail({String to = ''}) async {
    calls.add('test $to');
    return testResult;
  }

  @override
  Future<void> removePlate(String plate) async {
    calls.add('remove $plate');
    juan = {...juan, 'plates': [for (final p in juan['plates'] as List) if (p != plate) p]};
  }
}

void main() {
  setUpAll(loadRoboto);

  group('talking to the backend', () {
    test('a motorist is read with the e-mail and plates on file', () {
      final m = Motorist.fromJson(_juan(email: 'juan@example.test'));
      expect((m.id, m.name, m.licenseNo, m.email), ('user_001', 'Juan Dela Cruz', 'N01-12-345678', 'juan@example.test'));
      expect(m.plates, ['ABC 1234']);
      expect(Motorist.fromJson(const {}).plates, isEmpty);
    });

    test('each change goes to its own address with the right body', () async {
      final seen = <String>[];
      final api = _api((req) async {
        seen.add('${req.method} ${req.url.path} ${req.body}');
        return http.Response(jsonEncode({'motorists': [_juan()]}), 200);
      });
      expect((await api.motorists()).single.name, 'Juan Dela Cruz');
      await api.setEmail('user_001', 'juan@example.test');
      await api.registerPlate('ABC 1234', 'user_001');
      await api.removePlate('ABC 1234');
      expect(seen, [
        'GET /registry ',
        'PUT /registry/motorists/user_001/email {"email":"juan@example.test"}',
        'PUT /registry/plates/ABC%201234 {"user_id":"user_001"}',
        'DELETE /registry/plates/ABC%201234 ',
      ]);
    });

    test('the backend\'s own explanation reaches the screen', () async {
      final api = _api((req) async => http.Response(jsonEncode({'detail': 'That does not look like an e-mail address'}), 400));
      expect(api.setEmail('user_001', 'nope'), throwsA(isA<RegistryApiException>().having((e) => e.message, 'message', 'That does not look like an e-mail address')));
    });

    test('an old backend without the registry says to restart it, and a dead one says it is not running', () async {
      final old = _api((req) async => http.Response('{"detail":"Not Found"}', 404));
      expect(old.motorists(), throwsA(isA<RegistryApiException>().having((e) => e.message, 'message', contains('Restart the backend'))));
      final dead = _api((req) async => throw Exception('refused'));
      expect(dead.motorists(), throwsA(isA<RegistryApiException>().having((e) => e.message, 'message', contains('Is it running?'))));
    });
  });

  group('the notification card (online or offline)', () {
    Future<FakeRegistry> open(WidgetTester tester, [FakeRegistry? api]) async {
      api ??= FakeRegistry();
      await pumpScreen(tester, RegistryScreen(api: api), size: const Size(1600, 1400));
      await tester.pump(const Duration(milliseconds: 100));
      return api;
    }

    testWidgets('offline shows the address a phone on the same Wi-Fi opens, with a copy button', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await open(tester);
      expect(find.text('http://192.168.68.112:8000/mailbox'), findsOneWidget);
      expect(find.text('Sender Gmail (the HULI-KAMOTE account)'), findsNothing);
      await tester.tap(find.byTooltip('Copy address'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(copied, 'http://192.168.68.112:8000/mailbox');
      expect(find.text('Address copied.'), findsOneWidget);
    });

    testWidgets('with no network address it says to connect the laptop first', (tester) async {
      await open(tester, FakeRegistry()..notice = const NoticeSettings(mode: 'offline'));
      expect(find.textContaining('No Wi-Fi or hotspot address found'), findsOneWidget);
    });

    testWidgets('Online with nothing saved only shows the Gmail form; Save and switch on sends the login', (tester) async {
      final api = await open(tester);
      await tester.tap(find.text('Online'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls, isEmpty);                                               // nothing is switched on without a login
      expect(find.text('Sender Gmail (the HULI-KAMOTE account)'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Sender Gmail (the HULI-KAMOTE account)'), ' me@gmail.com ');
      await tester.enterText(find.widgetWithText(TextField, 'App password'), 'abcd efgh ijkl mnop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save and switch on'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls, ['notice online me@gmail.com pw']);
      expect(find.text('Saved. Notices are e-mailed through Gmail.'), findsOneWidget);
      expect(find.text('Save and switch on'), findsNothing);                      // it is on now
    });

    testWidgets('the password box never shows what was typed', (tester) async {
      await open(tester);
      await tester.tap(find.text('Online'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'App password')).obscureText, isTrue);
    });

    testWidgets('Offline is one click and keeps the saved login', (tester) async {
      final api = await open(tester, FakeRegistry()..notice = const NoticeSettings(mode: 'online', gmail: 'me@gmail.com', passwordSet: true));
      await tester.tap(find.text('Offline (same Wi-Fi)'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls, ['notice offline - -']);
      await tester.tap(find.text('Online'));                              // and back: one click, no retyping
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls.last, 'notice online - -');
    });

    testWidgets('the test e-mail button says the e-mail went out', (tester) async {
      final api = await open(tester, FakeRegistry()..notice = const NoticeSettings(mode: 'online', gmail: 'me@gmail.com', passwordSet: true));
      await tester.enterText(find.widgetWithText(TextField, 'Send the test to (your own e-mail)'), ' mine@example.test ');
      await tester.pump();
      await tester.tap(find.text('Send test e-mail'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls, ['test mine@example.test']);                              // from the sender account, to the address typed
      expect(find.text('Test e-mail sent to me@gmail.com. Check that inbox.'), findsOneWidget);
    });

    testWidgets('the test e-mail button explains a refused login', (tester) async {
      final api = FakeRegistry()
        ..notice = const NoticeSettings(mode: 'online', gmail: 'me@gmail.com', passwordSet: true)
        ..testResult = const TestEmailResult(status: 'failed', detail: 'The mail server refused the login.');
      await open(tester, api);
      await tester.enterText(find.widgetWithText(TextField, 'Send the test to (your own e-mail)'), 'mine@example.test');
      await tester.pump();
      await tester.tap(find.text('Send test e-mail'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('The test e-mail failed: The mail server refused the login.'), findsOneWidget);
    });

    testWidgets('the test e-mail button waits for a destination and for the typed login to be saved', (tester) async {
      await open(tester, FakeRegistry()..notice = const NoticeSettings(mode: 'online', gmail: 'me@gmail.com', passwordSet: true));
      OutlinedButton test() => tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Send test e-mail'));
      expect(test().onPressed, isNull);                                            // no destination yet
      await tester.enterText(find.widgetWithText(TextField, 'Send the test to (your own e-mail)'), 'mine@example.test');
      await tester.pump();
      expect(test().onPressed, isNotNull);
      await tester.enterText(find.widgetWithText(TextField, 'Sender Gmail (the HULI-KAMOTE account)'), 'other@gmail.com');
      await tester.pump();
      expect(test().onPressed, isNull);                                            // the typed login is not saved yet
    });

    testWidgets('a refused change shows the backend\'s reason', (tester) async {
      final api = await open(tester, FakeRegistry()..notice = const NoticeSettings(mode: 'online', gmail: 'me@gmail.com', passwordSet: true));
      api.nextError = RegistryApiException('Could not save the settings');
      await tester.tap(find.text('Offline (same Wi-Fi)'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Could not save the settings'), findsOneWidget);
    });

    testWidgets('the phone app cloud: save the project and key, then test it', (tester) async {
      final api = await open(tester);
      await tester.tap(find.text('Online'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save cloud')).onPressed, isNull);   // nothing typed

      await tester.enterText(find.widgetWithText(TextField, 'Project address'), 'https://abc.supabase.co');
      await tester.enterText(find.widgetWithText(TextField, 'Service key (secret)'), 'service-role-key');
      await tester.pump();
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Test cloud')).onPressed, isNull);   // save first
      await tester.tap(find.widgetWithText(FilledButton, 'Save cloud'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls, ['notice online - - cloud https://abc.supabase.co key']);
      expect(find.text('Cloud saved.'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));            // the first message slides in, its timer starts
      await tester.pump(const Duration(seconds: 5));                    // it goes away
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Test cloud'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.calls.last, 'cloud-test');
      expect(find.text('Cloud: Connected.'), findsOneWidget);
    });

    testWidgets('demo accounts can be created in the cloud once it is saved, and the result is counted', (tester) async {
      final api = await open(tester, FakeRegistry()..notice = const NoticeSettings(mode: 'online', cloudUrl: 'https://abc.supabase.co', cloudKeySet: true));
      await tester.tap(find.text('Online'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Create demo accounts'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls, ['demo-accounts']);
      expect(find.text('Demo accounts in the cloud: 1 created, 1 already there.'), findsOneWidget);
    });

    testWidgets('a demo account that could not be made names the plate and the reason', (tester) async {
      final api = await open(tester, FakeRegistry()
        ..notice = const NoticeSettings(mode: 'online', cloudUrl: 'https://abc.supabase.co', cloudKeySet: true)
        ..demoResults = const [CloudAccountResult(plate: 'ABC 1234', status: 'failed', detail: 'run supabase/schema.sql again')]);
      await tester.tap(find.text('Online'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Create demo accounts'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('ABC 1234: run supabase/schema.sql again'), findsOneWidget);
      expect(api.calls, ['demo-accounts']);
    });

    testWidgets('demo accounts wait until the cloud is saved', (tester) async {
      await open(tester);
      await tester.tap(find.text('Online'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Create demo accounts')).onPressed, isNull);
    });

    testWidgets('push can be checked and tested, and what it says stays on screen', (tester) async {
      final api = await open(tester, FakeRegistry()
        ..pushResult = const PushResult(ready: true, detail: 'Sent to 2 of 3 phones.', phones: 3, sent: 2, failed: 1));
      await tester.tap(find.text('Online'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Check push'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Send test push'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls, ['push-check', 'push-test']);
      expect(find.text('Push: Sent to 2 of 3 phones.'), findsOneWidget);
    });

    testWidgets('a cloud that is not ready says what to fix', (tester) async {
      final api = FakeRegistry()
        ..notice = const NoticeSettings(mode: 'online', cloudUrl: 'https://abc.supabase.co', cloudKeySet: true)
        ..cloudResult = const CloudTestResult(ok: false, detail: 'Connected, but the tables are missing. Run supabase/schema.sql in the Supabase SQL editor.');
      await open(tester, api);
      await tester.tap(find.text('Test cloud'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('schema.sql'), findsOneWidget);
    });

    testWidgets('with the cloud saved, Online switches on in one click', (tester) async {
      final api = await open(tester, FakeRegistry()..notice = const NoticeSettings(mode: 'offline', cloudUrl: 'https://abc.supabase.co', cloudKeySet: true));
      await tester.tap(find.text('Online'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls, ['notice online - -']);
    });

    testWidgets('the last notices show whether each was e-mailed, left in the mailbox, or failed and why', (tester) async {
      await open(tester, FakeRegistry()..notice = NoticeSettings(mode: 'online', notices: [_notice('sent'), _notice('local'), _notice('failed', detail: 'network is down')]));
      expect(find.text('E-mailed'), findsOneWidget);
      expect(find.text('In mailbox'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.textContaining('(network is down)'), findsOneWidget);
    });
  });

  group('the Motorists tab', () {
    testWidgets('shows each motorist with the e-mail and plates on file', (tester) async {
      final api = FakeRegistry()..juan = _juan(email: 'juan@example.test');
      await pumpScreen(tester, RegistryScreen(api: api));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(find.text('Licence N01-12-345678'), findsOneWidget);
      expect(find.text('ABC 1234'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'juan@example.test'), findsOneWidget);
    });

    testWidgets('Save only lights up once the address was changed, and then saves it', (tester) async {
      final api = FakeRegistry();
      await pumpScreen(tester, RegistryScreen(api: api));
      await tester.pump(const Duration(milliseconds: 100));

      FilledButton save() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
      expect(save().onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, '  juan@example.test ');
      await tester.pump();
      expect(save().onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls, ['email user_001 juan@example.test']);                      // trimmed
      expect(find.text('E-mail saved.'), findsOneWidget);
      expect(save().onPressed, isNull);                                              // nothing left to save
    });

    testWidgets('a plate can be added and removed', (tester) async {
      final api = FakeRegistry();
      await pumpScreen(tester, RegistryScreen(api: api));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).last, 'xyz 987');                // the plate box comes after the e-mail box
      await tester.tap(find.byTooltip('Add plate'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls, ['add xyz 987 user_001']);
      expect(find.text('xyz 987'), findsOneWidget);                                  // listed once the backend has it

      await tester.tap(find.byTooltip('Remove ABC 1234'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls.last, 'remove ABC 1234');
      expect(find.text('ABC 1234'), findsNothing);
    });

    testWidgets('when the backend refuses a change, its reason is shown', (tester) async {
      final api = FakeRegistry()..nextError = RegistryApiException('That does not look like an e-mail address');
      await pumpScreen(tester, RegistryScreen(api: api));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).first, 'nope');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('That does not look like an e-mail address'), findsOneWidget);
    });

    testWidgets('a backend problem on loading is shown with a way to try again', (tester) async {
      final api = _DeadRegistry();
      await pumpScreen(tester, RegistryScreen(api: api));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Loading the motorists failed: the backend did not answer. Is it running?'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}

NoticeRecord _notice(String status, {String detail = ''}) => NoticeRecord(
    id: status, userName: 'Juan Dela Cruz', toEmail: 'juan@example.test', subject: 'Traffic violation recorded: No Helmet (ABC 1234)', status: status, detail: detail);

class _DeadRegistry extends RegistryApi {
  _DeadRegistry() : super(baseUrl: 'http://test');

  @override
  Future<List<Motorist>> motorists() async =>
      throw RegistryApiException('Loading the motorists failed: the backend did not answer. Is it running?');
}
