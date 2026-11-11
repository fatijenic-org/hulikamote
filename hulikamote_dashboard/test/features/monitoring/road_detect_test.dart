import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/monitoring/data/camera_api.dart';
import 'package:hulikamote_dashboard/features/monitoring/domain/models/road_detect.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/road_detect_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// "Detect road": the frozen frame large, every step swept over it one at a time, then Apply or Discard.
/// A fake backend answers like routers/settings.py; the sweeps are made short so the tests stay fast.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

const _titles = {
  'steady': 'Steadying the picture',
  'empty': 'Taking the traffic away',
  'motion': 'Following the moving vehicles',
  'direction': 'Finding the road direction',
  'road': 'Marking where vehicles drive',
  'topview': 'Straightening the road',
  'paint': 'Picking out the paint',
  'marks': 'Finding crosswalks and lines',
};

Map<String, dynamic> _statusJson(
  String state, {
  Map<String, String> steps = const {},
  double progress = 0,
  List<String> rules = const [],
  String? reason,
  List<Map<String, dynamic>> zones = const [],
}) => {
  'id': 1,
  'state': state,
  'size': [1280, 720],
  'progress_s': progress,
  'need_s': 40.0,
  'reason': reason,
  'found': {'crosswalks': rules.isEmpty ? 0 : 1, 'stop_lines': 0, 'solid_lines': 0},
  'rules': rules,
  'hints': <String>[],
  'applied': false,
  'zones': zones,
  'edited': false,
  'steps': [
    for (final e in _titles.entries)
      {
        'id': e.key,
        'title': e.value,
        'about': 'About ${e.key}.',
        'state': steps[e.key] ?? 'waiting',
        'has_overlay': e.key != 'steady' && (steps[e.key] == 'done'),
        'info': <String, dynamic>{},
      },
  ],
};

class FakeRoadBackend {
  Map<String, dynamic> status = _statusJson('none');
  final requests = <String>[];
  Object? corrected; // the body of the last corrections POST

  CameraApi get api => CameraApi(
    baseUrl: 'http://test',
    client: MockClient((req) async {
      requests.add('${req.method} ${req.url.path}');
      switch (req.url.path) {
        case '/settings/video/road/detect':
          return http.Response(jsonEncode(req.method == 'POST' ? {'ok': true, 'detect': status} : status), 200);
        case '/settings/video/road/detect/frame':
          return http.Response.bytes(_png, 200);
        case '/settings/video/road/detect/zones':
          corrected = jsonDecode(req.body);
          return http.Response(jsonEncode({'ok': true, 'zones': (corrected as Map)['zones']}), 200);
        case '/settings/video/road/detect/apply':
          return http.Response(jsonEncode({'ok': true, 'zones': ['pedestrian_lane'], 'switched_on': <String>[]}), 200);
        case '/settings/video/road/detect/discard':
          return http.Response(jsonEncode({'ok': true}), 200);
      }
      if (req.url.path.startsWith('/settings/video/road/detect/step/')) {
        final id = req.url.pathSegments.last;
        final step = (status['steps'] as List).cast<Map<String, dynamic>>().firstWhere((s) => s['id'] == id);
        return step['has_overlay'] == true ? http.Response.bytes(_png, 200) : http.Response('{"detail":"no picture"}', 404);
      }
      return http.Response('{"detail":"unexpected ${req.url.path}"}', 404);
    }),
  );
}

Widget _host(FakeRoadBackend backend, void Function({required bool applied}) onClose) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 1100,
      height: 760,
      child: RoadDetectView(
        api: backend.api,
        onClose: onClose,
        reserveTopRight: const Size(300, 169),
        pollEvery: const Duration(milliseconds: 50),
        sweepTime: const Duration(milliseconds: 120),
        dwell: const Duration(milliseconds: 30),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 20) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

String _caption(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('road-caption'))).data ?? '';

void main() {
  group('the status', () {
    test('is read from the backend, in words', () {
      final s = RoadDetectStatus.fromJson(_statusJson('done', rules: ['pedestrian_lane'], steps: {'empty': 'done'}));
      expect(s.state, 'done');
      expect(s.finished, true);
      expect(s.aspect, closeTo(16 / 9, 0.001));
      expect(s.steps.length, 8);
      expect(s.steps[1].hasOverlay, true);
      expect(s.steps[0].hasOverlay, false);
      expect(s.foundText, '1 crosswalk');
      expect(RoadDetectStatus.fromJson({'state': 'collecting'}).foundText, '');
      expect(RoadDetectStatus.fromJson({}).state, 'none');
    });
  });

  group('the walkthrough', () {
    testWidgets('collecting shows the footage progress', (tester) async {
      final backend = FakeRoadBackend()..status = _statusJson('collecting', progress: 12);
      await tester.pumpWidget(_host(backend, ({required bool applied}) {}));
      await _settle(tester, 200);
      expect(_caption(tester), contains('Watching the traffic 12/40 s'));
      expect(find.byKey(const ValueKey('road-collect-progress')), findsOneWidget);
      expect(find.byKey(const ValueKey('road-apply')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('plays every step then shows the result; Apply calls the backend and closes', (tester) async {
      final backend = FakeRoadBackend()..status = _statusJson('analysing', steps: {'steady': 'done', 'empty': 'running'});
      final closed = <bool>[];
      await tester.pumpWidget(_host(backend, ({required bool applied}) => closed.add(applied)));
      await _settle(tester, 400);
      expect(find.byKey(const ValueKey('road-step-steady')), findsOneWidget);
      expect(_caption(tester), 'Reading the road...'); // the first step is done and played, the second is still being worked on
      expect(find.byKey(const ValueKey('road-apply')), findsNothing);

      backend.status = _statusJson('analysing', steps: {'steady': 'done', 'empty': 'done', 'motion': 'running'});
      await _settle(tester, 600);
      expect(backend.requests, contains('GET /settings/video/road/detect/step/empty'));
      expect(backend.requests.where((r) => r.contains('/step/steady')).length, 0, reason: 'the first step has no picture to fetch');

      backend.status = _statusJson('done', rules: ['pedestrian_lane'], steps: {for (final id in _titles.keys) id: 'done'});
      await _settle(tester, 2500);
      final fetched = backend.requests.where((r) => r.contains('/road/detect/step/')).map((r) => r.split('/').last).toList();
      expect(fetched, ['empty', 'motion', 'direction', 'road', 'topview', 'paint', 'marks']); // one at a time, in order, each once
      expect(find.byKey(const ValueKey('road-result')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('road-result'))).data, contains('Found: 1 crosswalk'));

      await tester.tap(find.byKey(const ValueKey('road-apply')));
      await _settle(tester, 100);
      expect(backend.requests, contains('POST /settings/video/road/detect/apply'));
      expect(closed, [true]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Discard closes without applying', (tester) async {
      final backend = FakeRoadBackend()..status = _statusJson('done', rules: ['pedestrian_lane'], steps: {for (final id in _titles.keys) id: 'done'});
      final closed = <bool>[];
      await tester.pumpWidget(_host(backend, ({required bool applied}) => closed.add(applied)));
      await _settle(tester, 3500);
      await tester.tap(find.byKey(const ValueKey('road-discard')));
      await _settle(tester, 100);
      expect(backend.requests, contains('POST /settings/video/road/detect/discard'));
      expect(backend.requests, isNot(contains('POST /settings/video/road/detect/apply')));
      expect(closed, [false]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('nothing clear: says so and Apply stays off', (tester) async {
      final backend = FakeRoadBackend()..status = _statusJson('done', steps: {for (final id in _titles.keys) id: 'done'});
      await tester.pumpWidget(_host(backend, ({required bool applied}) {}));
      await _settle(tester, 3500);
      expect(tester.widget<Text>(find.byKey(const ValueKey('road-result'))).data, contains('No clear crosswalk or line was found'));
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('road-apply'))).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed reading shows its reason and Close', (tester) async {
      final backend = FakeRoadBackend()
        ..status = _statusJson('failed', reason: 'Not enough traffic movement to find the road direction.', steps: {'steady': 'done'});
      final closed = <bool>[];
      await tester.pumpWidget(_host(backend, ({required bool applied}) => closed.add(applied)));
      await _settle(tester, 600);
      expect(find.byKey(const ValueKey('road-failed')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('road-failed'))).data, contains('Not enough traffic'));
      await tester.tap(find.text('Close'));
      await _settle(tester, 100);
      expect(closed, [false]);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the draft areas', () {
    final draft = [
      {'id': 'crosswalk-1', 'kind': 'crosswalk', 'polygon': [[100, 400], [500, 400], [500, 460], [100, 460]]},
      {'id': 'road-2', 'kind': 'road', 'polygon': [[300, 100], [900, 100], [900, 700], [300, 700]]},
      {'id': 'sidewalk-3', 'kind': 'sidewalk', 'side': 'left', 'polygon': [[20, 100], [300, 100], [300, 700], [20, 700]]},
    ];

    test('are read as crosswalk, road and sidewalk polygons', () {
      final s = RoadDetectStatus.fromJson(_statusJson('done', zones: draft));
      expect(s.zones.map((z) => z.kind), ['crosswalk', 'road', 'sidewalk']);
      expect(s.zones[2].side, 'left');
      expect(s.zones[0].polygon.first, const Offset(100, 400));
      final back = s.zones[1].toJson();
      expect(back['polygon'], [[300.0, 100.0], [900.0, 100.0], [900.0, 700.0], [300.0, 700.0]]);
      expect(RoadDetectStatus.fromJson({}).zones, isEmpty);
    });

    testWidgets('the operator corrects them: Apply saves the corrections first, then applies', (tester) async {
      final backend = FakeRoadBackend()
        ..status = _statusJson('done', zones: draft, steps: {for (final id in _titles.keys) id: 'done'});
      final closed = <bool>[];
      await tester.pumpWidget(_host(backend, ({required bool applied}) => closed.add(applied)));
      await _settle(tester, 3500);
      // a road and sidewalks were found even with no crosswalk rule: Apply is on and the way to correct is offered
      expect(tester.widget<Text>(find.byKey(const ValueKey('road-result'))).data, contains('road or sidewalk'));
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('road-apply'))).onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('road-correct')));
      await _settle(tester, 100);
      expect(find.byKey(const ValueKey('road-canvas')), findsOneWidget);
      expect(find.byKey(const ValueKey('road-kind')), findsNothing, reason: 'nothing is selected yet');

      await tester.tap(find.byKey(const ValueKey('road-add')));
      await _settle(tester, 100);
      expect(find.byKey(const ValueKey('road-kind')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('road-delete')));
      await _settle(tester, 100);
      expect(find.byKey(const ValueKey('road-kind')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('road-add')));        // add one again and keep it
      await _settle(tester, 100);
      await tester.tap(find.byKey(const ValueKey('road-apply')));
      await _settle(tester, 200);
      expect(backend.requests, containsAllInOrder(['POST /settings/video/road/detect/zones', 'POST /settings/video/road/detect/apply']));
      final sent = ((backend.corrected as Map)['zones'] as List).cast<Map>();
      expect(sent.length, 4);
      expect(sent.last['kind'], 'road');
      expect(sent.last['polygon'].length, 4);
      expect(closed, [true]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no corrections: Apply does not post any', (tester) async {
      final backend = FakeRoadBackend()
        ..status = _statusJson('done', zones: draft, steps: {for (final id in _titles.keys) id: 'done'});
      await tester.pumpWidget(_host(backend, ({required bool applied}) {}));
      await _settle(tester, 3500);
      await tester.tap(find.byKey(const ValueKey('road-apply')));
      await _settle(tester, 200);
      expect(backend.requests, isNot(contains('POST /settings/video/road/detect/zones')));
      expect(backend.requests, contains('POST /settings/video/road/detect/apply'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"Back to the scan" restores the draft', (tester) async {
      final backend = FakeRoadBackend()
        ..status = _statusJson('done', zones: draft, steps: {for (final id in _titles.keys) id: 'done'});
      await tester.pumpWidget(_host(backend, ({required bool applied}) {}));
      await _settle(tester, 3500);
      await tester.tap(find.byKey(const ValueKey('road-correct')));
      await _settle(tester, 100);
      await tester.tap(find.byKey(const ValueKey('road-add')));
      await _settle(tester, 100);
      await tester.tap(find.byKey(const ValueKey('road-reset')));
      await _settle(tester, 100);
      await tester.tap(find.byKey(const ValueKey('road-apply')));
      await _settle(tester, 200);
      expect(backend.requests, isNot(contains('POST /settings/video/road/detect/zones')), reason: 'back to the scan means nothing edited');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
