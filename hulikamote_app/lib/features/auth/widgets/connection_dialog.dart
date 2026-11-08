import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/cloud_portal_api.dart';
import '../../../core/services/portal_api.dart';

/// How this phone reaches the system: Online (the Supabase cloud, works anywhere) or Same Wi-Fi (the laptop's address,
/// no internet needed). Checks the connection answers before saving it. Returns true when a working one was saved.
Future<bool> showConnectionDialog(
  BuildContext context, {
  PortalApi Function(String baseUrl)? lanApi,
  Future<void> Function(String url, String anonKey)? checkCloud,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _ConnectionDialog(
      lanApi: lanApi ?? (url) => PortalApi(baseUrl: () => url),
      checkCloud: checkCloud ?? CloudPortalApi.checkProject,
    ),
  );
  return saved ?? false;
}

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({required this.lanApi, required this.checkCloud});

  final PortalApi Function(String baseUrl) lanApi;
  final Future<void> Function(String url, String anonKey) checkCloud;

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late bool _online = AppConfig.isOnline;
  late final _url = TextEditingController(text: AppConfig.cloudUrl);
  late final _key = TextEditingController(text: AppConfig.cloudKey);
  late final _address = TextEditingController(text: AppConfig.address);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_online) {
        final url = AppConfig.normalizeCloudUrl(_url.text);
        final key = _key.text.replaceAll(RegExp(r'\s'), '');
        if (url.isEmpty) return _fail('Type the project address, like https://your-project.supabase.co');
        if (key.isEmpty) return _fail('Paste the project\'s "anon" key.');
        await widget.checkCloud(url, key);
        await AppConfig.saveCloud(url, key);
        await AppConfig.setMode('online');
      } else {
        final address = AppConfig.normalize(_address.text);
        if (address.isEmpty) return _fail('Type the laptop\'s address, like 192.168.68.109');
        await widget.lanApi('http://$address').ping();
        await AppConfig.save(address);
        await AppConfig.setMode('lan');
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PortalException catch (e) {
      _fail(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connection'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, icon: Icon(Icons.cloud_outlined), label: Text('Online')),
              ButtonSegment(value: false, icon: Icon(Icons.wifi), label: Text('Same Wi-Fi')),
            ],
            selected: {_online},
            onSelectionChanged: _busy ? null : (v) => setState(() {
              _online = v.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          if (_online) ...[
            const Text('Works anywhere with internet. Use the project address and the "anon" key (Supabase: Project Settings > API).'),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Project address', hintText: 'https://your-project.supabase.co', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Anon key', border: const OutlineInputBorder(), errorText: _error, errorMaxLines: 4),
            ),
          ] else ...[
            const Text('No internet needed. Put the phone on the same Wi-Fi (or the laptop\'s hotspot). The address is on the dashboard, in the Motorists tab.'),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(labelText: 'Laptop address', hintText: '192.168.68.109', border: const OutlineInputBorder(), errorText: _error, errorMaxLines: 4),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Test and save'),
        ),
      ],
    );
  }
}
