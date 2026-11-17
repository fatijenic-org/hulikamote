import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../forensic/data/harvest_labeling.dart';
import '../../../forensic/data/harvest_source.dart';
import '../../../forensic/domain/harvest_labeling_models.dart';
import '../../../forensic/domain/harvest_models.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../../forensic/presentation/widgets/harvest_labeler.dart';

/// Where the pictures of every analysis are saved by default: the backend's evidence folder.
String? defaultEvidenceFolder() {
  final lab = LocalHarvestSource().findLab();
  if (lab == null) return null;
  return '${Directory(lab).parent.path}/hulikamote_backend/snapshots/evidence'.replaceAll('\\', '/');
}

/// Which personal details may be blurred for each model: a model never loses its own target.
({bool heads, bool plates, String? note}) piiAllowed(String model) => switch (model) {
      'plate_specialist' => (heads: true, plates: false, note: 'Plates stay readable: this model learns plates.'),
      'helmet_specialist' => (heads: false, plates: true, note: 'Heads stay visible: this model learns from the rider\'s head.'),
      'cabin_specialist' => (heads: true, plates: true, note: 'Check pictures where a driver holds a phone: a blurred head can hide it.'),
      _ => (heads: true, plates: true, note: null),
    };

/// Label EVERY picture of a folder for one model, then write a clean dataset (and move the pictures) to any folder,
/// an external drive too. The labelling screen is the one of the Forensic Analyzer's Harvest.
class LabellerScreen extends StatefulWidget {
  const LabellerScreen({super.key, this.labeling, this.defaultFolder, this.pickFolder});

  final FolderLabelling? labeling;
  final String? defaultFolder;

  /// Asks the person for a folder (tests pass a stand-in).
  final Future<String?> Function()? pickFolder;

  @override
  State<LabellerScreen> createState() => _LabellerScreenState();
}

class _LabellerScreenState extends State<LabellerScreen> {
  late final FolderLabelling _l = widget.labeling ?? LocalHarvestLabeling();
  late final TextEditingController _folder = TextEditingController(text: widget.defaultFolder ?? defaultEvidenceFolder() ?? '');
  final TextEditingController _dest = TextEditingController();

  List<LabelModelInfo> _models = const [];
  int _sel = 0;
  String? _task;
  HarvestCounts? _counts;
  LabellerStatus? _scan;
  LabellerStatus? _export;
  bool _predraw = true;
  bool _blurHeads = true;
  bool _blurPlates = true;
  String? _busyText;
  String? _error;

  LabelModelInfo? get _model => _sel < _models.length ? _models[_sel] : null;
  bool get _busy => _busyText != null;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
    _folder.dispose();
    _dest.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final s = await _l.session(null);
      if (mounted) setState(() => _models = s.models);
    } on HarvestLabelingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Runs one step with a "working" line; a failure becomes the red line instead of a crash.
  Future<void> _run(String working, Future<void> Function() step) async {
    setState(() {
      _busyText = working;
      _error = null;
    });
    try {
      await step();
    } on HarvestLabelingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyText = null);
    }
  }

  Future<String?> _pick() => widget.pickFolder != null ? widget.pickFolder!() : FilePicker.getDirectoryPath();

  Future<void> _refresh() async {
    final m = _model, t = _task;
    if (m == null || t == null) return;
    final s = await _l.folderStatus(m.key, t);
    if (mounted) setState(() => _counts = s.counts);
  }

  Future<void> _scanFolder() => _run('Looking at every picture in the folder. A big folder takes a minute...', () async {
        final m = _model;
        if (m == null) return;
        final s = await _l.scanFolder(m.key, _folder.text.trim());
        _task = s.task;
        _scan = s;
        _export = null;
        await _refresh();
      });

  Future<void> _start() async {
    final m = _model, t = _task;
    if (m == null || t == null) return;
    final allowed = piiAllowed(m.key);
    final heads = _blurHeads && allowed.heads, plates = _blurPlates && allowed.plates;
    if (_predraw || heads || plates) {
      await _run('Drawing the first guesses with the ${m.title} model...', () => _l.predraw(m.key, t, heads: heads, plates: plates));
    }
    if (!mounted || _error != null) return;
    await openHarvestLabeler(context, labeling: _l, model: m, taskId: t);
    await _run('Updating the numbers...', _refresh);
  }

  Future<void> _exportAndMove() async {
    final m = _model, t = _task, ready = _counts?.ready ?? 0;
    if (m == null || t == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move the finished pictures?'),
        content: Text(
          '$ready finished pictures will be MOVED out of the folder into\n${_dest.text.trim()}/${m.key}\n\n'
          'The folder will not have them any more. Tickets that used those photos lose them in the review screens. '
          'Pictures you did not finish stay where they are.',
        ),
        actions: [
          TextButton(key: const Key('labeller-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('labeller-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Move them')),
        ],
      ),
    );
    if (sure != true) return;
    await _run('Writing the dataset and moving the pictures...', () async {
      _export = await _l.exportFolder(m.key, t, _dest.text.trim());
      await _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    final m = _model;
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Fx.s24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Labeller', style: Fx.title(context)),
                const SizedBox(height: Fx.s8),
                Text(
                  'Label every picture of a folder for one model. The finished pictures are moved, as a clean dataset ready for '
                  'training, to a folder you choose (an external drive too).',
                  style: Fx.caption(context),
                ),
                const SizedBox(height: Fx.s24),
                if (_error != null) ...[
                  Container(
                    key: const Key('labeller-error'),
                    padding: const EdgeInsets.all(Fx.s12),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Fx.radiusSm)),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                  const SizedBox(height: Fx.s16),
                ],
                _card(context, '1. What should it learn?', [
                  Wrap(spacing: Fx.s8, runSpacing: Fx.s8, children: [
                    for (var i = 0; i < _models.length; i++)
                      ChoiceChip(
                        key: Key('labeller-model-${_models[i].key}'),
                        label: Text(_models[i].tileName),
                        selected: i == _sel,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() {
                                  _sel = i;
                                  _task = null;
                                  _counts = null;
                                  _scan = null;
                                  _export = null;
                                }),
                      ),
                  ]),
                  if (m != null) ...[const SizedBox(height: Fx.s8), Text(m.ask, style: Fx.caption(context))],
                ]),
                _card(context, '2. Which folder?', [
                  _folderRow(context, 'labeller-folder', _folder, 'Folder with the pictures'),
                  const SizedBox(height: Fx.s12),
                  Row(children: [
                    FilledButton.icon(
                      key: const Key('labeller-scan'),
                      onPressed: _busy || m == null || _folder.text.trim().isEmpty ? null : _scanFolder,
                      icon: const Icon(Icons.search),
                      label: const Text('Find the pictures'),
                    ),
                    const SizedBox(width: Fx.s12),
                    if (_scan != null) Flexible(child: Text('${_scan!.found} pictures found', key: const Key('labeller-found'), style: Fx.caption(context))),
                  ]),
                  if (counts != null) ...[
                    const SizedBox(height: Fx.s12),
                    Wrap(spacing: Fx.s16, runSpacing: Fx.s8, key: const Key('labeller-counts'), children: [
                      _count(context, 'To label', counts.needsEyes),
                      _count(context, 'Finished', counts.ready),
                      _count(context, 'Not sure', counts.skipped),
                      _count(context, 'Moved', counts.accepted),
                    ]),
                  ],
                ]),
                _card(context, '3. Label them', [
                  SwitchListTile(
                    key: const Key('labeller-predraw'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Draw the model\'s guess first'),
                    subtitle: const Text('Uses the model that is deployed now. You only fix the boxes.'),
                    value: _predraw,
                    onChanged: _busy ? null : (v) => setState(() => _predraw = v),
                  ),
                  if (m != null) ..._blurSwitches(context, m.key),
                  FilledButton.icon(
                    key: const Key('labeller-start'),
                    onPressed: _busy || m == null || (counts?.needsEyes ?? 0) == 0 ? null : _start,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Start labelling'),
                  ),
                  const SizedBox(height: Fx.s8),
                  Text('Enter = the boxes are right · drag = draw a box · wheel = zoom · N = nothing here · S = not sure',
                      style: Fx.caption(context)),
                ]),
                _card(context, '4. Move the finished pictures', [
                  _folderRow(context, 'labeller-dest', _dest, 'Folder to move them to (an external drive works)'),
                  const SizedBox(height: Fx.s12),
                  FilledButton.icon(
                    key: const Key('labeller-export'),
                    onPressed: _busy || m == null || (counts?.ready ?? 0) == 0 || _dest.text.trim().isEmpty ? null : _exportAndMove,
                    icon: const Icon(Icons.drive_file_move_outline),
                    label: const Text('Build the dataset and move the pictures'),
                  ),
                  if (_export != null) ...[const SizedBox(height: Fx.s12), _result(context, _export!)],
                ]),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: Fx.s8),
                    child: Row(children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: Fx.s12),
                      Flexible(child: Text(_busyText!, key: const Key('labeller-busy'), style: Fx.caption(context))),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Blur" boxes: what is inside one is blurred in the saved picture. The guesses come with the pre-drawn boxes.
  List<Widget> _blurSwitches(BuildContext context, String model) {
    final allowed = piiAllowed(model);
    return [
      const Divider(),
      Text('Hide personal details when saving', style: Fx.label(context)),
      SwitchListTile(
        key: const Key('labeller-blur-heads'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Heads of people'),
        subtitle: Text(allowed.heads ? 'Draws a Blur box over every head the finder sees.' : (allowed.note ?? '')),
        value: _blurHeads && allowed.heads,
        onChanged: _busy || !allowed.heads ? null : (v) => setState(() => _blurHeads = v),
      ),
      SwitchListTile(
        key: const Key('labeller-blur-plates'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Number plates'),
        subtitle: Text(allowed.plates ? 'Draws a Blur box over every plate (or where it should be).' : (allowed.note ?? '')),
        value: _blurPlates && allowed.plates,
        onChanged: _busy || !allowed.plates ? null : (v) => setState(() => _blurPlates = v),
      ),
      if (allowed.note != null && allowed.heads && allowed.plates) Text(allowed.note!, key: const Key('labeller-blur-note'), style: Fx.caption(context)),
      Text(
        'The Blur boxes use the last class in the labelling screen. Fix, delete or add them: everything inside a Blur box is blurred in the '
        'saved picture, and the original is removed from the folder. This cannot catch everybody, so look at every picture.',
        style: Fx.caption(context),
      ),
      const SizedBox(height: Fx.s12),
    ];
  }

  Widget _card(BuildContext context, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: Fx.s16),
        child: Material(
          color: Fx.raised(context),
          borderRadius: BorderRadius.circular(Fx.radius),
          child: Padding(
            padding: const EdgeInsets.all(Fx.s16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Fx.heading(context)),
              const SizedBox(height: Fx.s12),
              ...children,
            ]),
          ),
        ),
      );

  Widget _folderRow(BuildContext context, String key, TextEditingController controller, String label) => Row(children: [
        Expanded(
          child: TextField(
            key: Key(key),
            controller: controller,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: Fx.s8),
        OutlinedButton(
          key: Key('$key-browse'),
          onPressed: _busy
              ? null
              : () async {
                  final path = await _pick();
                  if (path != null && mounted) setState(() => controller.text = path);
                },
          child: const Text('Browse'),
        ),
      ]);

  Widget _count(BuildContext context, String label, int n) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$n', style: Fx.heading(context)), Text(label, style: Fx.caption(context))]);

  Widget _result(BuildContext context, LabellerStatus s) {
    final lines = <String>[
      '${s.exported} pictures moved: ${s.train} for training, ${s.val} for checking.',
      if (s.emptyLabels > 0) '${s.emptyLabels} of them are "nothing here" examples.',
      if (s.blurredPictures > 0) '${s.blurredPictures} pictures were blurred (${s.blurredRegions} places).',
      if (s.duplicates > 0) '${s.duplicates} copies of a picture were left out.',
      if (s.unreadable > 0) '${s.unreadable} pictures could not be opened and were left in the folder.',
      if (s.missing > 0) '${s.missing} pictures were already gone from the folder.',
      if (s.failed > 0) '${s.failed} could not be copied and stayed in the folder.',
      if (s.dest != null) 'Dataset: ${s.dest}',
    ];
    return Container(
      key: const Key('labeller-result'),
      padding: const EdgeInsets.all(Fx.s12),
      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Fx.radiusSm)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final l in lines) Text(l)]),
    );
  }
}
