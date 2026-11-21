import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import 'demo_editor_dialog.dart';

/// Demo replay: a recorded run played in the Live Monitor for a video file that has one (the screen shows a DEMO REPLAY badge).
/// Make a demo: run the Live Monitor once with "Save this run" on, review and fix the live tickets by hand, then "Make demo from the last
/// saved run". Turn the switch on, pick that video file as usual, set up the violations as usual and press Start.
class DemoDialog extends StatefulWidget {
  const DemoDialog({super.key, required this.api});

  final CameraApi api;

  static Future<void> show(BuildContext context, CameraApi api) =>
      showDialog<void>(context: context, builder: (_) => DemoDialog(api: api));

  @override
  State<DemoDialog> createState() => _DemoDialogState();
}

class _DemoDialogState extends State<DemoDialog> {
  bool _on = false;
  bool _busy = false;
  List<Map<String, dynamic>> _demos = const [];
  String? _message;
  final _title = TextEditingController();
  final _video = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _video.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> state) {
    _on = state['on'] == true;
    _demos = [for (final d in (state['demos'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)];
  }

  String _clean(Object e) => '$e'.replaceFirst('Exception: ', '');

  Future<void> _load() async {
    try {
      final state = await widget.api.demoState();
      if (mounted) setState(() => _apply(state));
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not read the demos: ${_clean(e)}');
    }
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      final state = await widget.api.setDemo(on);
      if (mounted) setState(() => _apply(state));
    } catch (e) {
      if (mounted) setState(() => _message = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _make() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final made = await widget.api.createDemo(_title.text.trim(), _video.text.trim());
      final state = await widget.api.demoState();
      if (mounted) {
        setState(() {
          _apply(state);
          _message = 'Demo made: ${made['title']} (${made['pictures']} pictures, ${made['tickets']} tickets, for ${(made['videos'] as List).join(', ')}).';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String id) async {
    setState(() => _busy = true);
    try {
      await widget.api.deleteDemo(id);
      final state = await widget.api.demoState();
      if (mounted) setState(() => _apply(state));
    } catch (e) {
      if (mounted) setState(() => _message = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Demo replay'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              key: const ValueKey('demo-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Demo replay'),
              subtitle: const Text('On: a video file that has a demo plays its recorded run (marked DEMO REPLAY). Off: the live system runs as normal.'),
              value: _on,
              onChanged: _busy ? null : _toggle,
            ),
            const Divider(),
            Text('DEMOS', style: Fx.label(context)),
            const SizedBox(height: Fx.s4),
            if (_demos.isEmpty) Text('No demo yet.', style: Fx.caption(context)),
            for (final d in _demos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${d['title']}'),
                subtitle: Text('for ${(d['videos'] as List? ?? const []).join(', ')} · ${d['pictures']} pictures · ${d['tickets']} tickets · ${d['duration_s']} s'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    key: ValueKey('demo-edit-${d['id']}'),
                    tooltip: 'Edit the vehicles, plates and violations of this demo',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _busy ? null : () => DemoEditorDialog.show(context, widget.api, '${d['id']}', '${d['title']}').then((_) => _load()),
                  ),
                  IconButton(tooltip: 'Delete this demo', icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : () => _delete('${d['id']}')),
                ]),
              ),
            const Divider(),
            Text('MAKE A DEMO', style: Fx.label(context)),
            const SizedBox(height: Fx.s4),
            Text('1. Run the Live Monitor once with "Save this run" on.  2. Review and fix the live tickets (plates, merge, split).  3. Make the demo here.',
                style: Fx.caption(context)),
            const SizedBox(height: Fx.s8),
            TextField(key: const ValueKey('demo-title'), controller: _title, decoration: const InputDecoration(labelText: 'Demo name', isDense: true)),
            const SizedBox(height: Fx.s8),
            TextField(
              key: const ValueKey('demo-video'),
              controller: _video,
              decoration: const InputDecoration(labelText: 'Video file name (empty: the video of that run)', isDense: true),
            ),
            const SizedBox(height: Fx.s8),
            FilledButton.icon(
              key: const ValueKey('demo-make'),
              onPressed: _busy ? null : _make,
              icon: const Icon(Icons.movie_creation_outlined),
              label: const Text('Make demo from the last saved run'),
            ),
            if (_message != null) ...[
              const SizedBox(height: Fx.s8),
              Text(_message!, style: Fx.caption(context)),
            ],
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
