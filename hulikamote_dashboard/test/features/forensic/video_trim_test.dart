import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_runner.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/analysis_wizard.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/video_trim_panel.dart';
import 'package:hulikamote_dashboard/features/trimmer/presentation/widgets/range_timeline.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../trimmer/support.dart';
import 'support/test_support.dart';

const video = 'C:/videos/street.mp4';

AnalysisDraft chosen({double duration = 20, double fps = 25}) => AnalysisDraft()
  ..chooseVideo(path: video, name: 'street.mp4')
  ..setFrame(url: '/f.jpg', seconds: 0, fps: fps, frames: (duration * fps).round(), duration: duration);

void main() {
  setUpAll(loadRoboto);

  // ─── what the draft remembers about the chosen part ───────────────────────

  group('the part of the video to analyze', () {
    test('starts as the whole video, and nothing about it is sent', () {
      final d = chosen(duration: 100);
      expect((d.trimStart, d.trimEnd, d.trimmed, d.keptSeconds, d.effectiveEnd), (0, null, false, 100, 100));
      final config = d.buildConfig();
      expect(config.containsKey('trim_start'), isFalse);
      expect(config.containsKey('trim_end'), isFalse);
    });

    test('a start and an end are kept and sent in seconds', () {
      final d = chosen(duration: 100)..setTrim(start: 10, end: 40);
      expect((d.trimmed, d.keptSeconds), (true, 30));
      expect(d.buildConfig()['trim_start'], 10);
      expect(d.buildConfig()['trim_end'], 40);
      expect(() => jsonEncode(d.buildConfig()), returnsNormally);
    });

    test('only a start is sent when the end is the end of the video', () {
      final config = (chosen(duration: 100)..setTrim(start: 10)).buildConfig();
      expect(config['trim_start'], 10);
      expect(config.containsKey('trim_end'), isFalse);
    });

    test('an end dragged to the very end of the video means no end', () {
      final d = chosen(duration: 100)..setTrim(start: 10, end: 40)..setTrim(end: 100);
      expect(d.trimEnd, isNull);
      expect(d.trimmed, isTrue);                               // the start still cuts something off
      d.setTrim(start: 0);
      expect(d.trimmed, isFalse);
    });

    test('the ends stay inside the video and at least one frame apart', () {
      final d = chosen(duration: 100, fps: 25)..setTrim(start: 40, end: 60);
      d.setTrim(start: 70);                                    // the start dragged past the end
      expect(d.trimStart, closeTo(60 - 1 / 25, 1e-9));
      d.setTrim(end: 5);                                       // the end dragged before the start
      expect(d.trimEnd, closeTo(d.trimStart + 1 / 25, 1e-9));
      d.setTrim(start: -5);
      expect(d.trimStart, 0);
      d.setTrim(end: 500);
      expect(d.trimEnd, isNull);
    });

    test('Use the whole video puts everything back', () {
      final d = chosen(duration: 100)..setTrim(start: 10, end: 40)..resetTrim();
      expect((d.trimStart, d.trimEnd, d.trimmed), (0, null, false));
    });

    test('a trim set before the length is known never sends an impossible end', () {
      final d = AnalysisDraft()..chooseVideo(path: video, name: 'street.mp4');
      d.setTrim(start: 5);
      expect(d.trimEnd, isNull);
      expect(() => jsonEncode(d.buildConfig()), returnsNormally);
    });

    test('choosing another video forgets the trim, the choices and the old picture', () {
      final d = chosen(duration: 100)
        ..setTrim(start: 10, end: 40)
        ..toggle('no_helmet', on: true);
      d.chooseVideo(path: 'C:/videos/other.mp4', name: 'other.mp4');
      expect((d.trimStart, d.trimEnd, d.duration, d.frameUrl, d.frameSeconds), (0, null, 0, null, null));
      expect(d.selection, isEmpty);
      expect((d.hasVideoPath, d.hasVideo), (true, false));     // chosen, but its picture is still on its way
    });

    test('the first to know the length wins; a later answer does not change it', () {
      final d = AnalysisDraft()..chooseVideo(path: video, name: 'a.mp4');
      d.learnDuration(61.5);
      d.learnDuration(99);
      d.learnDuration(0);
      expect(d.duration, 61.5);
    });

    test('the picture remembers which moment it shows', () {
      final d = AnalysisDraft()..chooseVideo(path: video, name: 'a.mp4');
      d.setFrame(url: '/g.jpg', seconds: 12.5, fps: 29.97, frames: 900, duration: 30);
      expect((d.frameUrl, d.frameSeconds, d.fps, d.frameCount, d.hasVideo), ('/g.jpg', 12.5, 29.97, 900, true));
    });
  });

  // ─── asking the backend for a frame by path ───────────────────────────────

  group('finding a frame by path', () {
    ForensicApi api(Future<http.Response> Function(http.Request) handler) => ForensicApi(baseUrl: 'http://test', client: MockClient(handler));

    test('sends the path and the moment, and reads the picture, speed, frame count and length', () async {
      late Uri seen;
      final info = await api((req) async {
        seen = req.url;
        return http.Response(jsonEncode({'frame_url': '/f.jpg', 'fps': 25.0, 'frame_count': 500, 'duration': 20.0}), 200);
      }).videoFrame('C:/videos/my clip.mp4', seconds: 12.5);
      expect(seen.path, '/api/forensic/video-frame');
      expect(seen.queryParameters, {'file_path': 'C:/videos/my clip.mp4', 'seconds': '12.5'});
      expect((info!.url, info.fps, info.frames, info.duration), ('/f.jpg', 25.0, 500, 20.0));
    });

    test('an older backend that does not know the call gives null, so the upload way can be used', () async {
      final info = await api((req) async => http.Response('{"detail":"Not Found"}', 404)).videoFrame(video);
      expect(info, isNull);
    });

    test('a video the backend cannot read says why', () async {
      expect(
        api((req) async => http.Response('{"detail":"Failed to read that video file"}', 400)).videoFrame(video),
        throwsA(isA<ForensicApiException>().having((e) => e.message, 'message', 'Failed to read that video file')),
      );
    });
  });

  // ─── the trim panel ───────────────────────────────────────────────────────

  group('the trim panel', () {
    Future<({AnalysisDraft draft, FakeTrimPlayer player})> pumpPanel(
      WidgetTester tester, {
      AnalysisDraft? draft,
      FakeTrimPlayer? player,
      bool preparing = false,
      VoidCallback? onPick,
      bool opened = true,
    }) async {
      final d = draft ?? chosen();
      final p = player ?? FakeTrimPlayer(lengths: {video: 20});
      if (opened) await p.open(video);
      await pumpScreen(
        tester,
        SingleChildScrollView(child: VideoTrimPanel(draft: d, player: p, preparing: preparing, onPick: onPick ?? () {})),
        size: const Size(1300, 1500),
      );
      return (draft: d, player: p);
    }

    Offset onTimeline(WidgetTester tester, double seconds, {double y = 60}) {
      final rect = tester.getRect(find.byType(RangeTimeline));
      return Offset(rect.left + seconds / 20 * rect.width, rect.top + y);
    }

    Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {LogicalKeyboardKey? holding}) async {
      if (holding != null) await tester.sendKeyDownEvent(holding);
      await tester.sendKeyEvent(k);
      if (holding != null) await tester.sendKeyUpEvent(holding);
      await tester.pump();
    }

    testWidgets('says it is opening until the player knows the length, then shows the timeline', (tester) async {
      final player = FakeTrimPlayer(lengths: {video: 20}, reportsLength: false);
      final draft = AnalysisDraft()..chooseVideo(path: video, name: 'street.mp4');
      await pumpPanel(tester, draft: draft, player: player);
      expect(find.text('Opening the video…'), findsOneWidget);
      expect(find.text('Reading the video…'), findsOneWidget);
      expect(find.byType(RangeTimeline), findsNothing);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.skip_next)).onPressed, isNull);   // nothing to step through yet

      player.reportsLength = true;
      await player.open(video);                                // the player got there first
      await tester.pump();
      expect(find.byType(RangeTimeline), findsOneWidget);
      expect(draft.duration, 20);                              // and the draft learned the length from it
      expect(find.text('Opening the video…'), findsNothing);
    });

    testWidgets('shows the time and the frame number the video is at', (tester) async {
      final h = await pumpPanel(tester);
      h.player.moveTo(5.0);
      await tester.pump();
      expect(find.textContaining('0:05.0 / 0:20.0  ·  frame 125'), findsOneWidget);
    });

    testWidgets('the arrow keys step one frame, Shift one second, Ctrl ten seconds, forwards and back', (tester) async {
      final h = await pumpPanel(tester);
      h.player.moveTo(5);
      await tester.pump();

      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(h.player.seeks.last, closeTo(5 + 1 / 25, 1e-6));
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(h.player.seeks.last, closeTo(5 + 2 / 25, 1e-6));                      // steps add up even before the player reports back
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(h.player.seeks.last, closeTo(5 + 1 / 25, 1e-6));
      await key(tester, LogicalKeyboardKey.arrowRight, holding: LogicalKeyboardKey.shiftLeft);
      expect(h.player.seeks.last, closeTo(6.04, 1e-6));
      await key(tester, LogicalKeyboardKey.arrowRight, holding: LogicalKeyboardKey.controlLeft);
      expect(h.player.seeks.last, closeTo(16.04, 1e-6));
      await key(tester, LogicalKeyboardKey.comma);
      expect(h.player.seeks.last, closeTo(16.0, 1e-6));
      await key(tester, LogicalKeyboardKey.period);
      expect(h.player.seeks.last, closeTo(16.04, 1e-6));
    });

    testWidgets('stepping never goes before the start of the video', (tester) async {
      final h = await pumpPanel(tester);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(h.player.seeks.last, 0);
      await key(tester, LogicalKeyboardKey.arrowLeft, holding: LogicalKeyboardKey.controlLeft);
      expect(h.player.seeks.last, 0);
    });

    testWidgets('stepping never goes past the end of the video', (tester) async {
      final h = await pumpPanel(tester);
      h.player.moveTo(19.99);
      await tester.pump();
      await key(tester, LogicalKeyboardKey.arrowRight, holding: LogicalKeyboardKey.controlLeft);
      expect(h.player.seeks.last, 20);
    });

    testWidgets('I and O put the start and the end at the playhead, and a cut that would be empty is refused', (tester) async {
      final h = await pumpPanel(tester);
      h.player.moveTo(8);
      await tester.pump();
      await key(tester, LogicalKeyboardKey.keyI);
      expect(h.draft.trimStart, 8);
      h.player.moveTo(15);
      await tester.pump(const Duration(milliseconds: 500));
      await key(tester, LogicalKeyboardKey.keyO);
      expect(h.draft.trimEnd, 15);
      expect(find.text('Analyzing 0:07 of 0:20'), findsOneWidget);

      h.player.moveTo(3);                                                            // before the start: it would be empty
      await tester.pump(const Duration(milliseconds: 500));
      await key(tester, LogicalKeyboardKey.keyO);
      expect(h.draft.trimEnd, 15);
    });

    testWidgets('Home and End jump to the two ends of the kept part', (tester) async {
      final h = await pumpPanel(tester);
      h.draft.setTrim(start: 4, end: 12);
      await tester.pump();
      await key(tester, LogicalKeyboardKey.home);
      expect(h.player.seeks.last, 4);
      await key(tester, LogicalKeyboardKey.end);
      expect(h.player.seeks.last, 12);
    });

    testWidgets('Space plays and pauses', (tester) async {
      final h = await pumpPanel(tester);
      await key(tester, LogicalKeyboardKey.space);
      expect(h.player.plays, 1);
      await key(tester, LogicalKeyboardKey.space);
      expect(h.player.pauses, greaterThan(0));
    });

    testWidgets('typing a time sets the start or the end and shows that frame; an impossible one is put back', (tester) async {
      final h = await pumpPanel(tester);
      await tester.enterText(find.widgetWithText(TextField, '0:20.0'), '0:12');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(h.draft.trimEnd, 12);
      expect(h.player.seeks.last, 12);

      await tester.enterText(find.widgetWithText(TextField, '0:00.0'), '0:30');       // after the end
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(h.draft.trimStart, 0);
      expect(find.widgetWithText(TextField, '0:00.0'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '0:00.0'), '0:04.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(h.draft.trimStart, 4.5);
    });

    testWidgets('typing in a time box never plays the video or steps it', (tester) async {
      final h = await pumpPanel(tester);
      await tester.tap(find.widgetWithText(TextField, '0:00.0'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(h.player.plays, 0);
      expect(h.player.seeks, isEmpty);
    });

    testWidgets('Use the whole video is only on when something is cut, and puts it all back', (tester) async {
      final h = await pumpPanel(tester);
      TextButton whole() => tester.widget<TextButton>(find.widgetWithText(TextButton, 'Use the whole video'));
      expect(whole().onPressed, isNull);
      expect(find.text('The whole video will be analyzed'), findsOneWidget);
      h.draft.setTrim(start: 5, end: 10);
      await tester.pump();
      expect(find.text('Analyzing 0:05 of 0:20'), findsOneWidget);
      await tester.tap(find.text('Use the whole video'));
      await tester.pump();
      expect((h.draft.trimStart, h.draft.trimEnd), (0, null));
    });

    testWidgets('Play this part starts at its start and pauses by itself when its end is passed', (tester) async {
      final h = await pumpPanel(tester);
      h.draft.setTrim(start: 5, end: 10);
      await tester.pump();
      await tester.tap(find.text('Play this part'));
      await tester.pump();
      expect((h.player.seeks.last, h.player.plays), (5, 1));
      final pauses = h.player.pauses;
      h.player.moveTo(9.5);
      expect(h.player.pauses, pauses);                                               // still inside
      h.player.moveTo(10.1);
      expect(h.player.pauses, pauses + 1);                                           // past the end: stopped
    });

    testWidgets('dragging along the timeline scrubs the video and pauses it', (tester) async {
      final h = await pumpPanel(tester);
      await h.player.play();
      await tester.dragFrom(onTimeline(tester, 4), const Offset(300, 0));
      await tester.pump();
      expect(h.player.seeks.length, greaterThan(0));
      expect(h.player.seeks.last, greaterThan(8));
      expect(h.draft.trimmed, isFalse);                                              // scrubbing never changes the cut
      expect(h.player.playing.value, isFalse);
    });

    testWidgets('dragging the start end moves the cut and shows that very frame', (tester) async {
      final h = await pumpPanel(tester);
      h.draft.setTrim(start: 5, end: 15);
      await tester.pump();
      final rect = tester.getRect(find.byType(RangeTimeline));
      final handle = Offset(rect.left + 5 / 20 * rect.width + 6, rect.top + 60);      // the handle sits just inside the part
      await tester.dragFrom(handle, const Offset(120, 0));
      await tester.pump();
      expect(h.draft.trimStart, greaterThan(5));
      expect(h.draft.trimEnd, 15);
      expect(h.player.seeks.last, closeTo(h.draft.trimStart, 0.05));
    });

    testWidgets('the picture lookup and the other-video button are shown', (tester) async {
      var picked = 0;
      await pumpPanel(tester, preparing: true, onPick: () => picked++);
      expect(find.text('Getting the picture for drawing zones…'), findsOneWidget);
      await tester.tap(find.text('Choose another'));
      expect(picked, 1);
    });
  });

  // ─── the first step of the wizard ─────────────────────────────────────────

  group('the wizard\'s video step', () {
    Future<({AnalysisDraft draft, FakeTrimPlayer player, _TrimApi api})> pumpWizard(WidgetTester tester, _TrimApi api, {double length = 20}) async {
      final draft = AnalysisDraft();
      final runner = AnalysisRunner(api, pollEvery: const Duration(milliseconds: 200));
      addTearDown(runner.dispose);
      final player = FakeTrimPlayer(lengths: {video: length});
      await pumpScreen(
        tester,
        AnalysisWizard(
          draft: draft,
          runner: runner,
          api: api,
          media: FakeMedia(),
          models: ModelChoices.empty,
          onOpenResult: (id, r) {},
          pickVideo: () async => (path: video, name: 'street.mp4'),
          playerFactory: () => player,
        ),
        size: const Size(1500, 2300),
      );
      return (draft: draft, player: player, api: api);
    }

    Finder continueButton() => find.widgetWithText(FilledButton, 'Continue');

    Future<void> choose(WidgetTester tester) async {
      await tester.tap(find.text('Choose video…').first);
      await tester.pump(const Duration(milliseconds: 50));    // the panel appears and finds out the length after its first frame
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the video opens by its path the moment it is chosen: nothing is uploaded and nothing is waited for', (tester) async {
      final api = _TrimApi()..gate = Completer<void>();                                 // the picture is still on its way
      final h = await pumpWizard(tester, api);
      await choose(tester);

      expect(h.player.opened, [video]);                                                  // already opening
      expect(find.text('Choose and trim the video'), findsOneWidget);
      expect(find.byType(RangeTimeline), findsOneWidget);                                // the player told us the length: trimming works now
      expect(find.text('Getting the picture for drawing zones…'), findsOneWidget);
      expect(api.uploads, 0);
      expect(tester.widget<FilledButton>(continueButton()).onPressed, isNull);          // only the zones picture is missing

      api.gate!.complete();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<FilledButton>(continueButton()).onPressed, isNotNull);
      expect(api.asks, [0.0]);
    });

    testWidgets('Continue uses the picture at the start of the chosen part, and only looks it up again when the start moved', (tester) async {
      final api = _TrimApi();
      final h = await pumpWizard(tester, api);
      await choose(tester);
      expect(api.asks, [0.0]);

      h.draft.setTrim(start: 5);
      await tester.tap(continueButton());
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.asks, [0.0, 5.0]);
      expect(h.draft.frameSeconds, 5);
      expect(find.text('What should we look for?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(continueButton());                                                // nothing moved: no new lookup
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.asks, [0.0, 5.0]);

      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pump(const Duration(milliseconds: 100));
      h.draft.setTrim(end: 12);                                                          // only the end moved: the picture is still right
      await tester.tap(continueButton());
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.asks, [0.0, 5.0]);
    });

    testWidgets('the chosen part goes into the analysis settings', (tester) async {
      final api = _TrimApi();
      final h = await pumpWizard(tester, api);
      await choose(tester);
      h.draft.setTrim(start: 5, end: 12);
      final config = h.draft.buildConfig();
      expect((config['trim_start'], config['trim_end']), (5.0, 12.0));
    });

    testWidgets('the summary says how much of the video is analyzed', (tester) async {
      final api = _TrimApi();
      final h = await pumpWizard(tester, api);
      await choose(tester);
      h.draft.setTrim(start: 5, end: 12);
      await tester.pump();
      expect(find.textContaining('7 s of 20 s'), findsWidgets);
    });

    testWidgets('a backend too old for the by-path call gets the video uploaded for its first frame, once', (tester) async {
      final api = _TrimApi()..byPath = false;
      final h = await pumpWizard(tester, api);
      await choose(tester);
      expect(api.uploads, 1);
      h.draft.setTrim(start: 5);
      await tester.tap(continueButton());
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.uploads, 1);                                                            // no second upload, and no waiting loop
      expect(find.text('What should we look for?'), findsOneWidget);
    });

    testWidgets('a video nobody can read goes back to the picker with the reason', (tester) async {
      final api = _TrimApi()..fail = true;
      final h = await pumpWizard(tester, api);
      await choose(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Could not read that video'), findsOneWidget);
      expect(find.text('Choose a video to analyze'), findsOneWidget);
      expect(h.draft.hasVideoPath, isFalse);
      expect(h.player.pauses, greaterThan(0));
    });

    testWidgets('choosing another video starts again from the whole video', (tester) async {
      final api = _TrimApi();
      final h = await pumpWizard(tester, api);
      await choose(tester);
      h.draft.setTrim(start: 5, end: 12);
      await tester.pump();
      await tester.tap(find.text('Choose another'));
      await tester.pump(const Duration(milliseconds: 100));
      expect((h.draft.trimStart, h.draft.trimEnd), (0, null));
      expect(h.player.opened, [video, video]);
      expect(api.asks.last, 0.0);
    });
  });
}

/// A backend that answers without a network: records how the zones picture was asked for.
class _TrimApi extends ForensicApi {
  _TrimApi() : super(baseUrl: 'http://test');

  final asks = <double>[];
  int uploads = 0;
  bool byPath = true;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<FrameInfo?> videoFrame(String videoPath, {double seconds = 0}) async {
    if (gate != null) await gate!.future;
    if (fail) throw ForensicApiException('Reading the video failed (HTTP 500).');
    if (!byPath) return null;
    asks.add(seconds);
    return const FrameInfo(url: '/snapshots/frame.jpg', fps: 25, frames: 500, duration: 20);
  }

  @override
  Future<FrameInfo> extractFrame(String videoPath) async {
    uploads++;
    if (fail) throw ForensicApiException('Reading the video failed (HTTP 500).');
    return const FrameInfo(url: '/snapshots/frame.jpg', fps: 25, frames: 500);
  }

  @override
  Future<ModelChoices> models() async => ModelChoices.empty;
}
