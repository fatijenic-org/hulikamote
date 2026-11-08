import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/review_controller.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/evidence_viewer.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/fx.dart';

import 'support/test_support.dart';

ReviewController _controller(FakeGateway g) => ReviewController(gateway: g, taskId: 'task', tickets: sampleTickets(4));

/// The 12 photos of the open ticket sit in the strip at the bottom: this finds one of them.
Finder _thumb(int k) => find.descendant(of: find.byType(ListView), matching: find.byType(InkWell)).at(k);

Future<void> _open(WidgetTester tester, ReviewController c, {List<String>? messages}) async {
  await pumpScreen(tester, EvidenceViewer(controller: c, media: FakeMedia(), onMessage: messages?.add), size: const Size(1900, 900));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tapWith(WidgetTester tester, Finder at, {LogicalKeyboardKey? hold, int buttons = kPrimaryButton}) async {
  if (hold != null) await tester.sendKeyDownEvent(hold);
  await tester.tap(at, buttons: buttons);
  if (hold != null) await tester.sendKeyUpEvent(hold);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(loadRoboto);

  group('selecting photos in the strip', () {
    testWidgets('Ctrl+click adds and takes away photos; the photo on screen counts when the selection starts', (tester) async {
      final c = _controller(FakeGateway());
      await _open(tester, c);
      expect(find.textContaining('Ctrl+click or Shift+click'), findsOneWidget);          // the hint is there until something is selected
      final current = c.frameIndex;
      final other = current == 2 ? 3 : 2;

      await _tapWith(tester, _thumb(other), hold: LogicalKeyboardKey.controlLeft);
      expect(find.text('2 photos ticked.'), findsOneWidget);
      final third = [0, 1, 2, 3, 4].firstWhere((k) => k != current && k != other);
      await _tapWith(tester, _thumb(third), hold: LogicalKeyboardKey.controlLeft);
      expect(find.text('3 photos ticked.'), findsOneWidget);
      await _tapWith(tester, _thumb(third), hold: LogicalKeyboardKey.controlLeft);
      expect(find.text('2 photos ticked.'), findsOneWidget);                                // clicked again: taken away
    });

    testWidgets('Shift+click selects everything from the last clicked photo to this one', (tester) async {
      final c = _controller(FakeGateway());
      await _open(tester, c);
      await _tapWith(tester, _thumb(1));                                                     // look at photo 2 (no selection yet)
      expect(find.textContaining('ticked'), findsNothing);
      await _tapWith(tester, _thumb(5), hold: LogicalKeyboardKey.shiftLeft);
      expect(find.text('5 photos ticked.'), findsOneWidget);                                // photos 2, 3, 4, 5, 6

      await _tapWith(tester, _thumb(9), hold: LogicalKeyboardKey.shiftLeft);                // a new range from the anchor
      expect(find.textContaining('photos ticked'), findsOneWidget);
    });

    testWidgets('plain clicks only look at photos, until a selection is going', (tester) async {
      final c = _controller(FakeGateway());
      await _open(tester, c);
      await _tapWith(tester, _thumb(7));
      expect(c.frameIndex, 7);
      expect(find.textContaining('ticked'), findsNothing);
    });
  });

  group('the right-click menu', () {
    testWidgets('right-click on a photo that is not selected selects it and offers a new ticket right away', (tester) async {
      final g = FakeGateway()..onAction = (a, b) => sampleTickets(4);
      final c = _controller(g);
      final messages = <String>[];
      await _open(tester, c, messages: messages);
      final t = c.selected!;

      await _tapWith(tester, _thumb(3), buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('New ticket from 1 photo'), findsOneWidget);
      expect(find.text('Move 1 photo to another ticket…'), findsOneWidget);
      expect(find.text('Remove 1 photo from this ticket'), findsOneWidget);

      await tester.tap(find.text('New ticket from 1 photo'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.actionCalls.single.action, 'split');
      expect(g.actionCalls.single.body['ticket_uid'], t.uid);
      expect(g.actionCalls.single.body['frames'], [t.frames[3].file]);
      expect(messages, ['Moved 1 photo into a new ticket.']);
    });

    testWidgets('right-click on a selected photo acts on the whole selection', (tester) async {
      final g = FakeGateway()..onAction = (a, b) => sampleTickets(4);
      final c = _controller(g);
      await _open(tester, c);
      final t = c.selected!;
      await _tapWith(tester, _thumb(1));
      await _tapWith(tester, _thumb(3), hold: LogicalKeyboardKey.shiftLeft);                // photos 2, 3, 4
      expect(find.text('3 photos ticked.'), findsOneWidget);

      await _tapWith(tester, _thumb(2), buttons: kSecondaryButton);                          // right-click inside the selection
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('New ticket from 3 photos'), findsOneWidget);
      await tester.tap(find.text('New ticket from 3 photos'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.actionCalls.single.body['frames'], [t.frames[1].file, t.frames[2].file, t.frames[3].file]);
    });

    testWidgets('"Move to another ticket" asks which one and then moves exactly those photos there', (tester) async {
      final g = FakeGateway()..onAction = (a, b) => sampleTickets(4);
      final c = _controller(g);
      final messages = <String>[];
      await _open(tester, c, messages: messages);
      final t = c.selected!;
      final target = c.all.firstWhere((x) => x.uid != t.uid);
      await _tapWith(tester, _thumb(1));
      await _tapWith(tester, _thumb(2), hold: LogicalKeyboardKey.shiftLeft);

      await _tapWith(tester, _thumb(2), buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Move 2 photos to another ticket…'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Move 2 photos to which ticket?'), findsOneWidget);
      expect(find.text('This ticket keeps the other photos.'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.byType(FxCard)).first);
      await tester.pump(const Duration(milliseconds: 400));

      expect(g.actionCalls.single.action, 'move-frames');
      expect(g.actionCalls.single.body, containsPair('keep_uid', target.uid));
      expect(g.actionCalls.single.body, containsPair('from_uid', t.uid));
      expect(g.actionCalls.single.body['frames'], [t.frames[1].file, t.frames[2].file]);
      expect(messages.single, 'Moved 2 photos into ticket #${target.trackId}.');
      expect(find.textContaining('ticked'), findsNothing);                                  // the selection is cleared
    });

    testWidgets('with every photo selected, a new ticket is not offered and moving them is a merge', (tester) async {
      final g = FakeGateway()..onAction = (a, b) => sampleTickets(4);
      final c = _controller(g);
      await _open(tester, c);
      final t = c.selected!;
      final target = c.all.firstWhere((x) => x.uid != t.uid);
      await _tapWith(tester, _thumb(0));
      await _tapWith(tester, _thumb(t.frameCount - 1), hold: LogicalKeyboardKey.shiftLeft);
      expect(find.textContaining('Every photo is ticked'), findsOneWidget);

      await _tapWith(tester, _thumb(2), buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<PopupMenuItem<String>>(find.widgetWithText(PopupMenuItem<String>, 'New ticket from ${t.frameCount} photos')).enabled, isFalse);
      await tester.tap(find.text('Move ${t.frameCount} photos to another ticket…'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Merge this ticket into which ticket?'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.byType(FxCard)).first);
      await tester.pump(const Duration(milliseconds: 400));

      expect(g.actionCalls.single.action, 'merge');
      expect(g.actionCalls.single.body, {'task_id': 'task', 'keep_uid': target.uid, 'merge_uid': t.uid});
    });

    testWidgets('Clear selection puts everything back', (tester) async {
      final c = _controller(FakeGateway());
      await _open(tester, c);
      await _tapWith(tester, _thumb(3), buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Clear selection'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('ticked'), findsNothing);
    });

    testWidgets('a ticket with a single photo has nothing to move, so no menu opens', (tester) async {
      final c = ReviewController(gateway: FakeGateway(), taskId: 'task', tickets: [ForensicTicket.fromJson(ticketJson(1, frames: 1))]);
      await _open(tester, c);
      await _tapWith(tester, _thumb(0), buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Clear selection'), findsNothing);
    });
  });

  group('the controller\'s quick actions', () {
    test('separating asks for a new ticket and stays on this one', () async {
      final g = FakeGateway()..onAction = (a, b) => sampleTickets(4);
      final c = _controller(g);
      final t = c.selected!;
      expect(await c.separateFrames(t, [t.frames[0].file]), isTrue);
      expect(g.actionCalls.single.action, 'split');
      expect(c.selectedUid, t.uid);
    });

    test('moving some photos moves only those and stays on the ticket that keeps the rest', () async {
      final g = FakeGateway()..onAction = (a, b) => sampleTickets(4);
      final c = _controller(g);
      final t = c.selected!;
      final to = c.all.firstWhere((x) => x.uid != t.uid);
      await c.moveFramesTo(t, to, [t.frames[0].file, t.frames[1].file]);
      expect(g.actionCalls.single.action, 'move-frames');
      expect(c.selectedUid, t.uid);
    });

    test('moving all the photos merges the ticket into the other one and opens that one', () async {
      late ForensicTicket from;
      final g = FakeGateway()..onAction = (a, b) => sampleTickets(4).where((x) => x.uid != from.uid).toList();
      final c = _controller(g);
      from = c.selected!;
      final to = c.all.firstWhere((x) => x.uid != from.uid);
      await c.moveFramesTo(from, to, [for (final f in from.frames) f.file]);
      expect(g.actionCalls.single.action, 'merge');
      expect(c.selectedUid, to.uid);
    });
  });
}

