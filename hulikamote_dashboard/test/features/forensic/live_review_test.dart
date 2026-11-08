import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/review_controller.dart';

import 'support/test_support.dart';

/// The status of a run with [n] tickets released so far (ticket i is `ticketJson(i)`).
RunStatus _status(String status, int n, {double progress = 40, String? video, String message = ''}) => RunStatus(
      status: status,
      progress: progress,
      resultVideo: video,
      message: message,
      tickets: ForensicTicket.parseList([for (var i = 1; i <= n; i++) ticketJson(i, frames: 6)]),
      ticketCount: n,
    );

/// Lets the (instant) fake backend answer and the controller act on it.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('a running analysis in the models', () {
    test('a status says how many tickets there are, with or without the list itself', () {
      expect(RunStatus.fromJson({'status': 'processing', 'progress': 10, 'ticket_count': 4}).ticketCount, 4);
      expect(RunStatus.fromJson({'status': 'completed', 'progress': 100, 'tickets': [ticketJson(1)]}).ticketCount, 1);
      expect(RunStatus.fromJson({'status': 'processing', 'progress': 1}).ticketCount, 0);
    });

    test('a merged ("3 & 7") or split ("5 (split)") ticket still parses: its first number stands for it', () {
      expect(ForensicTicket.fromJson({...ticketJson(1), 'track_id': '3 & 7'}).trackId, 3);
      expect(ForensicTicket.fromJson({...ticketJson(1), 'track_id': '5 (split)'}).trackId, 5);
      expect(ForensicTicket.fromJson({...ticketJson(1), 'track_id': 12}).trackId, 12);
      expect(ForensicTicket.fromJson({...ticketJson(1), 'track_id': null}).trackId, -1);
    });

    test('a library entry knows its analysis is still running', () {
      final running = RunSummary.fromJson({'task_id': 'x', 'created_at': 1, 'report_url': '/r', 'running': true});
      expect(running.running, isTrue);
      expect(RunSummary.fromJson({'task_id': 'x', 'created_at': 1, 'report_url': '/r'}).running, isFalse);
    });
  });

  group('the review follows an analysis that is still running', () {
    ReviewController open(FakeGateway g, {int n = 2}) {
      final c = ReviewController(gateway: g, taskId: 'T', tickets: _status('processing', n).tickets);
      addTearDown(c.dispose);
      return c;
    }

    test('new tickets appear while the reviewer keeps the open ticket, the photo and the decisions', () async {
      final g = FakeGateway();
      final c = open(g);
      c.select('uid2');
      c.setFrame(3);
      await c.decide('uid1', ReviewStatus.confirmed);

      g.onFollow = (_) => _status('processing', 4, progress: 55, message: 'Watching the video');
      c.followRun(every: const Duration(days: 1));
      await _settle();

      expect(c.analyzing, isTrue);
      expect(c.total, 4);
      expect(c.selectedUid, 'uid2'); // the reviewer's place
      expect(c.frameIndex, 3);
      expect(c.statusOf(c.all.firstWhere((t) => t.uid == 'uid1')), ReviewStatus.confirmed);
      expect(c.runProgress, 55);
      expect(c.runMessage, 'Watching the video');
    });

    test('a ticket that was merged into another disappears and the open one moves on', () async {
      final g = FakeGateway();
      final c = open(g, n: 3);
      c.select('uid3');
      await c.decide('uid3', ReviewStatus.rejected);

      g.onFollow = (_) => _status('processing', 2);
      c.followRun(every: const Duration(days: 1));
      await _settle();

      expect(c.total, 2);
      expect(c.selected, isNotNull);
      expect(c.selectedUid, isNot('uid3'));
      expect(c.all.any((t) => t.uid == 'uid3'), isFalse);
    });

    test('when the analysis ends, following stops and the evidence video is known', () async {
      final g = FakeGateway();
      final c = open(g);
      g.onFollow = (_) => _status('completed', 3, progress: 100, video: '/snapshots/evidence/forensic/T/output/evidence_replay.mp4');
      c.followRun(every: const Duration(days: 1));
      await _settle();

      expect(c.analyzing, isFalse);
      expect(c.total, 3);
      expect(c.resultVideo, endsWith('evidence_replay.mp4'));
      final looks = g.follows;
      await c.refreshLive(); // nothing left to follow
      expect(g.follows, looks);
    });

    test('a run cancelled while it is open empties the list and says so', () async {
      final g = FakeGateway();
      final c = open(g);
      g.onFollow = (_) => const RunStatus(status: 'cancelled', progress: 31);
      c.followRun(every: const Duration(days: 1));
      await _settle();

      expect(c.runGone, isTrue);
      expect(c.analyzing, isFalse);
      expect(c.total, 0);
      expect(c.selected, isNull);
    });

    test('a failed look keeps what is on screen; ten in a row stop following', () async {
      final g = FakeGateway()..followError = Exception('backend down');
      final c = open(g);
      c.followRun(every: const Duration(days: 1)); // look 1
      await _settle();
      expect(c.analyzing, isTrue);
      expect(c.total, 2);
      for (var i = 0; i < 9; i++) {
        await c.refreshLive();
      }
      expect(c.analyzing, isFalse);
      expect(c.total, 2); // what was released stays
    });

    test('a look that comes back while an edit is in flight does not overwrite the edit', () async {
      final g = FakeGateway();
      final c = open(g);
      g.onAction = (action, body) => _status('processing', 5).tickets; // the edit's own, newer list
      g.onFollow = (_) => _status('processing', 3); // an older picture of the run
      c.followRun(every: const Duration(days: 1));
      await _settle();
      expect(c.total, 3);

      final edit = c.ticketAction('merge', {'keep_uid': 'uid1', 'merge_uid': 'uid2'});
      final look = c.refreshLive(); // starts while the edit is busy
      await Future.wait([edit, look]);
      expect(c.total, 5);
    });
  });
}
