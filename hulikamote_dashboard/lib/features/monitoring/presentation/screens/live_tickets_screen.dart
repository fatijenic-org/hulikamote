import 'dart:async';

import 'package:flutter/material.dart';

import '../../../forensic/data/forensic_api.dart';
import '../../../forensic/data/forensic_media.dart';
import '../../../forensic/domain/forensic_models.dart';
import '../../../forensic/domain/review_controller.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../../forensic/presentation/widgets/results_workspace.dart';

/// "Live tickets": the vehicles the Live Monitor finished, reviewed with the Forensic Analyzer's own review (queue | photos | decision).
///
/// The live feed keeps no plate. Here the reviewer
///  - opens a ticket (a potential violation) and ticks photos with Shift or Ctrl,
///  - sets the ticked photos aside (they wait in Holding) or moves them into another ticket (merge),
///  - presses "Read the plate": the plate is found in the photos that are in the ticket and read twice, as seen and enhanced (GAN);
///    every crop shows both readings, the candidates are graded, the best one is in a text field to keep, change or replace,
///  - or marks the vehicle as having no plate (the "no plate" violation can only be set on a ticket without a plate number),
///  - then confirms: only the evidence photos (cut from a blurred copy of the picture) go to the phone app.
///
/// The tickets are the standing run "live" of the forensic review (see routers/forensic.py publish_live_ticket), so every ticket tool of
/// the analyzer works on them. New tickets appear while this page is open.
class LiveTicketsScreen extends StatefulWidget {
  const LiveTicketsScreen({super.key, this.api, this.media = const ForensicMedia(), this.focusDbId});

  final ForensicApi? api;
  final ForensicMedia media;

  /// The Inbox row of a ticket to open at once (the alert the reviewer tapped).
  final String? focusDbId;

  @override
  State<LiveTicketsScreen> createState() => _LiveTicketsScreenState();
}

class _LiveTicketsScreenState extends State<LiveTicketsScreen> {
  static const _reportUrl = '/snapshots/evidence/forensic/live/output/report.json';
  static const _task = 'live';

  late final ForensicApi _api = widget.api ?? ForensicApi();
  ReviewController? _controller;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// The tickets of the live run; none yet (no report on disk) is an empty list, not an error.
  Future<List<ForensicTicket>> _fetch() async {
    try {
      return await _api.report(_reportUrl);
    } on ForensicApiException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  static ReviewStatus _statusFromRows(ForensicTicket t, Map<String, ReviewStatus> saved) {
    final s = [for (final id in t.dbIds) if (saved[id] != null) saved[id]!];
    if (s.isEmpty) return ReviewStatus.pending;
    return s.contains(ReviewStatus.rejected) && !s.contains(ReviewStatus.confirmed) ? ReviewStatus.rejected : ReviewStatus.confirmed;
  }

  Future<void> _load() async {
    try {
      final tickets = await _fetch();
      if (tickets.isNotEmpty) await _show(tickets);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _show(List<ForensicTicket> tickets) async {
    final saved = await _api.savedStatuses({for (final t in tickets) ...t.dbIds});
    if (!mounted) return;
    final controller = ReviewController(
      gateway: _api,
      taskId: _task,
      tickets: tickets,
      statuses: {for (final t in tickets) t.uid: _statusFromRows(t, saved)},
    );
    final focus = widget.focusDbId;
    if (focus != null) {
      for (final t in tickets) {
        if (t.dbIds.contains(focus)) controller.select(t.uid);
      }
    }
    _controller?.dispose();
    _controller = controller;
  }

  /// New tickets appear while the page is open; a ticket the reviewer is working on is never replaced under their hands.
  Future<void> _refresh() async {
    if (!mounted || _loading) return;
    final c = _controller;
    if (c != null && c.busy) return;
    try {
      final tickets = await _fetch();
      if (tickets.isEmpty || !mounted) return;
      if (c == null) {
        await _show(tickets);
        if (mounted) setState(() {});
        return;
      }
      final known = {for (final t in c.all) t.uid};
      if (tickets.length != known.length || tickets.any((t) => !known.contains(t.uid))) c.replaceTickets(tickets);
    } catch (_) {
      // the next refresh tries again
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Fx.page(context),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : c == null
            ? _empty(context)
            : ResultsWorkspace(
                key: const ValueKey('live-tickets'),
                controller: c,
                media: widget.media,
                title: 'Live tickets',
                subtitle: 'The plate is read here, from the photos of each ticket',
                onBack: () => Navigator.of(context).pop(),
                onNewAnalysis: () => Navigator.of(context).pop(),
              ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Column(children: [
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(Fx.s8),
            child: IconButton(tooltip: 'Back to the Live Monitor', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
          ),
        ),
        Expanded(
          child: EmptyState(
            icon: Icons.fact_check_outlined,
            title: _error == null ? 'No live tickets yet' : 'Could not open the live tickets',
            message: _error ?? 'A ticket is made when a vehicle that broke a rule leaves the picture. It will appear here.',
          ),
        ),
      ]);
}
