import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/core/utils/app_toast.dart';
import 'package:hulikamote_dashboard/core/utils/visible_poller.dart';
import 'package:hulikamote_dashboard/features/forensic/data/harvest_source.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/fx.dart';
import 'package:hulikamote_dashboard/features/training/data/dataset_browser.dart';
import 'package:hulikamote_dashboard/features/training/presentation/screens/training_studio_screen.dart';
import 'package:hulikamote_dashboard/features/training/presentation/widgets/training_state_bar.dart';

import '../../data/models_hub_api.dart';
import '../../domain/hub_models.dart';
import '../hub_format.dart';
import '../widgets/import_dialog.dart';
import '../widgets/job_rail.dart';
import '../widgets/live_card.dart';
import '../widgets/version_row.dart';

/// Every model in one place: the jobs on the left, and for the one you pick, what is live and every version trained
/// or imported, each with its numbers and one button to make it live. Training a new version opens beside it.
class ModelsHubScreen extends StatefulWidget {
  const ModelsHubScreen({super.key, this.initialJob, this.api, this.harvest, this.datasets});

  /// Which job to open (`vehicles`, `plate`, `helmet`, `cabin`, `reader`, `matcher`, `enhancer`).
  final String? initialJob;

  /// Injected by tests.
  final ModelsHubApi? api;
  final HarvestSource? harvest;
  final DatasetBrowser? datasets;

  @override
  State<ModelsHubScreen> createState() => _ModelsHubScreenState();
}

class _ModelsHubScreenState extends State<ModelsHubScreen> {
  late final ModelsHubApi _api = widget.api ?? ModelsHubApi();
  List<HubJob> _jobs = [];
  late String _selected = widget.initialJob ?? 'vehicles';
  bool _loading = true;
  String? _error;

  String? _expanded; // version id with its details open
  String? _confirming; // version id asking "Switch?"
  String? _busy; // version id being switched
  bool _trainOpen = false, _trainMounted = false;

  // A per-type check runs in the background on the backend: follow it while one is running, only while this page is shown.
  late final VisiblePoller _poller = VisiblePoller(interval: const Duration(seconds: 4), onTick: () => _load(quiet: true), initiallyActive: false);

  HubJob? get _job => _jobs.where((j) => j.job == _selected).firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.attach(context);
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _error = null);
    try {
      final jobs = await _api.fetch();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
        if (!jobs.any((j) => j.job == _selected) && jobs.isNotEmpty) _selected = jobs.first.job;
      });
      _poller.active = jobs.any((j) => j.versions.any((v) => v.checking == 'running'));
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the models: $e';
      });
    }
  }

  void _select(String job) {
    if (job == _selected) return;
    setState(() {
      _selected = job;
      _expanded = null;
      _confirming = null;
      _trainOpen = false;
      _trainMounted = false;
    });
  }

  Future<void> _use(HubJob job, HubVersion v) async {
    setState(() => _busy = v.id);
    try {
      final detail = await _api.use(job.job, v.id);
      if (mounted) AppToast.show(context, detail);
      if (mounted) setState(() => _confirming = null);
      await _load(quiet: true);
    } catch (e) {
      if (mounted) AppToast.show(context, 'Could not switch: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _check(HubJob job, HubVersion v) async {
    try {
      await _api.check(job.job, v.id);
      await _load(quiet: true);
    } catch (e) {
      if (mounted) AppToast.show(context, 'Could not start the check: $e', isError: true);
    }
  }

  void _openTrain() => setState(() {
        _trainOpen = true;
        _trainMounted = true;
      });

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, style: TextStyle(color: Fx.danger)),
            const SizedBox(height: Fx.s12),
            FilledButton(onPressed: () => _load(), child: const Text('Retry')),
          ]),
        ),
      );
    }
    final job = _job;
    return Scaffold(
      body: Row(children: [
        SizedBox(width: 248, child: JobRail(jobs: _jobs, selected: _selected, onSelect: _select)),
        const VerticalDivider(width: 1),
        Expanded(child: job == null ? const SizedBox() : _main(job)),
        if (_trainMounted && job != null)
          Offstage(
            offstage: !_trainOpen,
            child: Row(children: [
              const VerticalDivider(width: 1),
              SizedBox(width: 560, child: _trainPanel(job)),
            ]),
          ),
      ]),
    );
  }

  Widget _main(HubJob job) {
    final liveName = job.live?.name;
    return ListView(
      padding: const EdgeInsets.all(Fx.s24),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(jobIcon(job.job), size: 28, color: Fx.accent),
                const SizedBox(width: Fx.s12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(job.label, style: Fx.title(context)),
                    const SizedBox(height: 2),
                    Text(job.purpose, style: Fx.caption(context)),
                  ]),
                ),
                IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => _load()),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (v) => v == 'import' ? showImportDialog(context, job, onImported: () => _load(quiet: true)) : showPublishDialog(context),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'import', child: Text('Import a model')),
                    PopupMenuItem(value: 'publish', child: Text('Publish to GitHub')),
                  ],
                ),
                const SizedBox(width: Fx.s8),
                FilledButton.icon(icon: const Icon(Icons.add), label: const Text('Train new version'), onPressed: _openTrain),
              ]),
              const SizedBox(height: Fx.s16),
              // Pause / Continue shows only while a detector is training or paused
              if (job.isDetector) TrainingStateBar(key: ValueKey('state-${job.key}'), modelKey: job.key, onResumed: (_) => _openTrain()),
              LiveCard(job: job),
              const SizedBox(height: Fx.s24),
              SectionLabel(
                'All versions, newest first',
                trailing: job.stats.isEmpty ? null : Text('${job.stats.first.label}: ${job.stats.first.hint}', style: Fx.caption(context)),
              ),
              if (job.versions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Fx.s24),
                  child: EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No versions yet',
                    message: job.canSwitch ? 'Train one and it shows up here, next to the live one.' : job.note,
                    action: FilledButton.icon(icon: const Icon(Icons.add), label: const Text('Train new version'), onPressed: _openTrain),
                  ),
                )
              else
                for (final v in job.versions)
                  VersionRow(
                    key: ValueKey('${job.job}/${v.id}'),
                    job: job,
                    version: v,
                    expanded: _expanded == v.id,
                    confirming: _confirming == v.id,
                    busy: _busy == v.id,
                    onToggle: () => setState(() => _expanded = _expanded == v.id ? null : v.id),
                    onUse: () => setState(() => _confirming = v.id),
                    onConfirm: () => _use(job, v),
                    onCancel: () => setState(() => _confirming = null),
                    onCheck: () => _check(job, v),
                  ),
              if (liveName != null && job.versions.length == 1)
                Padding(
                  padding: const EdgeInsets.only(top: Fx.s8),
                  child: Text('This is the only version so far. Train a new one to compare it with $liveName.', style: Fx.caption(context)),
                ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _trainPanel(HubJob job) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Fx.s24, Fx.s16, Fx.s8, 0),
        child: Row(children: [
          Expanded(child: Text('Train a new ${job.label.toLowerCase()} version', style: Fx.heading(context))),
          IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => setState(() => _trainOpen = false)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: TrainingStudioScreen(
          key: ValueKey('train-${job.key}'),
          modelKey: job.key,
          harvest: widget.harvest,
          datasets: widget.datasets,
          onRunEnded: () => _load(quiet: true),
        ),
      ),
    ]);
  }
}
