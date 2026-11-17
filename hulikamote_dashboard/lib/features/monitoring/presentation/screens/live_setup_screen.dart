import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../forensic/data/forensic_api.dart';
import '../../../forensic/data/forensic_media.dart';
import '../../../forensic/domain/analysis_draft.dart';
import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../../forensic/presentation/widgets/wizard_steps.dart';
import '../../data/camera_api.dart';

/// The violations picked on a live picture. A live camera has no recording to search, so a solid line cannot be
/// "found in the video when the analysis starts": it must be drawn.
class LiveSetupDraft extends AnalysisDraft {
  @override
  bool get isLive => true;

  @override
  bool findsLinesItself(String key) => false;

  /// The solid-line editor's "find the lines automatically" switch starts OFF on a live picture.
  @override
  Map<String, dynamic> config(String key) {
    final cfg = super.config(key);
    if (key == 'crossing_solid_line') cfg.putIfAbsent('auto_lines', () => false);
    return cfg;
  }
}

/// "Set up violations" of the Live Monitor: the Forensic Analyzer's own steps (the same violations, zones and settings),
/// drawn on ONE frozen picture of the running camera. Apply sends them to the Live Monitor, which goes on with the new rules.
/// Pops with the number of violations that are now on, or null when it was closed without applying.
class LiveSetupScreen extends StatefulWidget {
  const LiveSetupScreen({super.key, required this.cameraApi, required this.shot, this.api, this.media = const ForensicMedia()});

  final CameraApi cameraApi;

  /// What [CameraApi.captureReference] answered: version, width, height, fps of the frozen picture.
  final Map<String, dynamic> shot;
  final ForensicApi? api;
  final ForensicMedia media;

  @override
  State<LiveSetupScreen> createState() => _LiveSetupScreenState();
}

class _LiveSetupScreenState extends State<LiveSetupScreen> {
  static const _steps = ['Violations', 'Rules & zones', 'Settings', 'Apply'];

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

  @override
  void initState() {
    super.initState();
    final shot = widget.shot;
    _draft.setVideo(
      path: 'live',
      name: 'Live camera',
      frame: widget.cameraApi.referenceFrameUrl((shot['version'] as num?)?.toInt() ?? 0),
      fps: (shot['fps'] as num?)?.toDouble(),
    );
    _loadSaved();
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

  /// Opens with what the Live Monitor uses now, so a second setup changes it instead of starting from nothing.
  Future<void> _loadSaved() async {
    Map<String, dynamic> saved = {};
    try {
      saved = await widget.cameraApi.liveSetup();
    } catch (_) {}
    if (!mounted) return;
    _applySaved(saved);
    setState(() => _loading = false);
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
    }
    _draft.touch();
  }

  // ── navigation ──
  String? get _blockedReason => switch (_step) {
    0 => _draft.selection.isEmpty ? 'Pick at least one violation.' : null,
    1 => _draft.missingZones.isEmpty ? null : 'Still needs a zone: ${_draft.missingZones.map((k) => ViolationCatalog.of(k).label).join(', ')}',
    _ => null,
  };

  void _goto(int i) => setState(() {
    _step = i;
    if (i > _reached) _reached = i;
    if (i == 1) _ensureRulesKey();
  });

  void _ensureRulesKey() {
    final sel = _draft.selection;
    if (sel.isEmpty) return;
    if (_rulesKey == null || !sel.contains(_rulesKey)) {
      _rulesKey = sel.firstWhere((k) => !_draft.zonesReady(k), orElse: () => sel.first);
    }
  }

  Future<void> _apply() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await _api.useForLive(_draft.buildConfig(activePlateModel: _models.active('plate')));
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
        title: const Text('Set up violations on the live camera'),
        leading: IconButton(
          tooltip: 'Back to the live picture',
          icon: const Icon(Icons.close),
          onPressed: _applying ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: _draft,
              builder: (context, _) {
                if (_step == 1) _ensureRulesKey();
                return Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(Fx.s24, Fx.s12, Fx.s24, Fx.s12), child: _stepper(context)),
                  Divider(height: 1, color: Fx.border(context)),
                  Expanded(child: Padding(padding: const EdgeInsets.all(Fx.s24), child: _body(context))),
                  Divider(height: 1, color: Fx.border(context)),
                  _footer(context),
                ]);
              },
            ),
    );
  }

  Widget _stepper(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < _steps.length; i++) ...[
        InkWell(
          borderRadius: BorderRadius.circular(Fx.radiusSm),
          onTap: (i <= _reached && i != _step && !_applying) ? () => _goto(i) : null,
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

  Widget _body(BuildContext context) {
    final title = switch (_step) {
      0 => ('What should the live camera look for?', _hadSetup ? 'Your current live setup is loaded. Change it as you need.' : 'Pick every violation to watch. Each one is set up in the next step.'),
      1 => ('Set up the rules', 'Draw each area on this picture of the live camera, and set the limits. A rule marked as needing no drawing watches the whole picture.'),
      2 => ('Fine-tune the pipeline', 'The defaults suit most cameras. Change a setting only when you know why.'),
      _ => ('Review and apply', 'The live picture restarts for a few seconds with the new rules, then goes on.'),
    };
    final Widget content = switch (_step) {
      0 => ViolationsStep(draft: _draft, models: _models),
      1 => RulesStep(
        draft: _draft,
        media: widget.media,
        current: _rulesKey ?? (_draft.selection.isEmpty ? '' : _draft.selection.first),
        onPick: (k) => setState(() => _rulesKey = k),
      ),
      2 => SettingsStep(draft: _draft, models: _models),
      _ => _review(context),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title.$1, style: Fx.title(context)),
      const SizedBox(height: 4),
      Text(title.$2, style: Fx.caption(context)),
      const SizedBox(height: Fx.s16),
      Expanded(child: content),
    ]);
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
              label: Text(_applying ? 'Applying…' : 'Apply to the Live Monitor'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s24, vertical: Fx.s12),
      child: Row(children: [
        TextButton.icon(
          onPressed: (_step == 0 || _applying) ? null : () => _goto(_step - 1),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back'),
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
            onPressed: reason == null ? () => _goto(_step + 1) : null,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(_step == 2 ? 'Review' : 'Continue'),
            iconAlignment: IconAlignment.end,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
      ]),
    );
  }
}
