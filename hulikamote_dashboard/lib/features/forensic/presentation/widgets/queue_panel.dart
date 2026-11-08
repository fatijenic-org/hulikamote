import 'package:flutter/material.dart';

import '../../data/forensic_media.dart';
import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import '../../domain/violation_catalog.dart';
import 'fx.dart';

const double kTileHeight = 88;

/// One row of the review queue: photo, plate, what it did, where in the video, and its status.
class TicketTile extends StatelessWidget {
  const TicketTile({
    super.key,
    required this.ticket,
    required this.status,
    required this.selected,
    required this.media,
    required this.onTap,
    this.selecting = false,
    this.checked = false,
    this.onCheck,
  });

  final ForensicTicket ticket;
  final ReviewStatus status;
  final bool selected;
  final ForensicMedia media;
  final VoidCallback onTap;
  final bool selecting;
  final bool checked;
  final VoidCallback? onCheck;

  String get _meta {
    final parts = <String>['#${ticket.trackId}'];
    if (ticket.vehicleClass != null) {
      final c = ticket.vehicleClass!;
      parts.add('${c[0].toUpperCase()}${c.substring(1)}');
    }
    final span = ticket.span;
    if (span != null) parts.add('${formatVideoTime(span.start)}–${formatVideoTime(span.end)}');
    parts.add('${ticket.frameCount} photo${ticket.frameCount == 1 ? '' : 's'}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final hero = ticket.hero;
    final accent = selected ? Fx.accent : Colors.transparent;
    final violations = ticket.violations;
    return Material(
      color: selected ? Fx.accent.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        canRequestFocus: false,
        onTap: selecting ? onCheck : onTap,
        child: Container(
          height: kTileHeight,
          decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 3))),
          padding: const EdgeInsets.fromLTRB(Fx.s12, Fx.s8, Fx.s12, Fx.s8),
          child: Row(children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: Fx.s8),
                child: Checkbox(value: checked, onChanged: (_) => onCheck?.call(), visualDensity: VisualDensity.compact),
              ),
            SizedBox(
              width: 84,
              height: 56,
              child: Stack(fit: StackFit.expand, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Fx.radiusSm),
                  child: hero == null
                      ? Container(color: Fx.raised(context), child: Icon(Icons.image_not_supported_outlined, color: Fx.muted(context)))
                      : FxImage(image: media.thumb(hero.file), errorLabel: ''),
                ),
                if (ticket.isFlagged)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Tooltip(
                      message: ticket.flags.map((f) => f.title).join('\n'),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Fx.warning, shape: BoxShape.circle),
                        child: const Icon(Icons.flag, size: 11, color: Colors.black87),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: Fx.s12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: ticket.plateRead
                          ? Text(ticket.plateText,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: Fx.plate.copyWith(fontSize: 15))
                          : Text('Plate unread',
                              maxLines: 1,
                              style: Fx.body(context).copyWith(color: Fx.muted(context), fontStyle: FontStyle.italic)),
                    ),
                    Tooltip(
                      message: Fx.statusLabel(status),
                      child: Icon(Fx.statusIcon(status), size: 18, color: Fx.statusColor(status)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Tooltip(
                    message: violations.map((v) => ViolationCatalog.of(v).label).join(', '),
                    child: Row(children: [
                      if (violations.isNotEmpty) Flexible(child: ViolationChip(violations.first, dense: true)),
                      if (violations.length > 1) ...[
                        const SizedBox(width: 4),
                        StatusPill(label: '+${violations.length - 1}', color: Fx.muted(context), dense: true),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Text(_meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: Fx.caption(context)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The ticket queue: search, status filters, violation filter, sort, batch select, and the list.
class QueuePanel extends StatefulWidget {
  const QueuePanel({
    super.key,
    required this.controller,
    required this.media,
    required this.onBatchDecision,
    this.onPicked,
  });

  final ReviewController controller;
  final ForensicMedia media;

  /// Asks the host to confirm / reject every ticked ticket (it shows the warning dialog).
  final void Function(ReviewStatus status) onBatchDecision;

  /// Called after a ticket was opened from the list (the narrow layout closes its drawer).
  final VoidCallback? onPicked;

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  bool _selecting = false;

  ReviewController get c => widget.controller;

  String? _shownUid;

  @override
  void initState() {
    super.initState();
    _shownUid = c.selectedUid;
    c.addListener(_keepSelectionInView);
  }

  @override
  void dispose() {
    c.removeListener(_keepSelectionInView);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// After the open ticket changed (keyboard, merge, advance), scroll the list to it.
  void _keepSelectionInView() {
    if (c.selectedUid == _shownUid) return;
    _shownUid = c.selectedUid;
    final i = c.visible.indexWhere((t) => t.uid == _shownUid);
    if (i < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final top = i * kTileHeight;
      final bottom = top + kTileHeight;
      final view = _scroll.position.viewportDimension;
      final offset = _scroll.offset;
      if (top < offset) {
        _scroll.animateTo(top, duration: const Duration(milliseconds: 140), curve: Curves.easeOut);
      } else if (bottom > offset + view) {
        _scroll.animateTo(bottom - view, duration: const Duration(milliseconds: 140), curve: Curves.easeOut);
      }
    });
  }

  static const _filterLabels = {
    QueueFilter.all: 'All',
    QueueFilter.toReview: 'To review',
    QueueFilter.flagged: 'Flagged',
    QueueFilter.confirmed: 'Confirmed',
    QueueFilter.rejected: 'False alarms',
  };

  static const _sortLabels = {
    QueueSort.flaggedFirst: 'Needs attention first',
    QueueSort.timeInVideo: 'Time in video',
    QueueSort.mostFrames: 'Most photos',
    QueueSort.trackId: 'Vehicle ID',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final visible = c.visible;
        final selecting = _selecting || c.checked.isNotEmpty;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Fx.s12, Fx.s12, Fx.s12, Fx.s8),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _search,
                onChanged: c.setQuery,
                decoration: InputDecoration(
                  hintText: 'Search plate, vehicle ID, violation',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            c.setQuery('');
                          },
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: Fx.raised(context),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(Fx.radiusSm), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Fx.s12),
            child: Wrap(spacing: Fx.s8, runSpacing: 0, children: [
              for (final f in QueueFilter.values)
                ChoiceChip(
                  label: Text('${_filterLabels[f]} ${c.countFor(f)}'),
                  selected: c.filter == f,
                  onSelected: (_) => c.setFilter(f),
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Fx.s8),
            child: Row(children: [
              _violationMenu(context),
              _sortMenu(context),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  _selecting = !selecting;
                  if (!_selecting) c.clearChecked();
                }),
                icon: Icon(selecting ? Icons.close : Icons.checklist, size: 16),
                label: Text(selecting ? 'Done' : 'Select'),
              ),
            ]),
          ),
          Divider(height: 1, color: Fx.border(context)),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    icon: c.total == 0 ? Icons.inbox_outlined : Icons.filter_alt_off_outlined,
                    title: c.total == 0 ? 'No tickets in this analysis' : 'No tickets match',
                    message: c.total == 0
                        ? 'The analysis did not flag any vehicle.'
                        : 'Try a different filter or search.',
                    action: c.hasActiveFilters
                        ? OutlinedButton(
                            onPressed: () {
                              _search.clear();
                              c.clearFilters();
                            },
                            child: const Text('Clear filters'),
                          )
                        : null,
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: visible.length,
                    itemExtent: kTileHeight,
                    itemBuilder: (context, i) {
                      final t = visible[i];
                      return TicketTile(
                        key: ValueKey(t.uid),
                        ticket: t,
                        status: c.statusOf(t),
                        selected: t.uid == c.selectedUid,
                        media: widget.media,
                        selecting: selecting,
                        checked: c.checked.contains(t.uid),
                        onCheck: () => c.toggleChecked(t.uid),
                        onTap: () {
                          c.select(t.uid);
                          widget.onPicked?.call();
                        },
                      );
                    },
                  ),
          ),
          if (c.checked.isNotEmpty) _batchBar(context),
        ]);
      },
    );
  }

  Widget _violationMenu(BuildContext context) {
    final counts = c.violationCounts;
    final active = c.violationFilter;
    return MenuAnchor(
      menuChildren: [
        for (final k in counts.keys)
          CheckboxMenuButton(
            closeOnActivate: false,
            value: active.contains(k),
            onChanged: (_) => c.toggleViolationFilter(k),
            child: Text('${ViolationCatalog.of(k).label}  (${counts[k]})'),
          ),
      ],
      builder: (context, menu, _) => TextButton.icon(
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.rule, size: 16),
        label: Text(active.isEmpty ? 'Violation' : 'Violation (${active.length})'),
      ),
    );
  }

  Widget _sortMenu(BuildContext context) {
    return PopupMenuButton<QueueSort>(
      tooltip: 'Sort',
      initialValue: c.sort,
      onSelected: c.setSort,
      itemBuilder: (_) => [
        for (final e in _sortLabels.entries) CheckedPopupMenuItem(value: e.key, checked: c.sort == e.key, child: Text(e.value)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Fx.s8, vertical: Fx.s8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sort, size: 16),
          const SizedBox(width: 6),
          Text('Sort', style: Theme.of(context).textTheme.labelLarge),
        ]),
      ),
    );
  }

  Widget _batchBar(BuildContext context) {
    final n = c.checked.length;
    return Container(
      padding: const EdgeInsets.all(Fx.s12),
      decoration: BoxDecoration(color: Fx.raised(context), border: Border(top: BorderSide(color: Fx.border(context)))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('$n selected', style: Fx.heading(context)),
          const Spacer(),
          TextButton(onPressed: c.checkAllVisible, child: const Text('All')),
          TextButton(onPressed: c.clearChecked, child: const Text('None')),
        ]),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: c.busy ? null : () => widget.onBatchDecision(ReviewStatus.rejected),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('False alarm'),
              style: OutlinedButton.styleFrom(foregroundColor: Fx.danger),
            ),
          ),
          const SizedBox(width: Fx.s8),
          Expanded(
            child: FilledButton.icon(
              onPressed: c.busy ? null : () => widget.onBatchDecision(ReviewStatus.confirmed),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Confirm'),
              style: FilledButton.styleFrom(backgroundColor: Fx.success, foregroundColor: Colors.black87),
            ),
          ),
        ]),
      ]),
    );
  }
}
