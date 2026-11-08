import 'package:flutter/material.dart';

import '../../data/camera_api.dart';

/// Camera input: choose where the live monitor gets its picture. A real CCTV / DVR channel, a phone camera app
/// and another laptop playing a clip are all just an address (rtsp://...), so only the address changes.
/// Pops `true` when the source was changed.
class CameraInputDialog extends StatefulWidget {
  const CameraInputDialog({super.key, this.api});

  final CameraApi? api;

  @override
  State<CameraInputDialog> createState() => _CameraInputDialogState();
}

class _Preset {
  const _Preset(this.label, this.name, this.url);
  final String label;
  final String name;
  final String url;
}

const _presets = [
  _Preset('CCTV / DVR', 'CCTV', 'rtsp://user:password@192.168.1.10:554/stream1'),
  _Preset('Phone camera', 'Phone', 'rtsp://192.168.1.20:8554/live'),
  _Preset('Laptop B (clip as a camera)', 'Laptop B', 'rtsp://192.168.1.30:8554/cam1'),
  _Preset('Webcam', 'Webcam', '0'),
];

class _CameraInputDialogState extends State<CameraInputDialog> {
  late final CameraApi _api = widget.api ?? CameraApi();
  final _name = TextEditingController();
  final _url = TextEditingController();
  List<CameraProfile> _profiles = [];
  String? _selected; // name of the saved profile being edited, null = a new address
  String _selectedUrl = ''; // its (masked) address as loaded
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profiles = await _api.profiles();
      if (mounted) setState(() => _profiles = profiles);
    } catch (e) {
      _say('Could not load saved cameras: $e', error: true);
    }
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  void _pick(CameraProfile? profile) {
    setState(() {
      _selected = profile?.name;
      _selectedUrl = profile?.url ?? '';
      _name.text = profile?.name ?? '';
      _url.text = profile?.url ?? '';
      _message = null;
    });
  }

  /// A saved profile whose address was not touched is used by name, so its hidden password still applies.
  bool get _useSavedProfile => _selected != null && _url.text.trim() == _selectedUrl;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      _say('$e'.replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() => _run(() async {
        if (_url.text.trim().isEmpty) throw Exception('Enter an address first');
        _say('Trying the camera...');
        final result = _useSavedProfile
            ? await _api.test(profile: _selected)
            : await _api.test(address: _url.text.trim());
        _say(result.ok ? 'Works: ${result.summary}' : result.message, error: !result.ok);
      });

  Future<void> _save() => _run(() async {
        final name = _name.text.trim(), url = _url.text.trim();
        if (name.isEmpty || url.isEmpty) throw Exception('A saved camera needs a name and an address');
        final others = _profiles.where((p) => p.name != name && p.name != _selected).toList();
        await _api.saveProfiles([...others, CameraProfile(name: name, url: url)]);
        await _load();
        final saved = _profiles.where((p) => p.name == name);
        if (saved.isNotEmpty) _pick(saved.first);
        _say('Saved "$name"');
      });

  Future<void> _delete() => _run(() async {
        await _api.saveProfiles(_profiles.where((p) => p.name != _selected).toList());
        await _load();
        _pick(null);
        _say('Deleted');
      });

  Future<void> _use() => _run(() async {
        if (_url.text.trim().isEmpty) throw Exception('Enter an address first');
        final label = _useSavedProfile ? await _api.use(profile: _selected) : await _api.use(address: _url.text.trim());
        if (mounted) Navigator.of(context).pop(true);
        debugPrint('Camera input set to $label');
      });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Camera input'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Real CCTV, a phone camera and another laptop playing a clip are all just an address. '
                'Pick a saved camera or type one.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('profile-picker'),
                initialValue: _selected,
                decoration: const InputDecoration(labelText: 'Saved cameras', border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('New address')),
                  for (final p in _profiles) DropdownMenuItem<String?>(value: p.name, child: Text('${p.name}  (${p.kind})')),
                ],
                onChanged: _busy
                    ? null
                    : (name) => _pick(name == null ? null : _profiles.firstWhere((p) => p.name == name)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final p in _presets)
                    ActionChip(
                      label: Text(p.label, style: const TextStyle(fontSize: 12)),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _selected = null;
                                _selectedUrl = '';
                                _name.text = p.name;
                                _url.text = p.url;
                                _message = null;
                              }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('camera-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('camera-address'),
                controller: _url,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'rtsp://...   http://...   0 (webcam)   C:\\clips\\test.mp4',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, key: const Key('camera-message'),
                    style: TextStyle(color: _messageIsError ? Colors.red : Colors.green)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_selected != null) TextButton(onPressed: _busy ? null : _delete, child: const Text('Delete')),
        TextButton(onPressed: _busy ? null : _save, child: const Text('Save camera')),
        OutlinedButton(onPressed: _busy ? null : _test, child: const Text('Test')),
        FilledButton(onPressed: _busy ? null : _use, child: const Text('Use this camera')),
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Close')),
      ],
    );
  }
}
