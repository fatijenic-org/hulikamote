import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/cloud_portal_api.dart';
import '../../../core/services/laptop_finder.dart';
import '../../../core/services/portal_api.dart';

/// How this phone reaches the system: Online (the Supabase cloud, works anywhere) or Same Wi-Fi (the laptop's address,
/// no internet needed). Checks the connection answers before saving it. Returns true when a working one was saved.
Future<bool> showConnectionDialog(
  BuildContext context, {
  PortalApi Function(String baseUrl)? lanApi,
  Future<void> Function(String url, String anonKey)? checkCloud,
  Future<ConnectResult> Function()? autoConnect,
  Future<ConnectResult> Function()? autoConnectLocal,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _ConnectionDialog(
      lanApi: lanApi ?? (url) => PortalApi(baseUrl: () => url),
      checkCloud: checkCloud ?? CloudPortalApi.checkProject,
      autoConnect: autoConnect ?? () => LaptopFinder().connect(),
      autoConnectLocal: autoConnectLocal ?? () => LaptopFinder().connect(preferCloud: false),
    ),
  );
  return saved ?? false;
}

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({required this.lanApi, required this.checkCloud, required this.autoConnect, required this.autoConnectLocal});

  final PortalApi Function(String baseUrl) lanApi;
  final Future<void> Function(String url, String anonKey) checkCloud;
  final Future<ConnectResult> Function() autoConnect;
  final Future<ConnectResult> Function() autoConnectLocal;

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late bool _online = AppConfig.isOnline;
  late final _url = TextEditingController(text: AppConfig.cloudUrl);
  late final _key = TextEditingController(text: AppConfig.cloudKey);
  late final _address = TextEditingController(text: AppConfig.address);
  String? _error;
  String? _found;           // what the last automatic Connect said
  bool _busy = false;
  bool _finding = false;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _address.dispose();
    super.dispose();
  }

  /// One press: find the laptop on the network and set the phone up (cloud if ready, else the laptop's Wi-Fi).
  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _finding = true;
      _error = null;
      _found = null;
    });
    try {
      final result = await widget.autoConnect();
      if (!mounted) return;
      if (result.ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _found = result.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _finding = false;
        });
      }
    }
  }

  /// Same Wi-Fi tab: look for the laptop on this network and use it, never the cloud. The address is found, not typed (it changes
  /// whenever the router gives the laptop a new one).
  Future<void> _findLocal() async {
    setState(() {
      _busy = true;
      _finding = true;
      _error = null;
    });
    try {
      final result = await widget.autoConnectLocal();
      if (!mounted) return;
      if (result.ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = result.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _finding = false;
        });
      }
    }
  }

  /// For a phone that cannot find the laptop (a venue Wi-Fi that keeps devices apart): the dashboard copies a setup code, this reads
  /// it from the clipboard and sets the cloud up from it.
  Future<void> _pasteCode() async {
    setState(() {
      _busy = true;
      _error = null;
      _found = null;
    });
    try {
      final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      final code = AppConfig.parseSetupCode(clip);
      if (code == null) {
        if (mounted) setState(() => _found = 'No setup code on the clipboard. On the laptop: dashboard > Motorists > Online > Copy phone setup code. Then press this again.');
        return;
      }
      await widget.checkCloud(code.url, code.key);
      await AppConfig.saveCloud(code.url, code.key);
      await AppConfig.setMode('online');
      if (mounted) Navigator.of(context).pop(true);
    } on PortalException catch (e) {
      if (mounted) setState(() => _found = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        if (address.isEmpty) return _fail('Type the laptop\'s address, like 192.168.1.20 (the dashboard shows it), or press "Find the laptop for me".');
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
          const Text('Press Connect. The phone finds the laptop by itself (same Wi-Fi, hotspot or USB) and picks the right way in.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: _finding ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find),
            label: Text(_finding ? 'Looking for the laptop...' : 'Connect'),
          ),
          if (_found != null) ...[
            const SizedBox(height: 8),
            Text(_found!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          TextButton.icon(
            onPressed: _busy ? null : _pasteCode,
            icon: const Icon(Icons.content_paste_go_outlined, size: 18),
            label: const Text('Paste setup code'),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          const Text('Or set it up by hand:'),
          const SizedBox(height: 8),
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
            const Text('No internet needed. Put the phone on the same Wi-Fi (or the laptop\'s hotspot). The dashboard (Motorists tab) shows the address; or let the phone find it.'),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(labelText: 'Laptop address', hintText: '192.168.1.20', border: const OutlineInputBorder(), errorText: _error, errorMaxLines: 4),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _busy ? null : _findLocal,
              icon: _finding ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find, size: 18),
              label: Text(_finding ? 'Looking...' : 'Find the laptop for me'),
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
