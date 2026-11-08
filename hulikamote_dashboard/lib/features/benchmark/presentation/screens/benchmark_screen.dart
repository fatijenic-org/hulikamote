import 'dart:async';

import 'package:flutter/material.dart';

import '../../../forensic/data/forensic_api.dart';
import '../../../forensic/domain/forensic_models.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/benchmark_api.dart';
import '../../domain/benchmark_models.dart';
import '../widgets/clip_dialog.dart';
import '../widgets/report_view.dart';

/// The Benchmark tab: score the system on clips where the answers are known (the same job as `python -m tools.benchmark`).
/// Steps: run a clip in the Forensic Analyzer, add it here and write down what really happens, press Run benchmark.
class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({
    super.key,
    this.api,
    this.forensic,
    this.pickVideo = pickOriginalVideo,
    this.pollEvery = const Duration(seconds: 2),
  });

  /// Injected by tests; the app uses the real backend.
  final BenchmarkApi? api;
  final ForensicApi? forensic;
  final Future<String?> Function() pickVideo;
  final Duration pollEvery;

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  late final BenchmarkApi _api = widget.api ?? BenchmarkApi();
  late final ForensicApi _forensic = widget.forensic ?? ForensicApi();

  BenchOverview? _overview;
  String? _error;
  String? _reportName;
  ReportDetail? _report;
  String? _reportError;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _load() async {
    try {
      final o = await _api.overview();
      if (!mounted) return;
      setState(() {
        _overview = o;
        _error = null;
      });
      _syncTimer(o.run);
      final names = [for (final r in o.reports) r.name];
      if (_reportName == null || !names.contains(_reportName)) {
        if (names.isNotEmpty) {
          await _openReport(names.first);
        } else {
          setState(() {
            _reportName = null;
            _report = null;
          });
        }
      }
    } on BenchmarkApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Cannot reach the backend: $e');
    }
  }

  void _syncTimer(RunProgress? run) {
    if (run != null && run.running) {
      _timer ??= Timer.periodic(widget.pollEvery, (_) => _poll());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _poll() async {
    final run = _overview?.run;
    if (run == null) return;
    try {
      final next = await _api.runProgress(run.id);
      if (!mounted) return;
      if (next.running) {
        setState(() => _overview = _overview!.withRun(next));
        return;
      }
      _timer?.cancel();
      _timer = null;
      await _load();
      if (mounted && next.report != null) await _openReport(next.report!);
    } catch (_) {
      // a missed poll is fine; the next one tries again
    }
  }

  Future<void> _openReport(String name) async {
    setState(() {
      _reportName = name;
      _reportError = null;
    });
    try {
      final r = await _api.report(name);
      if (mounted && _reportName == name) setState(() => _report = r);
    } catch (e) {
      if (mounted) {
        setState(() {
          _report = null;
          _reportError = '$e';
        });
      }
    }
  }

  Future<void> _clipDialog(BenchClip? clip) async {
    var runs = <RunSummary>[];
    if (clip == null) {
      try {
        runs = [...await _forensic.history()]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } catch (e) {
        _toast('Could not load the Forensic Analyzer runs: $e');
        return;
      }
      if (runs.isEmpty) {
        _toast('Run a clip in the Forensic Analyzer first, then add it here.');
        return;
      }
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ClipDialog(api: _api, runs: runs, clip: clip, pickVideo: widget.pickVideo),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteClip(BenchClip clip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${clip.id}?'),
        content: const Text("The benchmark's own copy of the video and its settings are deleted. Your original video is not touched."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('confirm-delete'), onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteClip(clip.id);
      await _load();
    } on BenchmarkApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _startRun() async {
    final o = _overview;
    if (o == null) return;
    final label = await showDialog<String>(
      context: context,
      builder: (_) => _RunDialog(clips: o.clips.length, seconds: o.totalSeconds),
    );
    if (label == null) return;
    try {
      await _api.startRun(label: label);
      await _load();
    } on BenchmarkApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _stopRun() async {
    final run = _overview?.run;
    if (run == null) return;
    try {
      await _api.cancelRun(run.id);
      _toast('Stopping after the clip that is being analysed.');
    } on BenchmarkApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _overview;
    final running = o?.run?.running ?? false;
    return ColoredBox(
      color: Fx.page(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(Fx.s24),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Benchmark', style: Fx.title(context)),
                    const SizedBox(height: Fx.s4),
                    Text(
                      'Score the system on clips where you know what really happens.  '
                      '1. Run a clip in the Forensic Analyzer.  2. Add it here and write down what really happens.  3. Run the benchmark.',
                      style: Fx.caption(context),
                    ),
                  ]),
                ),
                const SizedBox(width: Fx.s16),
                OutlinedButton.icon(
                  key: const Key('add-clip'),
                  onPressed: o == null ? null : () => _clipDialog(null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add clip'),
                ),
                const SizedBox(width: Fx.s8),
                FilledButton.icon(
                  key: const Key('run-benchmark'),
                  onPressed: (o != null && o.clips.isNotEmpty && !running) ? _startRun : null,
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Run benchmark'),
                ),
              ]),
              const SizedBox(height: Fx.s16),
              if (_error != null) ...[
                FxBanner(message: _error!, action: TextButton(onPressed: _load, child: const Text('Retry'))),
                const SizedBox(height: Fx.s16),
              ],
              if (o == null && _error == null)
                const Padding(padding: EdgeInsets.all(Fx.s32), child: Center(child: CircularProgressIndicator())),
              if (o != null) ..._sections(context, o),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, BenchOverview o) {
    final run = o.run;
    const gap = SizedBox(height: Fx.s16);
    return [
      if (o.problems.isNotEmpty) ...[
        FxBanner(message: 'Fix before running: ${o.problems.join('  |  ')}', color: Fx.warning, icon: Icons.warning_amber_outlined),
        gap,
      ],
      if (run != null && run.running) ...[_runCard(context, run), gap],
      if (run != null && run.status == 'failed') ...[
        FxBanner(message: 'The benchmark "${run.label}" failed: ${run.error ?? 'unknown error'}'),
        gap,
      ],
      if (run != null && run.status == 'cancelled') ...[
        FxBanner(message: 'The benchmark "${run.label}" was stopped after ${run.clipsDone} of ${run.clipsTotal} clips.', color: Fx.warning),
        gap,
      ],
      _resultsCard(context, o),
      gap,
      _clipsCard(context, o),
      gap,
      _coverageCard(context, o),
    ];
  }

  Widget _runCard(BuildContext context, RunProgress run) {
    return FxCard(
      key: const Key('run-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Running "${run.label}"', style: Fx.heading(context))),
          TextButton(key: const Key('stop-run'), onPressed: _stopRun, child: const Text('Stop after this clip')),
        ]),
        const SizedBox(height: Fx.s8),
        LinearProgressIndicator(value: run.fraction),
        const SizedBox(height: Fx.s8),
        Text(
          '${run.clipsDone} of ${run.clipsTotal} clips done'
          '${run.current != null ? '  ·  now: ${run.current}' : ''}'
          '${run.stage.isNotEmpty ? '  ·  ${run.stage}' : ''}',
          style: Fx.caption(context),
        ),
        const SizedBox(height: Fx.s4),
        Text('This is slow: about 10 times the length of the clips. Keep the Live Monitor and other analyses off meanwhile.', style: Fx.caption(context)),
      ]),
    );
  }

  Widget _resultsCard(BuildContext context, BenchOverview o) {
    return FxCard(
      key: const Key('results-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionLabel(
          'Results',
          trailing: o.reports.length > 1
              ? DropdownButton<String>(
                  key: const Key('report-picker'),
                  value: _reportName,
                  isDense: true,
                  items: [for (final r in o.reports) DropdownMenuItem(value: r.name, child: Text(r.title))],
                  onChanged: (n) {
                    if (n != null) _openReport(n);
                  },
                )
              : null,
        ),
        if (_report != null)
          ReportView(report: _report!)
        else if (_reportError != null)
          FxBanner(message: _reportError!)
        else if (o.reports.isNotEmpty)
          const Padding(padding: EdgeInsets.all(Fx.s16), child: Center(child: CircularProgressIndicator()))
        else
          const SizedBox(
            height: 240,
            child: EmptyState(
              icon: Icons.fact_check_outlined,
              title: 'No benchmark run yet',
              message: 'Add clips with their real events, then press Run benchmark. The report appears here.',
            ),
          ),
      ]),
    );
  }

  Widget _clipsCard(BuildContext context, BenchOverview o) {
    return FxCard(
      key: const Key('clips-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionLabel('Clips (${o.clips.length})'),
        if (o.clips.isEmpty)
          SizedBox(
            height: 300,
            child: EmptyState(
              icon: Icons.movie_outlined,
              title: 'No clips yet',
              message: 'Run a clip in the Forensic Analyzer, then add it here and write down what really happens in it.',
              action: FilledButton(onPressed: () => _clipDialog(null), child: const Text('Add clip')),
            ),
          )
        else
          for (final c in o.clips) _clipRow(context, c),
      ]),
    );
  }

  Widget _clipRow(BuildContext context, BenchClip c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Fx.s8),
      child: Row(children: [
        Icon(c.clean ? Icons.verified_outlined : Icons.movie_outlined, color: Fx.muted(context)),
        const SizedBox(width: Fx.s12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.id, style: Fx.body(context).copyWith(fontWeight: FontWeight.w600)),
            Text(c.note.isEmpty ? 'No note' : c.note, style: Fx.caption(context), overflow: TextOverflow.ellipsis),
          ]),
        ),
        Wrap(spacing: Fx.s8, children: [
          StatusPill(
            label: c.clean ? 'clean' : '${c.events.length} event${c.events.length == 1 ? '' : 's'}',
            color: (c.clean || c.events.isNotEmpty) ? Fx.success : Fx.warning,
            dense: true,
          ),
          if (c.seconds != null) StatusPill(label: _length(c.seconds!), color: const Color(0xFF9AA5B1), dense: true),
          if (!c.fileOk) const StatusPill(label: 'video missing', color: Fx.danger, dense: true),
          if (!c.settingsOk) const StatusPill(label: 'settings missing', color: Fx.danger, dense: true),
        ]),
        const SizedBox(width: Fx.s8),
        IconButton(key: Key('edit-${c.id}'), tooltip: 'Edit events', onPressed: () => _clipDialog(c), icon: const Icon(Icons.edit_outlined, size: 20)),
        IconButton(key: Key('delete-${c.id}'), tooltip: 'Remove', onPressed: () => _deleteClip(c), icon: const Icon(Icons.delete_outline, size: 20)),
      ]),
    );
  }

  Widget _coverageCard(BuildContext context, BenchOverview o) {
    return FxCard(
      key: const Key('coverage-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionLabel('What still needs clips'),
        Text(
          'A violation gets a pass or fail verdict only after ${o.minEvents} real events (ideally from 3 or more clips). '
          'What to film for each one: benchmarks/CLIP_CHECKLIST.md.',
          style: Fx.caption(context),
        ),
        const SizedBox(height: Fx.s8),
        for (final r in o.rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 280, child: Align(alignment: Alignment.centerLeft, child: ViolationChip(r.key, dense: true))),
              SizedBox(width: 120, child: Text('${r.events} of ${r.needed} events', style: Fx.body(context))),
              SizedBox(width: 80, child: Text('${r.clips} clip${r.clips == 1 ? '' : 's'}', style: Fx.caption(context))),
              StatusPill(
                label: r.state,
                color: r.ready ? Fx.success : (r.events > 0 ? Fx.warning : const Color(0xFF9AA5B1)),
                dense: true,
              ),
            ]),
          ),
      ]),
    );
  }

  static String _length(double seconds) {
    final s = seconds.round();
    return s >= 60 ? '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} min' : '$s s';
  }
}

/// Asks for a name for the run and says how long it will take.
class _RunDialog extends StatefulWidget {
  const _RunDialog({required this.clips, required this.seconds});

  final int clips;
  final double seconds;

  @override
  State<_RunDialog> createState() => _RunDialogState();
}

class _RunDialogState extends State<_RunDialog> {
  final _label = TextEditingController(text: 'baseline');

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (widget.seconds * 10 / 60).ceil();
    return AlertDialog(
      title: const Text('Run the benchmark'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '${widget.clips} clip${widget.clips == 1 ? '' : 's'}'
          '${widget.seconds > 0 ? ', about $minutes min to analyse (roughly 10 times their length)' : ''}. '
          'Nothing is written to the Inbox. Do not use the Live Monitor or start another analysis meanwhile.',
        ),
        const SizedBox(height: Fx.s16),
        TextField(
          key: const Key('run-label'),
          controller: _label,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name of this run',
            helperText: 'for example baseline, or finetuned-helmet',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('start-run'),
          onPressed: () => Navigator.pop(context, _label.text.trim().isEmpty ? 'baseline' : _label.text.trim()),
          child: const Text('Start'),
        ),
      ],
    );
  }
}
