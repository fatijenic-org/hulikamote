import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../forensic/domain/forensic_models.dart';
import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/benchmark_api.dart';
import '../../domain/benchmark_models.dart';

/// Opens the file dialog for the original clip. Returns its path, or null.
Future<String?> pickOriginalVideo() async {
  final file = await FilePicker.pickFile(type: FileType.video);
  return file?.path;
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _when(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// The text boxes of one event while it is being edited.
class _Row {
  _Row(BenchEvent e)
      : violation = e.violation,
        start = TextEditingController(text: e.start),
        end = TextEditingController(text: e.end),
        plate = TextEditingController(text: e.plate);

  static int _made = 0;

  /// Stable across removals, so a row keeps its own boxes when the ones above it go away.
  final int id = _made++;
  String violation;
  final TextEditingController start;
  final TextEditingController end;
  final TextEditingController plate;

  void dispose() {
    start.dispose();
    end.dispose();
    plate.dispose();
  }

  BenchEvent toEvent() =>
      BenchEvent(violation: violation, start: start.text.trim(), end: end.text.trim(), plate: plate.text.trim());
}

/// Add a clip (from a forensic run) or change an existing clip's events. Pops `true` when something was saved.
class ClipDialog extends StatefulWidget {
  const ClipDialog({super.key, required this.api, required this.runs, this.clip, this.pickVideo = pickOriginalVideo});

  final BenchmarkApi api;
  final List<RunSummary> runs;
  final BenchClip? clip; // null = a new clip
  final Future<String?> Function() pickVideo;

  @override
  State<ClipDialog> createState() => _ClipDialogState();
}

class _ClipDialogState extends State<ClipDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.clip?.id ?? '');
  late final TextEditingController _note = TextEditingController(text: widget.clip?.note ?? '');
  late bool _clean = widget.clip?.clean ?? false;
  late final List<_Row> _rows = [for (final e in widget.clip?.events ?? const <BenchEvent>[]) _Row(e)];

  String? _runId;
  RunSuggestions? _found;
  String? _video;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.clip != null;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// Only violations switched on in the run's settings can be judged on the clip.
  List<String> _choices(String? current) {
    final enabled = _editing ? widget.clip!.enabled : (_found?.enabled ?? const <String>[]);
    final list = enabled.isEmpty ? [for (final v in ViolationCatalog.all) v.key] : [...enabled];
    if (current != null && !list.contains(current)) list.add(current);
    return list;
  }

  void _say(String message) => setState(() {
        _error = message;
        _busy = false;
      });

  Future<void> _pickRun(String? id) async {
    if (id == null) return;
    setState(() {
      _runId = id;
      _found = null;
      _video = null;
      _error = null;
      _busy = true;
    });
    try {
      final found = await widget.api.suggestions(id);
      if (!mounted) return;
      setState(() {
        _found = found;
        _busy = false;
        if (_name.text.trim().isEmpty) _name.text = 'clip_${id.length > 6 ? id.substring(0, 6) : id}';
      });
    } on BenchmarkApiException catch (e) {
      _say(e.message);
    } catch (e) {
      _say('$e');
    }
  }

  void _addRow([BenchEvent? e]) {
    final first = _choices(null).first;
    setState(() => _rows.add(_Row(e ?? BenchEvent(violation: first))));
  }

  Future<void> _chooseVideo() async {
    final path = await widget.pickVideo();
    if (path != null && mounted) setState(() => _video = path);
  }

  Future<void> _save() async {
    final id = _name.text.trim();
    if (id.isEmpty) return _say('Give the clip a name.');
    if (!_editing && _runId == null) return _say('Pick the forensic run this clip comes from.');
    if (!_editing && _found != null && !_found!.videoKept && _video == null) {
      return _say('Choose the original video file: that run did not keep its own copy.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.saveClip(
        id: id,
        taskId: _editing ? null : _runId,
        videoPath: _video,
        note: _note.text.trim(),
        clean: _clean,
        events: _clean ? const [] : [for (final r in _rows) r.toEvent()],
      );
      if (mounted) Navigator.of(context).pop(true);
    } on BenchmarkApiException catch (e) {
      _say(e.message);
    } catch (e) {
      _say('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return AlertDialog(
      title: Text(_editing ? 'Edit ${widget.clip!.id}' : 'Add a clip'),
      content: SizedBox(
        width: 780,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('clip-name'),
                controller: _name,
                enabled: !_editing,
                decoration: const InputDecoration(
                  labelText: 'Clip name',
                  helperText: 'Letters, digits, - and _ only',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: Fx.s12),
              if (!_editing) ...[
                DropdownButtonFormField<String>(
                  key: const Key('run-picker'),
                  initialValue: _runId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Forensic run this clip comes from',
                    helperText: 'Run the clip in the Forensic Analyzer first (draw the zones, tick the violations), then pick that run.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final r in widget.runs)
                      DropdownMenuItem(value: r.taskId, child: Text('${r.shortId}  ·  ${_when(r.createdAt)}  ·  ${r.ticketCount} tickets')),
                  ],
                  onChanged: _busy ? null : _pickRun,
                ),
                const SizedBox(height: Fx.s12),
                if (found != null && !found.videoKept)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Fx.s12),
                    child: Row(children: [
                      OutlinedButton.icon(
                        key: const Key('choose-video'),
                        onPressed: _busy ? null : _chooseVideo,
                        icon: const Icon(Icons.video_file_outlined, size: 18),
                        label: const Text('Choose the original video…'),
                      ),
                      const SizedBox(width: Fx.s12),
                      Expanded(
                        child: Text(
                          _video ?? 'That run did not keep its own copy of the video.',
                          style: Fx.caption(context),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ),
              ],
              TextField(
                key: const Key('clip-note'),
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note (where and when it was filmed)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              CheckboxListTile(
                key: const Key('clip-clean'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _clean,
                onChanged: (v) => setState(() => _clean = v ?? false),
                title: const Text('Nothing illegal happens in this clip'),
                subtitle: const Text('Every ticket on it will count as a false alarm.'),
              ),
              if (!_clean) ...[
                Text('What REALLY happens (watch the clip)', style: Fx.label(context)),
                const SizedBox(height: Fx.s8),
                if (found != null && found.suggestions.isNotEmpty) ...[
                  Text('The run flagged these. Add the ones that really happened:', style: Fx.caption(context)),
                  const SizedBox(height: Fx.s4),
                  Wrap(spacing: Fx.s8, runSpacing: Fx.s4, children: [
                    for (final s in found.suggestions)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text(
                          '${ViolationCatalog.of(s.violation).label}  ${s.start == null ? '?' : '${secondsText(s.start)}-${secondsText(s.end)} s'}'
                          '${s.plate != null ? '  ${s.plate}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () => _addRow(s.toEvent()),
                      ),
                  ]),
                  const SizedBox(height: Fx.s8),
                ],
                for (var i = 0; i < _rows.length; i++) _eventRow(i),
                TextButton.icon(
                  key: const Key('add-event'),
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add an event'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: Fx.s8),
                FxBanner(message: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(key: const Key('save-clip'), onPressed: _busy ? null : _save, child: Text(_busy ? 'Working…' : 'Save')),
      ],
    );
  }

  Widget _eventRow(int i) {
    final row = _rows[i];
    final choices = _choices(row.violation);
    return Padding(
      key: ValueKey('event-row-${row.id}'),
      padding: const EdgeInsets.only(bottom: Fx.s8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 5,
          child: DropdownButtonFormField<String>(
            key: ValueKey('event-violation-${row.id}'),
            initialValue: row.violation,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: [for (final k in choices) DropdownMenuItem(value: k, child: Text(ViolationCatalog.of(k).label, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => row.violation = v ?? row.violation),
          ),
        ),
        const SizedBox(width: Fx.s8),
        Expanded(
          flex: 2,
          child: TextField(
            key: ValueKey('event-start-${row.id}'),
            controller: row.start,
            decoration: const InputDecoration(labelText: 'Start', hintText: 's or m:ss', border: OutlineInputBorder(), isDense: true),
          ),
        ),
        const SizedBox(width: Fx.s8),
        Expanded(
          flex: 2,
          child: TextField(
            key: ValueKey('event-end-${row.id}'),
            controller: row.end,
            decoration: const InputDecoration(labelText: 'End', hintText: 's or m:ss', border: OutlineInputBorder(), isDense: true),
          ),
        ),
        const SizedBox(width: Fx.s8),
        Expanded(
          flex: 3,
          child: TextField(
            key: ValueKey('event-plate-${row.id}'),
            controller: row.plate,
            decoration: const InputDecoration(labelText: 'Plate (optional)', border: OutlineInputBorder(), isDense: true),
          ),
        ),
        IconButton(
          tooltip: 'Remove',
          onPressed: () => setState(() => _rows.removeAt(i).dispose()),
          icon: const Icon(Icons.close, size: 18),
        ),
      ]),
    );
  }
}
