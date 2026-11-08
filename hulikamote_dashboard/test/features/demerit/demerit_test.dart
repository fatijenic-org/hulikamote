import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/demerit/data/demerit_api.dart';
import 'package:hulikamote_dashboard/features/demerit/domain/demerit_models.dart';
import 'package:hulikamote_dashboard/features/demerit/presentation/screens/demerit_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../forensic/support/test_support.dart';

const standingsJson = {
  'plates': [
    {'plate': 'ABC-1234', 'points': 3, 'by_class': {'no_helmet': 2, 'red_light': 1}, 'last_at': '2026-10-28T08:00:09+00:00'},
    {'plate': 'XYZ999', 'points': 1, 'by_class': {'no_plate': 1}, 'last_at': '2026-10-27T08:00:00+00:00'},
  ],
};

const detailJson = {
  'plate': 'ABC-1234',
  'points': 3,
  'by_class': {'no_helmet': 2, 'red_light': 1},
  'last_at': '2026-10-28T08:00:09+00:00',
  'violations': [
    {'id': 't3', 'cls': 'red_light', 'timestamp': '2026-10-28T08:00:09+00:00'},
    {'id': 't2', 'cls': 'no_helmet', 'timestamp': '2026-10-28T08:00:05+00:00'},
    {'id': 't1', 'cls': 'no_helmet', 'timestamp': '2026-10-28T08:00:01+00:00'},
  ],
};

DemeritApi _api(Future<http.Response> Function(http.Request) handler) =>
    DemeritApi(baseUrl: 'http://test', client: MockClient(handler));

/// A backend that answers from memory.
class FakeDemerit extends DemeritApi {
  FakeDemerit({this.standingsBody = standingsJson, this.error}) : super(baseUrl: 'http://test');

  final Map<String, dynamic> standingsBody;
  final DemeritApiException? error;
  final asked = <String>[];

  @override
  Future<List<DemeritEntry>> standings() async {
    if (error != null) throw error!;
    return [for (final p in standingsBody['plates'] as List) DemeritEntry.fromJson(Map<String, dynamic>.from(p as Map))];
  }

  @override
  Future<DemeritDetail> plate(String plate) async {
    asked.add(plate);
    return DemeritDetail.fromJson(detailJson);
  }
}

void main() {
  setUpAll(loadRoboto);

  group('reading the answers', () {
    test('a plate keeps its points, the split by violation and when it was last caught', () {
      final e = DemeritEntry.fromJson(Map<String, dynamic>.from(standingsJson['plates']![0] as Map));
      expect(e.plate, 'ABC-1234');
      expect(e.points, 3);
      expect(e.byClass, {'no_helmet': 2, 'red_light': 1});
      expect(e.lastAt, DateTime.parse('2026-10-28T08:00:09+00:00').toLocal());
    });

    test('a half-empty answer does not crash', () {
      final e = DemeritEntry.fromJson(const {});
      expect(e.plate, '');
      expect(e.points, 0);
      expect(e.byClass, isEmpty);
      expect(e.lastAt, isNull);
    });

    test('the detail lists the tickets in the order the backend sent them', () {
      final d = DemeritDetail.fromJson(detailJson);
      expect([for (final t in d.tickets) t.id], ['t3', 't2', 't1']);
    });

    test('standings asks /demerit and the plate lookup escapes the plate', () async {
      final paths = <String>[];
      final api = _api((req) async {
        paths.add(req.url.toString());
        return http.Response(jsonEncode(req.url.path == '/demerit' ? standingsJson : detailJson), 200);
      });
      expect((await api.standings()).length, 2);
      await api.plate('ABC 1/2');
      expect(paths, ['http://test/demerit', 'http://test/demerit/ABC%201%2F2']);
    });

    test('an old backend without the service says to restart it', () async {
      final api = _api((req) async => http.Response('{"detail":"Not Found"}', 404));
      expect(api.standings(), throwsA(isA<DemeritApiException>().having((e) => e.message, 'message', contains('Restart the backend'))));
    });

    test('a backend that is off is reported in plain words', () async {
      final api = _api((req) async => throw Exception('connection refused'));
      expect(api.standings(), throwsA(isA<DemeritApiException>().having((e) => e.message, 'message', contains('Is it running?'))));
    });
  });

  group('the Demerit points tab', () {
    testWidgets('lists plates with the most points first, their violations and the totals', (tester) async {
      await pumpScreen(tester, DemeritScreen(api: FakeDemerit()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('ABC-1234'), findsOneWidget);
      expect(find.text('XYZ999'), findsOneWidget);
      expect(tester.getTopLeft(find.text('ABC-1234')).dy, lessThan(tester.getTopLeft(find.text('XYZ999')).dy));
      expect(find.text('2 plates'), findsOneWidget);
      expect(find.text('4 points in total'), findsOneWidget);
      expect(find.text('No helmet ×2'), findsOneWidget);
      expect(find.text('points'), findsOneWidget);
      expect(find.text('point'), findsOneWidget);
    });

    testWidgets('searching finds a plate however it is typed', (tester) async {
      await pumpScreen(tester, DemeritScreen(api: FakeDemerit()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField), 'abc 1234');
      await tester.pump();
      expect(find.text('ABC-1234'), findsOneWidget);
      expect(find.text('XYZ999'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nothing');
      await tester.pump();
      expect(find.text('No plate matches "nothing"'), findsOneWidget);
    });

    testWidgets('tapping a plate shows the confirmed tickets behind its points', (tester) async {
      final api = FakeDemerit();
      await pumpScreen(tester, DemeritScreen(api: api));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('ABC-1234'));
      await tester.pump(const Duration(milliseconds: 300));      // the dialog opens and asks the backend
      await tester.pump(const Duration(milliseconds: 100));      // the answer arrives

      expect(api.asked, ['ABC-1234']);
      expect(find.text('Red light'), findsOneWidget);
      expect(find.text('No helmet'), findsNWidgets(2));
      for (final iso in const ['2026-10-28T08:00:09+00:00', '2026-10-28T08:00:05+00:00', '2026-10-28T08:00:01+00:00']) {
        expect(find.text(formatWhen(DateTime.parse(iso).toLocal())), findsOneWidget);   // three tickets, three different times
      }
    });

    testWidgets('with no confirmed tickets it explains how a plate gets a point', (tester) async {
      await pumpScreen(tester, DemeritScreen(api: FakeDemerit(standingsBody: const {'plates': []})));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No points yet'), findsOneWidget);
      expect(find.textContaining('confirm one of its tickets'), findsOneWidget);
    });

    testWidgets('a backend problem is shown with a way to try again', (tester) async {
      await pumpScreen(tester, DemeritScreen(api: FakeDemerit(error: DemeritApiException('The backend did not answer.'))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('The backend did not answer.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
