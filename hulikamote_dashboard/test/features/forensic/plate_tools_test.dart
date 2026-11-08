import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/plate_tools_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/review_controller.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/evidence_viewer.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/plate_draw_dialog.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/plate_tools.dart';

import 'support/test_support.dart';

ReviewController _controller(FakeGateway g, {int n = 4}) => ReviewController(gateway: g, taskId: 'task', tickets: sampleTickets(n));

RereadResult _reread({int found = 2, int checked = 3, String suggested = 'ABC1234', bool keptManual = false, int noPicture = 0, int noPlate = 0}) =>
    RereadResult(tickets: sampleTickets(4), checked: checked, found: found, suggested: suggested, keptManual: keptManual, noPicture: noPicture, noPlate: noPlate);

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 200, 100), Paint()..color = Colors.grey);
  final image = await recorder.endRecording().toImage(200, 100);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  setUpAll(loadRoboto);

  group('what the tools answer', () {
    test('"Read again" says what it found in plain words', () {
      expect(_reread(found: 2, suggested: 'ABC1234').message, 'Read again: ABC1234.');
      expect(_reread(found: 2, suggested: 'ABC1234', keptManual: true).message, 'The system now reads ABC1234. The plate you typed was kept.');
      expect(_reread(found: 0, checked: 3, noPlate: 3).message, 'No plate found in the 3 photos. Try “Draw plate”.');
      expect(_reread(found: 0, checked: 1, noPicture: 1).message, contains('no clean picture'));
      expect(_reread(found: 1, suggested: '').message, 'A plate was found in 1 photo but could not be read. Try “Draw plate”.');
    });

    test('the answer is read from the backend\'s JSON', () {
      final r = RereadResult.fromJson({
        'tickets': [ticketJson(1)],
        'reread': {'checked': 4, 'found': 3, 'no_picture': 1, 'no_plate': 0, 'suggested': 'unidentified', 'kept_manual': true},
      });
      expect((r.tickets.length, r.checked, r.found, r.noPicture, r.suggested, r.keptManual), (1, 4, 3, 1, '', true));   // "unidentified" means nothing read
    });

    test('a box the system could not read has an empty text, not the word "unidentified"', () {
      expect(PlateBoxRead.fromJson({'text': 'unidentified', 'crop': 'c.jpg'}).text, '');
      expect(PlateBoxRead.fromJson({'text': 'AB1234', 'raw': 'ab 1234', 'confidence': 0.9, 'crop': 'c.jpg'}).text, 'AB1234');
    });
  });

  group('drawing a box', () {
    const area = (w: 200.0, h: 100.0);

    test('the box is kept as fractions of the picture, whichever corner the drag started from', () {
      expect(boxFromDrag((x: 50.0, y: 50.0), (x: 150.0, y: 90.0), area), [0.25, 0.5, 0.75, 0.9]);
      expect(boxFromDrag((x: 150.0, y: 90.0), (x: 50.0, y: 50.0), area), [0.25, 0.5, 0.75, 0.9]);
    });

    test('a drag that leaves the picture stops at its edge', () {
      expect(boxFromDrag((x: 100.0, y: 50.0), (x: 500.0, y: -40.0), area), [0.5, 0.0, 1.0, 0.5]);
    });

    test('a slip of the finger is not a box', () {
      expect(boxFromDrag((x: 10.0, y: 10.0), (x: 14.0, y: 60.0), area), isNull);
      expect(boxFromDrag((x: 10.0, y: 10.0), (x: 10.0, y: 10.0), area), isNull);
      expect(boxFromDrag((x: 10.0, y: 10.0), (x: 20.0, y: 20.0), (w: 0.0, h: 0.0)), isNull);
    });
  });

  group('the review controller', () {
    test('Read again looks at every photo of a small ticket', () {
      final c = ReviewController(gateway: FakeGateway(), taskId: 't', tickets: [ForensicTicket.fromJson(ticketJson(1, frames: 5))]);
      expect(c.rereadSample(c.selected!), [for (var f = 0; f < 5; f++) 'ev_1_$f.jpg']);
    });

    test('and at an even spread of a big one, always including the best view, in order and without repeats', () {
      final c = ReviewController(gateway: FakeGateway(), taskId: 't', tickets: [ForensicTicket.fromJson(ticketJson(1, frames: 100))]);
      final t = c.selected!;
      final sample = c.rereadSample(t);
      expect(sample.length, ReviewController.rereadPhotos);
      expect(sample.toSet().length, sample.length);
      expect(sample, contains(t.frames[t.heroIndex].file));
      expect(sample.first, 'ev_1_0.jpg');
      expect(sample, [for (final f in t.frames) if (sample.contains(f.file)) f.file]);        // still in photo order
    });

    test('Read again sends those photos, swaps in the new tickets and returns what it found', () async {
      final g = FakeGateway()..onReread = (uid, frames) => _reread();
      final c = _controller(g);
      final ticket = c.selected!;
      final result = await c.rereadPlate(ticket);
      expect(result!.found, 2);
      expect(g.rereadCalls.single.uid, ticket.uid);
      expect(g.rereadCalls.single.frames, c.rereadSample(ticket));
      expect(c.busy, isFalse);
    });

    test('when the backend fails, the controller says so and nothing else changes', () async {
      final g = FakeGateway()..failReread = true;
      final c = _controller(g);
      final before = c.all.length;
      expect(await c.rereadPlate(c.selected!), isNull);
      expect(c.error, contains('Could not read the plate again'));
      expect(c.all.length, before);
    });

    test('removing photos asks the backend to take exactly those out of this ticket', () async {
      final g = FakeGateway()..onAction = (a, b) => sampleTickets(4);
      final c = _controller(g);
      final t = c.selected!;
      expect(await c.removeFrames(t, ['ev_x_1.jpg', 'ev_x_2.jpg']), isTrue);
      expect(g.actionCalls.single.action, 'remove-frames');
      expect(g.actionCalls.single.body['ticket_uid'], t.uid);
      expect(g.actionCalls.single.body['frames'], ['ev_x_1.jpg', 'ev_x_2.jpg']);
    });

    test('the right number of a drawn plate goes to the training data with its picture', () async {
      final g = FakeGateway();
      final c = _controller(g);
      expect(await c.sendPlateFeedbackImage(c.selected!, 'drawn.jpg', ' ab1234 '), isTrue);
      expect(g.feedbackCalls.single, (image: 'drawn.jpg', label: 'ab1234'));
    });
  });

  group('the buttons under the plate box', () {
    testWidgets('Read again runs it and tells the reviewer what happened', (tester) async {
      final g = FakeGateway()..onReread = (uid, frames) => _reread(suggested: 'KMO5221');
      final c = _controller(g);
      await pumpScreen(tester, Scaffold(body: Center(child: SizedBox(width: 360, child: PlateTools(controller: c, media: FakeMedia(), ticket: c.selected!)))));
      await tester.tap(find.text('Read again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.rereadCalls.length, 1);
      expect(find.text('Read again: KMO5221.'), findsOneWidget);
    });

    testWidgets('both buttons wait while another change is being saved', (tester) async {
      final c = _controller(FakeGateway());
      final ticket = c.selected!;
      await pumpScreen(tester, Scaffold(body: Center(child: SizedBox(width: 360, child: PlateTools(controller: c, media: FakeMedia(), ticket: ticket)))));
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Draw plate')).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Read again')).onPressed, isNotNull);
    });
  });

  group('the Draw plate window', () {
    testWidgets('drag a box, see what the system read, fix the number, and send it', (tester) async {
      final g = FakeGateway()
        ..onReadBox = ((image, box) => const PlateBoxRead(text: 'ABC1234', raw: 'abc 1234', confidence: 0.9, crop: 'drawn.jpg'))
        ..onSetPlate = (uid, plate, revert) => withEditedPlate(sampleTickets(4), uid, plate);
      final c = _controller(g);
      final bytes = (await tester.runAsync(_png))!;
      late BuildContext context;
      await pumpScreen(tester, Builder(builder: (ctx) {
        context = ctx;
        return const SizedBox();
      }), size: const Size(1400, 900));

      showPlateDrawDialog(context, controller: c, media: FakeMedia(), ticket: c.selected!, imageFor: (_) => MemoryImage(bytes));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));      // the picture decodes
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Draw the plate'), findsOneWidget);
      expect(find.text('No box yet. Press and drag on the photo.'), findsOneWidget);

      final photo = tester.getRect(find.byType(Image).first);
      await tester.dragFrom(photo.topLeft + Offset(photo.width * 0.3, photo.height * 0.4), Offset(photo.width * 0.4, photo.height * 0.2));
      await tester.pump(const Duration(milliseconds: 100));

      expect(g.boxCalls.length, 1);
      final box = g.boxCalls.single.box;
      expect(box[0], inInclusiveRange(0.3, 0.45));                       // the box is where the finger went, as fractions
      expect(box[2], inInclusiveRange(0.65, 0.75));
      expect(find.widgetWithText(TextField, 'ABC1234'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'abc 1235');           // the reviewer corrects the last digit
      await tester.pump();
      await tester.tap(find.text('Use this plate'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(g.plateCalls.single.plate, 'ABC1235');
      expect(g.feedbackCalls.single, (image: 'drawn.jpg', label: 'ABC1235'));
      await tester.pump(const Duration(milliseconds: 500));               // the window closes
      expect(find.text('Draw the plate'), findsNothing);
      expect(find.text('Plate sent: ABC1235'), findsOneWidget);
    });

    testWidgets('a box the system cannot read still lets the reviewer type the number', (tester) async {
      final g = FakeGateway()..onReadBox = (image, box) => const PlateBoxRead(text: '', crop: 'drawn.jpg');
      final c = _controller(g);
      final bytes = (await tester.runAsync(_png))!;
      late BuildContext context;
      await pumpScreen(tester, Builder(builder: (ctx) {
        context = ctx;
        return const SizedBox();
      }), size: const Size(1400, 900));
      showPlateDrawDialog(context, controller: c, media: FakeMedia(), ticket: c.selected!, imageFor: (_) => MemoryImage(bytes));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 100));

      final photo = tester.getRect(find.byType(Image).first);
      await tester.dragFrom(photo.topLeft + Offset(photo.width * 0.3, photo.height * 0.4), Offset(photo.width * 0.4, photo.height * 0.2));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('The system could not read this box. Type the number you see.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this plate')).onPressed, isNull);   // nothing typed yet
      await tester.enterText(find.byType(TextField), 'ZZZ999');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this plate')).onPressed, isNotNull);
    });
  });

  group('removing photos from a ticket', () {
    testWidgets('tick photos, remove them, confirm: the backend is asked to take exactly those out', (tester) async {
      final g = FakeGateway()..onAction = (a, b) => sampleTickets(4);
      final c = _controller(g);
      await pumpScreen(tester, EvidenceViewer(controller: c, media: FakeMedia()), size: const Size(1500, 900));
      await tester.pump(const Duration(milliseconds: 100));
      final t = c.selected!;

      await tester.tap(find.byTooltip('Select photos (separate a different car, or remove from this ticket)'));
      await tester.pump();
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Remove from this ticket')).onPressed, isNull);   // nothing ticked

      await tester.tap(find.byIcon(Icons.check_box_outline_blank).at(0));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.check_box_outline_blank).at(0));
      await tester.pump();
      expect(find.text('2 photos ticked.'), findsOneWidget);

      await tester.tap(find.text('Remove from this ticket'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Remove 2 photos from this ticket?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(g.actionCalls.single.action, 'remove-frames');
      expect(g.actionCalls.single.body['ticket_uid'], t.uid);
      expect((g.actionCalls.single.body['frames'] as List).length, 2);
    });

    testWidgets('Cancel leaves the ticket as it was', (tester) async {
      final g = FakeGateway();
      final c = _controller(g);
      await pumpScreen(tester, EvidenceViewer(controller: c, media: FakeMedia()), size: const Size(1500, 900));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Select photos (separate a different car, or remove from this ticket)'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.check_box_outline_blank).at(0));
      await tester.pump();
      await tester.tap(find.text('Remove from this ticket'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.actionCalls, isEmpty);
    });
  });
}
