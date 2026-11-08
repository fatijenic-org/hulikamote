import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/trimmer/data/trimmer_api.dart';
import 'package:hulikamote_dashboard/features/trimmer/domain/trimmer_controller.dart';

import 'support.dart';

const a = r'C:\clips\a.mp4';
const b = r'C:\clips\b.mp4';

Future<void> settle([int ms = 60]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late FakeTrimmerApi api;
  late TrimmerController c;

  setUp(() {
    api = FakeTrimmerApi(lengths: {a: 120, b: 300});
    c = TrimmerController(api: api, pollEvery: const Duration(milliseconds: 15));
  });
  tearDown(() => c.dispose());

  group('videos', () {
    test('opening one asks the backend how long it is and shows it', () async {
      final s = await c.open(a);
      expect((s!.duration, c.active, c.sessions.length), (120, s, 1));
    });

    test('the video appears at once; the backend\'s answer about its length comes after', () async {
      api.probeGate = Completer<void>();
      final opening = c.open(a);
      await settle(10);
      expect(c.sessions.length, 1);                            // already on screen, so the player can start opening it
      expect((c.active!.ready, c.active!.duration), (false, 0));

      api.probeGate!.complete();
      final session = await opening;
      expect((session!.ready, session.duration, session.fps), (true, 120, 25));
    });

    test('a video whose length the player already knew stays open even if the backend cannot read it', () async {
      api.probeGate = Completer<void>();
      api.probeError = TrimmerApiException('ffmpeg cannot read this file');
      final opening = c.open(a);
      await settle(10);
      c.active!.setInfo(duration: 90);                         // the player got there first
      api.probeGate!.complete();
      expect(await opening, isNotNull);
      expect((c.sessions.length, c.active!.duration), (1, 90));
    });

    test('opening the same video again brings it forward instead of adding a copy', () async {
      final first = await c.open(a);
      await c.open(b);
      expect(c.active!.path, b);
      expect(await c.open(a), first);
      expect((c.sessions.length, c.active, c.activeIndex), (2, first, 0));
    });

    test('a video that cannot be read gives a message and no empty tab', () async {
      api.probeError = TrimmerApiException('ffmpeg cannot read this file');
      expect(await c.open(a), isNull);
      expect(c.sessions, isEmpty);
      expect(c.error, 'ffmpeg cannot read this file');
    });

    test('closing a video shows a neighbour, and closing the last one leaves nothing open', () async {
      await c.open(a);
      await c.open(b);
      c.close(1);
      expect(c.sessions.map((s) => s.path).toList(), [a]);
      expect(c.active!.path, a);
      c.close(0);
      expect(c.sessions, isEmpty);
      expect(c.active, isNull);
    });

    test('each video keeps its own clips', () async {
      final first = (await c.open(a))!..addClip(0, 10);
      final second = (await c.open(b))!..addClip(5, 15)..addClip(20, 30);
      expect((first.clips.length, second.clips.length), (1, 2));
      c.activate(0);
      expect(c.active!.clips.length, 1);
    });
  });

  group('exporting', () {
    test('selected clips go out as one job each, with their names and the chosen options', () async {
      final s = (await c.open(a))!;
      final one = s.addClip(10, 20);
      s.rename(one.id, 'Red light');
      s.addClip(30, 45);
      s.selectAll();
      c.setExact(true);
      c.setOutputDir(r'D:\evidence');
      expect(await c.exportSelected(), isTrue);

      final call = api.starts.single;
      expect((call.path, call.exact, call.outputDir), (a, true, r'D:\evidence'));
      expect([for (final x in call.clips) (x.start, x.end, x.label)], [(10.0, 20.0, 'Red light'), (30.0, 45.0, '')]);
      expect(c.jobs.length, 2);
    });

    test('nothing selected means nothing is sent', () async {
      final s = (await c.open(a))!..addClip(10, 20)..clearSelection();
      expect(await c.exportSelected(), isFalse);
      expect(api.starts, isEmpty);
      expect(await c.export(s, []), isFalse);
    });

    test('Export all sends every clip, locked ones included', () async {
      final s = (await c.open(a))!;
      final first = s.addClip(0, 10);
      s.addClip(20, 30);
      s.setLocked(first.id, true);
      await c.exportAll();
      expect(api.starts.single.clips.length, 2);
    });

    test('the clips stay after exporting, so they can be changed and exported again', () async {
      final s = (await c.open(a))!..addClip(0, 10);
      await c.exportAll();
      expect(s.clips.length, 1);
    });

    test('a refused export shows the reason and adds no jobs', () async {
      final s = (await c.open(a))!..addClip(0, 10);
      api.startError = TrimmerApiException('Clip 1 ends after the video does (120.0 s)');
      expect(await c.export(s, s.clips), isFalse);
      expect(c.error, 'Clip 1 ends after the video does (120.0 s)');
      expect(c.jobs, isEmpty);
    });

    test('progress is followed while a job runs, and the asking stops when all are done', () async {
      final s = (await c.open(a))!..addClip(0, 10);
      await c.exportAll();
      final id = c.jobs.single.id;
      api.setStatus(id, 'running', progress: 0.4);
      await settle();
      expect(c.jobs.single.progress, 0.4);

      api.finishAll();
      await settle();
      expect((c.jobs.single.status.name, c.activeJobCount), ('done', 0));
      final calls = api.jobsCalls;
      await settle(100);
      expect(api.jobsCalls, calls);                            // no more asking once nothing is running
      expect(s.clips.length, 1);
    });
  });

  group('working in parallel', () {
    test('the next video can be opened, edited and exported while the first is still being cut', () async {
      final first = (await c.open(a))!..addClip(0, 10)..addClip(20, 30);
      await c.exportAll();
      expect(c.activeJobCount, 2);

      final second = (await c.open(b))!;                       // does not wait for the first
      second.addClip(100, 150);
      await c.exportAll();

      expect(api.starts.map((s) => s.path), [a, b]);
      expect(c.activeJobCount, 3);
      expect((c.jobsFor(first).length, c.jobsFor(second).length), (2, 1));
    });

    test('closing a video does not stop its exports', () async {
      final s = (await c.open(a))!..addClip(0, 10);
      await c.exportAll();
      c.close(0);
      expect(c.activeJobCount, 1);
      api.finishAll();
      await settle();
      expect(c.jobs.single.status.name, 'done');
      expect(s.clips.length, 1);
    });

    test('each video can be exported again while an earlier export of it runs', () async {
      final s = (await c.open(a))!..addClip(0, 10);
      await c.exportAll();
      s.addClip(40, 50);
      await c.exportAll();
      expect(api.starts.length, 2);
      expect(c.jobs.length, 3);
    });
  });

  group('stopping and tidying', () {
    test('a running job can be stopped', () async {
      final s = (await c.open(a))!..addClip(0, 10);
      await c.exportAll();
      final id = c.jobs.single.id;
      await c.cancel(c.jobs.single);
      expect(api.cancelled, [id]);
      expect(c.jobs.single.status.name, 'cancelled');
      expect(c.activeJobCount, 0);
      expect(s.clips.length, 1);
    });

    test('finished jobs can be cleared from the list while running ones stay', () async {
      (await c.open(a))!..addClip(0, 10)..addClip(20, 30);
      await c.exportAll();
      api.setStatus(api.jobIds.first, 'done');
      await c.clearFinished();
      expect((api.clearCalls, c.jobs.length), (1, 1));
    });
  });
}
