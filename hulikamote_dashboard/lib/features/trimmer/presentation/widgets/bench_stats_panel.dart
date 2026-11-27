import 'package:flutter/material.dart';

import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/trim_session.dart';
import '../../domain/trimmer_controller.dart';
import '../../domain/trimmer_models.dart';

/// What the benchmark folder holds for each violation: clips, events (against the number a verdict needs), seconds, typed plates and
/// clean clips. It reads the registry, so it shows everything exported so far (from any video), not only the open one.
class BenchStatsPanel extends StatelessWidget {
  const BenchStatsPanel({super.key, required this.controller});

  final TrimmerController controller;

  static String _time(double s) {
    final m = (s / 60).floor();
    return m >= 60 ? '${m ~/ 60} h ${m % 60} min' : (m > 0 ? '$m min ${(s % 60).round()} s' : '${s.round()} s');
  }

  String _name(String key) => key == cleanLabel ? 'Clean' : ViolationCatalog.of(key).label;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final stats = controller.stats;
        if (stats == null) {
          return Padding(
            padding: const EdgeInsets.all(Fx.s8),
            child: Row(children: [
              Expanded(child: Text(controller.statsError ?? (controller.statsLoading ? 'Counting the clips ...' : 'Not counted yet.'), style: Fx.caption(context))),
              TextButton(onPressed: controller.loadStats, child: const Text('Count')),
            ]),
          );
        }
        final shown = [for (final r in stats.rows) if (r.clips > 0 || r.cleanClips > 0) r]..sort((a, b) => b.events.compareTo(a.events));
        final empty = [for (final r in stats.rows) if (r.clips == 0 && r.cleanClips == 0 && r.violation != cleanLabel) _name(r.violation)];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(
                '${stats.clips} clips · ${_time(stats.seconds)} in the folder${stats.missing > 0 ? ' · ${stats.missing} video(s) missing' : ''}',
                style: Fx.caption(context),
              ),
            ),
            IconButton(
              tooltip: 'Count again',
              visualDensity: VisualDensity.compact,
              icon: controller.statsLoading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              onPressed: controller.statsLoading ? null : controller.loadStats,
            ),
          ]),
          if (controller.statsError != null) Text(controller.statsError!, style: Fx.caption(context).copyWith(color: Theme.of(context).colorScheme.error)),
          if (shown.isEmpty) Padding(padding: const EdgeInsets.all(Fx.s8), child: Text('Nothing exported yet.', style: Fx.caption(context))),
          for (final r in shown) _row(context, r),
          if (empty.isNotEmpty) ...[
            const SizedBox(height: Fx.s8),
            Text('No clips yet: ${empty.join(', ')}', style: Fx.caption(context)),
          ],
        ]);
      },
    );
  }

  Widget _row(BuildContext context, BenchStat r) {
    final isClean = r.violation == cleanLabel;
    final enough = r.events >= r.need;
    final color = isClean ? const Color(0xFF3CCB8C) : (enough ? const Color(0xFF3CCB8C) : Theme.of(context).colorScheme.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(_name(r.violation), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          Text(
            isClean ? '${r.clips} clip${r.clips == 1 ? '' : 's'}' : '${r.events}/${r.need} events',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ]),
        if (!isClean) ...[
          const SizedBox(height: 2),
          LinearProgressIndicator(value: (r.events / r.need).clamp(0.0, 1.0), minHeight: 4, color: color),
        ],
        const SizedBox(height: 2),
        Text(
          [
            if (!isClean) '${r.clips} clip${r.clips == 1 ? '' : 's'}',
            _time(r.seconds),
            if (!isClean) '${r.plates} with plate',
            '${r.cleanClips} clean',
          ].join(' · '),
          style: Fx.caption(context),
        ),
      ]),
    );
  }
}
