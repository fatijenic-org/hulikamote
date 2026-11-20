import 'package:flutter/material.dart';

import '../../../../core/ui/page_parts.dart';
import '../../../../core/utils/visible_poller.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/appeals_api.dart';
import '../../domain/appeal_models.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _when(DateTime? d) =>
    d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// The Appeals page: what motorists wrote when they contested a ticket in the phone app, with the ticket's photos beside it.
/// Accept cancels the ticket (it stops counting as a demerit point); reject keeps it. The motorist is told either way.
class AppealsScreen extends StatefulWidget {
  const AppealsScreen({super.key, this.api});

  /// Injected by tests; the app uses the real backend.
  final AppealsApi? api;

  @override
  State<AppealsScreen> createState() => _AppealsScreenState();
}

class _AppealsScreenState extends State<AppealsScreen> {
  late final AppealsApi _api = widget.api ?? AppealsApi();
  late final VisiblePoller _poller = VisiblePoller(interval: const Duration(seconds: 8), onTick: _load);

  AppealList? _list;
  String? _error;
  String _filter = 'pending';           // pending | accepted | rejected | all
  String? _busyId;                      // the appeal being decided

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.attach(context);            // asks again every few seconds while this page is on screen, so a new appeal shows up by itself
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _load() async {
    try {
      final list = await _api.appeals();
      if (mounted) {
        setState(() {
          _list = list;
          _error = null;
        });
      }
    } on AppealsApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _decide(AppealItem item, bool accept, String note) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(accept ? 'Accept this appeal?' : 'Reject this appeal?'),
        content: Text(accept
            ? 'The ticket is cancelled and stops counting as a demerit point. ${item.motorist.isEmpty ? 'The motorist' : item.motorist} is told. This cannot be undone.'
            : 'The ticket stays on the record. ${item.motorist.isEmpty ? 'The motorist' : item.motorist} is told. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(accept ? 'Accept appeal' : 'Reject appeal')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busyId = item.id);
    try {
      await _api.decide(item.id, accept: accept, note: note);
      if (mounted) _toast(accept ? 'Appeal accepted. The ticket is cancelled and the motorist is told.' : 'Appeal rejected. The motorist is told.');
    } on AppealsApiException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
    await _load();
  }

  List<AppealItem> get _shown {
    final all = _list?.items ?? const <AppealItem>[];
    return _filter == 'all' ? all : [for (final a in all) if (a.status == _filter) a];
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      backgroundColor: Fx.page(context),
      body: Padding(
        padding: const EdgeInsets.all(Fx.s24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(
            title: 'Appeals',
            subtitle: 'A motorist contests a ticket in the phone app. Accept cancels the ticket (no demerit point). Reject keeps it. The motorist is told.',
            actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load)],
          ),
          if (list != null && list.cloudError.isNotEmpty) ...[
            FxBanner(
              message: 'Appeals filed through the cloud could not be read: ${list.cloudError}',
              color: Fx.warning,
              icon: Icons.cloud_off_outlined,
              action: TextButton(onPressed: _load, child: const Text('Try again')),
            ),
            const SizedBox(height: Fx.s12),
          ],
          if (list != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Fx.s16),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'pending', label: Text('Waiting (${list.pending})')),
                  ButtonSegment(value: 'accepted', label: Text('Accepted (${list.accepted})')),
                  ButtonSegment(value: 'rejected', label: Text('Rejected (${list.rejected})')),
                  ButtonSegment(value: 'all', label: Text('All (${list.items.length})')),
                ],
                selected: {_filter},
                onSelectionChanged: (v) => setState(() => _filter = v.first),
              ),
            ),
          Expanded(
            child: list == null
                ? (_error == null ? const SkeletonRows(count: 3, height: 160) : ErrorPanel(message: _error!, onRetry: _load))
                : _shown.isEmpty
                    ? EmptyState(
                        icon: Icons.gavel_outlined,
                        title: _filter == 'pending' ? 'No appeals waiting' : 'Nothing here',
                        message: _filter == 'pending' ? 'When a motorist appeals a ticket in the phone app, it shows up here by itself.' : null,
                      )
                    : ListView.separated(
                        itemCount: _shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: Fx.s12),
                        itemBuilder: (context, i) {
                          final item = _shown[i];
                          return _AppealCard(
                            key: ValueKey(item.id),
                            item: item,
                            api: _api,
                            busy: _busyId == item.id,
                            onDecide: (accept, note) => _decide(item, accept, note),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

class _AppealCard extends StatefulWidget {
  const _AppealCard({super.key, required this.item, required this.api, required this.busy, required this.onDecide});

  final AppealItem item;
  final AppealsApi api;
  final bool busy;
  final void Function(bool accept, String note) onDecide;

  @override
  State<_AppealCard> createState() => _AppealCardState();
}

class _AppealCardState extends State<_AppealCard> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _openPhoto(int index) {
    final frames = widget.item.ticket.frames;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 900,
          height: 620,
          child: Stack(children: [
            PageView.builder(
              controller: PageController(initialPage: index),
              itemCount: frames.length,
              itemBuilder: (_, i) => InteractiveViewer(child: FxImage(image: NetworkImage(widget.api.photoUrl(frames[i])), fit: BoxFit.contain)),
            ),
            Positioned(top: 4, right: 4, child: IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context))),
            if (frames.length > 1)
              Positioned(left: 12, bottom: 8, child: Text('Swipe or drag for the other ${frames.length - 1} photos', style: Fx.caption(context))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final t = item.ticket;
    final (statusColor, statusLabel) = switch (item.status) {
      'accepted' => (Fx.success, 'Accepted'),
      'rejected' => (Fx.danger, 'Rejected'),
      _ => (Fx.warning, 'Waiting for a decision'),
    };
    return FxCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (t.cls.isNotEmpty) ViolationChip(t.cls) else const StatusPill(label: 'Ticket no longer on this laptop', color: Fx.warning),
          if (t.plate.isNotEmpty) Text(t.plate, style: Fx.plate),
          Text('Case ${item.caseNo}', style: Fx.caption(context)),
          StatusPill(label: statusLabel, color: statusColor),
          StatusPill(label: item.source == 'cloud' ? 'Cloud' : 'Wi-Fi', color: Fx.accent, dense: true),
        ]),
        const SizedBox(height: Fx.s8),
        Text(
          [
            if (item.motorist.isNotEmpty) item.motorist,
            if (t.time != null) 'ticket ${_when(t.time)}',
            if (item.createdAt != null) 'appealed ${_when(item.createdAt)}',
          ].join(' · '),
          style: Fx.caption(context),
        ),
        const SizedBox(height: Fx.s12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (t.frames.isNotEmpty)
            Flexible(
              flex: 3,
              child: Wrap(spacing: Fx.s8, runSpacing: Fx.s8, children: [
                for (var i = 0; i < t.frames.length && i < 3; i++)
                  GestureDetector(
                    onTap: () => _openPhoto(i),
                    child: SizedBox(width: 160, height: 100, child: FxImage(image: NetworkImage(widget.api.photoUrl(t.frames[i])), radius: Fx.radiusSm)),
                  ),
                if (t.frames.length > 3)
                  GestureDetector(
                    onTap: () => _openPhoto(3),
                    child: Container(
                      width: 160,
                      height: 100,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Fx.raised(context), borderRadius: BorderRadius.circular(Fx.radiusSm)),
                      child: Text('+${t.frames.length - 3} more', style: Fx.heading(context)),
                    ),
                  ),
              ]),
            ),
          if (t.frames.isNotEmpty) const SizedBox(width: Fx.s16),
          Flexible(
            flex: 4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionLabel('The motorist says'),
              SelectableText(item.reason, style: Fx.body(context)),
            ]),
          ),
        ]),
        const SizedBox(height: Fx.s16),
        if (item.pending) ...[
          TextField(
            controller: _note,
            enabled: !widget.busy,
            maxLength: 500,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(isDense: true, hintText: 'Note to the motorist (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: Fx.s8),
          Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Fx.success, foregroundColor: Colors.black),
              onPressed: widget.busy ? null : () => widget.onDecide(true, _note.text.trim()),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Accept appeal'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Fx.danger),
              onPressed: widget.busy ? null : () => widget.onDecide(false, _note.text.trim()),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Reject appeal'),
            ),
            if (widget.busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ] else ...[
          SectionLabel(item.accepted ? 'Accepted ${_when(item.decidedAt)}: the ticket is cancelled' : 'Rejected ${_when(item.decidedAt)}: the ticket stays'),
          if (item.note.isNotEmpty) Text('Your note: ${item.note}', style: Fx.body(context)),
        ],
      ]),
    );
  }
}
