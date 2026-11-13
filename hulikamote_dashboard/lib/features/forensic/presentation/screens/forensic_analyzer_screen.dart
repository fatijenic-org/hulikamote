import 'package:flutter/material.dart';

import '../../data/forensic_api.dart';
import '../../data/forensic_media.dart';
import '../../data/harvest_labeling.dart';
import '../../domain/analysis_draft.dart';
import '../../domain/analysis_runner.dart';
import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import '../widgets/analysis_wizard.dart';
import '../widgets/fx.dart';
import '../widgets/harvest_categories_view.dart';
import '../widgets/library_view.dart';
import '../widgets/results_workspace.dart';
import '../widgets/video_panel.dart';

/// The Forensic Analyzer page: start an analysis, browse the library, review a result.
///
/// Four places, one at a time:
///  - Analyze: the five-step wizard (state is kept while you look at the library);
///  - Library: every finished analysis;
///  - Harvest: the kinds of pictures that can teach the system (every analysis), one tile each; a tile opens the labeler;
///  - Results: the review workspace of one analysis (opened from the library or when a run ends), with its own Harvest tab.
class ForensicAnalyzerScreen extends StatefulWidget {
  const ForensicAnalyzerScreen({
    super.key,
    this.api,
    this.media,
    this.labeling,
    this.videoBuilder = defaultVideoPanel,
    this.initialTab = 0,
  });

  /// Injected by tests; the app uses the real backend and the Training Lab on disk.
  final ForensicApi? api;
  final ForensicMedia? media;
  final HarvestLabeling? labeling;
  final VideoPanelBuilder videoBuilder;

  /// 0 analyze, 1 library, 2 harvest. The Training Studio opens the Harvest tab with `/forensic-analyzer?tab=harvest`.
  final int initialTab;

  @override
  State<ForensicAnalyzerScreen> createState() => _ForensicAnalyzerScreenState();
}

class _OpenRun {
  _OpenRun({required this.taskId, required this.title, required this.subtitle, required this.videoUrl, required this.controller});

  final String taskId;
  final String title;
  final String subtitle;
  final String? videoUrl;
  final ReviewController controller;
}

class _ForensicAnalyzerScreenState extends State<ForensicAnalyzerScreen> {
  late final ForensicApi _api = widget.api ?? ForensicApi();
  late final ForensicMedia _media = widget.media ?? const ForensicMedia();
  final AnalysisDraft _draft = AnalysisDraft();
  late final AnalysisRunner _runner = AnalysisRunner(_api);
  late final HarvestLabeling _labeling = widget.labeling ?? LocalHarvestLabeling();

  ModelChoices _models = ModelChoices.empty;
  late int _tab = widget.initialTab; // 0 analyze, 1 library, 2 harvest
  int _libraryToken = 0;
  _OpenRun? _open;
  bool _opening = false;
  String? _openError;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void didUpdateWidget(ForensicAnalyzerScreen old) {
    super.didUpdateWidget(old);
    // The page stays alive behind the other tabs; a link to /forensic-analyzer?tab=harvest only changes this value.
    if (widget.initialTab != old.initialTab) setState(() => _tab = widget.initialTab);
  }

  @override
  void dispose() {
    _open?.controller.dispose();
    _runner.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    final m = await _api.models();
    if (mounted) setState(() => _models = m);
  }

  // ── opening results ──
  /// Opens an analysis that is still running: the tickets released so far, kept up to date until it ends.
  Future<void> _openLive(String taskId) async {
    if (_open?.taskId == taskId) {
      setState(() => _tab = 0); // already open; nothing to load
      return;
    }
    setState(() {
      _opening = true;
      _openError = null;
    });
    try {
      final s = await _api.followStatus(taskId);
      final saved = await _api.savedStatuses({for (final t in s.tickets) ...t.dbIds});
      final statuses = <String, ReviewStatus>{
        for (final t in s.tickets) t.uid: _statusFromRows(t, saved),
      };
      _show(taskId, s.tickets, s.resultVideo, DateTime.now(), statuses);
      if (!s.isDone && !s.isFailed && !s.isCancelled) _open?.controller.followRun();
    } catch (e) {
      if (mounted) setState(() => _openError = 'Could not open the running analysis: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openRun(RunSummary run) async {
    if (run.running) return _openLive(run.taskId);
    setState(() {
      _opening = true;
      _openError = null;
    });
    try {
      final tickets = await _api.report(run.reportUrl);
      final saved = await _api.savedStatuses({for (final t in tickets) ...t.dbIds});
      final statuses = <String, ReviewStatus>{
        for (final t in tickets) t.uid: _statusFromRows(t, saved),
      };
      _show(run.taskId, tickets, run.videoUrl, run.createdAt, statuses);
    } catch (e) {
      if (mounted) setState(() => _openError = 'Could not open that analysis: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// A ticket counts as decided when its violation rows carry a decision.
  static ReviewStatus _statusFromRows(ForensicTicket t, Map<String, ReviewStatus> saved) {
    final s = [for (final id in t.dbIds) if (saved[id] != null) saved[id]!];
    if (s.isEmpty) return ReviewStatus.pending;
    return s.contains(ReviewStatus.rejected) && !s.contains(ReviewStatus.confirmed)
        ? ReviewStatus.rejected
        : ReviewStatus.confirmed;
  }

  void _openFinished(String taskId, RunStatus result) {
    final open = _open;
    if (open != null && open.taskId == taskId) {
      // Already open while it ran: keep the reviewer's place, decisions and filters; the controller picks up the end itself.
      open.controller.refreshLive();
      setState(() => _libraryToken++);
      return;
    }
    if (open != null || _opening) {
      // The reviewer is looking at another analysis: do not pull them away from it, offer the finished one instead.
      setState(() => _libraryToken++);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('The analysis that was running has finished.'),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            if (mounted) _show(taskId, result.tickets, result.resultVideo, DateTime.now(), const {});
          },
        ),
      ));
      return;
    }
    _show(taskId, result.tickets, result.resultVideo, DateTime.now(), const {});
    setState(() => _libraryToken++);
  }

  void _show(String taskId, List<ForensicTicket> tickets, String? videoUrl, DateTime when, Map<String, ReviewStatus> statuses) {
    _open?.controller.dispose();
    final controller = ReviewController(gateway: _api, taskId: taskId, tickets: tickets, statuses: statuses);
    setState(() {
      _open = _OpenRun(
        taskId: taskId,
        title: 'Analysis · ${formatRunTime(when)}',
        subtitle: taskId.length > 8 ? taskId.substring(0, 8) : taskId,
        videoUrl: videoUrl,
        controller: controller,
      );
    });
  }

  void _closeRun({int toTab = 1}) {
    final run = _open;
    setState(() {
      _open = null;
      _tab = toTab;
      if (toTab == 1) _libraryToken++;
    });
    // The workspace is gone this frame; dispose its controller afterwards.
    WidgetsBinding.instance.addPostFrameCallback((_) => run?.controller.dispose());
  }

  Future<void> _sendToLive(String taskId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(SnackBar(content: Text(await _api.sendToLive(taskId))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not send to the Live Monitor: $e')));
    }
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Fx.page(context),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final run = _open;
    final Widget? cover = _opening
        ? const EmptyState(icon: Icons.hourglass_top, title: 'Opening the analysis…', message: 'Loading its tickets and your earlier decisions.')
        : run != null
            ? _workspace(run)
            : null;
    // The pages underneath (the wizard with the progress of a running analysis, the library) stay alive while a result is
    // open, so coming back finds them as they were; they are only hidden, and their animations are paused.
    return Stack(children: [
      Positioned.fill(
        child: Offstage(
          offstage: cover != null,
          child: TickerMode(enabled: cover == null, child: _pages(context, covered: cover != null)),
        ),
      ),
      if (cover != null) Positioned.fill(child: cover),
    ]);
  }

  Widget _pages(BuildContext context, {required bool covered}) {
    return Column(children: [
      _header(context),
      if (_openError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(Fx.s24, 0, Fx.s24, Fx.s8),
          child: FxBanner(message: _openError!, action: TextButton(onPressed: () => setState(() => _openError = null), child: const Text('Dismiss'))),
        ),
      Expanded(
        child: IndexedStack(index: _tab, children: [
          AnalysisWizard(
            draft: _draft,
            runner: _runner,
            api: _api,
            media: _media,
            models: _models,
            onOpenResult: _openFinished,
            onOpenLive: _openLive,
          ),
          LibraryView(
            api: _api,
            refreshToken: _libraryToken,
            onOpen: _openRun,
            onSendToLive: _sendToLive,
            onNew: () => setState(() => _tab = 0),
          ),
          HarvestCategoriesView(labeling: _labeling, active: _tab == 2 && !covered),
        ]),
      ),
    ]);
  }

  /// The review of one analysis. While an analysis is running, a bar on top says so and leads back to its progress.
  Widget _workspace(_OpenRun run) {
    return Column(children: [
      ListenableBuilder(
        listenable: _runner,
        builder: (context, _) => _runner.active ? _runningBar(context) : const SizedBox.shrink(),
      ),
      Expanded(
        // The controller changes while a run is followed (its video appears when it ends), so the button follows it.
        child: ListenableBuilder(
          listenable: run.controller,
          builder: (context, _) => ResultsWorkspace(
            key: ValueKey(run.taskId),
            controller: run.controller,
            media: _media,
            title: run.title,
            subtitle: run.subtitle,
            videoUrl: run.videoUrl,
            videoBuilder: widget.videoBuilder,
            onBack: () => _closeRun(),
            onNewAnalysis: () => _closeRun(toTab: 0),
            onSendToLive: (run.videoUrl ?? run.controller.resultVideo) == null ? null : () => _sendToLive(run.taskId),
            harvest: _labeling,
          ),
        ),
      ),
    ]);
  }

  /// "An analysis is running": always one press from its full progress with Stop here and Cancel.
  Widget _runningBar(BuildContext context) {
    return Container(
      key: const Key('running-bar'),
      padding: const EdgeInsets.symmetric(horizontal: Fx.s24, vertical: Fx.s8),
      decoration: BoxDecoration(
        color: Fx.accent.withValues(alpha: 0.10),
        border: Border(bottom: BorderSide(color: Fx.border(context))),
      ),
      child: Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: Fx.s12),
        Expanded(
          child: Text(
            'An analysis is running · ${_runner.progress.toStringAsFixed(0)}% · ${_runner.stage}',
            style: Fx.body(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: Fx.s12),
        FilledButton.tonalIcon(
          key: const Key('view-progress'),
          onPressed: _showProgress,
          icon: const Icon(Icons.timelapse, size: 18),
          label: const Text('View progress'),
        ),
      ]),
    );
  }

  /// Leaves the open result and shows the progress of the running analysis (Stop here / Cancel are there).
  void _showProgress() {
    final run = _open;
    setState(() {
      _open = null;
      _openError = null;
      _tab = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => run?.controller.dispose());
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Fx.s24, Fx.s16, Fx.s24, Fx.s12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Fx.border(context)))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Fx.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.biotech, color: Fx.accent),
        ),
        const SizedBox(width: Fx.s12),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Forensic Analyzer', style: Fx.title(context)),
            Text('Find, check and confirm violations in recorded video.', style: Fx.caption(context), overflow: TextOverflow.ellipsis),
          ]),
        ),
        const Spacer(),
        ListenableBuilder(
          listenable: _runner,
          // Shown while an analysis runs (the page itself is not rebuilt when it starts); pressing it shows the full
          // progress, with Stop here and Cancel, from any tab.
          builder: (context, _) => !_runner.active
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(right: Fx.s12),
                  child: Tooltip(
                    message: 'View progress',
                    child: InkWell(
                      key: const Key('header-progress'),
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setState(() => _tab = 0),
                      child: StatusPill(
                        label: 'Analyzing ${_runner.progress.toStringAsFixed(0)}%',
                        color: Fx.accent,
                        icon: Icons.autorenew,
                      ),
                    ),
                  ),
                ),
        ),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, icon: Icon(Icons.add_circle_outline, size: 18), label: Text('New analysis')),
            ButtonSegment(value: 1, icon: Icon(Icons.video_library_outlined, size: 18), label: Text('Library')),
            ButtonSegment(value: 2, icon: Icon(Icons.inventory_2_outlined, size: 18), label: Text('Harvest')),
          ],
          selected: {_tab},
          onSelectionChanged: (s) {
            setState(() => _tab = s.first);
            if (s.first == 0) _loadModels();
          },
        ),
      ]),
    );
  }
}
