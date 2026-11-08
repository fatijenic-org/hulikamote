import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/trimmer/presentation/widgets/range_timeline.dart';
import 'package:hulikamote_dashboard/features/trimmer/presentation/widgets/trim_player.dart';

/// A 100-second video on a 1000-pixel timeline (10 px a second at zoom 1): 20 s to 60 s is kept.
class Rig {
  Rig({this.start = 20, this.end = 60, this.zoom = 1, double playhead = 0}) : position = ValueNotifier(playhead);

  double start, end, zoom;
  final ValueNotifier<double> position;
  final seeks = <double>[];
  final ranges = <({double? start, double? end})>[];
  var interactions = 0;
  final zooms = <double>[];

  Widget build() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 1000,
                child: RangeTimeline(
                  duration: 100,
                  start: start,
                  end: end,
                  position: position,
                  zoom: zoom,
                  onSeek: seeks.add,
                  onRange: ({double? start, double? end}) {
                    ranges.add((start: start, end: end));
                    setState(() {
                      if (start != null) this.start = start;
                      if (end != null) this.end = end;
                    });
                  },
                  onInteract: () => interactions++,
                  onZoom: zooms.add,
                ),
              ),
            ),
          ),
        ),
      );
}

Future<Rig> pump(WidgetTester tester, Rig rig) async {
  tester.view.physicalSize = const Size(1400, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(rig.build());
  return rig;
}

/// A point on the timeline: [seconds] across at zoom 1 (10 px each), [y] down from its top.
Offset at(WidgetTester tester, double seconds, {double y = 60, double pixelsPerSecond = 10}) {
  final rect = tester.getRect(find.byType(RangeTimeline));
  return Offset(rect.left + seconds * pixelsPerSecond, rect.top + y);
}

void main() {
  testWidgets('dragging the left end moves the start, and the video jumps to that frame', (tester) async {
    final rig = await pump(tester, Rig());
    await tester.dragFrom(at(tester, 20) + const Offset(6, 0), const Offset(100, 0));   // the handle sits just inside the range
    await tester.pump();
    expect(rig.start, closeTo(30, 0.1));
    expect(rig.end, 60);
    expect(rig.seeks.last, closeTo(30, 0.1));
    expect(rig.ranges.every((r) => r.end == null), isTrue);                              // only the start was touched
  });

  testWidgets('dragging the right end moves the end, and the video jumps to that frame', (tester) async {
    final rig = await pump(tester, Rig());
    await tester.dragFrom(at(tester, 60) - const Offset(6, 0), const Offset(-200, 0));
    await tester.pump();
    expect(rig.end, closeTo(40, 0.1));
    expect(rig.start, 20);
    expect(rig.seeks.last, closeTo(40, 0.1));
  });

  testWidgets('dragging anywhere else scrubs through the video and leaves the range alone', (tester) async {
    final rig = await pump(tester, Rig());
    await tester.dragFrom(at(tester, 80), const Offset(100, 0));                         // outside the kept part
    await tester.dragFrom(at(tester, 40), const Offset(-50, 0));                         // inside it
    await tester.pump();
    expect(rig.ranges, isEmpty);
    expect(rig.seeks.first, greaterThan(80));
    expect(rig.seeks.any((s) => s > 85), isTrue);
    expect((rig.start, rig.end), (20, 60));
  });

  testWidgets('the ruler always scrubs, even right above an end', (tester) async {
    final rig = await pump(tester, Rig());
    await tester.dragFrom(at(tester, 20, y: 5) + const Offset(6, 0), const Offset(80, 0));   // from 20.6 s, 8 s on
    await tester.pump();
    expect(rig.ranges, isEmpty);
    expect(rig.seeks.last, closeTo(28.6, 0.1));
  });

  testWidgets('a click on the timeline moves the playhead there; a click on an end does not', (tester) async {
    final rig = await pump(tester, Rig());
    await tester.tapAt(at(tester, 80));
    expect(rig.seeks.last, closeTo(80, 0.1));
    rig.seeks.clear();
    await tester.tapAt(at(tester, 20) + const Offset(6, 0));
    expect(rig.seeks, isEmpty);
    expect(rig.interactions, 2);                                                         // the screen is told, to take the keyboard back
  });

  testWidgets('an end dragged close to the playhead snaps onto it', (tester) async {
    final rig = await pump(tester, Rig(playhead: 35));
    await tester.dragFrom(at(tester, 20) + const Offset(6, 0), const Offset(146, 0));   // 3 px short of 35 s (34.7 s)
    await tester.pump();
    expect(rig.start, 35);
    expect(rig.seeks.last, 35);
  });

  testWidgets('an end cannot be dragged off the video', (tester) async {
    final rig = await pump(tester, Rig());
    await tester.dragFrom(at(tester, 20) + const Offset(6, 0), const Offset(-400, 0));
    await tester.pump();
    expect(rig.start, 0);
    await tester.dragFrom(at(tester, 60) - const Offset(6, 0), const Offset(500, 0));
    await tester.pump();
    expect(rig.end, 100);
  });

  testWidgets('with a very short part both ends are on top of each other: each side pulls its own end', (tester) async {
    final rig = await pump(tester, Rig(start: 50, end: 50.2));
    await tester.dragFrom(at(tester, 50) + const Offset(-2, 0), const Offset(-30, 0));  // the left side: the start
    await tester.pump();
    expect(rig.start, lessThan(50));
    expect(rig.end, 50.2);
    final second = await pump(tester, Rig(start: 50, end: 50.2));
    await tester.dragFrom(at(tester, 50.2) + const Offset(8, 0), const Offset(30, 0));  // the right side: the end
    await tester.pump();
    expect(second.end, greaterThan(50.2));
    expect(second.start, 50);
  });

  testWidgets('zoomed in, an end is dragged in the zoomed scale, so cuts are frame-exact', (tester) async {
    final rig = await pump(tester, Rig(zoom: 4));
    // 40 px a second now: the start (20 s) is at 800 px
    final rect = tester.getRect(find.byType(RangeTimeline));
    await tester.dragFrom(Offset(rect.left + 800 + 6, rect.top + 60), const Offset(120, 0));   // 3 seconds of the zoomed strip
    await tester.pump();
    expect(rig.start, closeTo(23, 0.05));                                                       // at zoom 1 the same drag would be 12 s
  });

  testWidgets('Ctrl + wheel asks to zoom, and the plain wheel does not', (tester) async {
    final rig = await pump(tester, Rig());
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(at(tester, 40)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    expect(rig.zooms, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    expect(rig.zooms.single, greaterThan(1));
  });

  testWidgets('the playhead moves without rebuilding the range', (tester) async {
    final rig = await pump(tester, Rig());
    rig.position.value = 55;
    await tester.pump();
    expect(rig.ranges, isEmpty);
    expect(find.byType(RangeTimeline), findsOneWidget);
  });

  group('ScrubSeeker', () {
    test('asks for the first moment at once and keeps only the newest while a seek is running', () async {
      final asked = <double>[];
      final gate = <Completer<void>>[];
      final seeker = ScrubSeeker((s) {
        asked.add(s);
        final c = Completer<void>();
        gate.add(c);
        return c.future;
      });
      seeker.request(1);
      seeker.request(2);
      seeker.request(3);
      seeker.request(4);
      expect(asked, [1]);                                     // 2 and 3 were never worth asking for
      gate.first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(asked, [1, 4]);
      gate.last.complete();
      await Future<void>.delayed(Duration.zero);
      seeker.request(9);
      expect(asked, [1, 4, 9]);                               // idle again: the next one goes straight through
      gate.last.complete();
    });

    test('a failed seek does not stop later ones', () async {
      final asked = <double>[];
      final seeker = ScrubSeeker((s) async {
        asked.add(s);
        if (s == 1) throw StateError('seek failed');
      });
      runZonedGuarded(() => seeker.request(1), (_, _) {});
      await Future<void>.delayed(Duration.zero);
      seeker.request(2);
      await Future<void>.delayed(Duration.zero);
      expect(asked, [1, 2]);
    });
  });
}
