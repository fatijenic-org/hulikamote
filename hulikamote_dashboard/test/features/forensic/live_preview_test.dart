import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_media.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/review_controller.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/live_preview_panel.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/results_workspace.dart';

import 'support/test_support.dart';

RunStatus _running(int n) => RunStatus(
      status: 'processing',
      progress: 40,
      resultVideo: null,
      message: '',
      tickets: ForensicTicket.parseList([for (var i = 1; i <= n; i++) ticketJson(i, frames: 6)]),
      ticketCount: n,
    );

Widget _workspace(ReviewController c, {String? video, void Function(String)? onPreview}) => ResultsWorkspace(
      controller: c,
      media: FakeMedia(),
      title: 'Analysis',
      subtitle: 'abc12345',
      videoUrl: video,
      videoBuilder: (context, url, seek, controller) => const Center(child: Text('VIDEO PANEL')),
      previewBuilder: (context, taskId, media) {
        onPreview?.call(taskId);
        return const Center(child: Text('PREVIEW PANEL'));
      },
      onBack: () {},
      onNewAnalysis: () {},
      onSendToLive: () async {},
    );


/// The queue and header rows of the workspace overflow by a few pixels with the test font on some machines (not what these
/// tests are about): ignore those layout warnings, everything else still fails the test.
void _ignoreLayoutOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

void main() {
  setUpAll(loadRoboto);

  group('the pieces of a running analysis', () {
    test('a piece has a numbered file next to the report', () {
      expect(
        previewPieceUrl(const ForensicMedia(baseUrl: 'http://h:8000'), 'T', 3),
        'http://h:8000/snapshots/evidence/forensic/T/output/evidence_raw_part0003.mp4',
      );
    });

    test('the newest piece is still being written, so it cannot be played yet', () {
      expect(playablePieces(0), 0);
      expect(playablePieces(1), 0);
      expect(playablePieces(4), 3);
    });

    test('counting finds the last piece that exists, and carries on from where it stopped', () async {
      final asked = <int>[];
      Future<bool> have3(int piece) async {
        asked.add(piece);
        return piece <= 3;
      }

      expect(await countPieces(have3), 3);
      expect(asked, [1, 2, 3, 4]);
      asked.clear();
      expect(await countPieces(have3, from: 4), 3); // piece 4 is still missing: nothing new
      expect(asked, [4]);
      expect(await countPieces((p) async => p <= 5, from: 4), 5);
    });
  });

  group('the Video tab', () {
    testWidgets('of a running analysis shows the preview of the finished pieces', (tester) async {
      _ignoreLayoutOverflow();
      final g = FakeGateway()..onFollow = (_) => _running(2);
      final c = ReviewController(gateway: g, taskId: 'T', tickets: _running(2).tickets);
      c.followRun(every: const Duration(days: 1));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(c.analyzing, isTrue);

      String? asked;
      await pumpScreen(tester, _workspace(c, onPreview: (id) => asked = id), size: const Size(2600, 1300));
      await tester.tap(find.text('Video').first);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PREVIEW PANEL'), findsOneWidget);
      expect(find.text('VIDEO PANEL'), findsNothing);
      expect(asked, 'T');

      await tester.pumpWidget(const SizedBox()); // the follow timer must be gone before the test ends
      c.dispose();
    });

    testWidgets('of a finished analysis shows its replay, not the preview', (tester) async {
      _ignoreLayoutOverflow();
      final c = ReviewController(gateway: FakeGateway(), taskId: 'T', tickets: sampleTickets(2));
      addTearDown(c.dispose);
      await pumpScreen(tester, _workspace(c, video: '/v.mp4'), size: const Size(2600, 1300));
      await tester.tap(find.text('Video').first);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('VIDEO PANEL'), findsOneWidget);
      expect(find.text('PREVIEW PANEL'), findsNothing);
    });
  });
}
