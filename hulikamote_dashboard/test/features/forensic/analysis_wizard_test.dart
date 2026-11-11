import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_runner.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/analysis_wizard.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/wizard_steps.dart' show RunStep;

import '../trimmer/support.dart';
import 'support/test_support.dart';

/// A backend that answers without a network and records the upload.
class FakeApi extends ForensicApi {
  FakeApi({this.fail = false}) : super(baseUrl: 'http://test');

  Map<String, dynamic>? uploaded;
  Map<String, dynamic>? liveConfig;
  String? uploadedPath;
  bool fail;
  double progress = 42;

  /// What the stop buttons asked for ('finish' = Stop here, 'cancel'), and how the backend answers.
  final List<String> stopped = [];
  Object? stopFails;
  RunStatus? answer; // when set, status() returns this instead of "processing"

  /// Where the picture for zones was asked for (seconds), and whether this backend knows the by-path call at all.
  final List<double> frameAsks = [];
  bool byPath = true;
  int uploadReads = 0;

  @override
  Future<FrameInfo?> videoFrame(String videoPath, {double seconds = 0}) async {
    if (fail) throw ForensicApiException('Reading the video failed (HTTP 500).');
    if (!byPath) return null;
    frameAsks.add(seconds);
    return const FrameInfo(url: '/snapshots/frame.jpg', fps: 25, frames: 500, duration: 20);
  }

  @override
  Future<FrameInfo> extractFrame(String videoPath) async {
    uploadReads++;
    if (fail) throw ForensicApiException('Reading the video failed (HTTP 500).');
    return const FrameInfo(url: '/snapshots/frame.jpg', fps: 25, frames: 500);
  }

  @override
  Future<String> submit(String videoPath, Map<String, dynamic> config) async {
    uploaded = config;
    uploadedPath = videoPath;
    return 'T1';
  }

  @override
  Future<String> useForLive(Map<String, dynamic> config) async {
    liveConfig = config;
    return 'Live rules sent.';
  }

  @override
  Future<RunStatus> status(String taskId, {bool tickets = false}) async =>
      answer ?? RunStatus(status: 'processing', progress: progress);

  @override
  Future<void> stopRun(String taskId, {required bool keep}) async {
    if (stopFails != null) throw stopFails!;
    stopped.add(keep ? 'finish' : 'cancel');
  }

  @override
  Future<ModelChoices> models() async => ModelChoices.empty;
}

final _models = ModelChoices({
  'plate': (active: 'plate_active.onnx', names: ['plate_active.onnx', 'plate_old.onnx']),
  'helmet': (active: null, names: <String>[]),
  'cabin': (active: null, names: <String>[]),
  'vehicles': (active: 'yolo11.onnx', names: ['yolo11.onnx']),
});

Future<({AnalysisDraft draft, AnalysisRunner runner, FakeApi api, FakeTrimPlayer player})> _pump(WidgetTester tester, {bool failRead = false}) async {
  final api = FakeApi(fail: failRead);
  final player = FakeTrimPlayer(lengths: {'C:/videos/street.mp4': 20});
  final draft = AnalysisDraft();
  final runner = AnalysisRunner(api, pollEvery: const Duration(milliseconds: 200));
  addTearDown(runner.dispose);
  await pumpScreen(
    tester,
    AnalysisWizard(
      draft: draft,
      runner: runner,
      api: api,
      media: FakeMedia(),
      models: _models,
      onOpenResult: (id, r) {},
      pickVideo: () async => (path: 'C:/videos/street.mp4', name: 'street.mp4'),
      playerFactory: () => player,
    ),
    size: const Size(1500, 2300), // tall: the picker lists 25 violations and builds only what is on screen
  );
  return (draft: draft, runner: runner, api: api, player: player);
}

Finder _continue() => find.widgetWithText(FilledButton, 'Continue');

Future<void> _next(WidgetTester tester) async {
  await tester.tap(_continue());
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _zoneCanvas() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_ZonePainter');

Future<void> _tapButton(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _tapCanvas(WidgetTester tester, double fx, double fy) async {
  final r = tester.getRect(_zoneCanvas());
  await tester.tapAt(Offset(r.left + r.width * fx, r.top + r.height * fy));
  await tester.pump(const Duration(milliseconds: 30));
}

void main() {
  setUpAll(loadRoboto);

  testWidgets('first step asks for a video and says why Continue is off', (tester) async {
    await _pump(tester);
    expect(find.text('Choose a video to analyze'), findsOneWidget);
    expect(tester.widget<FilledButton>(_continue()).onPressed, isNull);
    expect(find.text('Choose a video to continue.'), findsOneWidget);
  });

  testWidgets('a video that cannot be read shows the reason and lets the user retry', (tester) async {
    await _pump(tester, failRead: true);
    await tester.tap(find.text('Choose video…'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Could not read that video'), findsOneWidget);
    expect(find.text('Choose video…'), findsOneWidget); // can try again
  });

  testWidgets('full flow: video, violation, zone, settings, start', (tester) async {
    final h = await _pump(tester);

    // 1 video
    await tester.tap(find.text('Choose video…'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('street.mp4'), findsWidgets);
    expect(tester.widget<FilledButton>(_continue()).onPressed, isNotNull);
    await _next(tester);

    // 2 violations: Continue is off until one is picked, the summary follows the choice
    expect(find.text('What should we look for?'), findsOneWidget);
    expect(tester.widget<FilledButton>(_continue()).onPressed, isNull);
    await tester.tap(find.text('Counterflow').first);
    await tester.pump();
    expect(find.text('Violations (1)'), findsOneWidget);
    // a violation whose model is not trained yet says so
    expect(find.text('Model not trained yet'), findsWidgets);
    await _next(tester);

    // 3 rules: needs a zone before it can go on
    expect(find.text('Set up the rules'), findsOneWidget);
    expect(tester.widget<FilledButton>(_continue()).onPressed, isNull);
    expect(find.textContaining('Still needs a zone: Counterflow'), findsOneWidget);

    await _tapCanvas(tester, 0.2, 0.9);
    await _tapCanvas(tester, 0.8, 0.9);
    await _tapCanvas(tester, 0.5, 0.3);
    expect(find.widgetWithText(FilledButton, 'Save this zone'), findsOneWidget);
    // counterflow also needs its legal-flow arrow
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save this zone')).onPressed, isNull);
    await _tapButton(tester, find.text('Legal-flow arrow'));
    await _tapCanvas(tester, 0.5, 0.8);
    await _tapCanvas(tester, 0.5, 0.4);
    await _tapButton(tester, find.widgetWithText(FilledButton, 'Save this zone'));

    expect(find.text('Zone saved.'), findsOneWidget);
    expect(h.draft.zones('counterflow'), hasLength(1));
    final zone = h.draft.zones('counterflow').first as Map;
    expect((zone['polygon'] as List), hasLength(3));
    final first = (zone['polygon'] as List).first as List;
    expect(first[0], closeTo(1920 * 0.2, 1e-6)); // reference space, like the backend wants
    expect(first[1], closeTo(1080 * 0.9, 1e-6));
    expect(zone['vector'], {'x_dir': 0.0, 'y_dir': closeTo(-1080 * 0.4, 1e-6)});
    expect(tester.widget<FilledButton>(_continue()).onPressed, isNotNull);
    await _next(tester);

    // 4 settings
    expect(find.text('Fine-tune the pipeline'), findsOneWidget);
    expect(find.textContaining('Active model (plate_active.onnx)'), findsOneWidget);
    await tester.tap(find.text('DeepSORT (accurate)'));
    await tester.pump();
    expect(h.draft.settings.tracker, 'deepsort');
    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pump(const Duration(milliseconds: 100));

    // 5 start
    expect(find.text('Ready to analyze'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Start analysis'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.api.uploadedPath, 'C:/videos/street.mp4');
    final cfg = h.api.uploaded!;
    expect(cfg['active_violations'], ['counterflow']);
    expect(cfg['tracker'], 'deepsort');
    expect(cfg['plate_model'], 'plate_active.onnx');
    expect((cfg['per_violation_configs'] as Map)['counterflow']['rois'], hasLength(1));

    // progress is shown with a plain stage name
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('Watching the video and tracking vehicles'), findsOneWidget);
    expect(tester.takeException(), isNull);
    h.runner.clear(); // stop polling
  });

  testWidgets('counterflow can skip the drawing from the zones step itself, other rules cannot', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('Choose video…'));
    await tester.pump(const Duration(milliseconds: 100));
    await _next(tester);
    await tester.tap(find.text('Counterflow').first);
    await tester.pump();
    await _next(tester);

    // this step blocks without a zone, so the switch must be right here (not only in Settings, which is behind it)
    expect(tester.widget<FilledButton>(_continue()).onPressed, isNull);
    expect(find.text('Detect traffic flow automatically'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 50));
    expect(h.draft.settings.autoFlow, isTrue);
    expect(find.text('Automatic: learns the flow'), findsOneWidget);
    expect(tester.widget<FilledButton>(_continue()).onPressed, isNotNull);
    await _next(tester);
    expect(find.text('Fine-tune the pipeline'), findsOneWidget);
    expect(h.draft.zones('counterflow'), isEmpty);

    // a rule that only the law can place has no such switch
    h.draft
      ..clearSelection()
      ..toggle('pedestrian_lane', on: true);
    await tester.tap(find.text('Rules & zones').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Detect traffic flow automatically'), findsNothing);
    expect(tester.widget<FilledButton>(_continue()).onPressed, isNull);
  });

  testWidgets('the learned flow can be hidden or shown right under "Detect traffic flow automatically", and in Settings', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('Choose video…'));
    await tester.pump(const Duration(milliseconds: 100));
    await _next(tester);
    await tester.tap(find.text('Counterflow').first);
    await tester.pump();
    await _next(tester);

    final flowSwitch = find.byKey(const ValueKey('show-flow-switch'));
    expect(find.text('Show the learned flow'), findsNothing); // nothing to show while the flow is not learned
    h.draft.settings.autoFlow = true;
    h.draft.touch();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Show the learned flow'), findsOneWidget);
    expect(tester.takeException(), isNull); // the extra row fits
    expect(tester.widget<Switch>(flowSwitch).value, isTrue); // on by default, as before
    await tester.tap(flowSwitch);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<Switch>(flowSwitch).value, isFalse);
    expect(h.draft.config('counterflow')['show_flow'], isFalse); // the very value Counterflow's own switch uses
    final sent = h.draft.buildConfig()['per_violation_configs'] as Map;
    expect(sent['counterflow']['show_flow'], isFalse);

    await _next(tester); // Settings: the same switch, the same value
    expect(find.text('Fine-tune the pipeline'), findsOneWidget);
    await tester.scrollUntilVisible(flowSwitch, 200, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    expect(tester.widget<Switch>(flowSwitch).value, isFalse);
    await tester.tap(flowSwitch);
    await tester.pump(const Duration(milliseconds: 50));
    expect(h.draft.config('counterflow')['show_flow'], isTrue);
  });

  testWidgets('the show-the-flow switch is not offered when Counterflow (the rule that draws it) is not chosen', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('Choose video…'));
    await tester.pump(const Duration(milliseconds: 100));
    await _next(tester);
    await tester.tap(find.text('Illegal turn').first);
    await tester.pump();
    await _next(tester);
    h.draft.settings.autoFlow = true;
    h.draft.touch();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Detect traffic flow automatically'), findsOneWidget);
    expect(find.text('Show the learned flow'), findsNothing);
  });

  testWidgets('the last step can send the same rules to the Live Monitor without an analysis', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('Choose video…'));
    await tester.pump(const Duration(milliseconds: 100));
    await _next(tester);
    await tester.tap(find.text('Swerving').first);
    await tester.pump();
    await _next(tester);
    await _tapCanvas(tester, 0.2, 0.8);
    await _tapCanvas(tester, 0.8, 0.8);
    await _tapCanvas(tester, 0.5, 0.2);
    await _tapButton(tester, find.widgetWithText(FilledButton, 'Save this zone'));
    await _next(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Ready to analyze'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Use for Live Monitor'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(h.api.liveConfig!['active_violations'], ['swerving']);
    expect((h.api.liveConfig!['per_violation_configs'] as Map)['swerving']['rois'], hasLength(1));
    expect(h.api.uploaded, isNull, reason: 'no analysis was started');
    expect(find.text('Live rules sent.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zones can be deleted again', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('Choose video…'));
    await tester.pump(const Duration(milliseconds: 100));
    await _next(tester);
    await tester.tap(find.text('Swerving').first);
    await tester.pump();
    await _next(tester);
    await _tapCanvas(tester, 0.2, 0.8);
    await _tapCanvas(tester, 0.8, 0.8);
    await _tapCanvas(tester, 0.5, 0.2);
    expect(find.text('3 points, at least 3'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save this zone')).onPressed, isNotNull);
    await _tapButton(tester, find.widgetWithText(FilledButton, 'Save this zone'));
    expect(h.draft.zones('swerving'), hasLength(1));

    await _tapButton(tester, find.byTooltip('Delete zone 1'));
    expect(h.draft.zones('swerving'), isEmpty);
    expect(find.text('Save at least one zone to continue.'), findsOneWidget);
  });

  group('a running analysis can be stopped here or cancelled', () {
    Future<({AnalysisRunner runner, FakeApi api})> running(WidgetTester tester, {VoidCallback? onOpenLive}) async {
      final api = FakeApi();
      final runner = AnalysisRunner(api, pollEvery: const Duration(milliseconds: 100));
      addTearDown(runner.dispose);
      await pumpScreen(
        tester,
        RunStep(
          draft: AnalysisDraft(),
          runner: runner,
          models: ModelChoices.empty,
          onStart: () {},
          onBackToSettings: () {},
          onOpenLive: onOpenLive,
        ),
        size: const Size(1200, 900),
      );
      await runner.start('C:/videos/street.mp4', {});
      await tester.pump(const Duration(milliseconds: 300));
      return (runner: runner, api: api);
    }

    testWidgets('both buttons show while it runs; Stop here asks the backend to keep what was found', (tester) async {
      final h = await running(tester);
      expect(find.byKey(const Key('stop-here')), findsOneWidget);
      expect(find.byKey(const Key('cancel-analysis')), findsOneWidget);
      await tester.tap(find.byKey(const Key('stop-here')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.api.stopped, ['finish']);
      expect(h.runner.phase, RunPhase.running); // it keeps running until the backend wraps up, then the result opens
      h.runner.clear();
    });

    testWidgets('Cancel asks first; "Keep going" changes nothing, "Cancel analysis" sends the cancel', (tester) async {
      final h = await running(tester);
      await tester.tap(find.byKey(const Key('cancel-analysis')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Cancel this analysis?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel-keep-going')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.api.stopped, isEmpty);

      await tester.tap(find.byKey(const Key('cancel-analysis')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.api.stopped, ['cancel']);
      h.runner.clear();
    });

    testWidgets('when the backend reports the run cancelled, the start screen comes back with a note', (tester) async {
      final h = await running(tester);
      h.api.answer = const RunStatus(status: 'cancelled', progress: 31);
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.runner.phase, RunPhase.idle);
      expect(find.text('Ready to analyze'), findsOneWidget);
      expect(find.byKey(const Key('run-notice')), findsOneWidget);
      expect(find.textContaining('cancelled'), findsWidgets);
      expect(find.byKey(const Key('stop-here')), findsNothing);
    });

    testWidgets('a stopped-early run finishes like any other and is handed over', (tester) async {
      final h = await running(tester);
      await tester.tap(find.byKey(const Key('stop-here')));
      h.api.answer = const RunStatus(status: 'completed', progress: 100, stoppedEarly: {'frames': 120});
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.runner.phase, RunPhase.done);
      expect(h.runner.result!.stoppedEarly, {'frames': 120});
    });

    testWidgets('the stage shows what the backend says (stopping, reading plates 12 of 340)', (tester) async {
      final h = await running(tester);
      expect(find.text('Watching the video and tracking vehicles'), findsOneWidget);
      h.api.answer = const RunStatus(status: 'processing', progress: 95, message: 'Reading plates: 12 of 340');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Reading plates: 12 of 340'), findsOneWidget);
      h.runner.clear();
    });

    testWidgets('tickets released while it runs can be opened from the progress page', (tester) async {
      var opened = 0;
      final h = await running(tester, onOpenLive: () => opened++);
      expect(find.byKey(const Key('review-ready')), findsNothing); // nothing released yet
      h.api.answer = const RunStatus(status: 'processing', progress: 50, ticketCount: 3);
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.runner.ticketsReady, 3);
      expect(find.byKey(const Key('tickets-ready')), findsOneWidget);
      expect(find.textContaining('3 tickets are ready'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-ready')));
      expect(opened, 1);
      h.runner.clear();
    });

    testWidgets('Cancel says that the tickets already released go too', (tester) async {
      final h = await running(tester);
      await tester.tap(find.byKey(const Key('cancel-analysis')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(find.byKey(const Key('cancel-warning'))).data, isNot(contains('already released')));
      await tester.tap(find.byKey(const Key('cancel-keep-going')));
      await tester.pump(const Duration(milliseconds: 300));

      h.api.answer = const RunStatus(status: 'processing', progress: 60, ticketCount: 2);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('cancel-analysis')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(find.byKey(const Key('cancel-warning'))).data, contains('2 tickets already released'));
      await tester.tap(find.byKey(const Key('cancel-keep-going')));
      await tester.pump(const Duration(milliseconds: 300));
      h.runner.clear();
    });

    testWidgets('a backend without the stop endpoint is explained, not swallowed', (tester) async {
      final h = await running(tester);
      h.api.stopFails = ForensicApiException('Stopping the analysis failed (HTTP 404).', statusCode: 404);
      await tester.tap(find.byKey(const Key('stop-here')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('stop-error')), findsOneWidget);
      expect(find.textContaining('HTTP 404'), findsOneWidget);
      h.runner.clear();
    });
  });

  for (final (name, size) in const [('laptop', Size(1125, 700)), ('narrow', Size(760, 700))]) {
    testWidgets('every step fits a $name window', (tester) async {
      final api = FakeApi();
      final draft = AnalysisDraft()
        ..setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg', fps: 25, frames: 500)
        ..toggle('counterflow')
        ..toggle('red_light')
        ..toggle('overloading');
      final runner = AnalysisRunner(api);
      addTearDown(runner.dispose);
      await pumpScreen(
        tester,
        AnalysisWizard(draft: draft, runner: runner, api: api, media: FakeMedia(), models: _models, onOpenResult: (a, b) {}, playerFactory: () => FakeTrimPlayer()),
        size: size,
      );
      for (var step = 0; step < 4; step++) {
        expect(tester.takeException(), isNull, reason: 'step ${step + 1}');
        await tester.tap(_continue().evaluate().isNotEmpty ? _continue() : find.widgetWithText(FilledButton, 'Review'));
        await tester.pump(const Duration(milliseconds: 100));
        // satisfy the zone rule so the walk can continue
        for (final k in ['counterflow', 'red_light']) {
          if (draft.zones(k).isEmpty) draft.zones(k).add({'polygon': [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0]]});
        }
        draft.touch();
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
