import 'package:flutter/material.dart';

import '../../../../core/ui/page_parts.dart';
import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/demerit_api.dart';
import '../../domain/demerit_models.dart';

/// The Demerit Points tab: how many confirmed violations each plate has (one point each).
/// Points come from tickets a reviewer approved in the Inbox or the Forensic Analyzer; a rejected ticket gives none.
class DemeritScreen extends StatefulWidget {
  const DemeritScreen({super.key, this.api});

  /// Injected by tests; the app uses the real backend.
  final DemeritApi? api;

  @override
  State<DemeritScreen> createState() => _DemeritScreenState();
}

class _DemeritScreenState extends State<DemeritScreen> {
  late final DemeritApi _api = widget.api ?? DemeritApi();
  final _search = TextEditingController();

  List<DemeritEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entries = await _api.standings();
      if (mounted) {
        setState(() {
          _entries = entries;
          _error = null;
        });
      }
    } on DemeritApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static String _squash(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  List<DemeritEntry> get _shown {
    final q = _squash(_search.text);
    return [for (final e in _entries ?? const <DemeritEntry>[]) if (q.isEmpty || _squash(e.plate).contains(q)) e];
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final shown = _shown;
    return Scaffold(
      backgroundColor: Fx.page(context),
      body: Padding(
        padding: const EdgeInsets.all(Fx.s24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(
            title: 'Demerit points',
            subtitle: 'One point for every violation a reviewer confirmed, counted per plate.',
            actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load)],
          ),
          if (_error != null && entries != null) ...[
            FxBanner(message: _error!, action: TextButton(onPressed: _load, child: const Text('Try again'))),
            const SizedBox(height: Fx.s16),
          ],
          if (entries != null && entries.isNotEmpty) ...[
            Row(children: [
              StatusPill(label: '${entries.length} ${entries.length == 1 ? 'plate' : 'plates'}', color: Fx.accent),
              const SizedBox(width: Fx.s8),
              StatusPill(label: '${entries.fold<int>(0, (sum, e) => sum + e.points)} points in total', color: Fx.accent),
              const Spacer(),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search a plate',
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: Fx.s16),
          ],
          Expanded(child: _body(entries, shown)),
        ]),
      ),
    );
  }

  Widget _body(List<DemeritEntry>? entries, List<DemeritEntry> shown) {
    if (entries == null) {
      return _error == null ? const SkeletonRows(count: 5, height: 72) : ErrorPanel(message: _error!, onRetry: _load);
    }
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.balance_outlined,
        title: 'No points yet',
        message: 'A plate gets a point when you confirm one of its tickets in the Inbox or the Forensic Analyzer.',
      );
    }
    if (shown.isEmpty) {
      return EmptyState(icon: Icons.search_off, title: 'No plate matches "${_search.text.trim()}"');
    }
    return ListView.separated(
      itemCount: shown.length,
      separatorBuilder: (_, _) => const SizedBox(height: Fx.s8),
      itemBuilder: (context, i) => _PlateRow(
        rank: entries.indexOf(shown[i]) + 1,
        entry: shown[i],
        onTap: () => showDialog<void>(context: context, builder: (_) => _PlateDialog(api: _api, entry: shown[i])),
      ),
    );
  }
}

String formatWhen(DateTime? at) {
  if (at == null) return 'unknown time';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
}

class _PlateRow extends StatelessWidget {
  const _PlateRow({required this.rank, required this.entry, required this.onTap});

  final int rank;
  final DemeritEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FxCard(
      onTap: onTap,
      child: Row(children: [
        SizedBox(width: 32, child: Text('$rank', style: Fx.caption(context))),
        SizedBox(
          width: 150,
          child: Text(entry.plate, style: Fx.plate.copyWith(fontSize: 17), overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: Wrap(spacing: Fx.s8, runSpacing: Fx.s4, children: [
            for (final c in entry.byClass.entries)
              StatusPill(
                label: '${ViolationCatalog.of(c.key).label} ×${c.value}',
                color: ViolationCatalog.of(c.key).color,
                dense: true,
              ),
          ]),
        ),
        Text('last caught ${formatWhen(entry.lastAt)}', style: Fx.caption(context)),
        const SizedBox(width: Fx.s16),
        Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: Fx.s8),
          decoration: BoxDecoration(color: Fx.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Fx.radiusSm)),
          child: Column(children: [
            Text('${entry.points}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Fx.accent)),
            Text(entry.points == 1 ? 'point' : 'points', style: Fx.caption(context)),
          ]),
        ),
      ]),
    );
  }
}

/// The tickets behind one plate's points.
class _PlateDialog extends StatefulWidget {
  const _PlateDialog({required this.api, required this.entry});

  final DemeritApi api;
  final DemeritEntry entry;

  @override
  State<_PlateDialog> createState() => _PlateDialogState();
}

class _PlateDialogState extends State<_PlateDialog> {
  late final Future<DemeritDetail> _detail = widget.api.plate(widget.entry.plate);   // asked once, not on every rebuild

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return AlertDialog(
      title: Row(children: [
        Text(entry.plate, style: Fx.plate.copyWith(fontSize: 20)),
        const SizedBox(width: Fx.s12),
        StatusPill(label: '${entry.points} ${entry.points == 1 ? 'point' : 'points'}', color: Fx.accent),
      ]),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<DemeritDetail>(
          future: _detail,
          builder: (context, snap) {
            if (snap.hasError) return FxBanner(message: '${snap.error}');
            final detail = snap.data;
            if (detail == null) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionLabel('Confirmed tickets, newest first'),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final t in detail.tickets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Fx.s8),
                      child: Row(children: [
                        ViolationChip(t.cls, dense: true),
                        const Spacer(),
                        Text(formatWhen(t.at), style: Fx.caption(context)),
                      ]),
                    ),
                ]),
              ),
            ]);
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
