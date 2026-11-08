import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/trimmer/data/trimmer_api.dart';
import 'package:hulikamote_dashboard/features/trimmer/domain/trim_session.dart';
import 'package:hulikamote_dashboard/features/trimmer/domain/trimmer_controller.dart';
import 'package:hulikamote_dashboard/features/trimmer/presentation/screens/trimmer_screen.dart';
import 'package:hulikamote_dashboard/features/trimmer/presentation/widgets/trim_timeline.dart';

import '../forensic/support/test_support.dart';
import 'support.dart';

const a = r'C:\clips\street.mp4';
const b = r'C:\clips\junction.mp4';

class Rig {
  Rig(this.api, this.player, this.controller, this.revealed, this.picks);

  final FakeTrimmerApi api;
  final FakeTrimPlayer player;
  final TrimmerController controller;
  final List<String> revealed;
  final List<String> picks;
  String? folder;

  TrimSession get session => controller.active!;
}

/// The trimmer on screen with a stand-in player and backend. [picks] are the videos the file dialog "chooses", in order.
Future<Rig> pumpTrimmer(WidgetTester tester, {List<String> picks = const [a]}) async {
  final lengths = {a: 100.0, b: 200.0};
  final api = FakeTrimmerApi(lengths: lengths);
  final player = FakeTrimPlayer(lengths: lengths);
  final controller = TrimmerController(api: api, pollEvery: const Duration(milliseconds: 50));
  final rig = Rig(api, player, controller, [], List.of(picks));
  await pumpScreen(
    tester,
    TrimmerScreen(
      controller: controller,
      playerFactory: () => player,
      pickVideo: () async => rig.picks.isEmpty ? null : rig.picks.removeAt(0),
      pickFolder: () async => rig.folder,
      reveal: (path) async => rig.revealed.add(path),
    ),
    size: const Size(1700, 1000),
  );
  return rig;
}

Future<void> openFirst(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Open a video').first);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Pixel on the timeline for a time in a 100-second video (zoom 1).
Offset at(WidgetTester tester, double seconds, {double duration = 100, double y = 70}) {
  final rect = tester.getRect(find.byType(TrimTimeline));
  return Offset(rect.left + seconds / duration * rect.width, rect.top + y);
}

Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
  await tester.dragFrom(from, to - from);
  await tester.pump();
}

Future<void> finish(WidgetTester tester, Rig rig) async {
  await tester.pumpWidget(const SizedBox());
  rig.controller.dispose();
}

void main() {
  setUpAll(loadRoboto);

  testWidgets('the video starts opening at once, before the backend has answered, and is usable on the player\'s own length', (tester) async {
    final rig = await pumpTrimmer(tester);
    rig.api.probeGate = Completer<void>();
    await openFirst(tester);
    expect(rig.player.opened, [a]);                           // not waiting for the backend
    expect(find.byType(TrimTimeline), findsOneWidget);        // the player told us the length
    rig.session.addClip(10, 20);
    rig.api.probeGate!.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(rig.session.clips.length, 1);
    await finish(tester, rig);
  });

  testWidgets('while nobody knows the length yet it says so, blocks clips, and the timeline appears when it is known', (tester) async {
    final lengths = {a: 100.0};
    final api = FakeTrimmerApi(lengths: lengths)..probeGate = Completer<void>();
    final player = FakeTrimPlayer(lengths: lengths, reportsLength: false);
    final controller = TrimmerController(api: api, pollEvery: const Duration(milliseconds: 50));
    await pumpScreen(tester, TrimmerScreen(controller: controller, playerFactory: () => player, pickVideo: () async => a), size: const Size(1700, 1000));
    await openFirst(tester);

    expect(find.text('Reading the video…'), findsOneWidget);
    expect(find.text('Opening the video…'), findsOneWidget);
    expect(find.byType(TrimTimeline), findsNothing);
    expect(tester.widget<ButtonStyleButton>(find.widgetWithText(FilledButton, 'Add clip at the playhead')).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(controller.active!.clips, isEmpty);

    api.probeGate!.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TrimTimeline), findsOneWidget);
    expect(find.text('Reading the video…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('a player kept by the owner is not stopped or reopened when the page is left and entered again', (tester) async {
    final lengths = {a: 100.0};
    final api = FakeTrimmerApi(lengths: lengths);
    final player = FakeTrimPlayer(lengths: lengths);
    final controller = TrimmerController(api: api, pollEvery: const Duration(milliseconds: 50));
    Widget page() => TrimmerScreen(controller: controller, player: player, pickVideo: () async => a);

    await pumpScreen(tester, page(), size: const Size(1700, 1000));
    await openFirst(tester);
    player.moveTo(42);
    await tester.pumpWidget(const SizedBox());                // leave the page
    expect(player.disposed, isFalse);                         // the owner still has it
    expect(player.pauses, greaterThan(0));                    // and it does not play on behind another page

    await pumpScreen(tester, page(), size: const Size(1700, 1000));
    await tester.pump(const Duration(milliseconds: 100));
    expect(player.opened, [a]);                               // not opened a second time
    expect(find.byType(TrimTimeline), findsOneWidget);
    expect(controller.sessions.length, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('with no video it invites you to open one, and opening shows the timeline and the clip list', (tester) async {
    final rig = await pumpTrimmer(tester);
    expect(find.text('Open a video to trim it'), findsOneWidget);
    await openFirst(tester);
    expect(find.text('street.mp4'), findsWidgets);
    expect(find.byType(TrimTimeline), findsOneWidget);
    expect(find.text('No clips yet'), findsOneWidget);
    expect(rig.player.opened, [a]);
    await finish(tester, rig);
  });

  testWidgets('dragging on empty space marks a clip, in either direction', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);

    await drag(tester, at(tester, 10), at(tester, 30));
    expect(rig.session.clips.length, 1);
    expect(rig.session.clips.first.start, closeTo(10, 0.3));
    expect(rig.session.clips.first.end, closeTo(30, 0.3));

    await drag(tester, at(tester, 80), at(tester, 60));                // right to left
    expect(rig.session.clips.length, 2);
    expect(rig.session.clips.last.start, closeTo(60, 0.3));
    expect(rig.session.clips.last.end, closeTo(80, 0.3));
    expect(find.text('2 clips'), findsNothing);                         // the new one is selected
    expect(find.text('1 of 2 selected'), findsOneWidget);
    await finish(tester, rig);
  });

  testWidgets('dragging an edge trims, dragging the middle slides', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    final clip = rig.session.addClip(20, 40);
    await tester.pump();

    await drag(tester, at(tester, 40), at(tester, 55));                // right edge
    expect(clip.start, 20);
    expect(clip.end, closeTo(55, 0.3));
    await drag(tester, at(tester, 20), at(tester, 12));                // left edge
    expect(clip.start, closeTo(12, 0.3));
    expect(clip.end, closeTo(55, 0.3));
    final length = clip.length;
    await drag(tester, at(tester, 30), at(tester, 50));                // the middle, 20 s later
    expect(clip.length, closeTo(length, 0.001));
    expect(clip.start, closeTo(32, 0.5));
    expect(rig.session.clips.length, 1);                                // none of this made a new clip
    await finish(tester, rig);
  });

  testWidgets('an edge grabbed off its exact line moves with the pointer instead of jumping to it', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    final clip = rig.session.addClip(20, 40);
    await tester.pump();
    // grab 8 px (about 0.7 s on this strip) inside the right edge, then move 100 px
    final start = at(tester, 40) - const Offset(8, 0);
    await tester.dragFrom(start, const Offset(100, 0));
    await tester.pump();
    final secondsPer100px = 100 / tester.getRect(find.byType(TrimTimeline)).width * 100;
    expect(clip.end, closeTo(40 + secondsPer100px, 0.3));                // 40 plus the distance moved, not 40 plus 0.7 more
  });

  testWidgets('dragging along the ruler scrubs the video and never starts a clip', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    await tester.dragFrom(at(tester, 10, y: 8), Offset(tester.getRect(find.byType(TrimTimeline)).width * 0.3, 0));
    await tester.pump();
    expect(rig.session.clips, isEmpty);
    expect(rig.player.seeks.length, greaterThan(0));
    expect(rig.player.seeks.last, greaterThan(30));
  });

  testWidgets('a click on the ruler moves the playhead and does not unselect or select a clip', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    final clip = rig.session.addClip(20, 40);
    await tester.pump();
    await tester.tapAt(at(tester, 30, y: 8));                             // the ruler, right above the clip
    await tester.pump();
    expect(rig.player.seeks.last, closeTo(30, 0.5));
    expect(rig.session.selected, {clip.id});                              // the clip stays selected
  });

  testWidgets('an edge cannot be dragged past the other edge or off the video', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    final clip = rig.session.addClip(40, 60);
    await tester.pump();
    await drag(tester, at(tester, 40), at(tester, 80));
    expect(clip.start, closeTo(60 - TrimSession.minLength, 0.001));
    await drag(tester, at(tester, 60), at(tester, 100) + const Offset(300, 0));
    expect(clip.end, 100);
    await finish(tester, rig);
  });

  testWidgets('a locked clip ignores drags, and unlocking gives it back', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    final clip = rig.session.addClip(20, 40);
    await tester.pump();

    await tester.tap(find.byTooltip('Lock this clip so it cannot be moved by accident'));
    await tester.pump();
    expect(clip.locked, isTrue);
    await drag(tester, at(tester, 40), at(tester, 70));                // edge
    await drag(tester, at(tester, 30), at(tester, 50));                // middle
    expect((clip.start, clip.end), (20, 40));
    expect(rig.session.clips.length, 1);                                // and no new clip was started on top of it

    await tester.tap(find.byTooltip('Locked: click to unlock'));
    await tester.pump();
    await drag(tester, at(tester, 40), at(tester, 70));
    expect(clip.end, closeTo(70, 0.3));
    await finish(tester, rig);
  });

  testWidgets('several clips can be ticked, locked together, and exported together', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    final one = rig.session.addClip(5, 15);
    rig.session.addClip(25, 35);
    final three = rig.session.addClip(45, 55);
    await tester.pump();
    expect(rig.session.selected, {three.id});

    await tester.tap(find.byType(Checkbox).at(1));                       // clip 1 (the first one is "select all")
    await tester.pump();
    expect(rig.session.selected, {one.id, three.id});
    expect(find.text('Export selected (2)'), findsOneWidget);

    await tester.tap(find.byTooltip('Lock the selected clips'));
    await tester.pump();
    expect([for (final c in rig.session.clips) c.locked], [true, false, true]);

    await tester.tap(find.text('Export selected (2)'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(rig.api.starts.single.clips.map((c) => (c.start, c.end)), [(5.0, 15.0), (45.0, 55.0)]);
    expect(find.text('EXPORTS · 2 RUNNING'), findsOneWidget);
    await finish(tester, rig);
  });

  testWidgets('select all, then Export all, uses the chosen folder and the exact cut', (tester) async {
    final rig = await pumpTrimmer(tester);
    rig.folder = 'D:/evidence';
    await openFirst(tester);
    rig.session
      ..addClip(5, 15)
      ..addClip(25, 35);
    await tester.pump();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('2 of 2 selected'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Choose folder'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('D:/evidence'), findsOneWidget);

    await tester.tap(find.text('Export all (2)'));
    await tester.pump(const Duration(milliseconds: 100));
    final call = rig.api.starts.single;
    expect((call.clips.length, call.exact, call.outputDir), (2, true, 'D:/evidence'));
    await finish(tester, rig);
  });

  testWidgets('the exports list follows each job and offers Stop, Show in folder and Clear', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    rig.session
      ..addClip(5, 15)
      ..addClip(25, 35)
      ..addClip(45, 55);
    await tester.pump();
    await tester.tap(find.text('Export all (3)'));
    await tester.pump(const Duration(milliseconds: 100));

    final ids = rig.api.jobIds;                                          // newest first
    rig.api.setStatus(ids[0], 'running', progress: 0.42);
    rig.api.setStatus(ids[1], 'done');
    rig.api.setStatus(ids[2], 'failed', error: 'No space left on device');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Cutting 42%'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('No space left on device'), findsOneWidget);

    await tester.tap(find.byTooltip('Show in folder'));
    expect(rig.revealed.single, contains('street_clip_25-35.mp4'));

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(rig.api.cancelled, [ids[0]]);
    expect(find.text('Cancelled'), findsOneWidget);

    await tester.tap(find.text('Clear finished'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Done'), findsNothing);
    expect(find.text('Nothing exported yet.'), findsOneWidget);
    await finish(tester, rig);
  });

  testWidgets('while one video exports, the next can be opened and its clips are its own', (tester) async {
    final rig = await pumpTrimmer(tester, picks: [a, b]);
    await openFirst(tester);
    rig.session.addClip(5, 15);
    await tester.pump();
    await tester.tap(find.text('Export all (1)'));
    await tester.pump(const Duration(milliseconds: 100));
    rig.player.moveTo(33);

    await tester.tap(find.widgetWithText(FilledButton, 'Open another video'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(rig.player.opened, [a, b]);
    expect(rig.controller.active!.path, b);
    expect(find.text('No clips yet'), findsOneWidget);                   // the other video's clips are not shown here
    expect(find.textContaining('street.mp4 · 1 exporting'), findsOneWidget);
    expect(find.text('EXPORTS · 1 RUNNING'), findsOneWidget);            // and the first export is still on the list

    rig.session.addClip(100, 150);
    await tester.pump();
    await tester.tap(find.text('Export all (1)'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(rig.api.starts.map((s) => s.path), [a, b]);
    expect(find.text('EXPORTS · 2 RUNNING'), findsOneWidget);

    await tester.tap(find.textContaining('street.mp4'));                 // back to the first: where it was left, clips intact
    await tester.pump(const Duration(milliseconds: 100));
    expect(rig.player.opened, [a, b, a]);
    expect(rig.player.seeks, contains(33));
    expect(find.text('1 clips'), findsNothing);
    expect(rig.controller.active!.clips.length, 1);
    await finish(tester, rig);
  });

  testWidgets('closing a video leaves its exports running', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    rig.session.addClip(5, 15);
    await tester.pump();
    await tester.tap(find.text('Export all (1)'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Close this video (its exports keep going)'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Open a video to trim it'), findsOneWidget);
    expect(find.text('EXPORTS'), findsNothing);                          // the empty state has no list, but the jobs live on
    expect(rig.controller.activeJobCount, 1);
    await finish(tester, rig);
  });

  testWidgets('typing a time in a clip changes it, a bad one is put back, and a locked clip cannot be typed into', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    final clip = rig.session.addClip(10, 20);
    await tester.pump();

    final start = find.widgetWithText(TextField, '0:10.0');
    await tester.enterText(start, '0:05');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(clip.start, 5);

    await tester.enterText(find.widgetWithText(TextField, '0:05.0'), 'later');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(clip.start, 5);
    expect(find.widgetWithText(TextField, '0:05.0'), findsOneWidget);   // back to the real value

    await tester.enterText(find.widgetWithText(TextField, '0:20.0'), '9:00');   // past the end of a 100 s video
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(clip.end, 20);
    expect(find.textContaining('does not fit'), findsOneWidget);

    rig.session.setLocked(clip.id, true);
    await tester.pump();
    expect(tester.widget<TextField>(find.widgetWithText(TextField, '0:05.0')).enabled, isFalse);
    await finish(tester, rig);
  });

  testWidgets('the keyboard: Space plays, A adds a clip where the video is, I and O set its edges, L locks, Delete removes', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(rig.player.plays, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(rig.player.pauses, greaterThan(0));

    rig.player.moveTo(40);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    final clip = rig.session.clips.single;
    expect((clip.start, clip.end), (40, 50));

    rig.player.moveTo(42);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    rig.player.moveTo(47);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    expect((clip.start, clip.end), (42, 47));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(clip.locked, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(rig.session.clips.length, 1);                                 // locked: stays
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(rig.session.clips, isEmpty);
    await finish(tester, rig);
  });

  testWidgets('typing a space in a time box does not play the video', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    rig.session.addClip(10, 20);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextField, '0:10.0'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(rig.player.plays, 0);
    await finish(tester, rig);
  });

  testWidgets('a clip plays up to its end and then stops', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    final clip = rig.session.addClip(10, 20);
    await tester.pump();
    await tester.tap(find.byTooltip('Play this clip'));
    await tester.pump();
    expect((rig.player.seeks.last, rig.player.plays), (10, 1));
    final pauses = rig.player.pauses;
    rig.player.moveTo(clip.end - 1);
    expect(rig.player.pauses, pauses);
    rig.player.moveTo(clip.end + 0.1);
    expect(rig.player.pauses, pauses + 1);
    await finish(tester, rig);
  });

  testWidgets('a video neither the player nor the backend can read is closed with the reason', (tester) async {
    final rig = await pumpTrimmer(tester);
    rig.player.reportsLength = false;
    rig.api.probeError = TrimmerApiException('ffmpeg cannot read this file (no video found)');
    await openFirst(tester);
    expect(find.text('ffmpeg cannot read this file (no video found)'), findsOneWidget);
    expect(find.text('Open a video to trim it'), findsOneWidget);
    await finish(tester, rig);
  });

  testWidgets('locked clips are marked on the timeline and every clip has a number', (tester) async {
    final rig = await pumpTrimmer(tester);
    await openFirst(tester);
    final clip = rig.session.addClip(10, 40);
    rig.session.setLocked(clip.id, true);
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
    expect(clipColor(clip), isNotNull);
    expect(find.text('1'), findsWidgets);                                // the number badge in the list
    await finish(tester, rig);
  });
}
