import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import '../../domain/models/road_detect.dart';
import '../../domain/models/road_preset.dart';

/// What the dialog hands back when it closes: which saved road the setup now follows (null = none), and, when the operator pressed
/// "Use", the markings of that road (1920x1080 reference space).
class SavedRoadsResult {
  const SavedRoadsResult({this.loadedId, this.loadedName, this.markings});

  final String? loadedId;
  final String? loadedName;
  final List<RoadArea>? markings;
}

/// "Saved roads": the road markings of the setup under a name. Save the current road, use a saved one again, duplicate it, rename it,
/// delete it. A road that was used can be edited in the setup and then saved over itself ("Update").
class SavedRoadsDialog extends StatefulWidget {
  const SavedRoadsDialog({super.key, required this.api, required this.current, this.loadedId, this.loadedName});

  final CameraApi api;

  /// The markings of the setup now, in the 1920x1080 reference space (what Save keeps).
  final List<RoadArea> current;
  final String? loadedId;
  final String? loadedName;

  @override
  State<SavedRoadsDialog> createState() => _SavedRoadsDialogState();
}

class _SavedRoadsDialogState extends State<SavedRoadsDialog> {
  List<RoadPreset> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _loadedId;
  String? _loadedName;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadedId = widget.loadedId;
    _loadedName = widget.loadedName;
    _refresh();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final items = await widget.api.roadPresets();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _say(e);
      });
    }
  }

  static String _say(Object e) => '$e'.replaceFirst('Exception: ', '');

  /// Runs [job] with the busy flag on; a failure is shown in the dialog.
  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = _say(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close([SavedRoadsResult? result]) =>
      Navigator.of(context).pop(result ?? SavedRoadsResult(loadedId: _loadedId, loadedName: _loadedName));

  Future<void> _saveNew() => _run(() async {
    final name = _name.text.trim();
    if (name.isEmpty) throw Exception('Give the road a name.');
    final saved = await widget.api.saveRoadPreset(name, widget.current);
    _close(SavedRoadsResult(loadedId: saved.id, loadedName: saved.name));
  });

  Future<void> _update() => _run(() async {
    final id = _loadedId;
    if (id == null) return;
    final saved = await widget.api.updateRoadPreset(id, markings: widget.current);
    _close(SavedRoadsResult(loadedId: saved.id, loadedName: saved.name));
  });

  Future<void> _use(RoadPreset p) => _run(() async {
    final markings = await widget.api.roadPresetMarkings(p.id);
    _close(SavedRoadsResult(loadedId: p.id, loadedName: p.name, markings: markings));
  });

  Future<void> _duplicate(RoadPreset p) => _run(() async {
    await widget.api.duplicateRoadPreset(p.id);
    await _refresh();
  });

  Future<void> _rename(RoadPreset p) async {
    final name = await _ask(p.name);
    if (name == null || name.isEmpty) return;
    await _run(() async {
      await widget.api.updateRoadPreset(p.id, name: name);
      if (_loadedId == p.id) _loadedName = name;
      await _refresh();
    });
  }

  Future<void> _delete(RoadPreset p) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text('This saved road is removed for good. The road in the setup stays as it is.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true) return;
    await _run(() async {
      await widget.api.deleteRoadPreset(p.id);
      if (_loadedId == p.id) {
        _loadedId = null;
        _loadedName = null;
      }
      await _refresh();
    });
  }

  Future<String?> _ask(String initial) {
    final field = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Name of the road'),
        content: TextField(controller: field, autofocus: true, maxLength: 80, onSubmitted: (v) => Navigator.pop(c, v.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, field.text.trim()), child: const Text('OK')),
        ],
      ),
    ).whenComplete(field.dispose);
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrent = widget.current.isNotEmpty;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(Fx.s24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Saved roads', style: Fx.title(context))),
              IconButton(key: const ValueKey('saved-roads-close'), tooltip: 'Close', onPressed: _close, icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: Fx.s8),
            Text('Save the road you marked, and use it again later. A road you use can be changed, then saved over itself.', style: Fx.caption(context)),
            const SizedBox(height: Fx.s16),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('saved-roads-name'),
                  controller: _name,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Save the current road as…', counterText: '', isDense: true),
                  onSubmitted: (_) => hasCurrent ? _saveNew() : null,
                ),
              ),
              const SizedBox(width: Fx.s8),
              FilledButton(key: const ValueKey('saved-roads-save'), onPressed: (_busy || !hasCurrent) ? null : _saveNew, child: const Text('Save as new')),
            ]),
            if (_loadedId != null) ...[
              const SizedBox(height: Fx.s8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('saved-roads-update'),
                  onPressed: (_busy || !hasCurrent) ? null : _update,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text('Update "${_loadedName ?? 'this road'}" with the current road'),
                ),
              ),
            ],
            if (!hasCurrent) ...[
              const SizedBox(height: Fx.s8),
              Text('The setup has no markings yet: there is nothing to save.', style: Fx.caption(context)),
            ],
            if (_error != null) ...[const SizedBox(height: Fx.s8), FxBanner(message: _error!)],
            const SizedBox(height: Fx.s16),
            Divider(height: 1, color: Fx.border(context)),
            Flexible(
              child: _loading
                  ? const Padding(padding: EdgeInsets.all(Fx.s24), child: Center(child: CircularProgressIndicator()))
                  : _items.isEmpty
                  ? Padding(padding: const EdgeInsets.all(Fx.s24), child: Text('No saved roads yet.', style: Fx.body(context)))
                  : ListView(
                      shrinkWrap: true,
                      children: [for (final p in _items) _row(context, p)],
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, RoadPreset p) {
    final inUse = p.id == _loadedId;
    return ListTile(
      key: ValueKey('saved-road-${p.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: inUse ? FontWeight.w700 : FontWeight.w500)),
      subtitle: Text('${p.count} marking${p.count == 1 ? '' : 's'} · ${_when(p.updated)}${inUse ? ' · in use' : ''}', style: Fx.caption(context)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        FilledButton.tonal(key: ValueKey('saved-road-use-${p.id}'), onPressed: _busy ? null : () => _use(p), child: const Text('Use')),
        IconButton(tooltip: 'Duplicate', onPressed: _busy ? null : () => _duplicate(p), icon: const Icon(Icons.copy_outlined, size: 18)),
        IconButton(tooltip: 'Rename', onPressed: _busy ? null : () => _rename(p), icon: const Icon(Icons.edit_outlined, size: 18)),
        IconButton(tooltip: 'Delete', onPressed: _busy ? null : () => _delete(p), icon: const Icon(Icons.delete_outline, size: 18)),
      ]),
    );
  }
}
