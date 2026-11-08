import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/trimmer/domain/time_format.dart';
import 'package:hulikamote_dashboard/features/trimmer/domain/timeline_geometry.dart';
import 'package:hulikamote_dashboard/features/trimmer/domain/trim_session.dart';
import 'package:hulikamote_dashboard/features/trimmer/domain/trimmer_models.dart';

TrimSession session({double duration = 100}) => TrimSession(path: r'C:\clips\street.mp4', duration: duration);

void main() {
  group('times', () {
    test('are shown as minutes and seconds, with hours when needed', () {
      expect(formatClock(0), '0:00.0');
      expect(formatClock(75.55), '1:15.5');
      expect(formatClock(3725), '1:02:05.0');
      expect(formatClock(75.9, tenths: false), '1:15');
      expect(formatClock(-3), '0:00.0');
    });

    test('are understood however they are typed', () {
      expect(parseClock('75'), 75);
      expect(parseClock('1:15'), 75);
      expect(parseClock(' 1:15.5 '), 75.5);
      expect(parseClock('0:01:15'), 75);
      expect(parseClock('1:02:05'), 3725);
    });

    test('anything else is not a time', () {
      for (final bad in ['', 'abc', '1:', ':30', '-5', '1:2:3:4', '1.5:30', '1:xx']) {
        expect(parseClock(bad), isNull, reason: bad);
      }
    });
  });

  group('clips', () {
    test('a new clip may be drawn in either direction and always fits the video', () {
      final s = session();
      expect((s.addClip(30, 10).start, s.clips.last.end), (10, 30));
      final late = s.addClip(95, 130);
      expect((late.start, late.end), (95, 100));
      final tiny = s.addClip(50, 50.1);
      expect(tiny.length, TrimSession.minLength);
    });

    test('a clip at the very end keeps its minimum length by moving back', () {
      final s = session();
      final c = s.addClip(100, 100);
      expect((c.start, c.end), (99.5, 100));
    });

    test('Add clip starts at the playhead and runs 10 seconds, or less before the end', () {
      final s = session()..position = 20;
      final c = s.addAtPlayhead();
      expect((c.start, c.end), (20, 30));
      s.position = 97;
      final end = s.addAtPlayhead();
      expect((end.start, end.end), (90, 100));                 // shifted back so it keeps its length
    });

    test('the edges stop at each other and at the ends of the video', () {
      final s = session();
      final c = s.addClip(20, 40);
      s.setStart(c.id, 39.9);
      expect(c.start, 40 - TrimSession.minLength);
      s.setStart(c.id, -5);
      expect(c.start, 0);
      s.setEnd(c.id, 0);
      expect(c.end, c.start + TrimSession.minLength);
      s.setEnd(c.id, 500);
      expect(c.end, 100);
    });

    test('sliding keeps the length and stops at the ends', () {
      final s = session();
      final c = s.addClip(20, 30);
      s.moveClip(c.id, 50);
      expect((c.start, c.end), (50, 60));
      s.moveClip(c.id, 95);
      expect((c.start, c.end), (90, 100));
      s.moveClip(c.id, -10);
      expect((c.start, c.end), (0, 10));
    });

    test('typed times are accepted only when they fit', () {
      final s = session();
      final c = s.addClip(10, 20);
      expect(s.setRange(c.id, 5, 15), isTrue);
      expect((c.start, c.end), (5, 15));
      expect(s.setRange(c.id, 15, 15.1), isFalse);             // too short
      expect(s.setRange(c.id, 90, 120), isFalse);              // past the end
      expect(s.setRange(c.id, -1, 10), isFalse);
      expect((c.start, c.end), (5, 15));                       // untouched by the refused ones
    });
  });

  group('selecting and locking', () {
    test('clicking selects one, Ctrl-clicking adds and removes', () {
      final s = session();
      final a = s.addClip(0, 10), b = s.addClip(20, 30), c = s.addClip(40, 50);
      s.select(a.id);
      s.select(c.id, additive: true);
      expect(s.selected, {a.id, c.id});
      s.select(a.id, additive: true);
      expect(s.selected, {c.id});
      s.select(b.id);
      expect(s.selected, {b.id});
      s.selectAll();
      expect(s.selected.length, 3);
      s.clearSelection();
      expect(s.selected, isEmpty);
    });

    test('a locked clip cannot be moved, resized, renamed or deleted', () {
      final s = session();
      final c = s.addClip(10, 20);
      s.setLocked(c.id, true);
      expect(s.setStart(c.id, 5), isFalse);
      expect(s.setEnd(c.id, 30), isFalse);
      expect(s.moveClip(c.id, 50), isFalse);
      expect(s.setRange(c.id, 0, 5), isFalse);
      expect(s.rename(c.id, 'x'), isFalse);
      expect(s.remove(c.id), isFalse);
      expect((c.start, c.end, c.label), (10, 20, ''));
      s.setLocked(c.id, false);
      expect(s.setStart(c.id, 5), isTrue);
    });

    test('lock and unlock work on the whole selection, and delete skips the locked ones', () {
      final s = session();
      final a = s.addClip(0, 10), b = s.addClip(20, 30), c = s.addClip(40, 50);
      s.select(a.id);
      s.select(b.id, additive: true);
      s.lockSelected(true);
      expect([a.locked, b.locked, c.locked], [true, true, false]);
      s.selectAll();
      expect(s.removeSelected(), 1);                           // only the unlocked one
      expect(s.clips.map((x) => x.id), [a.id, b.id]);
      s.lockSelected(false);
      expect(s.removeSelected(), 2);
      expect(s.clips, isEmpty);
    });

    test('unnamed clips are called by their number', () {
      final s = session();
      final a = s.addClip(0, 10), b = s.addClip(20, 30);
      s.rename(b.id, '  Red light  ');
      expect((s.titleOf(a), s.titleOf(b)), ('Clip 1', 'Red light'));
    });

    test('listeners hear about changes, and the session knows the video name', () {
      final s = session();
      var heard = 0;
      s.addListener(() => heard++);
      s.addClip(0, 10);
      expect(heard, 1);
      expect(s.name, 'street.mp4');
    });
  });

  group('the timeline picture', () {
    const geo = TimelineGeometry(width: 1000, duration: 100);

    test('times and pixels convert both ways and stay inside the strip', () {
      expect(geo.xOf(25), 250);
      expect(geo.tOf(250), 25);
      expect(geo.tOf(-40), 0);
      expect(geo.tOf(5000), 100);
    });

    test('the pointer grabs an edge, then a body, else nothing', () {
      final s = session();
      final a = s.addClip(20, 40), b = s.addClip(60, 80);
      TimelineHit hit(double x) => geo.hit(x, s.clips, s.selected);
      expect(hit(200).kind, HitKind.start);
      expect(hit(206).clip, a);                                // inside the grab margin
      expect(hit(400).kind, HitKind.end);
      expect(hit(300), isA<TimelineHit>().having((h) => h.kind, 'kind', HitKind.body));
      expect(hit(300).clip, a);
      expect(hit(500).kind, HitKind.empty);
      expect(hit(700).clip, b);
    });

    test('where two clips touch, the selected one\'s edge wins', () {
      final s = session();
      final a = s.addClip(20, 40), b = s.addClip(40, 60);
      s.select(b.id);
      expect(geo.hit(400, s.clips, s.selected).clip, b);
      s.select(a.id);
      expect(geo.hit(400, s.clips, s.selected).clip, a);
    });

    test('overlapping clips: the selected one is picked first', () {
      final s = session();
      final a = s.addClip(20, 60), b = s.addClip(30, 50);
      s.select(a.id);
      expect(geo.hit(450, s.clips, s.selected).clip, a);
      s.select(b.id);
      expect(geo.hit(450, s.clips, s.selected).clip, b);
    });

    test('ruler labels are never closer than the minimum, whatever the zoom', () {
      for (final width in [300.0, 1000.0, 10000.0, 80000.0]) {
        final g = TimelineGeometry(width: width, duration: 3600);
        expect(g.rulerStep() * width / 3600, greaterThanOrEqualTo(90));
      }
      expect(const TimelineGeometry(width: 0, duration: 0).rulerStep(), 1);
    });
  });

  group('exports', () {
    test('a job knows its file name and whether it is still going', () {
      final job = TrimJob.fromJson({'id': 'a', 'source': 'x', 'output': r'C:\out\street_c1.mp4', 'start': 1, 'end': 2, 'label': '', 'status': 'running', 'progress': 0.5});
      expect((job.outputName, job.active, job.status), ('street_c1.mp4', true, JobStatus.running));
      expect(TrimJob.fromJson({...{'id': 'b', 'output': 'o'}, 'status': 'done'}).active, isFalse);
      expect(JobStatus.parse('nonsense'), JobStatus.failed);
    });
  });
}
