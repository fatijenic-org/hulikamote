import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_app/core/config/app_config.dart';
import 'package:hulikamote_app/core/services/cloud_portal_api.dart';
import 'package:hulikamote_app/core/services/photo_source.dart';
import 'package:hulikamote_app/core/services/portal_api.dart';
import 'package:hulikamote_app/core/services/session.dart';
import 'package:hulikamote_app/features/auth/widgets/connection_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const cloudPrefs = {'connection_mode': 'online', 'cloud_url': 'https://abc.supabase.co', 'cloud_anon_key': 'anon-key'};

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// A Supabase that answers from memory and remembers every request.
class FakeCloud {
  final requests = <http.Request>[];
  http.Response Function(http.Request req)? answer;

  CloudPortalApi get api => CloudPortalApi(client: MockClient((req) async {
        requests.add(req);
        return answer!(req);
      }));

  http.Request last(String path) => requests.lastWhere((r) => r.url.path == path);
}

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

Map<String, Object?> session(String access) => {'access_token': access, 'refresh_token': 'refresh-$access', 'expires_in': 3600, 'user': {'id': 'u-1'}};

Future<void> signedInAs(String access, {int expiresIn = 3600}) async {
  await Session.saveTokens(access: access, refresh: 'refresh-$access', expiresAt: _now() + expiresIn);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(cloudPrefs);
    await AppConfig.load();
    Session.accessToken = null;
  });

  group('online or on the same Wi-Fi', () {
    test('a project in the app means online, a laptop only means same Wi-Fi, nothing means online', () async {
      SharedPreferences.setMockInitialValues({'cloud_url': 'https://abc.supabase.co', 'cloud_anon_key': 'k', 'server_address': '1.2.3.4:8000'});
      await AppConfig.load();
      expect(AppConfig.isOnline, isTrue);
      SharedPreferences.setMockInitialValues({'server_address': '1.2.3.4:8000'});
      await AppConfig.load();
      expect(AppConfig.isOnline, isFalse);
      SharedPreferences.setMockInitialValues({});
      await AppConfig.load();
      expect(AppConfig.isOnline, isTrue);
      expect(AppConfig.ready, isFalse);                                                  // nothing is set up yet
    });

    test('what was chosen is kept, and ready means the chosen way is set up', () async {
      SharedPreferences.setMockInitialValues({'server_address': '1.2.3.4:8000'});
      await AppConfig.load();
      await AppConfig.setMode('online');
      expect(AppConfig.ready, isFalse);                                                  // online, but no cloud yet
      expect(await AppConfig.saveCloud('abc.supabase.co/rest/v1', ' ey J \n'), isTrue);
      expect((AppConfig.cloudUrl, AppConfig.cloudKey, AppConfig.ready), ('https://abc.supabase.co', 'eyJ', true));
      await AppConfig.load();                                                            // after a restart
      expect((AppConfig.isOnline, AppConfig.cloudUrl), (true, 'https://abc.supabase.co'));
    });

    test('a project address is cleaned up, and anything unusable saves nothing', () async {
      expect(AppConfig.normalizeCloudUrl('abc.supabase.co'), 'https://abc.supabase.co');
      expect(AppConfig.normalizeCloudUrl('https://abc.supabase.co/auth/v1/'), 'https://abc.supabase.co');
      for (final bad in ['', '  ', 'http://abc.supabase.co', 'a b.co', 'https://']) {
        expect(AppConfig.normalizeCloudUrl(bad), '', reason: bad);
      }
      expect(await AppConfig.saveCloud('not a url', 'key'), isFalse);
      expect(await AppConfig.saveCloud('abc.supabase.co', '   '), isFalse);
    });

    test('PortalApi() is the one that was chosen; a given laptop address always means the laptop', () {
      expect(PortalApi(), isA<CloudPortalApi>());
      expect(PortalApi(baseUrl: () => 'http://1.2.3.4:8000'), isA<LanPortalApi>());
    });
  });

  group('photos', () {
    test('online they come from the private bucket, one path part at a time, with the sign-in token', () async {
      await signedInAs('tok');
      Session.accessToken = 'tok';
      expect(PhotoSource.url('u-1/tick 1/f.jpg'), 'https://abc.supabase.co/storage/v1/object/authenticated/evidence/u-1/tick%201/f.jpg');
      expect(PhotoSource.headers, {'apikey': 'anon-key', 'Authorization': 'Bearer tok'});
    });

    test('on the laptop they come from its evidence folder with nothing extra', () async {
      SharedPreferences.setMockInitialValues({'connection_mode': 'lan', 'server_address': '1.2.3.4:8000'});
      await AppConfig.load();
      expect(PhotoSource.url('a b.jpg'), 'http://1.2.3.4:8000/snapshots/evidence/a%20b.jpg');
      expect(PhotoSource.headers, isNull);
    });
  });

  group('the cloud', () {
    test('the sign-in e-mail is made from the plate, however it is typed', () {
      expect(CloudPortalApi.emailFor(' abc-1234 '), 'abc1234@plates.hulikamote.app');
    });

    test('creating an account checks the plate is free, signs up with the details, and keeps the token', () async {
      final cloud = FakeCloud()
        ..answer = (req) => req.url.path == '/rest/v1/rpc/plate_taken' ? json(false) : json(session('tok-1'));
      final account = await cloud.api.register(name: 'Ana Cruz', plate: 'abc 1234', password: 'secret1', email: 'ana@example.test');

      expect(jsonDecode(cloud.last('/rest/v1/rpc/plate_taken').body), {'p_plate': 'abc 1234'});
      expect(cloud.requests.map((r) => r.url.path), ['/rest/v1/rpc/plate_taken', '/auth/v1/signup']);   // no second call to make a profile
      final signup = jsonDecode(cloud.last('/auth/v1/signup').body) as Map;
      expect(signup['email'], 'abc1234@plates.hulikamote.app');
      expect(signup['data'], {'name': 'Ana Cruz', 'plate': 'abc 1234', 'contact_email': 'ana@example.test'});   // the project's trigger reads these
      expect(cloud.last('/auth/v1/signup').headers['apikey'], 'anon-key');
      expect((account.userId, account.plate, account.name), ('u-1', 'ABC 1234', 'Ana Cruz'));
      expect((await Session.tokens())!.access, 'tok-1');
    });

    test('a plate that already has an account is refused before anything is created', () async {
      final cloud = FakeCloud()..answer = (req) => json(true);
      await expectLater(cloud.api.register(name: 'X', plate: 'ABC 1234', password: 'secret1'),
          throwsA(isA<PortalException>().having((e) => e.message, 'message', 'That plate already has an account.')));
      expect(cloud.requests.map((r) => r.url.path), ['/rest/v1/rpc/plate_taken']);                      // no sign-up was attempted
    });

    test('if two people race for a plate, the cloud\'s own refusal is put in plain words', () async {
      final cloud = FakeCloud()
        ..answer = (req) => req.url.path == '/rest/v1/rpc/plate_taken'
            ? json(false)
            : json({'code': 422, 'error_code': 'user_already_exists', 'msg': 'User already registered'}, 422);
      expect(cloud.api.register(name: 'X', plate: 'ABC 1234', password: 'secret1'),
          throwsA(isA<PortalException>().having((e) => e.message, 'message', 'That plate already has an account.')));
    });

    test('a project that has not had the SQL run is told so, and so is a broken sign-up trigger', () async {
      final missing = FakeCloud()..answer = (req) => json({'code': 'PGRST202', 'message': 'Could not find the function public.plate_taken'}, 404);
      await expectLater(missing.api.register(name: 'X', plate: 'ABC 1234', password: 'secret1'),
          throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('schema.sql'))));
      final broken = FakeCloud()
        ..answer = (req) => req.url.path == '/rest/v1/rpc/plate_taken' ? json(false) : json({'code': 500, 'error_code': 'unexpected_failure', 'msg': 'Database error saving new user'}, 500);
      await expectLater(broken.api.register(name: 'X', plate: 'ABC 1234', password: 'secret1'),
          throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('schema.sql'))));
    });

    test('a project that wants e-mail confirmation is told what to switch off', () async {
      final cloud = FakeCloud()
        ..answer = (req) => req.url.path == '/rest/v1/rpc/plate_taken' ? json(false) : json({'id': 'u-1', 'email': 'x', 'confirmation_sent_at': 'now'});
      expect(cloud.api.register(name: 'X', plate: 'ABC 1234', password: 'secret1'),
          throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('Confirm email'))));
    });

    test('signing in reads the profile with the new token', () async {
      final cloud = FakeCloud()
        ..answer = (req) => req.url.path == '/auth/v1/token'
            ? json(session('tok-2'))
            : json([{'user_id': 'u-1', 'plate': 'ABC 1234', 'name': 'Ana Cruz', 'email': 'ana@example.test'}]);
      final account = await cloud.api.login('ABC 1234', 'secret1');
      expect(cloud.last('/auth/v1/token').url.queryParameters['grant_type'], 'password');
      expect(cloud.last('/rest/v1/profiles').headers['Authorization'], 'Bearer tok-2');
      expect(cloud.last('/rest/v1/profiles').url.queryParameters['user_id'], 'eq.u-1');
      expect((account.name, account.email), ('Ana Cruz', 'ana@example.test'));
    });

    test('a wrong password reads as plain words', () async {
      final cloud = FakeCloud()..answer = (req) => json({'code': 400, 'error_code': 'invalid_credentials', 'msg': 'Invalid login credentials'}, 400);
      expect(cloud.api.login('ABC 1234', 'x'), throwsA(isA<PortalException>().having((e) => e.message, 'message', 'Wrong plate number or password.')));
    });

    test('tickets come as confirmed violations with the photo paths, as the signed-in motorist', () async {
      await signedInAs('tok-3');
      final cloud = FakeCloud()
        ..answer = (req) => json([{'id': 't-1', 'cls': 'no_helmet', 'confidence': 0.9, 'occurred_at': '2026-10-31T08:00:00+00:00', 'frames': ['u-1/t-1/a.jpg', 'u-1/t-1/b.jpg']}]);
      final tickets = await cloud.api.tickets('u-1');
      expect(cloud.last('/rest/v1/tickets').headers['Authorization'], 'Bearer tok-3');
      expect((tickets.single.id, tickets.single.displayClass), ('t-1', 'No Helmet'));
      expect(tickets.single.evidencePaths, ['u-1/t-1/a.jpg', 'u-1/t-1/b.jpg']);          // the full cloud paths are kept
    });

    test('notices are asked for newer than the last one seen (the time is encoded safely)', () async {
      await signedInAs('tok-4');
      final cloud = FakeCloud()
        ..answer = (req) => json([{'id': 'n-1', 'subject': 'S', 'body': 'B', 'frames': ['u-1/t-1/a.jpg'], 'created_at': '2026-10-31T09:00:00+00:00'}]);
      final notices = await cloud.api.notices('u-1', after: '2026-10-31T08:00:00.5+00:00');
      expect(cloud.last('/rest/v1/notices').url.queryParameters['created_at'], 'gt.2026-10-31T08:00:00.5+00:00');
      expect(cloud.last('/rest/v1/notices').url.toString(), contains('%2B'));                // a plus sign would have become a space
      expect(notices.single.subject, 'S');
      expect(notices.single.frames, ['u-1/t-1/a.jpg']);
      await cloud.api.notices('u-1', after: '');
      expect(cloud.last('/rest/v1/notices').url.queryParameters.containsKey('created_at'), isFalse);
    });

    test('an expired sign-in is renewed first, and the new token is used', () async {
      await signedInAs('old', expiresIn: 10);
      final cloud = FakeCloud()
        ..answer = (req) => req.url.path == '/auth/v1/token' ? json(session('fresh')) : json([]);
      await cloud.api.notices('u-1');
      expect(cloud.requests.first.url.queryParameters['grant_type'], 'refresh_token');
      expect(jsonDecode(cloud.requests.first.body), {'refresh_token': 'refresh-old'});
      expect(cloud.last('/rest/v1/notices').headers['Authorization'], 'Bearer fresh');
      expect(Session.accessToken, 'fresh');                                              // photos use it too
    });

    test('an appeal goes in as the motorist; a second one for the same ticket is refused', () async {
      await signedInAs('tok-5');
      final cloud = FakeCloud()..answer = (req) => http.Response('', 201);
      await cloud.api.fileAppeal(violationId: 't-1', userId: 'u-1', reason: 'I was parked');
      expect(jsonDecode(cloud.last('/rest/v1/appeals').body), {'ticket_id': 't-1', 'user_id': 'u-1', 'reason': 'I was parked'});
      cloud.answer = (req) => json({'code': '23505', 'message': 'duplicate key value'}, 409);
      expect(cloud.api.fileAppeal(violationId: 't-1', userId: 'u-1', reason: 'again'),
          throwsA(isA<PortalException>().having((e) => e.message, 'message', 'You already appealed this ticket.')));
    });

    test('the phone is registered for push through the project\'s function, as the signed-in motorist', () async {
      await signedInAs('tok-6');
      final cloud = FakeCloud()..answer = (req) => http.Response('', 204);
      await cloud.api.registerPushToken('fcm-token', 'u-1');
      final req = cloud.last('/rest/v1/rpc/register_device');
      expect(req.headers['Authorization'], 'Bearer tok-6');
      expect(jsonDecode(req.body), {'p_token': 'fcm-token'});                       // the owner is whoever is signed in
    });

    test('signing out stops pushes to this phone for that account', () async {
      await signedInAs('tok-6');
      final cloud = FakeCloud()..answer = (req) => http.Response('', 204);
      await cloud.api.forgetPushToken('fcm-token');
      final req = cloud.last('/rest/v1/rpc/forget_device');
      expect(req.headers['Authorization'], 'Bearer tok-6');
      expect(jsonDecode(req.body), {'p_token': 'fcm-token'});
    });

    test('without internet it says so; a signed-out phone is asked to sign in', () async {
      await signedInAs('tok-7');
      final offline = CloudPortalApi(client: MockClient((req) async => throw Exception('no route')));
      expect(offline.tickets('u-1'), throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('online'))));
      await Session.clear();
      expect(FakeCloud().api.tickets('u-1'), throwsA(isA<PortalException>().having((e) => e.message, 'message', 'Sign in again.')));
    });

    test('the project check explains a wrong key and a wrong address', () async {
      expect(CloudPortalApi.checkProject('https://abc.supabase.co', 'bad', client: MockClient((r) async => http.Response('', 401))),
          throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('anon'))));
      expect(CloudPortalApi.checkProject('https://abc.supabase.co', 'k', client: MockClient((r) async => throw Exception('x'))),
          throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('Cannot reach'))));
      await CloudPortalApi.checkProject('https://abc.supabase.co', 'k', client: MockClient((r) async => http.Response('{}', 200)));
    });
  });

  group('the connection window, online', () {
    Future<void> open(WidgetTester tester, {Future<void> Function(String, String)? check}) async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig.load();
      late BuildContext context;
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      })));
      showConnectionDialog(context, checkCloud: check);
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('it opens on Online and asks for the project address and the anon key', (tester) async {
      await open(tester);
      expect(find.text('Project address'), findsOneWidget);
      expect(find.text('Anon key'), findsOneWidget);
    });

    testWidgets('a project that answers is saved and made the way in', (tester) async {
      final checked = <String>[];
      await open(tester, check: (url, key) async => checked.add('$url $key'));
      await tester.enterText(find.widgetWithText(TextField, 'Project address'), 'abc.supabase.co');
      await tester.enterText(find.widgetWithText(TextField, 'Anon key'), 'eyJ abc');
      await tester.tap(find.text('Test and save'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(checked, ['https://abc.supabase.co eyJabc']);
      expect((AppConfig.cloudUrl, AppConfig.cloudKey, AppConfig.isOnline), ('https://abc.supabase.co', 'eyJabc', true));
    });

    testWidgets('a project that does not answer is explained and nothing is saved', (tester) async {
      await open(tester, check: (url, key) async => throw PortalException('The cloud refused that key. Use the "anon" key of the project.'));
      await tester.enterText(find.widgetWithText(TextField, 'Project address'), 'abc.supabase.co');
      await tester.enterText(find.widgetWithText(TextField, 'Anon key'), 'wrong');
      await tester.tap(find.text('Test and save'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('refused that key'), findsOneWidget);
      expect(AppConfig.hasCloud, isFalse);
    });

    testWidgets('empty fields are named before anything is asked', (tester) async {
      await open(tester, check: (url, key) async => fail('nothing should be checked'));
      await tester.tap(find.text('Test and save'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Type the project address'), findsOneWidget);
    });
  });
}
