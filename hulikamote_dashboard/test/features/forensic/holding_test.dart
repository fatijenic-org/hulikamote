import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/holding_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/review_controller.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/evidence_viewer.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/holding_view.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/results_workspace.dart';

import 'support/test_support.dart';

List<HoldingBatch> _batches([int n = 1]) =>
    HoldingBatch.parseList([for (var i = 1; i <= n; i++) batchJson('b$i', from: 'uid1', fromTrack: 1, frames: 2 + i)]);

ReviewController _controller(FakeGateway g, {int n = 4}) =>
    ReviewController(gateway: g, taskId: 'task', tickets: sampleTickets(n));

/// A controller that has read [batches] from Holding (through the fake backend, as the app does).
Future<ReviewController> _held(FakeGateway g, List<HoldingBatch> batches, {int n = 4}) async {
  g.holdingNow = batches;
  final c = _controller(g, n: n);
  await c.loadHolding();
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUpAll(loadRoboto);

  group('HoldingBatch', () {
    test('reads the photos, the plate read from them and where they came from', () {
      final b = HoldingBatch.fromJson(batchJson('b1', from: 'uid7', fromTrack: 12, frames: 4, plate: 'KMO5222'));
      expect(b.id, 'b1');
      expect(b.fromUid, 'uid7');
      expect(b.fromTrack, 12);
      expect(b.frameCount, 4);
      expect(b.ticket.uid, 'b1'); // shaped like a ticket, so the same widgets can show it
      expect(b.ticket.plateText, 'KMO5222');
      expect(b.createdAt, isNotNull);
    });

    test('a result carries the tickets, what still waits, and the ticket that was made', () {
      final r = HoldingResult.fromJson({
        'tickets': [ticketJson(1), ticketJson(2)],
        'holding': [batchJson('b1')],
        'ticket_uid': 'abc',
      });
      expect(r.tickets, hasLength(2));
      expect(r.holding.single.id, 'b1');
      expect(r.ticketUid, 'abc');
    });
  });

  group('ReviewController and Holding', () {
    test('setting photos aside sends them, adopts the new lists and keeps the ticket open', () async {
      final g = FakeGateway();
      final c = _controller(g);
      addTearDown(c.dispose);
      final t = c.selected!;
      g.onSetAside = (uid, frames) => HoldingResult(tickets: sampleTickets(4), holding: _batches());

      expect(await c.setAside(t, [t.frames[1].file, t.frames[2].file]), isTrue);
      expect(g.asideCalls.single.uid, t.uid);
      expect(g.asideCalls.single.frames, [t.frames[1].file, t.frames[2].file]);
      expect(c.holdingCount, 1);
      expect(c.selectedUid, t.uid);
    });

    test('a new ticket made from Holding is the one that opens', () async {
      final g = FakeGateway();
      final c = await _held(g, _batches());
      final all = sampleTickets(4);
      g.onHoldingAction = (action, body) =>
          HoldingResult(tickets: [...all, ForensicTicket.fromJson({...ticketJson(9), 'ticket_uid': 'made1'})], holding: const [], ticketUid: 'made1');

      expect(await c.holdingAction('make-ticket', c.holding.first), isTrue);
      expect(g.holdingCalls.single.action, 'make-ticket');
      expect(g.holdingCalls.single.body, {'batch_id': 'b1'});
      expect(c.selectedUid, 'made1');
      expect(c.holdingCount, 0);
    });

    test('adding to a ticket names it, putting back opens the ticket the photos came from', () async {
      final g = FakeGateway();
      final c = await _held(g, _batches());
      final all = sampleTickets(4);
      g.onHoldingAction = (action, body) => HoldingResult(tickets: all, holding: const []);
      final target = c.all.firstWhere((t) => t.uid == 'uid3');

      await c.holdingAction('add-to-ticket', c.holding.first, into: target);
      expect(g.holdingCalls.single.body, {'batch_id': 'b1', 'keep_uid': 'uid3'});
      expect(c.selectedUid, 'uid3');

      g.holdingNow = _batches();
      await c.loadHolding();
      await c.holdingAction('put-back', c.holding.first);
      expect(g.holdingCalls.last.action, 'put-back');
      expect(c.selectedUid, 'uid1'); // where they came from
    });

    test('a failed Holding action says why and leaves everything as it was', () async {
      final g = FakeGateway();
      final c = await _held(g, _batches());
      g.failHolding = true;
      expect(await c.holdingAction('throw-away', c.holding.first), isFalse);
      expect(c.error, contains('That Holding action failed'));
      expect(c.holdingCount, 1);
    });

    test('Holding that cannot be read (an older backend) is quiet: the review still works', () async {
      final g = FakeGateway()..failHolding = true;
      final c = _controller(g);
      addTearDown(c.dispose);
      await c.loadHolding();
      expect(c.holdingCount, 0);
      expect(c.error, isNull);
    });
  });

  group('the Holding view', () {
    Future<void> open(WidgetTester tester, ReviewController c, {VoidCallback? onShow, List<String>? messages}) async {
      await pumpScreen(
        tester,
        HoldingView(controller: c, media: FakeMedia(), onShowTicket: onShow, onMessage: messages?.add),
        size: const Size(1400, 900),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('nothing set aside says how to set photos aside', (tester) async {
      await open(tester, _controller(FakeGateway()));
      expect(find.text('Nothing is set aside'), findsOneWidget);
      expect(find.textContaining('Set aside for later'), findsOneWidget);
    });

    testWidgets('a set of photos shows where it came from and offers the four choices', (tester) async {
      final c = await _held(FakeGateway(), _batches());
      await open(tester, c);
      expect(find.text('3 photos from vehicle #1'), findsOneWidget);
      expect(find.text('No plate read'), findsOneWidget);
      for (final k in ['new', 'add', 'back', 'drop']) {
        expect(find.byKey(Key('batch-$k-b1')), findsOneWidget);
      }
    });

    testWidgets('"Make a new ticket" does it, says so and goes back to the review', (tester) async {
      final g = FakeGateway();
      final c = await _held(g, _batches());
      g.onHoldingAction = (a, b) => HoldingResult(tickets: sampleTickets(4), holding: const [], ticketUid: 'uid2');
      var shown = 0;
      final messages = <String>[];
      await open(tester, c, onShow: () => shown++, messages: messages);

      await tester.tap(find.byKey(const Key('batch-new-b1')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.holdingCalls.single.action, 'make-ticket');
      expect(shown, 1);
      expect(messages.single, 'Made a new ticket from 3 photos.');
      expect(find.text('Nothing is set aside'), findsOneWidget);
    });

    testWidgets('"Add to a ticket" asks which one and sends exactly that ticket', (tester) async {
      final g = FakeGateway();
      final c = await _held(g, _batches());
      g.onHoldingAction = (a, b) => HoldingResult(tickets: sampleTickets(4), holding: const []);
      var shown = 0;
      await open(tester, c, onShow: () => shown++);

      await tester.tap(find.byKey(const Key('batch-add-b1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Add these photos to which ticket?'), findsOneWidget);
      await tester.tap(find.textContaining('#2 · '));
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.holdingCalls.single.action, 'add-to-ticket');
      expect(g.holdingCalls.single.body['keep_uid'], 'uid2');
      expect(shown, 1);
    });

    testWidgets('throwing away asks first; "Keep them" changes nothing', (tester) async {
      final g = FakeGateway();
      final c = await _held(g, _batches());
      g.onHoldingAction = (a, b) => HoldingResult(tickets: sampleTickets(4), holding: const []);
      await open(tester, c);

      await tester.tap(find.byKey(const Key('batch-drop-b1')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('throw-keep')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.holdingCalls, isEmpty);

      await tester.tap(find.byKey(const Key('batch-drop-b1')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('throw-confirm')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.holdingCalls.single.action, 'throw-away');
    });

    testWidgets('"Put back" is off when the ticket the photos came from no longer exists', (tester) async {
      final gone = HoldingBatch.parseList([batchJson('b9', from: 'ghost', fromTrack: 40)]);
      final c = await _held(FakeGateway(), gone);
      await open(tester, c);
      expect(tester.widget<TextButton>(find.byKey(const Key('batch-back-b9'))).onPressed, isNull);
    });
  });

  group('setting photos aside from a ticket', () {
    Future<void> openViewer(WidgetTester tester, ReviewController c, {List<String>? messages}) async {
      await pumpScreen(tester, EvidenceViewer(controller: c, media: FakeMedia(), onMessage: messages?.add), size: const Size(1900, 900));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Finder thumb(int k) => find.descendant(of: find.byType(ListView), matching: find.byType(InkWell)).at(k);

    Future<void> tapWith(WidgetTester tester, Finder at, {LogicalKeyboardKey? hold, int buttons = kPrimaryButton}) async {
      if (hold != null) await tester.sendKeyDownEvent(hold);
      await tester.tap(at, buttons: buttons);
      if (hold != null) await tester.sendKeyUpEvent(hold);
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('ticked photos can be set aside with one button', (tester) async {
      final g = FakeGateway();
      final c = _controller(g);
      addTearDown(c.dispose);
      final messages = <String>[];
      g.onSetAside = (uid, frames) => HoldingResult(tickets: sampleTickets(4), holding: _batches());
      await openViewer(tester, c, messages: messages);
      final t = c.selected!;

      await tapWith(tester, thumb(1));
      await tapWith(tester, thumb(3), hold: LogicalKeyboardKey.shiftLeft); // photos 2, 3, 4
      expect(find.text('3 photos ticked.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('set-aside')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(g.asideCalls.single.uid, t.uid);
      expect(g.asideCalls.single.frames, [t.frames[1].file, t.frames[2].file, t.frames[3].file]);
      expect(messages.single, 'Set 3 photos aside. They wait in Holding.');
      expect(find.textContaining('ticked'), findsNothing); // the selection is over
    });

    testWidgets('the right-click menu offers it too', (tester) async {
      final g = FakeGateway();
      final c = _controller(g);
      addTearDown(c.dispose);
      g.onSetAside = (uid, frames) => HoldingResult(tickets: sampleTickets(4), holding: _batches());
      await openViewer(tester, c);

      await tapWith(tester, thumb(2), buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Set 1 photo aside for later'), findsOneWidget);
      await tester.tap(find.text('Set 1 photo aside for later'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.asideCalls.single.frames, [c.selected!.frames[2].file]);
    });
  });

  group('Holding in the workspace', () {
    Widget workspace(ReviewController c) => ResultsWorkspace(
          controller: c,
          media: FakeMedia(),
          title: 'Analysis',
          videoUrl: '/v.mp4',
          videoBuilder: (context, url, seek, controller) => const Center(child: Text('VIDEO PANEL')),
          onBack: () {},
          onNewAnalysis: () {},
        );

    testWidgets('the header button shows how many sets wait and opens Holding; the same button comes back', (tester) async {
      final g = FakeGateway()..holdingNow = _batches(2);
      final c = _controller(g);
      addTearDown(c.dispose);
      await pumpScreen(tester, workspace(c), size: const Size(1680, 1000));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.holdingCount, 2); // read when the workspace opened
      expect(find.text('2'), findsWidgets); // the badge

      await tester.tap(find.byKey(const Key('open-holding')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('holding-list')), findsOneWidget);
      expect(find.text('Back to review'), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-holding')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('holding-list')), findsNothing);
      expect(find.textContaining('Photos'), findsWidgets); // the review is back
    });
  });
}
