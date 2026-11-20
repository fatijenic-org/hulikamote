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
/// Every ticket is listed at once, in the order it came (first come, first served), with no limit. The plate is NOT read on its own: it is
/// read when a ticket is clicked (a tap opens the ticket in the live review, which reads it), and a ticket whose plate is read carries a
/// "plate read" badge.
class LiveTicketsPanel extends StatefulWidget {
  const LiveTicketsPanel({super.key, this.api, this.media = const ForensicMedia(), this.pollEvery = const Duration(seconds: 4), this.onAway});

  /// Told true when the enforcer goes to look at a ticket (the live view can hold still meanwhile), false when they are back.
  final ValueChanged<bool>? onAway;

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

  /// The tickets of the live run, in the order they came. No report yet = no tickets.
  Future<List<ForensicTicket>> _fetch() async {
    try {
      return await _api.report(_reportUrl);
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
            sort: QueueSort.arrival,
            plateBadge: true,
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
    widget.onAway?.call(true);
    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LiveTicketsScreen(focusUid: uid)));
    } finally {
      widget.onAway?.call(false);
    }
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
          tooltip: 'Open the live review: click a ticket to read its plate, set photos aside, merge, confirm',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.fact_check_outlined, size: 20),
          onPressed: () => _openReview(),
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
        message: _problem ?? 'A ticket is made when a vehicle that broke a rule leaves the picture. Click it to read its plate.',
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
