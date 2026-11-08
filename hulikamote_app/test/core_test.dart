import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_app/core/config/app_config.dart';
import 'package:hulikamote_app/core/models/account.dart';
import 'package:hulikamote_app/core/models/notice.dart';
import 'package:hulikamote_app/core/services/notice_poller.dart';
import 'package:hulikamote_app/core/services/portal_api.dart';
import 'package:hulikamote_app/core/services/session.dart';
import 'package:hulikamote_app/core/utils/plate.dart';
import 'package:shared_preferences/shared_preferences.dart';

const profileJson = {
  'user_id': 'user_9', 'name': 'Ana Cruz', 'plate': 'ANA 777', 'email': 'ana@example.test', 'license_no': 'PLATE-ANA777',
  'license_type': 'Not provided', 'restrictions': '', 'expiry': '-', 'address': '-',
};

PortalApi apiFor(Future<http.Response> Function(http.Request) handler) =>
    PortalApi(client: MockClient(handler), baseUrl: () => 'http://192.168.68.109:8000');

Map<String, dynamic> noticeJson(String id, String at) => {'id': id, 'subject': 'Traffic violation recorded: $id', 'body': 'Hello', 'created_at': at};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the laptop address', () {
    test('whatever is typed or copied becomes host:port', () {
      expect(AppConfig.normalize('192.168.68.109'), '192.168.68.109:8000');
      expect(AppConfig.normalize(' 192.168.68.109:8001 '), '192.168.68.109:8001');
      expect(AppConfig.normalize('http://192.168.68.109:8000/mailbox'), '192.168.68.109:8000');
      expect(AppConfig.normalize('MY-LAPTOP.local'), 'my-laptop.local:8000');
    });

    test('things that cannot be an address give nothing', () {
      for (final bad in ['', '   ', 'a b', '1.2.3.4:99999', '1.2.3.4:abc', '1.2.3.4:80:90', '-bad', 'http://']) {
        expect(AppConfig.normalize(bad), '', reason: bad);
      }
    });

    test('a saved address survives a restart, and a bad one saves nothing', () async {
      expect(await AppConfig.save('not an address'), isFalse);
      expect(await AppConfig.save('192.168.68.109'), isTrue);
      await AppConfig.load();
      expect(AppConfig.address, '192.168.68.109:8000');
      expect(AppConfig.baseUrl, 'http://192.168.68.109:8000');
    });
  });

  group('signing up', () {
    String? check({String name = 'Ana', String plate = 'ANA 777', String password = 'secret1', String repeat = 'secret1', String email = ''}) =>
        validateSignUp(name: name, plate: plate, password: password, repeat: repeat, email: email);

    test('a good form has no complaint', () => expect(check(email: 'ana@example.test'), isNull));

    test('each mistake is named', () {
      expect(check(name: ' '), 'Enter your name.');
      expect(check(plate: '---'), 'Enter your plate number.');
      expect(check(plate: 'ABCDEFGHIJKLM'), contains('at most 12'));
      expect(check(email: 'not an email'), contains('e-mail'));
      expect(check(password: '12345', repeat: '12345'), contains('at least 6'));
      expect(check(repeat: 'different'), contains('not the same'));
    });

    test('plates are compared without spaces, hyphens or case', () => expect(normalizePlate('abc-12 34'), 'ABC1234'));
  });

  group('talking to the laptop', () {
    test('login sends the plate and password and reads the account', () async {
      late http.Request seen;
      final api = apiFor((req) async {
        seen = req;
        return http.Response(jsonEncode(profileJson), 200);
      });
      final account = await api.login(' ANA 777 ', 'secret1');
      expect(seen.url.path, '/auth/login');
      expect(jsonDecode(seen.body), {'plate': 'ANA 777', 'password': 'secret1'});
      expect((account.userId, account.plate, account.hasLicense), ('user_9', 'ANA 777', false));
    });

    test('a wrong password reads as plain words', () async {
      final api = apiFor((req) async => http.Response('{"detail":"Invalid credentials"}', 401));
      expect(api.login('ANA 777', 'x'), throwsA(isA<PortalException>().having((e) => e.message, 'message', 'Wrong plate number or password.')));
    });

    test('sign-up sends everything and the laptop\'s reason for a refusal is shown as it is', () async {
      final api = apiFor((req) async => http.Response('{"detail":"That plate already has an account"}', 409));
      expect(api.register(name: 'Ana', plate: 'ANA 777', password: 'secret1'),
          throwsA(isA<PortalException>().having((e) => e.message, 'message', 'That plate already has an account')));
    });

    test('only confirmed tickets are asked for', () async {
      late Uri seen;
      final api = apiFor((req) async {
        seen = req.url;
        return http.Response(jsonEncode({'total': 0, 'page': 1, 'size': 50, 'items': []}), 200);
      });
      await api.tickets('user_9');
      expect(seen.queryParameters, {'page': '1', 'size': '50', 'user_id': 'user_9', 'status': 'approved'});
    });

    test('notices are asked for newer than the last one seen, and an empty marker asks for all', () async {
      final seen = <Map<String, String>>[];
      final api = apiFor((req) async {
        seen.add(req.url.queryParameters);
        return http.Response(jsonEncode({'notices': [noticeJson('a', '2026-10-29T01:00:00+00:00')]}), 200);
      });
      expect((await api.notices('user_9', after: '2026-10-29T00:00:00+00:00')).single.id, 'a');
      await api.notices('user_9', after: '');
      expect(seen, [{'user_id': 'user_9', 'after': '2026-10-29T00:00:00+00:00'}, {'user_id': 'user_9'}]);
    });

    test('an appeal goes with the ticket, the motorist and the reason', () async {
      late http.Request seen;
      final api = apiFor((req) async {
        seen = req;
        return http.Response('{}', 201);
      });
      await api.fileAppeal(violationId: 'v1', userId: 'user_9', reason: 'I was parked');
      expect(jsonDecode(seen.body), {'violation_id': 'v1', 'user_id': 'user_9', 'reason': 'I was parked'});
    });

    test('signing out tells the laptop to stop pushing to this phone', () async {
      late http.Request seen;
      final api = apiFor((req) async {
        seen = req;
        return http.Response('{"status":"ok"}', 200);
      });
      await api.forgetPushToken('fcm-token');
      expect(seen.url.path, '/notifications/forget-token');
      expect(jsonDecode(seen.body), {'token': 'fcm-token'});
    });

    test('a laptop that does not answer is explained with the address that was tried', () async {
      final api = apiFor((req) async => throw Exception('refused'));
      expect(api.ping(), throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('192.168.68.109:8000'))));
    });
  });

  group('the session', () {
    const ana = Account(userId: 'user_9', name: 'Ana Cruz', plate: 'ANA 777', email: 'ana@example.test');

    test('is kept after login and forgotten on logout, but the laptop address stays', () async {
      await AppConfig.save('192.168.68.109');
      await Session.save(ana);
      final back = await Session.current();
      expect((back!.userId, back.name, back.plate, back.email), ('user_9', 'Ana Cruz', 'ANA 777', 'ana@example.test'));
      await Session.clear();
      expect(await Session.current(), isNull);
      await AppConfig.load();
      expect(AppConfig.hasServer, isTrue);
    });
  });

  group('new notices on the phone', () {
    Future<(NoticePoller, List<String>, List<List<Map<String, dynamic>>>)> setup(List<Map<String, dynamic>> existing) async {
      final shown = <String>[];
      final replies = <List<Map<String, dynamic>>>[existing];
      final api = apiFor((req) async {
        final after = req.url.queryParameters['after'];
        final all = replies.last.where((n) => after == null || (n['created_at'] as String).compareTo(after) > 0).toList()
          ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
        return http.Response(jsonEncode({'notices': all}), 200);
      });
      final poller = NoticePoller(api: api, userId: 'user_9', onNew: (Notice n) => shown.add(n.id), every: const Duration(hours: 1));
      return (poller, shown, replies);
    }

    test('what was already there when the app first opens is not announced', () async {
      final (poller, shown, _) = await setup([noticeJson('old', '2026-10-29T01:00:00+00:00')]);
      await poller.start();
      poller.stop();
      expect(shown, isEmpty);
    });

    test('a notice that arrives later is announced once, oldest first', () async {
      final (poller, shown, replies) = await setup([noticeJson('old', '2026-10-29T01:00:00+00:00')]);
      await poller.start();
      replies.add([...replies.last, noticeJson('b', '2026-10-29T02:00:00+00:00'), noticeJson('c', '2026-10-29T03:00:00+00:00')]);
      await poller.poll();
      await poller.poll();                                   // nothing new the second time
      poller.stop();
      expect(shown, ['b', 'c']);
    });

    test('the first notice after an empty inbox is announced too', () async {
      final (poller, shown, replies) = await setup([]);
      await poller.start();
      replies.add([noticeJson('first', '2026-10-29T02:00:00+00:00')]);
      await poller.poll();
      poller.stop();
      expect(shown, ['first']);
    });

    test('what it has seen is remembered across restarts', () async {
      final (first, shownFirst, replies) = await setup([noticeJson('old', '2026-10-29T01:00:00+00:00')]);
      await first.start();
      replies.add([...replies.last, noticeJson('b', '2026-10-29T02:00:00+00:00')]);
      await first.poll();
      first.stop();
      expect(shownFirst, ['b']);

      final shownAgain = <String>[];
      final api = apiFor((req) async {
        final after = req.url.queryParameters['after'];
        final newer = replies.last.where((n) => after == null || (n['created_at'] as String).compareTo(after) > 0).toList();
        return http.Response(jsonEncode({'notices': newer}), 200);
      });
      final again = NoticePoller(api: api, userId: 'user_9', onNew: (n) => shownAgain.add(n.id), every: const Duration(hours: 1));
      await again.start();
      again.stop();
      expect(shownAgain, isEmpty);                           // b was already announced
    });

    test('a laptop that is out of reach is not an error, just a missed round', () async {
      final api = apiFor((req) async => throw Exception('no route'));
      final poller = NoticePoller(api: api, userId: 'user_9', onNew: (_) => fail('nothing to announce'), every: const Duration(hours: 1));
      await poller.start();
      poller.stop();
    });
  });
}
