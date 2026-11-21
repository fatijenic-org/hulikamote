import 'package:flutter/material.dart';

import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import '../../domain/models/setup_preset.dart';

/// Saved violation setups, above the violation list of the live setup. A setup is saved with the fingerprint of the video it was made for:
/// when the same video is used again the bar offers that setup at once ("Use"), and every saved setup is in the drop-down. Using one switches
/// on all its violations with the way each is set; more can be added and each can still be edited in the next steps.
class SetupPresetBar extends StatefulWidget {
  const SetupPresetBar({
    super.key,
    required this.api,
    required this.videoHash,
    required this.videoName,
    required this.currentConfig,
    required this.onUse,
    this.compact = false,
  });

  /// One slim row (the "Rules & zones" step): the drop-down, Use, Update and Save; no suggestion line and no delete.
  final bool compact;

  final CameraApi api;

  /// The fingerprint of the video in use (null: a camera, nothing to match).
  final String? videoHash;
  final String? videoName;

  /// The setup as it is now (what Save keeps).
  final Map<String, dynamic> Function() currentConfig;

  /// Told the saved setup to apply and its name.
  final void Function(Map<String, dynamic> config, String name) onUse;

  @override
  State<SetupPresetBar> createState() => _SetupPresetBarState();
}

class _SetupPresetBarState extends State<SetupPresetBar> {
  List<SetupPreset> _items = const [];
  String? _selected;
  bool _busy = false;
  bool _loaded = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(SetupPresetBar old) {
    super.didUpdateWidget(old);
    if (old.videoHash != widget.videoHash) _refresh();
  }

  static String _say(Object e) => '$e'.replaceFirst('Exception: ', '');

  Future<void> _refresh() async {
    try {
      final items = await widget.api.setupPresets(widget.videoHash);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loaded = true;
        if (_selected == null || !items.any((p) => p.id == _selected)) _selected = items.isEmpty ? null : items.first.id;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _message = _say(e);
        });
      }
    }
  }

  Future<void> _use(SetupPreset p) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final config = await widget.api.setupPresetConfig(p.id);
      if (!mounted) return;
      widget.onUse(config, p.name);
      setState(() => _message = 'Applied "${p.name}": ${p.violations.length} violation${p.violations.length == 1 ? '' : 's'} switched on. Add more or change them if you like.');
    } catch (e) {
      if (mounted) setState(() => _message = _say(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final config = widget.currentConfig();
    if (((config['active_violations'] as List?) ?? const []).isEmpty) {
      setState(() => _message = 'Pick at least one violation first, then save the setup.');
      return;
    }
    final field = TextEditingController(text: widget.videoName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save this setup'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(key: const ValueKey('setup-preset-name'), controller: field, autofocus: true, maxLength: 80, decoration: const InputDecoration(labelText: 'Name'), onSubmitted: (v) => Navigator.pop(c, v.trim())),
          Text(
            widget.videoHash == null
                ? 'It is not tied to a video (the source is a camera).'
                : 'It is saved for this video (${widget.videoName ?? ''}): it is offered again when the same video is used.',
            style: Fx.caption(c),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, field.text.trim()), child: const Text('Save')),
        ],
      ),
    ).whenComplete(field.dispose);
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await widget.api.saveSetupPreset(name, config, videoHash: widget.videoHash, videoName: widget.videoName);
      _selected = saved.id;
      await _refresh();
      if (mounted) setState(() => _message = 'Saved "${saved.name}".');
    } catch (e) {
      if (mounted) setState(() => _message = _say(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The chosen saved setup is replaced by the setup as it is now (zones and signs edited in the next steps are kept this way).
  Future<void> _update(SetupPreset p) async {
    final config = widget.currentConfig();
    if (((config['active_violations'] as List?) ?? const []).isEmpty) {
      setState(() => _message = 'Pick at least one violation first.');
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Update "${p.name}"?'),
        content: const Text('The saved setup is replaced by the setup on screen now (violations, zones, signs and settings).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Update')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.updateSetupPreset(p.id, config);
      await _refresh();
      if (mounted) setState(() => _message = 'Updated "${p.name}".');
    } catch (e) {
      if (mounted) setState(() => _message = _say(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SetupPreset p) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text('This saved setup is removed for good. The setup on screen stays as it is.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await widget.api.deleteSetupPreset(p.id);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _message = _say(e));
    }
  }

  String _label(SetupPreset p) => '${p.match ? '★ ' : ''}${p.name}  ·  ${p.violations.length} violation${p.violations.length == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final matches = [for (final p in _items) if (p.match) p];
    SetupPreset? picked;
    for (final p in _items) {
      if (p.id == _selected) picked = p;
    }
    return Container(
      key: const ValueKey('setup-preset-bar'),
      margin: const EdgeInsets.only(bottom: Fx.s12),
      padding: const EdgeInsets.all(Fx.s12),
      decoration: BoxDecoration(
        color: Fx.panel(context),
        borderRadius: BorderRadius.circular(Fx.radiusSm),
        border: Border.all(color: matches.isNotEmpty ? Fx.accent : Fx.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (matches.isNotEmpty && !widget.compact)
          Padding(
            padding: const EdgeInsets.only(bottom: Fx.s8),
            child: Row(children: [
              const Icon(Icons.auto_awesome, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A saved setup was found for this video: "${matches.first.name}" (${matches.first.violations.map((k) => ViolationCatalog.of(k).label).join(', ')}).',
                  style: Fx.body(context),
                ),
              ),
              const SizedBox(width: Fx.s8),
              FilledButton(key: const ValueKey('setup-preset-use-match'), onPressed: _busy ? null : () => _use(matches.first), child: const Text('Use it')),
            ]),
          ),
        Row(children: [
          Text('Saved setups', style: Fx.label(context)),
          const SizedBox(width: Fx.s12),
          Expanded(
            child: _items.isEmpty
                ? Text('None yet. Pick the violations, then save the setup to use it again.', style: Fx.caption(context))
                : DropdownButton<String>(
                    key: const ValueKey('setup-preset-dropdown'),
                    isExpanded: true,
                    isDense: true,
                    value: _selected,
                    items: [for (final p in _items) DropdownMenuItem(value: p.id, child: Text(_label(p), overflow: TextOverflow.ellipsis))],
                    onChanged: _busy ? null : (v) => setState(() => _selected = v),
                  ),
          ),
          const SizedBox(width: Fx.s8),
          FilledButton.tonal(
            key: const ValueKey('setup-preset-use'),
            onPressed: (_busy || picked == null) ? null : () => _use(picked!),
            child: const Text('Use'),
          ),
          IconButton(
            key: const ValueKey('setup-preset-update'),
            tooltip: 'Replace the chosen saved setup with the setup on screen now',
            onPressed: (_busy || picked == null) ? null : () => _update(picked!),
            icon: const Icon(Icons.sync_alt, size: 18),
          ),
          if (!widget.compact)
            IconButton(
              key: const ValueKey('setup-preset-delete'),
              tooltip: 'Delete the chosen saved setup',
              onPressed: (_busy || picked == null) ? null : () => _delete(picked!),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          OutlinedButton.icon(
            key: const ValueKey('setup-preset-save'),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save this setup'),
          ),
        ]),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: Fx.s8), child: Text(_message!, style: Fx.caption(context))),
      ]),
    );
  }
}
