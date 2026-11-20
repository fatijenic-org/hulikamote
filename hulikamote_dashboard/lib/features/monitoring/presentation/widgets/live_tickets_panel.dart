import 'dart:async';

import 'package:flutter/material.dart';

import '../../../forensic/data/forensic_api.dart';
import '../../../forensic/data/forensic_media.dart';
import '../../../forensic/domain/forensic_models.dart';
import '../../../forensic/domain/review_controller.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../../forensic/presentation/widgets/queue_panel.dart';
import '../screens/live_tickets_screen.dart';

/// The Live Monitor's side list: the same ticket list as the live review (search, filters, sort, select, photo + plate + violation per
/// ticket), drawn by the Forensic Analyzer's own [QueuePanel].
///
/// A ticket is listed only when it is ready: the backend keeps a queue and reads the plates one ticket after the other (see
/// routers/forensic.py, "The live plate queue"), so nothing floods the list. While plates are still being read, a line says how many wait.
/// Every ticket stays in the list (no limit). A tap opens the ticket in the live review.
class LiveTicketsPanel extends StatefulWidget {
  const LiveTicketsPanel({super.key, this.api, this.media = const ForensicMedia(), this.pollEvery = const Duration(seconds: 4)});

  final ForensicApi? api;
  final ForensicMedia media;
  final Duration pollEvery;

  @override
  State<LiveTicketsPanel> createState() => _LiveTicketsPanelState();
}

class _LiveTicketsPanelState extends State<LiveTicketsPanel> {
  static const _reportUrl = '/snapshots/evidence/forensic/live/output/report.json';

  late final ForensicApi _api = widget.api ?? ForensicApi();
  ReviewController? _controller;
  Timer? _timer;
  int _waiting = 0; // tickets whose plate has not been read yet
  bool _loaded = false;
  bool _busy = false; // a refresh is running
  String? _problem;

  @override
  void initState() {
    super.initState();
    _refresh(first: true);
    _timer = Timer.periodic(widget.pollEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  static ReviewStatus _statusFromRows(ForensicTicket t, Map<String, ReviewStatus> saved) {
    final s = [for (final id in t.dbIds) if (saved[id] != null) saved[id]!];
    if (s.isEmpty) return ReviewStatus.pending;
    return s.contains(ReviewStatus.rejected) && !s.contains(ReviewStatus.confirmed) ? ReviewStatus.rejected : ReviewStatus.confirmed;
  }

  /// The tickets of the live run that are ready (their plate was read, or could not be). No report yet = no tickets.
  Future<List<ForensicTicket>> _fetch() async {
    try {
      final all = await _api.report(_reportUrl);
      return [for (final t in all) if (t.plateStatus != 'pending') t];
    } on ForensicApiException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  /// [first] / [rebuild]: build the list again from scratch (also the review decisions); otherwise only new or removed tickets are
  /// swapped in, so a ticket someone is looking at is not replaced.
  Future<void> _refresh({bool first = false, bool rebuild = false}) async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final tickets = await _fetch();
      var waiting = _waiting;
      try {
        waiting = await _api.liveQueueWaiting();
      } catch (_) {
        // an older backend has no queue: nothing waits then (its tickets are ready as they come)
      }
      if (!mounted) return;
      final c = _controller;
      if (c == null || rebuild) {
        if (tickets.isNotEmpty) {
          final saved = await _api.savedStatuses({for (final t in tickets) ...t.dbIds});
          if (!mounted) return;
          final next = ReviewController(
            gateway: _api,
            taskId: 'live',
            tickets: tickets,
            statuses: {for (final t in tickets) t.uid: _statusFromRows(t, saved)},
          );
          final old = _controller;
          _controller = next;
          old?.dispose();
        }
      } else if (!c.busy) {
        final known = {for (final t in c.all) t.uid};
        if (tickets.length != known.length || tickets.any((t) => !known.contains(t.uid))) {
          if (tickets.isEmpty) {
            _controller = null;
            c.dispose();
          } else {
            c.replaceTickets(tickets);
          }
        }
      }
      setState(() {
        _waiting = waiting;
        _loaded = true;
        _problem = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          if (first) _problem = '$e'.replaceFirst('Exception: ', '');
        });
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _openReview({String? uid}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LiveTicketsScreen(focusUid: uid)));
    if (mounted) _refresh(rebuild: true); // decisions made there show here
  }

  Future<void> _decideBatch(ReviewStatus s) async {
    final c = _controller;
    if (c == null) return;
    final n = c.checked.length;
    if (n == 0) return;
    final confirming = s == ReviewStatus.confirmed;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(confirming ? Icons.fact_check_outlined : Icons.report_off_outlined, color: confirming ? Fx.warning : Fx.danger),
        title: Text(confirming ? 'Confirm $n tickets?' : 'Mark $n tickets as false alarms?'),
        content: Text(confirming
            ? 'Each ticket is recorded as a confirmed violation. You can still change any of them later.'
            : 'They move out of the to-review list. You can still change any of them later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: confirming ? Fx.success : Fx.danger, foregroundColor: Colors.black87),
            child: Text(confirming ? 'Confirm $n' : 'Mark $n'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await c.decideChecked(s);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Material(
      color: Fx.panel(context),
      borderRadius: BorderRadius.circular(Fx.radius),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(context, c),
        if (_waiting > 0) _waitingLine(context),
        Divider(height: 1, color: Fx.border(context)),
        Expanded(child: _body(context, c)),
      ]),
    );
  }

  Widget _header(BuildContext context, ReviewController? c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Fx.s12, Fx.s8, Fx.s4, Fx.s8),
      child: Row(children: [
        Expanded(
          child: c == null
              ? Text('Live tickets', style: Fx.heading(context))
              : ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => Text('Live tickets (${c.total})', key: const ValueKey('live-tickets-title'), style: Fx.heading(context)),
                ),
        ),
        IconButton(
          key: const ValueKey('review-live-tickets'),
          tooltip: 'Open the live review: read plates again, set photos aside, merge, confirm',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.fact_check_outlined, size: 20),
          onPressed: () => _openReview(),
        ),
      ]),
    );
  }

  /// "Reading plates: 3 waiting": the backend works through them one by one; each ticket shows up here when it is done.
  Widget _waitingLine(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Fx.s12, 0, Fx.s12, Fx.s8),
      child: Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: Fx.s8),
        Expanded(
          child: Text(
            'Reading plates: $_waiting ticket${_waiting == 1 ? '' : 's'} waiting. Each one shows here when it is done.',
            key: const ValueKey('live-tickets-waiting'),
            style: Fx.caption(context),
          ),
        ),
      ]),
    );
  }

  Widget _body(BuildContext context, ReviewController? c) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (c == null || c.total == 0) {
      return EmptyState(
        icon: Icons.fact_check_outlined,
        title: _problem == null ? 'No tickets yet' : 'Could not load the tickets',
        message: _problem ??
            (_waiting > 0
                ? 'The plates are being read. The tickets show here when they are done.'
                : 'A ticket is made when a vehicle that broke a rule leaves the picture, and its plate has been read.'),
      );
    }
    return QueuePanel(
      key: const ValueKey('live-queue'),
      controller: c,
      media: widget.media,
      onBatchDecision: _decideBatch,
      onPicked: () => _openReview(uid: c.selectedUid),
    );
  }
}
