import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../forensic/data/forensic_api.dart';
import '../../../forensic/data/forensic_media.dart';
import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../../forensic/presentation/widgets/wizard_steps.dart';
import '../../data/camera_api.dart';
import '../../domain/live_setup_draft.dart';
import '../../domain/models/road_detect.dart';
import '../widgets/frame_picker_step.dart';
import '../widgets/road_markings_panel.dart';
import '../widgets/setup_layers_dialog.dart';

/// What the setup hands back when it was opened with `deferApply`: the rules to send, and how many violations they switch on. The Live
/// Monitor sends them itself, behind its "Processing" view, so the operator is back on the monitor the moment Apply is pressed.
class LiveSetupPending {
  const LiveSetupPending(this.config, this.count);
  final Map<String, dynamic> config;
  final int count;
}

/// "Set up violations" of the Live Monitor: the Forensic Analyzer's own steps (the same violations, zones and settings), drawn on ONE
/// picture of the source. Apply sends them to the Live Monitor.
///
/// Two ways in:
///  - the feed is running: [shot] is the picture that was just frozen from it, and the steps start at Violations;
///  - [chooseFrame] (Start was pressed, nothing plays yet): a first step collects pictures of the source (a file: spread over the video;
///    a camera: one a second) and the operator picks one.
///
/// Pops with the number of violations that are now on, or null when it was closed without applying.
class LiveSetupScreen extends StatefulWidget {
  const LiveSetupScreen({
    super.key,
    required this.cameraApi,
    this.shot,
    this.chooseFrame = false,
    this.deferApply = false,
    this.api,
    this.media = const ForensicMedia(),
  }) : assert(chooseFrame || shot != null, 'Give the frozen picture, or let the operator choose one');

  final CameraApi cameraApi;

  /// What [CameraApi.captureReference] answered: version, width, height, fps of the frozen picture. Null with [chooseFrame].
  final Map<String, dynamic>? shot;
  final bool chooseFrame;

  /// Apply does not wait for the backend: the screen closes at once and pops a [LiveSetupPending] for the caller to send.
  final bool deferApply;
  final ForensicApi? api;
  final ForensicMedia media;

  @override
  State<LiveSetupScreen> createState() => _LiveSetupScreenState();
}

class _LiveSetupScreenState extends State<LiveSetupScreen> {
  late final List<String> _steps = widget.chooseFrame
      ? const ['Frame', 'Road', 'Violations', 'Rules & zones', 'Settings', 'Apply']
      : const ['Violations', 'Rules & zones', 'Settings', 'Apply'];      // the monitor runs: only the violations are edited, the road stays

  late final ForensicApi _api = widget.api ?? ForensicApi();
  final LiveSetupDraft _draft = LiveSetupDraft();
  ModelChoices _models = ModelChoices.empty;
  int _step = 0;
  int _reached = 0;
  String? _rulesKey;
  bool _loading = true;       // the current live setup is being read
  bool _hadSetup = false;     // a live setup existed and was loaded
  bool _applying = false;
  String? _error;

  Map<String, dynamic> _saved = const {};   // what the Live Monitor uses now
  late final Future<void> _savedLoad;
  int? _pickedFrame;                        // the picture picked in the Frame step
  bool _busyFrame = false;
  String? _frameError;

  String get _stepName => _steps[_step];

  @override
  void initState() {
    super.initState();
    _savedLoad = _loadSaved();
    _loadModels();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    final models = await _api.models();
    if (mounted) setState(() => _models = models);
  }

  /// A new setup (Start was pressed) starts EMPTY: nothing of the last one comes back (a road to use again is kept under "Saved roads").
  /// While the monitor runs ([chooseFrame] is false) the screen EDITS the violations it watches now: they and the road markings are loaded.
  Future<void> _loadSaved() async {
    if (!widget.chooseFrame) {
      try {
        _saved = await widget.cameraApi.liveSetup();
      } catch (_) {}
    }
    if (!mounted) return;
    if (!widget.chooseFrame) _attachFrame(widget.shot!);     // the picture is already frozen
    setState(() => _loading = false);
  }

  /// A frozen picture becomes the one the steps work on. The first time it also brings back the current live setup; a second
  /// pick (the operator went back to the Frame step) only changes the picture and keeps every choice.
  void _attachFrame(Map<String, dynamic> shot) {
    final url = widget.cameraApi.referenceFrameUrl((shot['version'] as num?)?.toInt() ?? 0);
    final fps = (shot['fps'] as num?)?.toDouble();
    if (_draft.hasVideo) {
      _draft.setFrame(url: url, seconds: 0, fps: fps);
    } else {
      _draft.setVideo(path: 'live', name: 'Live camera', frame: url, fps: fps);   // setVideo starts empty ...
      _applySaved(_saved);                                                           // ... so the current setup comes back here
    }
  }

  void _applySaved(Map<String, dynamic> saved) {
    final s = _draft.settings;
    String pick(String key, List<String> allowed, String fallback) {
      final v = saved[key];
      return v is String && allowed.contains(v) ? v : fallback;
    }

    s.tracker = pick('tracker', const ['bytetrack', 'deepsort'], 'deepsort');   // ByteTrack leaves most boxes of a real clip without an ID
    s.plateMethod = pick('plate_method', const ['smart', 'direct_ocr'], s.plateMethod);
    s.plateFormat = pick('plate_format', const ['ph_standard', 'uk_standard', 'raw'], s.plateFormat);
    s.ocrEngine = pick('ocr_engine', const ['easyocr', 'paddleocr'], s.ocrEngine);
    s.enhancement = pick('enhancement', const ['realesrgan', 'lanczos', 'lapsrn', 'none'], s.enhancement);
    if (saved['use_sahi'] is bool) s.useSahi = saved['use_sahi'] as bool;
    if (saved['blur_privacy'] is bool) s.blurPrivacy = saved['blur_privacy'] as bool;
    if (saved['flag_sensitivity'] is num) s.flagSensitivity = (saved['flag_sensitivity'] as num).round().clamp(1, 7);
    if (saved['evidence_gap'] is num) s.evidenceGap = (saved['evidence_gap'] as num).round().clamp(1, 5);

    final offered = {for (final v in ViolationCatalog.selectable) v.key};
    final per = saved['per_violation_configs'];
    for (final raw in (saved['active_violations'] as List? ?? const [])) {
      final key = '$raw';
      if (!offered.contains(key)) continue;                     // a rule this dashboard does not offer (any more)
      _hadSetup = true;
      _draft.toggle(key, on: true);
      if (per is Map && per[key] is Map) {
        final copy = Map<String, dynamic>.from(jsonDecode(jsonEncode(per[key])) as Map);
        _draft.config(key)
          ..clear()
          ..addAll(copy);
      }
      _draft.rememberPulled(key);                               // zones that came from markings may be refreshed by a new sync
    }
    final marks = saved['road_markings'];
    if (marks is List) {
      _draft.markings = [for (final m in marks) if (m is Map) RoadArea.fromJson(Map<String, dynamic>.from(m))];
    }
    _draft.touch();
  }

  // ── navigation ──
  String? get _blockedReason => switch (_stepName) {
    'Frame' => _pickedFrame == null ? 'Wait for the first picture, then pick one.' : null,
    'Violations' => _draft.selection.isEmpty ? 'Pick at least one violation.' : null,
    'Rules & zones' => _draft.missingZones.isEmpty ? null : 'Still needs a zone: ${_draft.missingZones.map((k) => ViolationCatalog.of(k).label).join(', ')}',
    _ => null,
  };

  void _goto(int i) => setState(() {
    if (i > _step && _stepName == 'Violations') _draft.syncMarkings();   // the picked violations take the markings they need (also those picked before)
    _step = i;
    if (i > _reached) _reached = i;
    if (_stepName == 'Rules & zones') _ensureRulesKey();
  });

  void _ensureRulesKey() {
    final sel = _draft.selection;
    if (sel.isEmpty) return;
    if (_rulesKey == null || !sel.contains(_rulesKey)) {
      _rulesKey = sel.firstWhere((k) => !_draft.zonesReady(k), orElse: () => sel.first);
    }
  }

  /// "Show layers": the picture with the road markings, zones and overlay signs, and a checklist of what to show.
  void _showLayers() {
    final url = _draft.frameUrl;
    if (url == null) return;
    showDialog<void>(context: context, builder: (_) => SetupLayersDialog(draft: _draft, frame: widget.media.frame(url), api: _api));
  }

  /// Frame step, Continue: the picked picture becomes the setup picture, then on to the violations.
  Future<void> _useFrame() async {
    final id = _pickedFrame;
    if (id == null || _busyFrame) return;
    setState(() {
      _busyFrame = true;
      _frameError = null;
    });
    try {
      await _savedLoad;
      final shot = await widget.cameraApi.useFrame(id);
      if (shot['ok'] != true) throw Exception('${shot['reason'] ?? 'That picture could not be used.'}');
      if (!mounted) return;
      _attachFrame(shot);
      _goto(_step + 1);
    } catch (e) {
      if (mounted) setState(() => _frameError = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busyFrame = false);
    }
  }

  Future<void> _apply() async {
    final config = _draft.buildConfig(activePlateModel: _models.active('plate'));
    if (widget.deferApply) {
      Navigator.of(context).pop(LiveSetupPending(config, _draft.selection.length));
      return;
    }
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await _api.useForLive(config);
      if (mounted) Navigator.of(context).pop(_draft.selection.length);
    } catch (e) {
      if (mounted) {
        setState(() {
          _applying = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Fx.page(context),
      appBar: AppBar(
        title: Text(widget.chooseFrame ? 'Set up violations' : 'Edit violations'),
        leading: IconButton(
          tooltip: 'Close without changes',
          icon: const Icon(Icons.close),
          onPressed: _applying ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: _draft,
              builder: (context, _) {
                if (_stepName == 'Rules & zones') _ensureRulesKey();
                return Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(Fx.s16, Fx.s8, Fx.s16, Fx.s8), child: _stepper(context)),
                  Divider(height: 1, color: Fx.border(context)),
                  Expanded(child: Padding(padding: const EdgeInsets.all(Fx.s12), child: _body(context))),
                  Divider(height: 1, color: Fx.border(context)),
                  _footer(context),
                ]);
              },
            ),
    );
  }

  Widget _stepper(BuildContext context) {
    return Row(children: [
      Tooltip(
        key: const ValueKey('step-info'),
        richMessage: TextSpan(children: [
          TextSpan(text: '${_stepInfo.$1}\n', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: _stepInfo.$2),
        ]),
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(padding: const EdgeInsets.only(right: Fx.s12), child: Icon(Icons.info_outline, size: 20, color: Fx.muted(context))),
      ),
      for (var i = 0; i < _steps.length; i++) ...[
        InkWell(
          borderRadius: BorderRadius.circular(Fx.radiusSm),
          onTap: (i <= _reached && i != _step && !_applying && !_busyFrame) ? () => _goto(i) : null,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: i == _step ? Fx.accent : (i < _step ? Fx.success : Colors.transparent),
                child: i < _step
                    ? const Icon(Icons.check, size: 16, color: Colors.black87)
                    : Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i == _step ? Colors.white : Fx.muted(context))),
              ),
              const SizedBox(width: 8),
              Text(_steps[i], style: TextStyle(fontWeight: i == _step ? FontWeight.w700 : FontWeight.w500, color: i == _step ? null : Fx.muted(context))),
            ]),
          ),
        ),
        if (i < _steps.length - 1)
          Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 8), color: i < _step ? Fx.accent : Fx.border(context))),
      ],
    ]);
  }

  /// What the step is for: (title, hint). It is a hover note beside the steps, so the picture can have the room.
  (String, String) get _stepInfo => switch (_stepName) {
      'Frame' => ('Pick a picture of the video', 'The violations are set up on this one picture. Pictures appear while they are collected: pick one at any time.'),
      'Road' => ('Set up the road', 'Mark the road once, on this picture: crosswalks, lines, lanes, direction. Let the system find it, then correct it. Each violation you pick next takes only what it needs.'),
      'Violations' => ('What should the monitor look for?', _hadSetup ? 'Your current live setup is loaded. Change it as you need.' : 'Pick every violation to watch. Each one is set up in the next step.'),
      'Rules & zones' => ('Set up the rules', 'Draw each area on this picture, and set the limits. A rule marked as needing no drawing watches the whole picture.'),
      'Settings' => ('Fine-tune the pipeline', 'The defaults suit most cameras. Change a setting only when you know why.'),
      _ => ('Review and apply', widget.chooseFrame ? 'Monitoring starts as soon as you apply.' : 'The live picture restarts for a few seconds with the new rules, then goes on.'),
  };

  Widget _body(BuildContext context) {
    // The Frame step stays alive (hidden) behind the other steps, so going back to it does not collect new pictures.
    final Widget? picker = widget.chooseFrame
        ? Offstage(
            offstage: _stepName != 'Frame',
            child: Column(children: [
              Expanded(
                child: FramePickerStep(
                  key: const ValueKey('frame-picker'),
                  api: widget.cameraApi,
                  onPicked: (id) => setState(() => _pickedFrame = id),
                ),
              ),
              if (_frameError != null) ...[const SizedBox(height: Fx.s8), FxBanner(message: _frameError!)],
            ]),
          )
        : null;
    final Widget? content = switch (_stepName) {
      'Frame' => null,
      'Road' => RoadMarkingsPanel(
        key: const ValueKey('road-panel'),
        cameraApi: widget.cameraApi,
        markings: _draft.markings,
        onChanged: _draft.setMarkings,       // the violations that are picked already take what they need at once
      ),
      'Violations' => ViolationsStep(draft: _draft, models: _models),
      'Rules & zones' => RulesStep(
        draft: _draft,
        media: widget.media,
        current: _rulesKey ?? (_draft.selection.isEmpty ? '' : _draft.selection.first),
        onPick: (k) => setState(() => _rulesKey = k),
        api: _api,                                    // the realistic overlay objects (hydrant, signs, painted lines) are drawn by the backend
      ),
      'Settings' => SettingsStep(draft: _draft, models: _models),
      _ => _review(context),
    };
    return Stack(fit: StackFit.expand, children: [?picker, ?content]);
  }

  Widget _review(BuildContext context) {
    final sel = _draft.selection;
    final s = _draft.settings;
    final flow = _draft.learnsFlow;
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FxCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('VIOLATIONS (${sel.length})', style: Fx.label(context)),
                const SizedBox(height: Fx.s8),
                for (final k in sel)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Icon(ViolationCatalog.of(k).icon, size: 16, color: ViolationCatalog.of(k).color),
                      const SizedBox(width: 8),
                      Expanded(child: Text(ViolationCatalog.of(k).label, style: Fx.body(context))),
                      Text(_zoneNote(k), style: Fx.caption(context)),
                    ]),
                  ),
                const Divider(height: Fx.s24),
                Text('Tracker: ${s.tracker == 'deepsort' ? 'DeepSORT' : 'ByteTrack'}   ·   Plate format: ${s.plateFormat}   ·   Evidence: every ${s.evidenceGap} frames', style: Fx.caption(context)),
              ]),
            ),
            if (flow) ...[
              const SizedBox(height: Fx.s12),
              const FxBanner(
                color: Fx.warning,
                icon: Icons.info_outline,
                message: 'Counterflow, parking, loading and blocking the junction learn the traffic by watching. They judge only after the camera has seen enough traffic.',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Fx.s12),
              FxBanner(message: _error!),
            ],
            const SizedBox(height: Fx.s16),
            FilledButton.icon(
              key: const ValueKey('live-setup-apply'),
              onPressed: _applying || sel.isEmpty ? null : _apply,
              icon: _applying ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
              label: Text(_applying ? 'Applying…' : (widget.chooseFrame ? 'Apply and start monitoring' : 'Apply to the Live Monitor')),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 28)),
            ),
          ]),
        ),
      ),
    );
  }

  String _zoneNote(String key) {
    if (!ViolationCatalog.of(key).needsZone) return 'no zone needed';
    final zones = _draft.zones(key).length;
    if (zones > 0) return '$zones zone${zones == 1 ? '' : 's'}';
    if (_draft.watchesWholePicture(key)) return 'whole picture';
    return 'set up';
  }

  Widget _footer(BuildContext context) {
    final reason = _blockedReason;
    final last = _step == _steps.length - 1;
    final onFrame = _stepName == 'Frame';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s16, vertical: Fx.s8),
      child: Row(children: [
        TextButton.icon(
          onPressed: (_step == 0 || _applying || _busyFrame) ? null : () => _goto(_step - 1),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back'),
        ),
        if (!onFrame && _stepName != 'Road' && _draft.frameUrl != null)
          Padding(
            padding: const EdgeInsets.only(left: Fx.s8),
            child: OutlinedButton.icon(
              key: const ValueKey('show-layers'),
              onPressed: _showLayers,
              icon: const Icon(Icons.layers_outlined, size: 18),
              label: const Text('Show layers'),
            ),
          ),
        const Spacer(),
        if (reason != null && !last)
          Flexible(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.info_outline, size: 16, color: Fx.warning),
              const SizedBox(width: 6),
              Flexible(child: Text(reason, style: Fx.caption(context), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: Fx.s16),
            ]),
          ),
        if (!last)
          FilledButton.icon(
            key: const ValueKey('live-setup-continue'),
            onPressed: (reason == null && !_busyFrame) ? (onFrame ? _useFrame : () => _goto(_step + 1)) : null,
            icon: _busyFrame ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_forward, size: 16),
            label: Text(onFrame ? 'Use this picture' : (_stepName == 'Settings' ? 'Review' : (_stepName == 'Road' && _draft.markings.isEmpty ? 'Skip' : 'Continue'))),
            iconAlignment: IconAlignment.end,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
      ]),
    );
  }
}
