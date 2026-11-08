import 'package:flutter/material.dart';

import '../../../../core/services/api_service.dart';
import '../../../../core/ui/page_parts.dart';
import '../../../forensic/domain/forensic_models.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/models/violation.dart';

/// Every ticket the system found, with the decision a reviewer made. Confirmed tickets are shown first because
/// those are the ones that count.
class ViolationsScreen extends StatefulWidget {
  const ViolationsScreen({super.key, this.api});

  /// Injected by tests; the app uses the real backend.
  final ApiService? api;

  @override
  State<ViolationsScreen> createState() => _ViolationsScreenState();
}

/// The filter choices and the backend status each one asks for (null: all).
enum _Show {
  confirmed('Confirmed', 'approved'),
  toReview('To review', 'pending'),
  falseAlarm('False alarm', 'rejected'),
  all('All', null);

  const _Show(this.label, this.status);
  final String label;
  final String? status;
}

class _ViolationsScreenState extends State<ViolationsScreen> with AutomaticKeepAliveClientMixin {
  late final ApiService _api = widget.api ?? ApiService();
  static const int _pageSize = 20;

  int _page = 1;
  _Show _show = _Show.confirmed;
  ViolationPage? _data;
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true; // Keep state alive across tab switches

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.fetchViolations(page: _page, size: _pageSize, status: _show.status);
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _error = 'The backend did not answer. Start it with tools\\run_demo_backend.bat, then try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _choose(_Show show) {
    if (show == _show) return;
    _show = show;
    _page = 1;
    _data = null;
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final data = _data;
    return Scaffold(
      backgroundColor: Fx.page(context),
      body: Padding(
        padding: const EdgeInsets.all(Fx.s24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(
            title: 'Violation records',
            subtitle: 'Every ticket the system found, and what a reviewer decided about it.',
            actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _loading ? null : _fetch)],
          ),
          Row(children: [
            SegmentedButton<_Show>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(selectedBackgroundColor: Fx.accent.withValues(alpha: 0.22), selectedForegroundColor: Fx.accent),
              segments: [for (final s in _Show.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {_show},
              onSelectionChanged: (v) => _choose(v.first),
            ),
            const Spacer(),
            if (data != null) Text('${data.total} ${data.total == 1 ? 'ticket' : 'tickets'}', style: Fx.caption(context)),
          ]),
          const SizedBox(height: Fx.s16),
          Expanded(child: _body(data)),
          if (data != null && data.total > _pageSize) _pager(data),
        ]),
      ),
    );
  }

  Widget _body(ViolationPage? data) {
    if (_error != null && data == null) return ErrorPanel(message: _error!, onRetry: _fetch);
    if (data == null) return const SkeletonRows(count: 6, height: 56);
    if (data.items.isEmpty) {
      return switch (_show) {
        _Show.confirmed => const EmptyState(
            icon: Icons.verified_outlined,
            title: 'No confirmed tickets yet',
            message: 'A ticket shows here once a reviewer confirms it in the Inbox or the Forensic Analyzer.'),
        _Show.toReview => const EmptyState(icon: Icons.done_all, title: 'Nothing is waiting', message: 'Every ticket has a decision.'),
        _Show.falseAlarm => const EmptyState(icon: Icons.thumb_up_alt_outlined, title: 'No false alarms', message: 'No ticket was rejected.'),
        _Show.all => const EmptyState(icon: Icons.inbox_outlined, title: 'No tickets yet', message: 'Analyse a video to create some.'),
      };
    }
    return Column(children: [
      if (_error != null) ...[
        FxBanner(message: _error!, action: TextButton(onPressed: _fetch, child: const Text('Try again'))),
        const SizedBox(height: Fx.s8),
      ],
      const _HeaderRow(),
      const SizedBox(height: Fx.s4),
      Expanded(
        child: Opacity(
          opacity: _loading ? 0.5 : 1,
          child: ListView.separated(
            itemCount: data.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: Fx.s8),
            itemBuilder: (_, i) => _Row(data.items[i]),
          ),
        ),
      ),
    ]);
  }

  Widget _pager(ViolationPage data) {
    final pages = (data.total / _pageSize).ceil();
    return Padding(
      padding: const EdgeInsets.only(top: Fx.s12),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous page',
          onPressed: _page > 1 && !_loading ? () { _page--; _fetch(); } : null,
        ),
        Text('Page $_page of $pages', style: Fx.body(context)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next page',
          onPressed: _page < pages && !_loading ? () { _page++; _fetch(); } : null,
        ),
      ]),
    );
  }
}

const _flex = [3, 3, 2, 2, 2];

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const labels = ['Violation', 'Plate', 'Decision', 'Confidence', 'When'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s16),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++) Expanded(flex: _flex[i], child: Text(labels[i].toUpperCase(), style: Fx.label(context))),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.v);

  final Violation v;

  @override
  Widget build(BuildContext context) {
    final status = ReviewStatus.fromBackend(v.status);
    final at = DateTime.tryParse(v.timestamp)?.toLocal();
    final read = v.userName != null && v.userName!.isNotEmpty && v.userName != 'UNIDENTIFIED';
    return FxCard(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s16, vertical: Fx.s12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(flex: _flex[0], child: Align(alignment: Alignment.centerLeft, child: ViolationChip(v.cls))),
        Expanded(
          flex: _flex[1],
          child: Text(read ? v.userName! : 'Plate not read',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: read ? Fx.plate.copyWith(fontSize: 15) : Fx.caption(context)),
        ),
        Expanded(
          flex: _flex[2],
          child: Align(alignment: Alignment.centerLeft, child: StatusPill(label: Fx.statusLabel(status), color: Fx.statusColor(status), icon: Fx.statusIcon(status), dense: true)),
        ),
        Expanded(flex: _flex[3], child: Text(v.confidenceLabel, style: Fx.body(context))),
        Expanded(
          flex: _flex[4],
          child: Tooltip(message: at?.toString().split('.').first ?? v.timestamp, child: Text(ago(at), style: Fx.caption(context))),
        ),
      ]),
    );
  }
}
