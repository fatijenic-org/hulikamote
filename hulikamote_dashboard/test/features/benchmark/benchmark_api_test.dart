import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/benchmark/data/benchmark_api.dart';
import 'package:hulikamote_dashboard/features/benchmark/domain/benchmark_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

BenchmarkApi _api(Future<http.Response> Function(http.Request) handler) =>
    BenchmarkApi(baseUrl: 'http://test', client: MockClient(handler));

void main() {
  test('the overview is read: coverage, clips with their events, saved reports and a run in progress', () async {
    final api = _api((req) async {
      expect(req.url.path, '/api/benchmark/overview');
      return http.Response(
        jsonEncode({
          'defaults': {'tolerance_s': 3.0, 'min_events': 10, 'pass': {'precision': 0.8, 'recall': 0.75}},
          'violations': [
            {'key': 'counterflow', 'events': 4, 'clips': 2, 'needed': 10, 'state': 'needs 6 more events'},
          ],
          'clips': [
            {
              'id': 'cf_01', 'note': 'Rizal Ave', 'clean': false, 'file_ok': true, 'settings_ok': false,
              'enabled': ['counterflow'], 'seconds': 95.5,
              'events': [
                {'violation': 'counterflow', 'start': 3.0, 'end': 8.5, 'plate': 'ABC 1234', 'note': ''},
              ],
            },
          ],
          'problems': ['cf_01: settings file not found'],
          'reports': [
            {'name': '20261026_baseline', 'label': 'baseline', 'created': '2026-10-26T10:05:09', 'caught': 5, 'false_alarms': 1,
             'missed': 2, 'precision': 0.83, 'recall': 0.71},
          ],
          'run': {
            'id': 'r1', 'status': 'running', 'label': 'baseline', 'clips_total': 3, 'clips_done': 1, 'current': 'cf_02',
            'stage': 'cf_02: 40%', 'error': null, 'report': null, 'results': [],
          },
        }),
        200,
      );
    });
    final o = await api.overview();
    expect(o.minEvents, 10);
    expect(o.passRecall, 0.75);
    expect(o.rows.single.state, 'needs 6 more events');
    expect(o.rows.single.ready, isFalse);
    final clip = o.clips.single;
    expect(clip.events.single.start, '3');                 // 3.0 is shown as 3
    expect(clip.events.single.end, '8.5');
    expect(clip.events.single.plate, 'ABC 1234');
    expect(clip.settingsOk, isFalse);
    expect(o.totalSeconds, 95.5);
    expect(o.problems, ['cf_01: settings file not found']);
    expect(o.reports.single.title, 'baseline  ·  2026-10-26 10:05');
    expect(o.run!.running, isTrue);
    expect(o.run!.fraction, closeTo(1 / 3, 1e-9));
  });

  test('saving a clip sends the run, the original video and the events as typed', () async {
    late http.Request seen;
    final api = _api((req) async {
      seen = req;
      return http.Response(jsonEncode({'clip': {'id': 'cf_01'}, 'problems': ['cf_01: expects no_helmet but the settings do not switch it on']}), 200);
    });
    final problems = await api.saveClip(
      id: 'cf_01',
      taskId: 'run1',
      videoPath: 'C:/clips/street.mp4',
      note: 'Rizal Ave',
      events: [BenchEvent(violation: 'counterflow', start: '3', end: '0:08', plate: 'ABC 1234')],
    );
    expect(seen.method, 'PUT');
    expect(seen.url.path, '/api/benchmark/clips/cf_01');
    expect(jsonDecode(seen.body), {
      'task_id': 'run1',
      'video_path': 'C:/clips/street.mp4',
      'note': 'Rizal Ave',
      'clean': false,
      'events': [
        {'violation': 'counterflow', 'start': '3', 'end': '0:08', 'plate': 'ABC 1234'},
      ],
    });
    expect(problems.single, contains('do not switch it on'));
  });

  test('a refusal comes back as the backend wrote it; an old backend gets a clear hint', () async {
    final refused = _api((_) async => http.Response(jsonEncode({'detail': 'counterflow: the event ends (2 s) before it starts (9 s).'}), 400));
    await expectLater(
      refused.saveClip(id: 'a', taskId: 'r'),
      throwsA(isA<BenchmarkApiException>().having((e) => e.message, 'message', contains('before it starts'))),
    );
    final old = _api((_) async => http.Response(jsonEncode({'detail': 'Not Found'}), 404));
    await expectLater(
      old.overview(),
      throwsA(isA<BenchmarkApiException>().having((e) => e.message, 'message', contains('no Benchmark service'))),
    );
  });

  test('a run is started with its name, then followed and stopped by id', () async {
    final seen = <String>[];
    final api = _api((req) async {
      seen.add('${req.method} ${req.url.path}');
      if (req.url.path == '/api/benchmark/run' && req.method == 'POST') {
        expect(jsonDecode(req.body), {'label': 'baseline', 'clips': null});
        return http.Response(jsonEncode({'run_id': 'r1'}), 202);
      }
      if (req.url.path == '/api/benchmark/run/r1') {
        return http.Response(
          jsonEncode({'id': 'r1', 'status': 'done', 'label': 'baseline', 'clips_total': 1, 'clips_done': 1, 'report': '2026_baseline', 'results': []}),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'stopping'}), 200);
    });
    expect(await api.startRun(label: 'baseline'), 'r1');
    final progress = await api.runProgress('r1');
    expect(progress.status, 'done');
    expect(progress.report, '2026_baseline');
    await api.cancelRun('r1');
    expect(seen, ['POST /api/benchmark/run', 'GET /api/benchmark/run/r1', 'POST /api/benchmark/run/r1/cancel']);
  });

  test('a report keeps the catalog order and reads the verdicts', () {
    final r = ReportDetail.fromJson({
      'label': 'baseline',
      'created': '2026-10-26T10:00:00',
      'defaults': {'min_events': 10, 'pass': {'precision': 0.8, 'recall': 0.8}},
      'overall': {'caught': 1},
      'summary': {
        'no_plate': {'clips': 1, 'events': 3, 'caught': 3, 'false_alarms': 0, 'missed': 0, 'precision': 1.0, 'recall': 1.0, 'f1': 1.0,
                     'status': 'too few events (3 of 10)', 'plates': {'loar': null}},
        'counterflow': {'clips': 2, 'events': 12, 'caught': 10, 'false_alarms': 1, 'missed': 2, 'precision': 0.91, 'recall': 0.83, 'f1': 0.87,
                        'status': 'PASS', 'plates': {'loar': 0.5}},
      },
      'not_benchmarked': ['red_light'],
      'clips': [],
    });
    expect([for (final s in r.scores) s.key], ['counterflow', 'no_plate']);
    expect(r.scores.first.pass, isTrue);
    expect(r.scores.first.loar, 0.5);
    expect(r.scores.last.pass || r.scores.last.fail, isFalse);
    expect(r.notBenchmarked, ['red_light']);
  });
}
