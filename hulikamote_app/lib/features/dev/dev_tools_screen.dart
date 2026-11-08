import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_config.dart';
import '../../core/services/demo_accounts.dart';
import '../../core/services/dev_mode.dart';
import '../../core/services/friendly_error.dart';
import '../../core/services/push_notification_service.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/plate.dart';
import 'dev_api.dart';

/// DEVELOPER TOOLS (temporary). Manage the demo motorists on the laptop (and in the cloud): see them, create one, change a
/// name, e-mail, password or plates, delete one. Also the sign-in shortcuts shown on the sign-in page. Switch off from the
/// bottom of this page. To remove the feature, delete lib/features/dev and the lines that mention DevMode.
class DevToolsScreen extends StatefulWidget {
  const DevToolsScreen({super.key, this.api});

  /// Injected by tests.
  final DevApi? api;

  @override
  State<DevToolsScreen> createState() => _DevToolsScreenState();
}

class _DevToolsScreenState extends State<DevToolsScreen> {
  DevApi get _api => widget.api ?? DevApi();

  final _address = TextEditingController(text: AppConfig.address);
  List<DevAccount>? _accounts;
  List<DemoAccount> _shortcuts = const [];
  String? _error;
  String? _token;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
    if (AppConfig.hasServer) _load();
    PushNotificationService.instance.currentToken().then((t) {
      if (mounted) setState(() => _token = t);
    });
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadShortcuts() async {
    final list = await DemoAccounts.load();
    if (mounted) setState(() => _shortcuts = list);
  }

  Future<void> _connect() async {
    final address = AppConfig.normalize(_address.text);
    if (address.isEmpty) {
      setState(() => _error = 'Type the laptop\'s address, like 192.168.68.109');
      return;
    }
    await AppConfig.save(address);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final list = await _api.accounts();
      if (mounted) setState(() => _accounts = list);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(DevOutcome outcome, String done) {
    final message = switch (outcome.cloud) {
      'ok' => '$done Also in the cloud.',
      'off' => '$done (The cloud is not set up on the laptop, so only the laptop changed.)',
      final failed => '$done But the cloud change failed: ${failed.replaceFirst('failed: ', '')}',
    };
    AppToast.show(context, message, error: outcome.cloudFailed);
  }

  Future<void> _openAccount([DevAccount? account]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AccountSheet(account: account, api: _api, onDone: _say),
    );
    if (saved == true) {
      await _load();
      await _loadShortcuts();
    }
  }

  Future<void> _cloudDemo() async {
    setState(() => _busy = true);
    try {
      final text = await _api.createCloudDemoAccounts();
      if (mounted) AppToast.show(context, 'Demo accounts in the cloud: $text');
    } catch (e) {
      if (mounted) AppToast.show(context, friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editShortcut([DemoAccount? shortcut]) async {
    final edited = await showDialog<DemoAccount>(context: context, builder: (_) => _ShortcutDialog(shortcut: shortcut));
    if (edited == null) return;
    if (shortcut != null && normalizePlate(shortcut.plate) != normalizePlate(edited.plate)) await DemoAccounts.remove(shortcut.plate);
    await DemoAccounts.upsert(edited);
    await _loadShortcuts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer tools'),
        actions: const [Padding(padding: EdgeInsets.only(right: Sp.x4), child: StatusChip(label: 'Temporary', tone: Tone.warning, icon: Icons.build_outlined))],
      ),
      floatingActionButton: _accounts == null ? null : FloatingActionButton.extended(onPressed: () => _openAccount(), icon: const Icon(Icons.person_add_alt_1_outlined), label: const Text('Add account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, 96),
          children: [
            const SectionTitle('Laptop'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Sp.x4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('These tools talk to the laptop even when the app is online. Start the backend with tools\\run_demo_backend.bat.', style: context.text.bodyMedium?.copyWith(color: context.muted)),
                  const SizedBox(height: Sp.x3),
                  AppField(controller: _address, label: 'Laptop address', helper: 'For example 192.168.68.109', keyboard: TextInputType.url, action: TextInputAction.done, onSubmitted: (_) => _connect()),
                  const SizedBox(height: Sp.x3),
                  AppButton(label: _accounts == null ? 'Connect' : 'Reconnect', kind: AppButtonKind.secondary, onPressed: _connect, loading: _busy),
                ]),
              ),
            ),
            if (_error != null) ...[const SizedBox(height: Sp.x3), InfoBanner(message: _error!, tone: Tone.danger)],
            const SizedBox(height: Sp.x6),
            const SectionTitle('Demo accounts'),
            if (_accounts == null)
              Card(child: Padding(padding: const EdgeInsets.all(Sp.x4), child: Text('Connect to the laptop to see its accounts.', style: context.text.bodyMedium?.copyWith(color: context.muted))))
            else if (_accounts!.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(Sp.x4), child: Text('No accounts yet. Add one.')))
            else
              Card(
                child: Column(children: [
                  for (var i = 0; i < _accounts!.length; i++) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      leading: InitialsAvatar(_accounts![i].name, size: 40),
                      title: Text(_accounts![i].name),
                      subtitle: Text([_accounts![i].plates.join(', '), if (_accounts![i].email.isNotEmpty) _accounts![i].email].join('\n')),
                      isThreeLine: _accounts![i].email.isNotEmpty,
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _openAccount(_accounts![i]),
                    ),
                  ],
                ]),
              ),
            const SizedBox(height: Sp.x3),
            AppButton(label: 'Create the demo accounts in the cloud', icon: Icons.cloud_upload_outlined, kind: AppButtonKind.secondary, onPressed: _accounts == null ? null : _cloudDemo, loading: _busy),
            const SizedBox(height: Sp.x6),
            SectionTitle('Sign-in shortcuts', trailing: TextButton(onPressed: () => _editShortcut(), child: const Text('Add'))),
            Card(
              child: Column(children: [
                for (var i = 0; i < _shortcuts.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    leading: InitialsAvatar(_shortcuts[i].name, size: 40),
                    title: Text(_shortcuts[i].name),
                    subtitle: Text('${_shortcuts[i].plate} · password ${_shortcuts[i].password}'),
                    onTap: () => _editShortcut(_shortcuts[i]),
                    trailing: IconButton(
                      tooltip: 'Remove shortcut',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await DemoAccounts.remove(_shortcuts[i].plate);
                        await _loadShortcuts();
                      },
                    ),
                  ),
                ],
                if (_shortcuts.isEmpty) const Padding(padding: EdgeInsets.all(Sp.x4), child: Text('No shortcuts. The sign-in page shows none.')),
              ]),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  await DemoAccounts.reset();
                  await _loadShortcuts();
                },
                child: const Text('Reset shortcuts to the three demo accounts'),
              ),
            ),
            const SizedBox(height: Sp.x4),
            const SectionTitle('This phone'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Push token'),
                subtitle: Text(_token == null ? 'Not available (no Firebase or no internet).' : '${_token!.substring(0, _token!.length.clamp(0, 24))}…'),
                trailing: _token == null
                    ? null
                    : IconButton(
                        tooltip: 'Copy push token',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _token!));
                          if (mounted) AppToast.show(this.context, 'Token copied.');
                        },
                      ),
              ),
            ),
            const SizedBox(height: Sp.x6),
            AppButton(
              label: 'Turn developer mode off',
              kind: AppButtonKind.secondary,
              onPressed: () async {
                await DevMode.set(false);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Create or change one account.
class _AccountSheet extends StatefulWidget {
  const _AccountSheet({required this.account, required this.api, required this.onDone});

  final DevAccount? account;
  final DevApi api;
  final void Function(DevOutcome outcome, String done) onDone;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _email = TextEditingController(text: widget.account?.email ?? '');
  final _plate = TextEditingController();
  final _password = TextEditingController();
  late final List<String> _plates = [...?widget.account?.plates];
  final _added = <String>[], _removed = <String>[];
  bool _shortcut = true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.account == null;

  @override
  void dispose() {
    for (final c in [_name, _email, _plate, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addPlate() {
    final plate = _plate.text.trim().toUpperCase();
    if (normalizePlate(plate).isEmpty || _plates.any((p) => normalizePlate(p) == normalizePlate(plate))) return;
    setState(() {
      _plates.add(plate);
      if (!_isNew) _added.add(plate);
      _plate.clear();
    });
  }

  void _removePlate(String plate) {
    setState(() {
      _plates.remove(plate);
      if (_added.remove(plate)) return;
      _removed.add(plate);
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final password = _password.text;
      late final DevOutcome outcome;
      if (_isNew) {
        if (_plates.isEmpty) throw StateError('Add the plate this account signs in with.');
        outcome = await widget.api.create(name: _name.text.trim(), plate: _plates.first, password: password, email: _email.text.trim());
      } else {
        final a = widget.account!;
        outcome = await widget.api.change(
          a.id,
          name: _name.text.trim() == a.name ? null : _name.text.trim(),
          email: _email.text.trim() == a.email ? null : _email.text.trim(),
          password: password.isEmpty ? null : password,
          addPlates: _added,
          removePlates: _removed,
        );
      }
      final login = outcome.account?.loginPlate ?? widget.account?.loginPlate ?? _plates.first;
      if (_shortcut && password.isNotEmpty) {
        await DemoAccounts.upsert(DemoAccount(_name.text.trim().split(' ').first, login, password));
      }
      if (!mounted) return;
      widget.onDone(outcome, _isNew ? 'Account created.' : 'Account saved.');
      Navigator.of(context).pop(true);
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this account?'),
        content: Text('${widget.account!.name} and their plates are removed here and in the cloud. Their tickets stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: context.colors.error), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true) return;
    setState(() => _busy = true);
    try {
      final outcome = await widget.api.delete(widget.account!.id);
      await DemoAccounts.remove(widget.account!.loginPlate);
      if (!mounted) return;
      widget.onDone(outcome, 'Account deleted.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, MediaQuery.of(context).viewInsets.bottom + Sp.x6),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_isNew ? 'New account' : 'Edit account', style: context.text.headlineSmall),
          const SizedBox(height: Sp.x4),
          AppField(controller: _name, label: 'Full name', capitalization: TextCapitalization.words, action: TextInputAction.next, enabled: !_busy),
          const SizedBox(height: Sp.x3),
          AppField(controller: _email, label: 'E-mail (optional)', keyboard: TextInputType.emailAddress, action: TextInputAction.next, enabled: !_busy),
          const SizedBox(height: Sp.x3),
          AppField(controller: _password, label: _isNew ? 'Password' : 'New password (leave empty to keep)', password: true, enabled: !_busy),
          const SizedBox(height: Sp.x4),
          Text(_isNew ? 'Plate (the first one is the sign-in plate)' : 'Plates', style: context.text.titleMedium),
          const SizedBox(height: Sp.x2),
          Wrap(spacing: Sp.x2, runSpacing: Sp.x2, children: [
            for (final p in _plates)
              InputChip(
                label: Text(p),
                onDeleted: _busy || (!_isNew && normalizePlate(p) == normalizePlate(widget.account!.loginPlate)) ? null : () => _removePlate(p),
                deleteButtonTooltipMessage: 'Remove $p',
              ),
          ]),
          const SizedBox(height: Sp.x3),
          Row(children: [
            Expanded(child: AppField(controller: _plate, label: 'Add a plate', capitalization: TextCapitalization.characters, onSubmitted: (_) => _addPlate(), enabled: !_busy)),
            const SizedBox(width: Sp.x2),
            IconButton.filledTonal(tooltip: 'Add plate', onPressed: _busy ? null : _addPlate, icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: Sp.x3),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep a sign-in shortcut with this password'),
            subtitle: const Text('Shown on the sign-in page.'),
            value: _shortcut,
            onChanged: _busy ? null : (v) => setState(() => _shortcut = v),
          ),
          if (_error != null) ...[const SizedBox(height: Sp.x2), InfoBanner(message: _error!, tone: Tone.danger)],
          const SizedBox(height: Sp.x4),
          AppButton(label: _isNew ? 'Create account' : 'Save changes', onPressed: _save, loading: _busy),
          if (!_isNew) ...[
            const SizedBox(height: Sp.x2),
            AppButton(label: 'Delete account', kind: AppButtonKind.text, onPressed: _busy ? null : _delete),
          ],
        ]),
      ),
    );
  }
}


/// Name, plate and password of one sign-in shortcut. It owns its text boxes, so they live exactly as long as the dialog.
class _ShortcutDialog extends StatefulWidget {
  const _ShortcutDialog({required this.shortcut});

  final DemoAccount? shortcut;

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  late final _name = TextEditingController(text: widget.shortcut?.name ?? '');
  late final _plate = TextEditingController(text: widget.shortcut?.plate ?? '');
  late final _password = TextEditingController(text: widget.shortcut?.password ?? '');

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    _password.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty || normalizePlate(_plate.text).isEmpty || _password.text.isEmpty) return;
    Navigator.of(context).pop(DemoAccount(_name.text.trim(), _plate.text.trim().toUpperCase(), _password.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.shortcut == null ? 'New shortcut' : 'Edit shortcut'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: Sp.x2),
          AppField(controller: _name, label: 'Name on the button', action: TextInputAction.next),
          const SizedBox(height: Sp.x3),
          AppField(controller: _plate, label: 'Plate number', capitalization: TextCapitalization.characters, action: TextInputAction.next),
          const SizedBox(height: Sp.x3),
          AppField(controller: _password, label: 'Password', password: true, onSubmitted: (_) => _save()),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
