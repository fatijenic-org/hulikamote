import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/fx.dart';

import '../../domain/hub_models.dart';
import '../hub_format.dart';

/// The jobs down the left: what is live for each, at a glance. Picking one shows its versions.
class JobRail extends StatelessWidget {
  const JobRail({super.key, required this.jobs, required this.selected, required this.onSelect});

  final List<HubJob> jobs;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Fx.s12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Fx.s8, Fx.s8, Fx.s8, Fx.s12),
          child: Text('JOBS', style: Fx.label(context)),
        ),
        for (final j in jobs) _RailItem(job: j, selected: j.job == selected, onTap: () => onSelect(j.job)),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.job, required this.selected, required this.onTap});

  final HubJob job;
  final bool selected;
  final VoidCallback onTap;

  String get _liveLine {
    final v = job.live;
    if (v == null) return job.canSwitch ? 'Nothing live' : 'Set up automatically';
    final score = v.score;
    return score == null ? v.name : '${v.name} · ${fmtScore(job, score)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Fx.s4),
      child: Material(
        color: selected ? Fx.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(Fx.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Fx.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Fx.s12, vertical: 10),
            child: Row(children: [
              Icon(jobIcon(job.job), size: 20, color: selected ? Fx.accent : Fx.muted(context)),
              const SizedBox(width: Fx.s12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(job.label, style: Fx.body(context).copyWith(fontWeight: FontWeight.w600)),
                  Text(_liveLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: Fx.caption(context)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
