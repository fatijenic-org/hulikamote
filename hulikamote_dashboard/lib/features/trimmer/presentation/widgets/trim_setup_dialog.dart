import 'package:flutter/material.dart';

import '../../../forensic/data/forensic_api.dart';
import '../../../forensic/data/forensic_media.dart';
import '../../../forensic/domain/analysis_draft.dart';
import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../../forensic/presentation/widgets/wizard_steps.dart';
import '../../../monitoring/data/camera_api.dart';

/// Set up the violations of a video by hand, inside the trimmer: pick the violations, then draw their zones and place their signs on a
/// picture of the open video (the same editors as the Forensic Analyzer and the Live Monitor). The result is saved as a named setup in
/// the SAME list the Live Monitor uses, so it can be picked again there (and a Live Monitor setup can be picked here). Returns the id of
/// the saved setup, or null when the person closed the dialog.
Future<String?> showTrimSetupDialog(BuildContext context, {required String videoPath, required String videoName, double seconds = 0}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TrimSetupDialog(videoPath: videoPath, videoName: videoName, seconds: seconds),
  );
}

class TrimSetupDialog extends StatefulWidget {
  const TrimSetupDialog({super.key, required this.videoPath, required this.videoName, this.seconds = 0, this.api, this.cameraApi});

  final String videoPath;
  final String videoName;

  /// The time of the picture the zones are drawn on.
  final double seconds;
  final ForensicApi? api;
  final CameraApi? cameraApi;

  @override
  State<TrimSetupDialog> createState() => _TrimSetupDialogState();
}

class _TrimSetupDialogState extends State<TrimSetupDialog> {
  late final ForensicApi _api = widget.api ?? ForensicApi();
  late final CameraApi _camera = widget.cameraApi ?? CameraApi();
  final _draft = AnalysisDraft();
  final _name = TextEditingController();
  ModelChoices _models = ModelChoices.empty;
  String? _rulesKey;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  int _tab = 0; // 0 violations, 1 rules & zones

  @override
  void initState() {
    super.initState();
    _name.text = '${widget.videoName.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')} setup';
    _draft.chooseVideo(path: widget.videoPath, name: widget.videoName);
    _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _models = await _api.models();
      FrameInfo? info;
      try {
        info = await _api.videoFrame(widget.videoPath, seconds: widget.seconds);
      } catch (_) {
        info = null;
      }
      info ??= await _api.extractFrame(widget.videoPath);
      if (!mounted) return;
      _draft.setFrame(url: info.url, seconds: widget.seconds, fps: info.fps, frames: info.frames, duration: info.duration);
      _error = null;
    } catch (e) {
      _error = 'Could not read a picture of that video: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _go(int tab) {
    setState(() {
      _tab = tab;
      final sel = _draft.selection;
      if (tab == 1 && sel.isNotEmpty && (_rulesKey == null || !sel.contains(_rulesKey))) {
        _rulesKey = sel.firstWhere((k) => !_draft.zonesReady(k), orElse: () => sel.first);
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the setup a name.');
      return;
    }
    if (_draft.selection.isEmpty) {
      setState(() => _error = 'Pick at least one violation.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await _camera.saveSetupPreset(name, _draft.buildConfig(activePlateModel: _models.active('plate')), videoName: widget.videoName);
      if (mounted) Navigator.of(context).pop(saved.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: size.width.clamp(0, 1280),
        height: size.height.clamp(0, 860),
        child: Padding(
          padding: const EdgeInsets.all(Fx.s16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Set up the violations of ${widget.videoName}', style: Fx.title(context))),
              IconButton(tooltip: 'Close without saving', icon: const Icon(Icons.close), onPressed: _saving ? null : () => Navigator.of(context).pop()),
            ]),
            Text(
              'Pick the violations, then draw their zones and place their signs. Saved under a name: the Live Monitor lists it too, and you pick it '
              'in the export panel to score the clips inside these zones.',
              style: Fx.caption(context),
            ),
            const SizedBox(height: Fx.s8),
            SegmentedButton<int>(
              key: const ValueKey('trim-setup-tabs'),
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 0, label: Text('1  Violations')), ButtonSegment(value: 1, label: Text('2  Rules & zones'))],
              selected: {_tab},
              onSelectionChanged: (v) => _go(v.first),
            ),
            const SizedBox(height: Fx.s8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListenableBuilder(
                      listenable: _draft,
                      builder: (context, _) => _tab == 0
                          ? ViolationsStep(draft: _draft, models: _models)
                          : _draft.selection.isEmpty
                              ? Center(child: Text('Pick at least one violation first.', style: Fx.caption(context)))
                              : RulesStep(
                                  draft: _draft,
                                  media: const ForensicMedia(),
                                  current: _rulesKey ?? _draft.selection.first,
                                  onPick: (k) => setState(() => _rulesKey = k),
                                ),
                    ),
            ),
            const SizedBox(height: Fx.s8),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))),
            ListenableBuilder(
              listenable: _draft,
              builder: (context, _) {
                final missing = _draft.missingZones;
                return Row(children: [
                  Expanded(
                    child: Text(
                      missing.isEmpty ? '${_draft.selection.length} violation${_draft.selection.length == 1 ? '' : 's'} set up' : 'Still needs a zone: ${missing.map((k) => ViolationCatalog.of(k).label).join(', ')}',
                      style: Fx.caption(context),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      key: const ValueKey('trim-setup-name'),
                      controller: _name,
                      decoration: const InputDecoration(isDense: true, labelText: 'Name of the setup', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: Fx.s8),
                  FilledButton.icon(
                    key: const ValueKey('trim-setup-save'),
                    onPressed: _saving || _loading ? null : _save,
                    icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save setup'),
                  ),
                ]);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
