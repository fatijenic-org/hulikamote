import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/fx.dart';
import 'package:hulikamote_dashboard/features/training/presentation/widgets/training_report_widget.dart';

import '../../domain/hub_models.dart';
import '../hub_format.dart';

/// One version of a job: a line with its score and one action. Details open under it; "Use this" asks once, in place.
class VersionRow extends StatelessWidget {
  const VersionRow({
    super.key,
    required this.job,
    required this.version,
    required this.expanded,
    required this.confirming,
    required this.busy,
    required this.onToggle,
    required this.onUse,
    required this.onConfirm,
    required this.onCancel,
    required this.onCheck,
  });

  final HubJob job;
  final HubVersion version;
  final bool expanded, confirming, busy;
  final VoidCallback onToggle, onUse, onConfirm, onCancel, onCheck;

  String get _sub {
    final v = version;
    final parts = <String>[];
    if (v.isRun) {
      parts.add(v.run ?? v.id);
      final when = fmtDate(v.when);
      if (when.isNotEmpty) parts.add(when);
      if (v.epochsDone != null) {
        parts.add(v.epochsPlanned == null || v.epochsPlanned == v.epochsDone
            ? '${v.epochsDone} passes'
            : 'stopped at pass ${v.epochsDone} of ${v.epochsPlanned}');
      }
    } else {
      parts.add(v.origin == 'backup' ? 'An earlier live file' : 'Came with the app or was imported');
      if (v.sizeMb != null) parts.add('${v.sizeMb} MB');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final v = version;
    final liveScore = job.live?.score;
    final delta = v.live ? null : fmtDelta(job, liveScore, v.score);
    return Container(
      margin: const EdgeInsets.only(bottom: Fx.s8),
      decoration: BoxDecoration(
        color: Fx.panel(context),
        borderRadius: BorderRadius.circular(Fx.radiusSm),
        border: Border.all(color: Fx.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(Fx.radiusSm),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Fx.s12, vertical: 10),
            child: Row(children: [
              Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 20, color: Fx.muted(context)),
              const SizedBox(width: Fx.s8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.name, style: Fx.body(context).copyWith(fontWeight: FontWeight.w600)),
                  Text(_sub, style: Fx.caption(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              SizedBox(width: 176, child: _score(context, delta)),
              const SizedBox(width: Fx.s12),
              SizedBox(width: 92, child: Align(alignment: Alignment.centerRight, child: _action(context))),
            ]),
          ),
        ),
        if (confirming) _confirm(context),
        if (expanded) VersionDetails(job: job, version: v, onCheck: onCheck),
      ]),
    );
  }

  Widget _score(BuildContext context, String? delta) {
    final s = version.score;
    if (s == null) return Text('No score', style: Fx.caption(context));
    final up = delta != null && delta.startsWith('+');
    final down = delta != null && delta.startsWith('−');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(fmtScore(job, s), style: Fx.body(context).copyWith(fontWeight: FontWeight.w600)),
        if (delta != null) ...[
          const SizedBox(width: Fx.s8),
          Flexible(
            child: Text(delta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Fx.caption(context).copyWith(color: up ? Fx.success : (down ? Fx.danger : Fx.muted(context)))),
          ),
        ],
      ]),
      const SizedBox(height: 4),
      LinearProgressIndicator(value: s.clamp(0.0, 1.0), minHeight: 6, borderRadius: BorderRadius.circular(3)),
    ]);
  }

  Widget _action(BuildContext context) {
    if (version.live) return const StatusPill(label: 'Live', color: Fx.success, dense: true);
    if (!job.canSwitch) return const SizedBox.shrink();
    if (!version.usable) return Text('Not usable', style: Fx.caption(context));
    return OutlinedButton(
      onPressed: busy ? null : onUse,
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
      child: const Text('Use this'),
    );
  }

  Widget _confirm(BuildContext context) {
    final liveName = job.live?.name ?? 'the current model';
    final prep = version.needsExport ? ' It is prepared first, which takes about half a minute.' : '';
    final applies = job.applies.isEmpty ? '' : ' ${job.applies}';
    return Container(
      margin: const EdgeInsets.fromLTRB(Fx.s12, 0, Fx.s12, Fx.s12),
      padding: const EdgeInsets.all(Fx.s12),
      decoration: BoxDecoration(
        color: Fx.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Fx.radiusSm),
        border: Border.all(color: Fx.warning.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Switch ${job.label.toLowerCase()} from $liveName to ${version.name}?$prep$applies You can switch back any time.',
            style: Fx.body(context)),
        const SizedBox(height: Fx.s12),
        Row(children: [
          FilledButton(
            onPressed: busy ? null : onConfirm,
            child: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Switch'),
          ),
          const SizedBox(width: Fx.s8),
          TextButton(onPressed: busy ? null : onCancel, child: const Text('Cancel')),
        ]),
      ]),
    );
  }
}

/// What opens under a version: per-type scores, the settings it was trained with, the curves.
class VersionDetails extends StatefulWidget {
  const VersionDetails({super.key, required this.job, required this.version, required this.onCheck});

  final HubJob job;
  final HubVersion version;
  final VoidCallback onCheck;

  @override
  State<VersionDetails> createState() => _VersionDetailsState();
}

class _VersionDetailsState extends State<VersionDetails> {
  bool _curves = false;

  HubJob get job => widget.job;
  HubVersion get v => widget.version;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(44, Fx.s12, Fx.s16, Fx.s16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Fx.border(context)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!v.isRun)
          Text('Nothing was trained here for this one, so there are no scores to show.', style: Fx.caption(context))
        else if (job.isDetector)
          _perType(context)
        else
          _matcherResult(context),
        if (v.isRun) ...[
          const SizedBox(height: Fx.s12),
          Wrap(spacing: Fx.s8, runSpacing: Fx.s8, children: [for (final t in _tags()) _Tag(t)]),
        ],
        if (v.isRun && job.isDetector) ...[
          const SizedBox(height: Fx.s8),
          TextButton.icon(
            icon: Icon(_curves ? Icons.expand_less : Icons.show_chart, size: 18),
            label: Text(_curves ? 'Hide training curves' : 'Training curves'),
            onPressed: () => setState(() => _curves = !_curves),
          ),
          if (_curves) TrainingReportWidget(modelName: job.key, run: v.run),
        ],
      ]),
    );
  }

  List<String> _tags() => [
        if (v.settings['epochs'] != null) '${v.settings['epochs']} passes planned',
        if (v.settings['imgsz'] != null) '${v.settings['imgsz']} px',
        if (v.settings['batch'] != null) 'batch ${v.settings['batch']}',
        if (v.bestEpoch != null && job.isDetector) 'best at pass ${v.bestEpoch}',
        if (v.sizeMb != null) '${v.sizeMb} MB',
      ];

  Widget _perType(BuildContext context) {
    final classes = v.classes;
    if (classes != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How well it finds each type${v.classesSplit == null ? '' : ' (${v.classesSplit} photos)'}', style: Fx.caption(context)),
        const SizedBox(height: Fx.s8),
        for (final c in classes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 120, child: Text(c.name, style: Fx.body(context))),
              Expanded(child: LinearProgressIndicator(value: c.score.clamp(0.0, 1.0), minHeight: 6, borderRadius: BorderRadius.circular(3))),
              SizedBox(width: 44, child: Text(c.score.toStringAsFixed(2), textAlign: TextAlign.end, style: Fx.body(context))),
              SizedBox(width: 88, child: Text('${c.boxes} boxes', textAlign: TextAlign.end, style: Fx.caption(context))),
            ]),
          ),
      ]);
    }
    final state = v.checking;
    if (state == 'running') {
      return Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: Fx.s8),
        Text('Checking each type on the test photos. This takes a minute or two.', style: Fx.caption(context)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Scores per type have not been checked for this version.', style: Fx.caption(context)),
      if (state != null) Text(state, style: Fx.caption(context).copyWith(color: Fx.danger)),
      const SizedBox(height: Fx.s4),
      if (v.usable && v.run != null)
        TextButton.icon(
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: Text(state == null ? 'Check per type' : 'Try again'),
          onPressed: widget.onCheck,
        ),
    ]);
  }

  Widget _matcherResult(BuildContext context) {
    final after = v.stats['score'];
    final before = v.stats['before'];
    final cars = v.stats['cars']?.round();
    if (after == null) {
      return Text(cars == null ? 'No check result was saved for this version.' : 'Trained on $cars cars: too few to test on cars it never saw.',
          style: Fx.caption(context));
    }
    final passed = v.passed;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Checked on ${cars ?? 'some'} cars it never saw: finds the right car '
        '${before == null ? '' : '${fmtScore(job, before)} → '}${fmtScore(job, after)}.',
        style: Fx.body(context),
      ),
      if (passed != null) ...[
        const SizedBox(height: Fx.s8),
        StatusPill(
          label: passed ? 'Passed the check' : 'Did not pass the check',
          color: passed ? Fx.success : Fx.warning,
          icon: passed ? Icons.check_circle : Icons.warning_amber_rounded,
        ),
      ],
      if (v.note != null && passed != true) Padding(padding: const EdgeInsets.only(top: Fx.s8), child: Text(v.note!, style: Fx.caption(context))),
    ]);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Fx.raised(context), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: Fx.caption(context)),
    );
  }
}
