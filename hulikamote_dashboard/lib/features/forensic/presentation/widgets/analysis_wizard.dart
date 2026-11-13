import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/forensic_api.dart';
import '../../data/forensic_media.dart';
import '../../domain/analysis_draft.dart';
import '../../domain/analysis_runner.dart';
import '../../domain/forensic_models.dart';
import '../../domain/violation_catalog.dart';
import '../../../trimmer/presentation/widgets/trim_player.dart';
import 'fx.dart';
import 'wizard_steps.dart';

/// Picks a video file. Replaceable in tests.
typedef VideoPicker = Future<({String path, String name})?> Function();

Future<({String path, String name})?> pickVideoFile() async {
  final file = await FilePicker.pickFile(type: FileType.video);
  if (file == null || file.path == null) return null;
  return (path: file.path!, name: file.name);
}

/// Five steps from "choose a video" to "analysis running": Video, Violations, Rules & zones,
/// Settings, Run. A stepper on top, one job per step, a summary of choices on the side,
/// and Back / Continue at the bottom that say why Continue is not available yet.
class AnalysisWizard extends StatefulWidget {
  const AnalysisWizard({
    super.key,
    required this.draft,
    required this.runner,
    required this.api,
    required this.media,
    required this.models,
    required this.onOpenResult,
    this.onOpenLive,
    this.pickVideo = pickVideoFile,
    this.playerFactory = defaultTrimPlayer,
  });

  final AnalysisDraft draft;
  final AnalysisRunner runner;
  final ForensicApi api;
  final ForensicMedia media;
  final ModelChoices models;

  /// The analysis finished: show its tickets.
  final void Function(String taskId, RunStatus result) onOpenResult;

  /// The analysis is still running: open the tickets released so far (they keep arriving).
  final void Function(String taskId)? onOpenLive;
  final VideoPicker pickVideo;

  /// Makes the player that shows the chosen video in the trim step. Replaced in tests: media_kit needs native libraries.
  final TrimPlayerFactory playerFactory;

  @override
  State<AnalysisWizard> createState() => _AnalysisWizardState();
}

class _AnalysisWizardState extends State<AnalysisWizard> {
  static const _steps = [
    'Video',
    'Violations',
    'Rules & zones',
    'Settings',
    'Run',
  ];

  int _step = 0;
  int _reached = 0;
  bool _preparing = false;              // the picture for drawing zones is being looked up
  String? _videoError;
  String? _rulesKey;
  TrimPlayer? _player;                  // made when the first video is chosen, then reused
  Future<void>? _frameLoad;
  bool _exactFrames = true;             // false on a backend that can only give the first frame (and only by upload)

  AnalysisDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    widget.runner.addListener(_onRunner);
    // Built again while an analysis runs (or just failed): go straight to its progress, the other steps are locked anyway.
    if (widget.runner.active || widget.runner.phase == RunPhase.failed) {
      _step = _steps.length - 1;
      _reached = _step;
    }
  }

  @override
  void dispose() {
    widget.runner.removeListener(_onRunner);
    _player?.dispose();
    super.dispose();
  }

  void _onRunner() {
    final r = widget.runner;
    if (r.phase == RunPhase.done && r.result != null && r.taskId != null) {
      final taskId = r.taskId!;
      final result = r.result!;
      // Hand over the result, then get ready for the next analysis.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onOpenResult(taskId, result);
        r.clear();
        _player?.pause();
        draft.reset();
        setState(() {
          _step = 0;
          _reached = 0;
          _rulesKey = null;
        });
      });
    }
  }

  // ── video ──
  /// The video shows in the trim step the moment it is chosen: the player opens it by its path (nothing is uploaded or
  /// waited for), and the picture zones are drawn on is looked up alongside.
  Future<void> _pick() async {
    final picked = await widget.pickVideo();
    if (picked == null || !mounted) return;
    _videoError = null;
    _rulesKey = null;
    _reached = 0;
    _exactFrames = true;
    draft.chooseVideo(path: picked.path, name: picked.name);
    final player = _player ??= widget.playerFactory();
    player.open(picked.path);                                   // not awaited: it starts opening now
    await _loadFrame();
  }

  /// The frame at the start of the chosen part (zones are drawn on it), with the video's speed and length. Looked up by
  /// path; a backend that cannot do that gets the video uploaded for its first frame instead.
  Future<void> _loadFrame() => _frameLoad = _fetchFrame();

  Future<void> _fetchFrame() async {
    final path = draft.videoPath;
    if (path == null) return;
    final at = draft.trimStart;
    if (mounted) setState(() => _preparing = true);
    try {
      FrameInfo? info;
      try {
        info = await widget.api.videoFrame(path, seconds: at);
      } catch (_) {
        info = null;                                            // an older backend, or one that stumbled: try the upload way
      }
      if (info == null) {
        _exactFrames = false;
        info = await widget.api.extractFrame(path);
      }
      if (!mounted || draft.videoPath != path) return;
      draft.setFrame(url: info.url, seconds: _exactFrames ? at : 0, fps: info.fps, frames: info.frames, duration: info.duration);
    } catch (e) {
      if (!mounted || draft.videoPath != path) return;
      _player?.pause();
      draft.reset();                                            // back to the picker, with the reason
      _videoError = 'Could not read that video: $e';
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  /// Leaving the video step: the picture must be the one at the start of the chosen part.
  Future<void> _framePrepared() async {
    await _frameLoad;
    if (!mounted || draft.videoPath == null) return;
    final stale = _exactFrames && draft.frameSeconds != null && (draft.frameSeconds! - draft.trimStart).abs() > 0.001;
    if (draft.frameUrl == null || stale) await _loadFrame();
  }

  String? _filmstripUrl() {
    final path = draft.videoPath;
    if (path == null) return null;
    return Uri.parse('${widget.api.baseUrl}/api/trimmer/filmstrip').replace(queryParameters: {'file_path': path, 'count': '24'}).toString();
  }

  Future<void> _convert() async {
    final picked = await widget.pickVideo();
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Flexible(
              child: Text('Converting to H.264. This can take a few minutes.'),
            ),
          ],
        ),
      ),
    );
    String message;
    try {
      message =
          'Converted. Saved as ${await widget.api.convertVideo(picked.path)}';
    } catch (e) {
      message = 'Conversion failed: $e';
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  // ── navigation ──
  bool get _locked => widget.runner.active;

  String? get _blockedReason {
    switch (_step) {
      case 0:
        return draft.hasVideoPath ? null : 'Choose a video to continue.';
      case 1:
        return draft.selection.isEmpty ? 'Pick at least one violation.' : null;
      case 2:
        final miss = draft.missingZones;
        return miss.isEmpty
            ? null
            : 'Still needs a zone: ${miss.map((k) => ViolationCatalog.of(k).label).join(', ')}';
      default:
        return null;
    }
  }

  /// Moves to a step. Leaving the video step waits for the picture of the chosen part, if it is not there yet.
  Future<void> _go(int i) async {
    if (_step == 0 && i > 0) {
      await _framePrepared();
      if (!mounted || !draft.hasVideo) return;
    }
    _goto(i);
  }

  void _goto(int i) => setState(() {
    _step = i;
    if (i > _reached) _reached = i;
    if (i == 2) _ensureRulesKey();
  });

  void _ensureRulesKey() {
    final sel = draft.selection;
    if (sel.isEmpty) return;
    if (_rulesKey == null || !sel.contains(_rulesKey)) {
      _rulesKey = sel.firstWhere(
        (k) => !draft.zonesReady(k),
        orElse: () => sel.first,
      );
    }
  }

  /// The same zones and settings, but for the Live Monitor instead of an analysis run.
  Future<void> _useForLive() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await widget.api.useForLive(
        draft.buildConfig(activePlateModel: widget.models.active('plate')),
      );
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _start() {
    final path = draft.videoPath;
    if (path == null) return;
    widget.runner.start(
      path,
      draft.buildConfig(activePlateModel: widget.models.active('plate')),
    );
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([draft, widget.runner]),
      builder: (context, _) {
        if (_step == 2) _ensureRulesKey();
        final reason = _blockedReason;
        return LayoutBuilder(
          builder: (context, box) {
            // The rules step has its own list of violations; a second rail would only squeeze the canvas.
            final rail = box.maxWidth >= 1180 && _step != 2;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Fx.s24,
                    Fx.s16,
                    Fx.s24,
                    Fx.s16,
                  ),
                  child: _stepper(context),
                ),
                Divider(height: 1, color: Fx.border(context)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(Fx.s24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _body(context)),
                        if (rail) ...[
                          const SizedBox(width: Fx.s24),
                          SizedBox(
                            width: 290,
                            child: _SummaryRail(
                              draft: draft,
                              models: widget.models,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: Fx.border(context)),
                _footer(context, reason),
              ],
            );
          },
        );
      },
    );
  }

  Widget _stepper(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          _StepNode(
            index: i,
            label: _steps[i],
            current: i == _step,
            done: i < _step || (i < _reached && i != _step),
            enabled: !_locked && i <= _reached && (i == 0 || draft.hasVideo),
            onTap: () => _go(i),
          ),
          if (i < _steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: i < _step ? Fx.accent : Fx.border(context),
              ),
            ),
        ],
      ],
    );
  }

  Widget _body(BuildContext context) {
    final title = switch (_step) {
      0 => (
        'Choose and trim the video',
        'Watch it and keep only the part that matters. The start of that part is the picture zones are drawn on.',
      ),
      1 => (
        'What should we look for?',
        'Pick every violation to check in this video. Each one is set up in the next step.',
      ),
      2 => (
        'Set up the rules',
        'Draw the areas and set the limits each violation needs.',
      ),
      3 => (
        'Fine-tune the pipeline',
        'The defaults suit most videos. Change a setting only when you know why.',
      ),
      _ => switch (widget.runner.phase) {
        RunPhase.uploading || RunPhase.running => (
          'Analyzing the video',
          'This runs on the backend, so the dashboard stays free.',
        ),
        RunPhase.done => ('Analysis complete', 'Opening the results…'),
        RunPhase.failed => (
          'Something went wrong',
          'Your choices are kept. Adjust the settings or try again.',
        ),
        RunPhase.idle => (
          'Review and start',
          'A last look before the analysis runs.',
        ),
      },
    };
    final Widget content = switch (_step) {
      0 => VideoStep(
        draft: draft,
        player: _player,
        preparing: _preparing,
        filmstripUrl: _filmstripUrl(),
        error: _videoError,
        onPick: _pick,
        onConvert: _convert,
      ),
      1 => ViolationsStep(draft: draft, models: widget.models),
      2 => RulesStep(
        draft: draft,
        media: widget.media,
        current:
            _rulesKey ?? (draft.selection.isEmpty ? '' : draft.selection.first),
        onPick: (k) => setState(() => _rulesKey = k),
        api: widget.api,
      ),
      3 => SettingsStep(draft: draft, models: widget.models, api: widget.api),
      _ => RunStep(
        draft: draft,
        runner: widget.runner,
        models: widget.models,
        onStart: _start,
        onUseForLive: _useForLive,
        onOpenLive: widget.onOpenLive == null || widget.runner.taskId == null
            ? null
            : () => widget.onOpenLive!(widget.runner.taskId!),
        onBackToSettings: () {
          widget.runner.clear();
          _goto(3);
        },
      ),
    };
    final scrolls = _step == 0 || _step == 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.$1, style: Fx.title(context)),
        const SizedBox(height: 4),
        Text(title.$2, style: Fx.caption(context)),
        const SizedBox(height: Fx.s16),
        Expanded(
          child: scrolls
              ? SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _centered(content),
                  ),
                )
              : content,
        ),
      ],
    );
  }

  /// Single-column steps stay at a comfortable reading width.
  Widget _centered(Widget child) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 880),
      child: child,
    ),
  );

  Widget _footer(BuildContext context, String? reason) {
    final last = _step == _steps.length - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s24, vertical: Fx.s12),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: (_step == 0 || _locked) ? null : () => _goto(_step - 1),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back'),
          ),
          const Spacer(),
          if (reason != null && !last)
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Fx.warning),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      reason,
                      style: Fx.caption(context),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Fx.s16),
                ],
              ),
            ),
          if (!last)
            FilledButton.icon(
              onPressed: (reason == null && !_preparing)
                  ? () => _go(_step + 1)
                  : null,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text(_step == 3 ? 'Review' : 'Continue'),
              iconAlignment: IconAlignment.end,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            ),
        ],
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.index,
    required this.label,
    required this.current,
    required this.done,
    required this.enabled,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool current;
  final bool done;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = current ? Fx.accent : (done ? Fx.success : Fx.muted(context));
    return InkWell(
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      onTap: enabled && !current ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: current
                  ? Fx.accent
                  : (done ? Fx.success : Colors.transparent),
              child: done && !current
                  ? const Icon(Icons.check, size: 16, color: Colors.black87)
                  : Container(
                      decoration: current
                          ? null
                          : BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: color),
                            ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: current ? Colors.white : color,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                color: current ? null : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What has been chosen so far, always in view, so nothing has to be remembered.
class _SummaryRail extends StatelessWidget {
  const _SummaryRail({required this.draft, required this.models});

  final AnalysisDraft draft;
  final ModelChoices models;

  @override
  Widget build(BuildContext context) {
    final sel = draft.selection;
    return SingleChildScrollView(
      child: FxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YOUR ANALYSIS', style: Fx.label(context)),
            const SizedBox(height: Fx.s12),
            _item(
              context,
              Icons.video_file_outlined,
              draft.hasVideo ? (draft.videoName ?? 'Video') : 'No video yet',
              draft.hasVideo
                  ? '${draft.fps.toStringAsFixed(0)} fps${draft.frameCount > 0 ? ' · ${draft.frameCount} frames' : ''}${draft.trimmed ? ' · ${draft.keptSeconds.toStringAsFixed(0)} s of ${draft.duration.toStringAsFixed(0)} s' : ''}'
                  : null,
              ok: draft.hasVideo,
            ),
            const Divider(height: Fx.s24),
            Text(
              'Violations (${sel.length})',
              style: Fx.body(context).copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Fx.s8),
            if (sel.isEmpty)
              Text('None picked yet.', style: Fx.caption(context))
            else
              for (final k in sel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        ViolationCatalog.of(k).icon,
                        size: 16,
                        color: ViolationCatalog.of(k).color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ViolationCatalog.of(k).label,
                          style: Fx.body(context),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ViolationCatalog.of(k).needsZone)
                        Tooltip(
                          message: draft.zonesReady(k)
                              ? '${draft.zones(k).length} zone(s) saved${AnalysisDraft.signZoneKeys.contains(k) && draft.signCount(k) > 0 ? ', ${draft.signCount(k)} sign(s) placed' : ''}'
                              : 'Needs a zone',
                          child: Icon(
                            draft.zonesReady(k)
                                ? Icons.check_circle
                                : Icons.error_outline,
                            size: 16,
                            color: draft.zonesReady(k)
                                ? Fx.success
                                : Fx.warning,
                          ),
                        ),
                    ],
                  ),
                ),
            const Divider(height: Fx.s24),
            _kv(
              context,
              'Tracker',
              draft.settings.tracker == 'deepsort' ? 'DeepSORT' : 'ByteTrack',
            ),
            _kv(
              context,
              'Plate model',
              draft.settings.plateModel.isEmpty
                  ? (models.active('plate') ?? 'active')
                  : draft.settings.plateModel,
            ),
            _kv(
              context,
              'Evidence',
              'every ${draft.settings.evidenceGap} frames',
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String title,
    String? sub, {
    required bool ok,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: ok ? Fx.success : Fx.muted(context)),
      const SizedBox(width: Fx.s8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Fx.body(context).copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            if (sub != null) Text(sub, style: Fx.caption(context)),
          ],
        ),
      ),
    ],
  );

  Widget _kv(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(k, style: Fx.caption(context)),
        const Spacer(),
        Flexible(
          child: Text(
            v,
            style: Fx.body(context),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
