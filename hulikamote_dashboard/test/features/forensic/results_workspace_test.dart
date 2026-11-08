import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/review_controller.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/evidence_viewer.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/queue_panel.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/results_workspace.dart';

import 'support/test_support.dart';

Widget _workspace(ReviewController c, {String? video = '/v.mp4', FakeLabeling? harvest}) => ResultsWorkspace(
      controller: c,
      media: FakeMedia(),
      title: 'Analysis · Oct 6',
      subtitle: 'abc12345',
      videoUrl: video,
      videoBuilder: (context, url, seek, controller) => const Center(child: Text('VIDEO PANEL')),
      onBack: () {},
      onNewAnalysis: () {},
      onSendToLive: () async {},
      harvest: harvest,
    );

ReviewController _controller(FakeGateway g, {int n = 8}) =>
    ReviewController(gateway: g, taskId: 'task', tickets: sampleTickets(n));

/// The right column starts as the list of tickets: picking one swaps it for that ticket's details.
Future<void> _openDetails(WidgetTester tester, String uid) async {
  await tester.tap(find.byKey(ValueKey(uid)));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(loadRoboto);

  group('layout', () {
    // The real content area is the window minus the 240 px sidebar.
    for (final (name, size) in const [
      ('full HD', Size(1680, 1000)),
      ('laptop 1366', Size(1125, 650)),
      ('small window', Size(900, 600)),
      ('narrow', Size(700, 700)),
    ]) {
      testWidgets('renders without overflow: $name', (tester) async {
        await pumpScreen(tester, _workspace(_controller(FakeGateway())), size: size);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Photos'), findsWidgets); // a ticket is open
      });
    }

    testWidgets('empty analysis shows an empty state, not a crash', (tester) async {
      final c = ReviewController(gateway: FakeGateway(), taskId: 't', tickets: const []);
      await pumpScreen(tester, _workspace(c));
      expect(tester.takeException(), isNull);
      expect(find.text('No tickets in this analysis'), findsOneWidget);
    });
  });

  group('two columns: the video and photos, and one right column that is the list OR the open ticket', () {
    Future<ReviewController> open(WidgetTester tester, {Size size = const Size(1680, 1000), int n = 8}) async {
      final c = _controller(FakeGateway(), n: n);
      await pumpScreen(tester, _workspace(c), size: size);
      await tester.pump(const Duration(milliseconds: 200));
      return c;
    }

    testWidgets('it starts on the list; the photos begin at the left edge and the verdict stays under them', (tester) async {
      final c = await open(tester);
      expect(find.byKey(ValueKey(c.all.first.uid)), findsOneWidget); // the list of tickets is on screen
      expect(find.text('PLATE NUMBER'), findsNothing); // the details are not
      expect(tester.getTopLeft(find.byType(EvidenceViewer)).dx, lessThan(60)); // no list column on the left any more
      expect(find.byKey(const Key('open-details')), findsOneWidget); // verdict strip under the evidence
      expect(find.byKey(const Key('back-to-list')), findsNothing);
    });

    testWidgets('picking a ticket swaps the list for its details; Back to the list brings the list back', (tester) async {
      final c = await open(tester);
      final uid = c.all[3].uid;
      await _openDetails(tester, uid);
      expect(c.selectedUid, uid);
      expect(find.text('PLATE NUMBER'), findsOneWidget);
      expect(find.text('All tickets (8)'), findsOneWidget);
      expect(find.byType(QueuePanel), findsNothing); // the list is out of sight (kept alive behind)
      expect(find.byKey(const Key('open-details')), findsNothing); // the verdict is in the details now

      await tester.tap(find.byKey(const Key('back-to-list')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(QueuePanel), findsOneWidget);
      expect(find.text('PLATE NUMBER'), findsNothing);
      expect(c.selectedUid, uid); // the same ticket is still the open one
    });

    testWidgets('the Details button under the photos opens the details too', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('PLATE NUMBER'), findsOneWidget);
    });

    testWidgets('previous and next move through the tickets without going back to the list', (tester) async {
      final c = await open(tester);
      await _openDetails(tester, c.selectedUid!);
      final first = c.selectedUid;
      expect(find.text('1 of 8'), findsOneWidget);
      await tester.tap(find.byKey(const Key('next-ticket')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.selectedUid, isNot(first));
      expect(find.text('2 of 8'), findsOneWidget);
      expect(find.byKey(const Key('back-to-list')), findsOneWidget); // still in the details
      await tester.tap(find.byKey(const Key('previous-ticket')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.selectedUid, first);
    });

    testWidgets('Esc goes back to the list', (tester) async {
      final c = await open(tester);
      await _openDetails(tester, c.selectedUid!);
      expect(find.byKey(const Key('back-to-list')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('back-to-list')), findsNothing);
      expect(find.byType(QueuePanel), findsOneWidget);
    });

    testWidgets('the list keeps its search while a ticket is open', (tester) async {
      final c = await open(tester);
      final search = find.descendant(of: find.byType(QueuePanel), matching: find.byType(TextField)).first;
      await tester.enterText(search, 'KMO');
      await tester.pump(const Duration(milliseconds: 100));
      final shown = c.visible;
      expect(shown, isNotEmpty);
      await _openDetails(tester, shown.first.uid);
      await tester.tap(find.byKey(const Key('back-to-list')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<TextField>(search).controller!.text, 'KMO');
      expect(c.query, 'KMO');
    });

    testWidgets('a medium window has the same two columns', (tester) async {
      final c = await open(tester, size: const Size(1125, 650));
      expect(tester.getTopLeft(find.byType(EvidenceViewer)).dx, lessThan(60));
      await _openDetails(tester, c.all.first.uid);
      expect(find.text('PLATE NUMBER'), findsOneWidget);
      expect(find.byKey(const Key('back-to-list')), findsOneWidget);
    });

    testWidgets('a narrow window keeps its drawers: no right column, no back bar', (tester) async {
      await open(tester, size: const Size(700, 700));
      expect(find.byKey(const Key('back-to-list')), findsNothing);
      expect(find.byType(QueuePanel), findsNothing); // the list is in the left drawer
      expect(find.byTooltip('Open the ticket queue'), findsOneWidget);
      expect(find.byTooltip('Ticket details'), findsOneWidget);
    });
  });

  group('the Harvest tab of one analysis', () {
    testWidgets('only an analysis that is given a harvest helper has the tab', (tester) async {
      await pumpScreen(tester, _workspace(_controller(FakeGateway())));
      expect(find.byKey(const Key('review-harvest-toggle')), findsNothing);
    });

    testWidgets('Harvest swaps the review for the categories of THIS analysis, and Review brings it back', (tester) async {
      final labeling = FakeLabeling();
      final c = _controller(FakeGateway());
      await pumpScreen(tester, _workspace(c, harvest: labeling), size: const Size(1680, 1000));
      expect(labeling.sessions, 0); // nothing is asked until the tab is opened
      final before = c.selectedUid;

      await tester.tap(find.descendant(of: find.byKey(const Key('review-harvest-toggle')), matching: find.text('Harvest')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(labeling.asked.single, 'task'); // this analysis' id, not every analysis
      expect(find.byKey(const Key('category-plate_specialist')), findsOneWidget);
      expect(find.byType(QueuePanel), findsNothing); // the review (list, photos, verdict) is out of the way
      expect(find.text('False alarm'), findsNothing);

      // the review shortcuts must not fire while looking at the categories
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.selectedUid, before);

      await tester.tap(find.descendant(of: find.byKey(const Key('review-harvest-toggle')), matching: find.text('Review')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(QueuePanel), findsOneWidget); // the review is back: the list of tickets and the photos
      expect(find.byKey(const Key('category-plate_specialist')), findsNothing);
    });
  });

  group('keyboard', () {
    testWidgets('arrow keys move through tickets and photos', (tester) async {
      final c = _controller(FakeGateway());
      await pumpScreen(tester, _workspace(c));
      final first = c.selectedUid;
      final photo = c.frameIndex;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(c.frameIndex, photo + 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.selectedUid, isNot(first));
    });

    testWidgets('C confirms and X marks a false alarm for the open ticket', (tester) async {
      final gateway = FakeGateway();
      final c = _controller(gateway);
      await pumpScreen(tester, _workspace(c));
      final uid = c.selectedUid!;

      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump(const Duration(milliseconds: 50));
      expect(gateway.statusCalls.single.status, ReviewStatus.confirmed);
      expect(gateway.statusCalls.single.ids, hasLength(2)); // both violation rows of the ticket
      expect(c.statusOf(c.all.firstWhere((t) => t.uid == uid)), ReviewStatus.confirmed);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.pump(const Duration(milliseconds: 50));
      expect(gateway.statusCalls.last.status, ReviewStatus.rejected);
    });

    testWidgets('typing in the plate field never triggers shortcuts', (tester) async {
      final gateway = FakeGateway();
      final c = _controller(gateway);
      await pumpScreen(tester, _workspace(c));
      await _openDetails(tester, c.selectedUid!); // the plate field is in the ticket's details

      await tester.tap(find.byType(TextField).last); // the plate field
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'CX1');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.pump(const Duration(milliseconds: 50));

      expect(gateway.statusCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('plate edit', () {
    Future<(ReviewController, FakeGateway)> open(WidgetTester tester) async {
      final g = FakeGateway();
      final c = _controller(g);
      g.onSetPlate = (uid, plate, revert) => withEditedPlate(c.all, uid, plate, revert: revert);
      c.select('uid2'); // a ticket with plate crops
      await pumpScreen(tester, _workspace(c), size: const Size(1680, 1000));
      await tester.pump(const Duration(milliseconds: 100));
      await _openDetails(tester, 'uid2'); // the plate and the decision are in the ticket's details
      return (c, g);
    }

    testWidgets('typing a different plate offers Send plate; sending puts it on the ticket and into the training data', (tester) async {
      final (c, g) = await open(tester);
      expect(find.text('Send plate'), findsNothing);

      await tester.enterText(find.byType(TextField).last, 'abc 123');
      await tester.pump();
      expect(find.text('Send plate'), findsOneWidget);

      await tester.tap(find.text('Send plate'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.plateCalls.single.plate, 'ABC123');
      expect(c.selected!.plateText, 'ABC123');
      expect(g.feedbackCalls.single.label, 'ABC123'); // the picture of the plate goes along with the right number
      expect(find.text('You fixed this plate.'), findsOneWidget);
      expect(find.text('Send plate'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the panel an enforcer sees has the plate and the decision, and nothing technical', (tester) async {
      await open(tester);
      expect(find.text('PLATE NUMBER'), findsOneWidget);
      expect(find.text('False alarm'), findsWidgets);
      expect(find.text('Confirm'), findsWidgets);
      for (final jargon in ['TEACH THE OCR', 'Teach the OCR', 'HOW IT WAS ANALYSED', 'Tracker', 'OCR engine', 'Merge with another ticket…']) {
        expect(find.text(jargon), findsNothing, reason: jargon);
      }
      // the rare things are folded away until asked for
      expect(find.text('Same car as another ticket…'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('more-options')));
      await tester.tap(find.byKey(const Key('more-options')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Same car as another ticket…'), findsOneWidget);
    });

    testWidgets('Enter saves, and the shortcuts work again afterwards', (tester) async {
      final (c, g) = await open(tester);
      final before = c.selectedUid;
      await tester.enterText(find.byType(TextField).last, 'xyz 987');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.plateCalls.single.plate, 'XYZ987');

      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump(const Duration(milliseconds: 50));
      expect(g.statusCalls, hasLength(1)); // C reached the workspace, not the text field
      expect(g.statusCalls.single.status, ReviewStatus.confirmed);
      expect(c.selectedUid, isNot(before)); // confirmed, so it moved on
    });

    testWidgets('an edited plate can go back to what the system read', (tester) async {
      final (c, g) = await open(tester);
      await tester.enterText(find.byType(TextField).last, 'abc 123');
      await tester.pump();
      await tester.tap(find.text('Send plate'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Undo'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.plateCalls.last.revert, isTrue);
      expect(c.selected!.plateManual, isFalse);
      expect(find.text('You fixed this plate.'), findsNothing);
    });

    testWidgets('a failed save keeps what was typed and says why', (tester) async {
      final (c, g) = await open(tester);
      g.failPlate = true;
      await tester.enterText(find.byType(TextField).last, 'abc 123');
      await tester.pump();
      await tester.tap(find.text('Send plate'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Could not save the plate'), findsOneWidget);
      expect(find.text('Send plate'), findsOneWidget); // still pending, can retry
      expect(c.selected!.plateManual, isFalse);
    });

    testWidgets('clearing a read plate offers to mark the vehicle as having none', (tester) async {
      final (c, g) = await open(tester);
      expect(c.selected!.plateRead, isTrue);
      await tester.enterText(find.byType(TextField).last, '');
      await tester.pump();
      expect(find.text('No plate on this vehicle'), findsOneWidget);
      await tester.tap(find.text('No plate on this vehicle'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.plateCalls.single.plate, '');
      expect(c.selected!.plateRead, isFalse);
    });
  });

  group('review flow', () {
    testWidgets('confirming moves on to the next ticket still waiting', (tester) async {
      final c = _controller(FakeGateway());
      await pumpScreen(tester, _workspace(c));
      final before = c.selectedUid;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.selectedUid, isNot(before));
      expect(c.statusOf(c.selected!), ReviewStatus.pending);
    });

    testWidgets('batch confirm asks first before recording many tickets', (tester) async {
      final gateway = FakeGateway();
      final c = _controller(gateway);
      await pumpScreen(tester, _workspace(c), size: const Size(1680, 1000));
      c.toggleChecked(c.all[0].uid);
      c.toggleChecked(c.all[1].uid);
      await tester.pump();

      // the batch bar in the queue; the open ticket has its own Confirm in the decision panel
      await tester.tap(find.descendant(of: find.byType(QueuePanel), matching: find.widgetWithText(FilledButton, 'Confirm')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Confirm 2 tickets?'), findsOneWidget);
      expect(find.textContaining('confirmed violation'), findsOneWidget);
      expect(gateway.statusCalls, isEmpty); // nothing sent before the reviewer agrees

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm 2'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(gateway.statusCalls, hasLength(2));
    });
  });
}
