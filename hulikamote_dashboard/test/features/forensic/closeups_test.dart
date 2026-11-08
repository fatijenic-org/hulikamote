import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/review_controller.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/evidence_viewer.dart';

import 'support/test_support.dart';

/// A ticket whose every photo carries a helmet close-up (what the helmet model looked at).
Map<String, dynamic> _withCloseups({int frames = 4}) {
  final j = ticketJson(1, frames: frames, violations: ['no_helmet']);
  for (final m in (j['evidence_meta'] as List)) {
    (m as Map)['details'] = [
      {'file': 'detail_helmet_1.jpg', 'kind': 'helmet', 'label': 'NO HELMET', 'violation': 'no_helmet', 'confidence': 0.82},
    ];
  }
  return j;
}

Future<void> _open(WidgetTester tester, Map<String, dynamic> ticket) async {
  final c = ReviewController(gateway: FakeGateway(), taskId: 'task', tickets: [ForensicTicket.fromJson(ticket)]);
  await pumpScreen(tester, EvidenceViewer(controller: c, media: FakeMedia()), size: const Size(1900, 900));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(loadRoboto);

  test('a photo reads its close-ups from the report, and older reports simply have none', () {
    final frame = ForensicTicket.fromJson(_withCloseups()).frames.first;
    expect(frame.details, hasLength(1));
    final d = frame.details.single;
    expect(d.file, 'detail_helmet_1.jpg');
    expect(d.kind, 'helmet');
    expect(d.title, 'Helmet check');
    expect(d.label, 'NO HELMET');
    expect(d.violation, 'no_helmet');
    expect(d.confidence, closeTo(0.82, 1e-9));
    expect(ForensicTicket.fromJson(ticketJson(2)).frames.first.details, isEmpty);
  });

  test('every kind of close-up has a plain name, and an unknown one still gets one', () {
    String title(String kind) => FrameDetail.fromJson({'file': 'x.jpg', 'kind': kind, 'label': ''}).title;
    expect(title('seatbelt'), 'Seatbelt check');
    expect(title('phone'), 'Phone check');
    expect(title('mirror'), 'Side-mirror check');
    expect(title('something_new'), 'Close-up');
  });

  test('a malformed close-up entry is skipped instead of breaking the ticket', () {
    final j = ticketJson(3, frames: 2);
    (j['evidence_meta'] as List).first['details'] = ['not a map', {'kind': 'helmet'}, {'file': 'ok.jpg', 'kind': 'helmet', 'label': 'NO HELMET'}];
    final frame = ForensicTicket.fromJson(j).frames.first;
    expect(frame.details.map((d) => d.file), ['ok.jpg']);
  });

  testWidgets('the viewer shows the close-ups of the open photo and enlarges one when it is clicked', (tester) async {
    await _open(tester, _withCloseups());
    expect(find.text('Helmet check'), findsOneWidget);
    await tester.tap(find.text('Helmet check'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Helmet check: NO HELMET'), findsOneWidget);          // the enlarged picture says what the model concluded
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Helmet check: NO HELMET'), findsNothing);
  });

  testWidgets('a ticket with no close-ups shows none', (tester) async {
    await _open(tester, ticketJson(4, frames: 3));
    expect(find.text('Helmet check'), findsNothing);
  });
}
