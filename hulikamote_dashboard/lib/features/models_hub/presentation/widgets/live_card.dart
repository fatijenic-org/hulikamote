import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/fx.dart';

import '../../domain/hub_models.dart';
import '../hub_format.dart';

/// The model that is live for a job, and its numbers in plain words.
class LiveCard extends StatelessWidget {
  const LiveCard({super.key, required this.job});

  final HubJob job;

  @override
  Widget build(BuildContext context) {
    final v = job.live;
    if (v == null) {
      return FxCard(
        child: Row(children: [
          Icon(Icons.info_outline, color: Fx.muted(context)),
          const SizedBox(width: Fx.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(job.canSwitch ? 'Nothing is live yet' : 'Nothing to switch here', style: Fx.heading(context)),
              const SizedBox(height: Fx.s4),
              Text(job.note ?? 'Train a version, then press Use this.', style: Fx.caption(context)),
            ]),
          ),
        ]),
      );
    }
    final shown = [for (final s in job.stats) if (v.stats[s.key] != null) s];
    return Container(
      padding: const EdgeInsets.all(Fx.s16),
      decoration: BoxDecoration(
        color: Fx.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Fx.radius),
        border: Border.all(color: Fx.success.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const StatusPill(label: 'Live now', color: Fx.success, icon: Icons.check_circle),
          const SizedBox(width: Fx.s12),
          Expanded(child: Text(v.name, style: Fx.heading(context))),
          if (job.applies.isNotEmpty) Flexible(child: Text(job.applies, style: Fx.caption(context), textAlign: TextAlign.end)),
        ]),
        const SizedBox(height: Fx.s12),
        if (shown.isEmpty)
          Text('No scores: this one was not trained here. Train a version to compare.', style: Fx.caption(context))
        else
          Row(children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(width: Fx.s12),
              Expanded(child: _Tile(label: shown[i].label, hint: shown[i].hint, value: fmtStat(job, shown[i].key, v.stats[shown[i].key]!))),
            ],
          ]),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.hint, required this.value});

  final String label, hint, value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Fx.s12),
      decoration: BoxDecoration(color: Fx.raised(context), borderRadius: BorderRadius.circular(Fx.radiusSm)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w600)),
        Text(label, style: Fx.body(context).copyWith(fontWeight: FontWeight.w600)),
        Text(hint, style: Fx.caption(context)),
      ]),
    );
  }
}
