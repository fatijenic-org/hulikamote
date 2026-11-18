import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/features/monitoring/data/video_upload.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/screens/live_monitoring_screen.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/upload_status_card.dart';

File _clip(int bytes) {
  final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}hk_upload_${DateTime.now().microsecondsSinceEpoch}.mp4');
  file.writeAsBytesSync(List.filled(bytes, 7));
  addTearDown(() {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {} // Windows keeps a file that was just read locked for a moment; a temp file may stay
  });
  return file;
}

const _video = {'width': 1920, 'height': 1080, 'fps': 25.0, 'frames': 2075, 'duration': 83.0, 'size_mb': 312.0};

void main() {
  group('uploadLiveVideo', () {
    test('counts the bytes that go out, up to the whole request, and returns the backend answer', () async {
      final clip = _clip(300000);
      final seen = <int>[];
      var total = 0;
      String? type;
      int? received;
      final client = MockClient((req) async {
        type = req.headers['content-type'];
        received = req.bodyBytes.length;
        return http.Response(jsonEncode({'message': 'Live source updated', 'path': 'x.mp4', 'video': _video}), 200);
      });
      final answer = await uploadLiveVideo(clip.path, client: client, baseUrl: 'http://test', onProgress: (sent, all) {
        seen.add(sent);
        total = all;
      });
      expect(type, startsWith('multipart/form-data; boundary='));
      expect(seen, isNotEmpty);
      expect(seen, orderedEquals([...seen]..sort()));        // never goes back
      expect(seen.last, total);                                // the last report is "everything sent"
      expect(total, received);                                 // the total it announced is what really went out
      expect(total, greaterThan(300000));                      // the file plus the multipart framing
      expect((answer['video'] as Map)['width'], 1920);
    });

    test('a refusal carries the backend reason', () async {
      final clip = _clip(1000);
      final client = MockClient((req) async => http.Response('{"detail":"Cannot open uploaded video"}', 400));
      await expectLater(
        uploadLiveVideo(clip.path, client: client, baseUrl: 'http://test'),
        throwsA(predicate((e) => e is Exception && '$e'.contains('Cannot open uploaded video'))),
      );
    });

    test('a refusal without a reason still says what happened', () async {
      final clip = _clip(1000);
      final client = MockClient((req) async => http.Response('boom', 500));
      await expectLater(
        uploadLiveVideo(clip.path, client: client, baseUrl: 'http://test'),
        throwsA(predicate((e) => e is Exception && '$e'.contains('HTTP 500'))),
      );
    });
  });

  group('UploadStatusCard', () {
    Future<void> show(WidgetTester tester, UploadStatus status, {bool playing = false}) => tester.pumpWidget(
      MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: UploadStatusCard(status: status, playing: playing, onCancel: () {}, onRetry: () {}, onDismiss: () {}))),
    );

    String caption(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('upload-caption'))).data!;

    testWidgets('sending: a bar that fills, the percent, the size, the speed and the time left, and a Cancel button', (tester) async {
      const mb = 1024 * 1024;
      await show(tester, const UploadStatus(name: 'clip.mp4', stage: UploadStage.sending, sent: 150 * mb, total: 300 * mb, bytesPerSecond: 10.0 * mb));
      expect(find.text('Uploading clip.mp4'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('upload-bar'))).value, 0.5);
      expect(caption(tester), '50%  ·  150 MB of 300 MB  ·  10.0 MB/s  ·  about 15 s left');
      expect(find.byKey(const ValueKey('upload-cancel')), findsOneWidget);
      expect(find.byKey(const ValueKey('upload-dismiss')), findsNothing);
    });

    testWidgets('preparing: a bar with no number, and the seconds the backend has been at it', (tester) async {
      await show(tester, const UploadStatus(name: 'clip.mp4', stage: UploadStage.preparing, sent: 10, total: 10, waited: Duration(seconds: 7)));
      expect(find.text('Upload finished. Getting the video ready…'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('upload-bar'))).value, isNull);
      expect(caption(tester), contains('7 s so far'));
      expect(find.byKey(const ValueKey('upload-cancel')), findsNothing);   // the bytes are there: Cancel could not stop the backend
    });

    testWidgets('done: says it is ready, what the video is, and what to do next', (tester) async {
      await show(tester, const UploadStatus(name: 'clip.mp4', stage: UploadStage.done, detail: '1920x1080  ·  25 fps'));
      expect(find.text('clip.mp4 is ready'), findsOneWidget);
      expect(caption(tester), '1920x1080  ·  25 fps  ·  Press Start monitoring to watch it.');
      expect(find.byKey(const ValueKey('upload-bar')), findsNothing);
      expect(find.byKey(const ValueKey('upload-dismiss')), findsOneWidget);
      await show(tester, const UploadStatus(name: 'clip.mp4', stage: UploadStage.done), playing: true);
      expect(caption(tester), 'Now showing in the live view.');
    });

    testWidgets('failed: the reason, Try again and a way to close it', (tester) async {
      await show(tester, const UploadStatus(name: 'clip.mp4', stage: UploadStage.failed, error: 'Cannot open uploaded video'));
      expect(find.text('Upload failed'), findsOneWidget);
      expect(caption(tester), 'Cannot open uploaded video');
      expect(find.byKey(const ValueKey('upload-retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('upload-dismiss')), findsOneWidget);
    });

    test('sizes and times read as people say them', () {
      expect(formatBytes(820 * 1024), '820 KB');
      expect(formatBytes(12.5 * 1024 * 1024), '12.5 MB');
      expect(formatBytes(310 * 1024 * 1024), '310 MB');
      expect(formatBytes(1.5 * 1024 * 1024 * 1024), '1.5 GB');
      expect(formatSeconds(14), '14 s');
      expect(formatSeconds(83), '1 min 23 s');
    });
  });

  group('Live Monitor, Video file…', () {
    /// A backend that answers the screen's own questions and holds the upload answer until the test lets it go.
    ({MockClient client, Completer<http.Response> answer}) backend() {
      final answer = Completer<http.Response>();
      final client = MockClient((req) async {
        if (req.url.path == '/settings/video/use-file') return http.Response('{"detail":"That file is not on the backend PC."}', 404);   // so a copy is uploaded
        if (req.url.path == '/settings/video/upload') return answer.future;
        return http.Response('{"source_url": "C:/clips/street_cam.mp4"}', 200);
      });
      return (client: client, answer: answer);
    }

    Future<void> open(WidgetTester tester, http.Client client, File clip) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: LiveMonitoringScreen(client: client, pickVideo: () async => (path: clip.path, name: 'clip.mp4')),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Change source'));
      await tester.pump();
      await tester.tap(find.text('Video file…'));
      await tester.pump();
    }

    /// Reading the file is real work (it needs real time, and each step finishes in the fake clock only when the tree is pumped):
    /// wait in short real steps, pumping after each, until [until] holds.
    Future<void> letItRun(WidgetTester tester, bool Function() until) async {
      for (var i = 0; i < 60 && !until(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('the card follows the upload: getting ready, then ready with what the video is; the source name changes', (tester) async {
      final b = backend();
      await open(tester, b.client, _clip(200000));
      await letItRun(tester, () => find.text('Upload finished. Getting the video ready…').evaluate().isNotEmpty);

      expect(find.text('Upload finished. Getting the video ready…'), findsOneWidget);          // all bytes are out, the backend is at work
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Change source')).onPressed, isNull);   // no second upload on top
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start monitoring')).onPressed, isNull);    // the new video is not the source yet

      b.answer.complete(http.Response(jsonEncode({'message': 'Live source updated', 'path': 'x.mp4', 'video': _video}), 200));
      await letItRun(tester, () => find.text('clip.mp4 is ready').evaluate().isNotEmpty);

      expect(find.text('clip.mp4 is ready'), findsOneWidget);
      expect(find.textContaining('1920x1080  ·  25 fps  ·  1 min 23 s  ·  312 MB'), findsOneWidget);
      expect(find.textContaining('Press Start monitoring to watch it.'), findsOneWidget);
      expect(find.textContaining('Source: clip.mp4'), findsOneWidget);                          // the paused screen names the new source
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start monitoring')).onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('upload-dismiss')));
      await tester.pump();
      expect(find.byKey(const ValueKey('upload-card')), findsNothing);
      await tester.pumpWidget(const SizedBox());                                                // dispose: no timer is left running
    });

    testWidgets('a refusal shows why, and Try again sends the same file again', (tester) async {
      final answers = <http.Response>[
        http.Response('{"detail":"Cannot open uploaded video"}', 400),
        http.Response(jsonEncode({'message': 'Live source updated', 'path': 'x.mp4', 'video': _video}), 200),
      ];
      var uploads = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/settings/video/use-file') return http.Response('{"detail":"That file is not on the backend PC."}', 404);   // so a copy is uploaded
        if (req.url.path == '/settings/video/upload') return answers[uploads++];
        return http.Response('{"source_url": "C:/clips/street_cam.mp4"}', 200);
      });
      await open(tester, client, _clip(50000));
      await letItRun(tester, () => find.text('Upload failed').evaluate().isNotEmpty);

      expect(find.text('Upload failed'), findsOneWidget);
      expect(find.text('Cannot open uploaded video'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('upload-retry')));
      await tester.pump();
      await letItRun(tester, () => find.text('clip.mp4 is ready').evaluate().isNotEmpty);

      expect(uploads, 2);
      expect(find.text('clip.mp4 is ready'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
