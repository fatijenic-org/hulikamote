import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/benchmark/data/benchmark_api.dart';
import 'package:hulikamote_dashboard/features/benchmark/domain/benchmark_models.dart';
import 'package:hulikamote_dashboard/features/benchmark/presentation/screens/benchmark_screen.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/violation_catalog.dart';

import '../forensic/support/test_support.dart';

Map<String, dynamic> overviewJson({
  List<Map<String, dynamic>> clips = const [],
  List<Map<String, dynamic>> reports = const [],
  Map<String, dynamic>? run,
  List<String> problems = const [],
}) =>
    {
      'defaults': {'tolerance_s': 3.0, 'min_events': 10, 'pass': {'precision': 0.8, 'recall': 0.8}},
      'violations': [
        for (final v in ViolationCatalog.all) {'key': v.key, 'events': 0, 'clips': 0, 'needed': 10, 'state': 'no clips yet'},
      ],
      'clips': clips,
      'problems': problems,
      'reports': reports,
      'run': run,
    };

Map<String, dynamic> clipJson({String id = 'cf_01', bool clean = false, List<Map<String, dynamic>>? events}) => {
      'id': id,
      'note': 'Rizal Ave',
      'clean': clean,
      'file_ok': true,
      'settings_ok': true,
      'enabled': ['counterflow', 'no_plate'],
      'seconds': 60.0,
      'events': events ??
          [
            {'violation': 'counterflow', 'start': 3.0, 'end': 7.0, 'plate': '', 'note': ''},
            {'violation': 'no_plate', 'start': 12.0, 'end': 15.0, 'plate': '', 'note': ''},
          ],
    };

const reportBrief = {
  'name': '20261026_100000_baseline', 'label': 'baseline', 'created': '2026-10-26T10:00:00', 'caught': 5, 'false_alarms': 1,
  'missed': 2, 'precision': 0.83, 'recall': 0.71,
};

final reportJson = {
  'label': 'baseline',
  'created': '2026-10-26T10:00:00',
  'defaults': {'min_events': 10, 'pass': {'precision': 0.8, 'recall': 0.8}},
  'overall': {'caught': 5, 'false_alarms': 1, 'missed': 2, 'precision': 0.83, 'recall': 0.71, 'plates_checked': 0},
  'summary': {
    'counterflow': {'clips': 1, 'events': 12, 'caught': 10, 'false_alarms': 1, 'missed': 2, 'precision': 0.91, 'recall': 0.83, 'f1': 0.87,
                    'status': 'PASS', 'plates': {'loar': null}},
    'no_plate': {'clips': 1, 'events': 3, 'caught': 3, 'false_alarms': 0, 'missed': 0, 'precision': 1.0, 'recall': 1.0, 'f1': 1.0,
                 'status': 'too few events (3 of 10)', 'plates': {'loar': null}},
  },
  'not_benchmarked': ['red_light'],
  'clips': [
    {
      'clip_id': 'cf_01',
      'caught': [{'violation': 'counterflow', 'start': 3.0, 'end': 7.0, 'track': 7}],
      'missed': [],
      'false_alarms': [],
      'skipped': [],
    },
  ],
};

/// A backend that answers without a network and records what the tab asked of it.
class FakeBench extends BenchmarkApi {
  FakeBench(this.overviewJson) : super(baseUrl: 'http://test');

  Map<String, dynamic> overviewJson;
  bool keepsVideo = true;
  int overviewCalls = 0;
  final saved = <Map<String, dynamic>>[];
  String? deleted;
  String? startedLabel;
  bool cancelled = false;
  Map<String, dynamic>? progressJson;
  Object? overviewError;

  @override
  Future<BenchOverview> overview() async {
    overviewCalls++;
    if (overviewError != null) throw overviewError!;
    return BenchOverview.fromJson(overviewJson);
  }

  @override
  Future<RunSuggestions> suggestions(String taskId) async => RunSuggestions(
        enabled: const ['counterflow', 'no_plate'],
        videoKept: keepsVideo,
        suggestions: const [RunSuggestion(violation: 'counterflow', track: 7, start: 3, end: 7, plate: 'ABC123')],
      );

  @override
  Future<List<String>> saveClip({
    required String id,
    String? taskId,
    String? videoPath,
    String note = '',
    bool clean = false,
    List<BenchEvent> events = const [],
  }) async {
    saved.add({'id': id, 'task': taskId, 'video': videoPath, 'note': note, 'clean': clean, 'events': [for (final e in events) e.toJson()]});
    return const [];
  }

  @override
  Future<void> deleteClip(String id) async => deleted = id;

  @override
  Future<String> startRun({required String label, List<String>? clips}) async {
    startedLabel = label;
    return 'r1';
  }

  @override
  Future<RunProgress> runProgress(String runId) async => RunProgress.fromJson(progressJson!);

  @override
  Future<void> cancelRun(String runId) async => cancelled = true;

  @override
  Future<ReportDetail> report(String name) async => ReportDetail.fromJson(reportJson);
}

class FakeForensic extends ForensicApi {
  FakeForensic() : super(baseUrl: 'http://test');

  @override
  Future<List<RunSummary>> history() async => [
        RunSummary(taskId: 'e4a858b6-7c74-40cb', createdAt: DateTime(2026, 10, 26, 10, 58), ticketCount: 12, videoUrl: null, reportUrl: '/r'),
      ];
}

Future<FakeBench> _pump(WidgetTester tester, FakeBench api, {Future<String?> Function()? pickVideo}) async {
  await pumpScreen(
    tester,
    BenchmarkScreen(
      api: api,
      forensic: FakeForensic(),
      pickVideo: pickVideo ?? () async => 'C:/clips/street.mp4',
      pollEvery: const Duration(milliseconds: 200),
    ),
    size: const Size(1500, 3400), // tall: the lists build only what is on screen
  );
  await tester.pump(const Duration(milliseconds: 100));
  return api;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  setUpAll(loadRoboto);

  testWidgets('with nothing yet it says what to do, lists all violations and cannot run', (tester) async {
    await _pump(tester, FakeBench(overviewJson()));
    expect(find.text('No clips yet'), findsOneWidget);
    expect(find.text('No benchmark run yet'), findsOneWidget);
    expect(find.text('0 of 10 events'), findsNWidgets(ViolationCatalog.all.length));
    expect(tester.widget<FilledButton>(find.byKey(const Key('run-benchmark'))).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('add-clip'))).onPressed, isNotNull);
  });

  testWidgets('clips and the latest report are shown, and the run button is on', (tester) async {
    await _pump(tester, FakeBench(overviewJson(clips: [clipJson()], reports: [reportBrief])));
    expect(find.text('cf_01'), findsWidgets);
    expect(find.text('2 events'), findsOneWidget);
    expect(find.text('Caught 5'), findsOneWidget);
    expect(find.text('False alarms 1'), findsOneWidget);
    expect(find.text('PASS'), findsOneWidget);
    expect(find.text('too few events (3 of 10)'), findsOneWidget);
    expect(find.text('91%'), findsOneWidget);                       // counterflow precision
    expect(tester.widget<FilledButton>(find.byKey(const Key('run-benchmark'))).onPressed, isNotNull);
  });

  testWidgets('a clip is added from a run: pick it, take what it flagged, save', (tester) async {
    final api = await _pump(tester, FakeBench(overviewJson()));
    await _tap(tester, find.byKey(const Key('add-clip')));
    expect(find.text('Add a clip'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('run-picker')));
    await _tap(tester, find.textContaining('e4a858b6'));
    expect(find.byKey(const Key('clip-name')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('clip-name'))).controller!.text, 'clip_e4a858');   // a default name

    // what the run flagged becomes an event with one tap
    await _tap(tester, find.textContaining('Counterflow  3-7 s'));
    expect(find.widgetWithText(TextField, 'Start'), findsOneWidget);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Start')).controller!.text, '3');
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Plate (optional)')).controller!.text, 'ABC123');

    await tester.enterText(find.byKey(const Key('clip-name')), 'cf_02');
    await _tap(tester, find.byKey(const Key('save-clip')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.saved.single['id'], 'cf_02');
    expect(api.saved.single['task'], 'e4a858b6-7c74-40cb');
    expect(api.saved.single['events'], [
      {'violation': 'counterflow', 'start': '3', 'end': '7', 'plate': 'ABC123'},
    ]);
    expect(api.overviewCalls, 2);                                    // the list was reloaded
    expect(find.text('Add a clip'), findsNothing);
  });

  testWidgets('a run that did not keep its video asks for the original clip before saving', (tester) async {
    final api = await _pump(tester, FakeBench(overviewJson())..keepsVideo = false);
    await _tap(tester, find.byKey(const Key('add-clip')));
    await _tap(tester, find.byKey(const Key('run-picker')));
    await _tap(tester, find.textContaining('e4a858b6'));
    expect(find.text('Choose the original video…'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('save-clip')));
    expect(find.textContaining('Choose the original video file'), findsOneWidget);
    expect(api.saved, isEmpty);

    await _tap(tester, find.byKey(const Key('choose-video')));
    expect(find.text('C:/clips/street.mp4'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('clip-clean')));          // nothing illegal in it
    await _tap(tester, find.byKey(const Key('save-clip')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.saved.single['video'], 'C:/clips/street.mp4');
    expect(api.saved.single['clean'], isTrue);
    expect(api.saved.single['events'], isEmpty);
  });

  testWidgets('a clip is edited without picking a run, and removed after a confirmation', (tester) async {
    final api = await _pump(tester, FakeBench(overviewJson(clips: [clipJson()])));
    await _tap(tester, find.byKey(const Key('edit-cf_01')));
    expect(find.text('Edit cf_01'), findsOneWidget);
    expect(find.byKey(const Key('run-picker')), findsNothing);
    expect(find.widgetWithText(TextField, 'Start'), findsNWidgets(2));
    await _tap(tester, find.byKey(const Key('save-clip')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.saved.single['task'], isNull);
    expect((api.saved.single['events'] as List), hasLength(2));

    await _tap(tester, find.byKey(const Key('delete-cf_01')));
    expect(find.text('Remove cf_01?'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('confirm-delete')));
    expect(api.deleted, 'cf_01');
  });

  testWidgets('the run dialog names the run and says how long it will take', (tester) async {
    final api = await _pump(tester, FakeBench(overviewJson(clips: [clipJson()])));
    await _tap(tester, find.byKey(const Key('run-benchmark')));
    expect(find.text('Run the benchmark'), findsOneWidget);
    expect(find.textContaining('about 10 min'), findsOneWidget); // 60 s of footage x 10
    await tester.enterText(find.byKey(const Key('run-label')), 'finetuned');
    await _tap(tester, find.byKey(const Key('start-run')));
    expect(api.startedLabel, 'finetuned');
  });

  testWidgets('progress is followed while a run is going, and the report opens by itself when it ends', (tester) async {
    final api = FakeBench(overviewJson(clips: [clipJson()], run: {
      'id': 'r1', 'status': 'running', 'label': 'baseline', 'clips_total': 3, 'clips_done': 1, 'current': 'cf_02',
      'stage': 'cf_02: 40%', 'error': null, 'report': null, 'results': [],
    }));
    await _pump(tester, api);
    expect(find.text('Running "baseline"'), findsOneWidget);
    expect(find.textContaining('1 of 3 clips done'), findsOneWidget);
    expect(find.textContaining('now: cf_02'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('run-benchmark'))).onPressed, isNull);   // one run at a time

    api.progressJson = {'id': 'r1', 'status': 'running', 'label': 'baseline', 'clips_total': 3, 'clips_done': 2, 'current': 'cf_03', 'stage': '', 'results': []};
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('2 of 3 clips done'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('stop-run')));
    expect(api.cancelled, isTrue);

    // finished: the backend now lists the report, and the tab shows it
    api.progressJson = {'id': 'r1', 'status': 'done', 'label': 'baseline', 'clips_total': 3, 'clips_done': 3, 'report': reportBrief['name'], 'results': []};
    api.overviewJson = overviewJson(clips: [clipJson()], reports: [reportBrief]);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Running "baseline"'), findsNothing);
    expect(find.text('PASS'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('run-benchmark'))).onPressed, isNotNull);
  });

  testWidgets('a backend without the Benchmark service gets a clear banner with a way to retry', (tester) async {
    final api = FakeBench(overviewJson())..overviewError = BenchmarkApiException('This backend has no Benchmark service yet.');
    await _pump(tester, api);
    expect(find.textContaining('no Benchmark service'), findsOneWidget);
    api.overviewError = null;
    await _tap(tester, find.text('Retry'));
    expect(find.text('No clips yet'), findsOneWidget);
  });
}
