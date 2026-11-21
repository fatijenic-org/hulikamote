import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';

/// Demo editor: the vehicles of one demo, each with its picture. Correct what a vehicle is (car, motorcycle ...), its plate and its violation;
/// the change is made in every picture and ticket of the demo. A vehicle can also be deleted (with its tickets).
class DemoEditorDialog extends StatefulWidget {
  const DemoEditorDialog({super.key, required this.api, required this.demoId, required this.title});

  final CameraApi api;
  final String demoId;
  final String title;

  static Future<void> show(BuildContext context, CameraApi api, String demoId, String title) =>
      showDialog<void>(context: context, builder: (_) => DemoEditorDialog(api: api, demoId: demoId, title: title));

  @override
  State<DemoEditorDialog> createState() => _DemoEditorDialogState();
}

class _DemoEditorDialogState extends State<DemoEditorDialog> {
  List<Map<String, dynamic>> _tracks = const [];
  List<String> _kinds = const [];
  List<String> _violations = const [];
  bool _loading = true;
  bool _busy = false;
  String? _message;
  int _stamp = 0; // changes after an edit, so the pictures are loaded again

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _clean(Object e) => '$e'.replaceFirst('Exception: ', '');

  Future<void> _load() async {
    try {
      final data = await widget.api.demoTracks(widget.demoId);
      if (!mounted) return;
      setState(() {
        _tracks = [for (final t in (data['tracks'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
        _kinds = [for (final k in (data['kinds'] as List? ?? const [])) '$k'];
        _violations = [for (final v in (data['violations'] as List? ?? const [])) '$v'];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Could not read the vehicles: ${_clean(e)}';
        });
      }
    }
  }

  Future<void> _edit(int trackId, {String? kind, String? plate, String? violation, bool delete = false}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await widget.api.editDemoTrack(widget.demoId, trackId, kind: kind, plate: plate, violation: violation, delete: delete);
      _stamp++;
      await _load();
      if (mounted) setState(() => _message = 'Done: ${r['pictures']} pictures and ${r['tickets']} tickets changed.');
    } catch (e) {
      if (mounted) setState(() => _message = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEdit(Map<String, dynamic> t) async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _TrackForm(track: t, kinds: _kinds, violations: _violations),
    );
    if (result == null) return;
    await _edit(
      t['track_id'] as int,
      kind: result['kind'] as String?,
      plate: result['plate'] as String?,
      violation: result['violation'] as String?,
      delete: result['delete'] == true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit demo: ${widget.title}'),
      content: SizedBox(
        width: 640,
        height: 460,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pick a vehicle to change what it is called, its plate and its violation, in every picture and ticket.', style: Fx.caption(context)),
                if (_message != null) ...[
                  const SizedBox(height: Fx.s4),
                  Text(_message!, style: Fx.caption(context)),
                ],
                const SizedBox(height: Fx.s8),
                Expanded(
                  child: _tracks.isEmpty
                      ? Center(child: Text('No vehicles in this demo.', style: Fx.caption(context)))
                      : ListView.separated(
                          itemCount: _tracks.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final t = _tracks[i];
                            final id = t['track_id'] as int;
                            final violation = '${t['violation'] ?? ''}';
                            return ListTile(
                              key: ValueKey('demo-track-$id'),
                              dense: true,
                              leading: SizedBox(
                                width: 84,
                                height: 60,
                                child: Image.network(
                                  '${widget.api.demoTrackPictureUrl(widget.demoId, id)}?v=$_stamp',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(Icons.directions_car_outlined),
                                ),
                              ),
                              title: Text('#$id · ${'${t['kind']}'.toUpperCase()} · ${t['plate'] ?? 'no plate'}'),
                              subtitle: Text(
                                '${violation.isEmpty ? 'no violation' : violation.replaceAll('_', ' ')} · ${t['frames']} pictures · '
                                '${t['first_s']}-${t['last_s']} s · ${t['tickets']} ticket(s)',
                              ),
                              trailing: IconButton(
                                tooltip: 'Edit this vehicle',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: _busy ? null : () => _openEdit(t),
                              ),
                              onTap: _busy ? null : () => _openEdit(t),
                            );
                          },
                        ),
                ),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}

class _TrackForm extends StatefulWidget {
  const _TrackForm({required this.track, required this.kinds, required this.violations});

  final Map<String, dynamic> track;
  final List<String> kinds;
  final List<String> violations;

  @override
  State<_TrackForm> createState() => _TrackFormState();
}

class _TrackFormState extends State<_TrackForm> {
  late String _kind = '${widget.track['kind']}';
  late String _violation = '${widget.track['violation'] ?? ''}';
  late final TextEditingController _plate = TextEditingController(text: '${widget.track['plate'] ?? ''}');

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kinds = widget.kinds.contains(_kind) ? widget.kinds : [_kind, ...widget.kinds];
    final violations = widget.violations.contains(_violation) || _violation.isEmpty ? widget.violations : [_violation, ...widget.violations];
    return AlertDialog(
      title: Text('Vehicle #${widget.track['track_id']}'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('demo-edit-kind'),
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Vehicle', isDense: true),
            items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text(k))],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: Fx.s12),
          TextField(
            key: const ValueKey('demo-edit-plate'),
            controller: _plate,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Plate number (empty: none)', isDense: true),
          ),
          const SizedBox(height: Fx.s12),
          DropdownButtonFormField<String>(
            key: const ValueKey('demo-edit-violation'),
            initialValue: _violation,
            decoration: const InputDecoration(labelText: 'Violation', isDense: true),
            items: [
              const DropdownMenuItem(value: '', child: Text('none (no ticket)')),
              for (final v in violations) DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' '))),
            ],
            onChanged: (v) => setState(() => _violation = v ?? ''),
          ),
        ]),
      ),
      actions: [
        TextButton(
          key: const ValueKey('demo-edit-delete'),
          onPressed: () => Navigator.of(context).pop(<String, Object?>{'delete': true}),
          child: Text('Delete vehicle', style: TextStyle(color: Fx.danger)),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('demo-edit-save'),
          onPressed: () {
            final oldKind = '${widget.track['kind']}';
            final oldPlate = '${widget.track['plate'] ?? ''}';
            final oldViolation = '${widget.track['violation'] ?? ''}';
            final plate = _plate.text.trim().toUpperCase();
            Navigator.of(context).pop(<String, Object?>{
              if (_kind != oldKind) 'kind': _kind,
              if (plate != oldPlate.toUpperCase()) 'plate': plate,
              if (_violation != oldViolation) 'violation': _violation,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
