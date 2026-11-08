import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/test_support.dart';

void main() {
  group('useForLive', () {
    test('posts the wizard config as JSON and explains what to do next', () async {
      late http.Request seen;
      final api = ForensicApi(
        baseUrl: 'http://test',
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'message': 'ok', 'violations': ['counterflow']}), 200);
        }),
      );
      final message = await api.useForLive({'active_violations': ['counterflow']});
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/forensic/live-config');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), {'active_violations': ['counterflow']});
      expect(message, contains('Camera input'));
    });

    test('a refusal from the backend is reported, not swallowed', () async {
      final api = ForensicApi(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response(jsonEncode({'error': 'Switch at least one violation on first.'}), 400)),
      );
      await expectLater(api.useForLive({}), throwsA(isA<ForensicApiException>()));
    });
  });

  group('stopRun', () {
    test('Stop here and Cancel are two modes of the same POST', () async {
      final seen = <http.Request>[];
      final api = ForensicApi(
        baseUrl: 'http://test',
        client: MockClient((req) async {
          seen.add(req);
          return http.Response(jsonEncode({'task_id': 'T1', 'stop': 'finish'}), 200);
        }),
      );
      await api.stopRun('T1', keep: true);
      await api.stopRun('T1', keep: false);
      expect(seen.map((r) => r.method), ['POST', 'POST']);
      expect(seen.map((r) => r.url.path), ['/api/forensic/stop/T1', '/api/forensic/stop/T1']);
      expect(seen.map((r) => r.url.queryParameters['mode']), ['finish', 'cancel']);
    });

    test('a run that is already over is reported with the backend\'s words', () async {
      final api = ForensicApi(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response(jsonEncode({'error': 'This analysis is not running.'}), 409)),
      );
      await expectLater(
        api.stopRun('T1', keep: true),
        throwsA(isA<ForensicApiException>().having((e) => e.message, 'message', 'This analysis is not running.')),
      );
    });
  });

  group('setPlate', () {
    test('posts the edit and returns the updated tickets', () async {
      late http.Request seen;
      final api = ForensicApi(
        baseUrl: 'http://test',
        client: MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'tickets': [
                {...ticketJson(1, plate: 'ABC123'), 'plate_manual': true, 'plate_ocr': 'unidentified'},
              ],
            }),
            200,
          );
        }),
      );

      final tickets = await api.setPlate('task-1', 'uid1', 'ABC123');
      expect(seen.url.path, '/api/forensic/tickets/set-plate');
      expect(jsonDecode(seen.body), {
        'task_id': 'task-1',
        'ticket_uid': 'uid1',
        'plate_text': 'ABC123',
        'revert': false,
      });
      expect(tickets.single.plateText, 'ABC123');
      expect(tickets.single.plateManual, isTrue);
    });

    test('an older backend without the route is explained, not a bare "Not Found"', () async {
      final api = ForensicApi(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response(jsonEncode({'detail': 'Not Found'}), 404)),
      );
      await expectLater(
        api.setPlate('t', 'uid1', 'ABC123'),
        throwsA(isA<ForensicApiException>().having((e) => e.message, 'message', contains('restart'))),
      );
    });

    test('a missing ticket keeps the backend\'s own words', () async {
      final api = ForensicApi(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response(jsonEncode({'error': 'Ticket not found'}), 404)),
      );
      await expectLater(
        api.setPlate('t', 'gone', 'ABC123'),
        throwsA(isA<ForensicApiException>().having((e) => e.message, 'message', 'Ticket not found')),
      );
    });
  });
}
