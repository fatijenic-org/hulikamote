import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/registry_api.dart';
import '../../domain/registry_models.dart';

/// How motorists are notified: Online (Gmail) or Offline (a phone on the same Wi-Fi or hotspot opens the laptop's
/// mailbox page). One click switches; Online also needs the Gmail address and its app password, kept in
/// hulikamote_backend/.env.
class NoticeCard extends StatefulWidget {
  const NoticeCard({super.key, required this.api, required this.onMessage, this.refresh = 0});

  final RegistryApi api;

  /// Changes when the page is refreshed, so the card reads the settings and last notices again.
  final int refresh;

  /// Where to tell the user how a change went.
  final void Function(String message) onMessage;

  @override
  State<NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<NoticeCard> {
  final _gmail = TextEditingController();
  final _password = TextEditingController();
  final _testTo = TextEditingController();
  final _cloudUrl = TextEditingController();
  final _cloudKey = TextEditingController();
  final _token = TextEditingController();

  NoticeSettings? _settings;
  String? _error;
  String _choice = 'offline';          // the segment on screen; "online" shows the Gmail form even before it is saved
  bool _busy = false;
  String? _pushDetail;        // what the last push check or test said
  bool _remember = false;     // keep the Supabase access token on the laptop (off: it is forgotten after the setup)
  CloudSetupResult? _setup;   // the checklist of the last "Set up cloud"

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NoticeCard old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh) _load();
  }

  @override
  void dispose() {
    _gmail.dispose();
    _password.dispose();
    _testTo.dispose();
    _cloudUrl.dispose();
    _cloudKey.dispose();
    _token.dispose();
    super.dispose();
  }

  void _apply(NoticeSettings s) {
    _settings = s;
    _error = null;
    _choice = s.mode;
    _gmail.text = s.gmail;
    _password.clear();
    _cloudUrl.text = s.cloudUrl;
    _cloudKey.clear();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.noticeSettings();
      if (mounted) setState(() => _apply(s));
    } on RegistryApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Runs one change on the backend and shows what is saved afterwards.
  Future<void> _save({
    required String mode,
    String gmail = '',
    String password = '',
    String cloudUrl = '',
    String cloudKey = '',
    String done = 'Saved.',
  }) async {
    setState(() => _busy = true);
    try {
      final s = await widget.api.saveNoticeSettings(
        mode: mode,
        gmail: gmail,
        appPassword: password,
        supabaseUrl: cloudUrl,
        supabaseServiceKey: cloudKey,
      );
      if (mounted) {
        setState(() => _apply(s));
        widget.onMessage(done);
      }
    } on RegistryApiException catch (e) {
      if (mounted) widget.onMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(String mode) async {
    final s = _settings;
    if (s == null || mode == _choice) return;
    if (mode == 'offline') {
      await _save(mode: 'offline', done: 'Offline: notices wait in the laptop\'s mailbox.');
    } else if ((s.passwordSet && s.gmail.isNotEmpty) || (s.cloudKeySet && s.cloudUrl.isNotEmpty)) {
      await _save(mode: 'online', done: 'Online: tickets go to the phone app and by e-mail.');
    } else {
      setState(() => _choice = 'online');                // show the form; Save switches it on
    }
  }

  bool get _formChanged {
    final s = _settings;
    return s != null && (_gmail.text.trim() != s.gmail || _password.text.trim().isNotEmpty || !s.online);
  }

  bool get _cloudChanged {
    final s = _settings;
    return s != null && (_cloudUrl.text.trim() != s.cloudUrl || _cloudKey.text.trim().isNotEmpty);
  }

  Future<void> _createDemoAccounts() async {
    setState(() => _busy = true);
    try {
      final results = await widget.api.createCloudDemoAccounts();
      final made = results.where((r) => r.status == 'created').length;
      final had = results.where((r) => r.status == 'exists').length;
      final failed = results.where((r) => r.status == 'failed').toList();
      if (mounted) {
        widget.onMessage(failed.isEmpty
            ? 'Demo accounts in the cloud: $made created, $had already there.'
            : 'Demo accounts: ${failed.length} failed (${failed.first.plate}: ${failed.first.detail})');
      }
    } on RegistryApiException catch (e) {
      if (mounted) widget.onMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setUpCloud() async {
    setState(() {
      _busy = true;
      _setup = null;
    });
    try {
      final r = await widget.api.setUpCloud(supabaseUrl: _cloudUrl.text.trim(), accessToken: _token.text.trim(), rememberToken: _remember);
      if (!mounted) return;
      if (r.ok) _token.clear();                 // done: the token is not needed here any more (a failed run keeps it for the retry)
      setState(() => _setup = r);
      final failed = r.steps.where((s) => !s.ok && !s.warn).toList();
      widget.onMessage(r.ok
          ? 'Cloud is ready.'
          : failed.isNotEmpty
              ? 'Setup stopped at: ${failed.first.text}. ${failed.first.detail}'
              : 'Cloud is ready, with a warning. See the list.');
      await _load();
    } on RegistryApiException catch (e) {
      if (mounted) widget.onMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickKeyFile() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Firebase service-account file (.json)', type: FileType.custom, allowedExtensions: ['json']);
    final path = picked?.path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.installPushKey(await File(path).readAsString());
      if (mounted) {
        setState(() => _pushDetail = r.detail);
        widget.onMessage(r.detail);
      }
    } on RegistryApiException catch (e) {
      if (mounted) widget.onMessage(e.message);
    } on FileSystemException {
      if (mounted) widget.onMessage('Cannot read that file.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stepRow(SetupStep step) {
    final color = step.ok ? Fx.success : (step.warn ? Fx.warning : Fx.danger);
    final icon = step.ok ? Icons.check_circle_outline : (step.warn ? Icons.warning_amber_rounded : Icons.cancel_outlined);
    return Padding(
      padding: const EdgeInsets.only(bottom: Fx.s4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: Fx.s8),
        Expanded(child: Text(step.detail.isEmpty ? step.text : '${step.text}: ${step.detail}', style: Fx.caption(context))),
      ]),
    );
  }

  Future<void> _push({required bool send}) async {
    setState(() => _busy = true);
    try {
      final r = send ? await widget.api.sendTestPush() : await widget.api.pushCheck();
      if (mounted) {
        setState(() => _pushDetail = r.detail);
        widget.onMessage(r.detail);
      }
    } on RegistryApiException catch (e) {
      if (mounted) widget.onMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testCloud() async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.testCloud();
      if (mounted) widget.onMessage(r.ok ? 'Cloud: ${r.detail}' : 'Cloud problem: ${r.detail}');
    } on RegistryApiException catch (e) {
      if (mounted) widget.onMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendTest() async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.sendTestEmail(to: _testTo.text.trim());
      if (mounted) widget.onMessage(r.sent ? 'Test e-mail sent to ${r.to}. Check that inbox.' : 'The test e-mail failed: ${r.detail}');
    } on RegistryApiException catch (e) {
      if (mounted) widget.onMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return FxCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionLabel('How motorists are notified'),
        if (_error != null)
          FxBanner(message: _error!, action: TextButton(onPressed: _load, child: const Text('Try again')))
        else if (s == null)
          const Padding(padding: EdgeInsets.all(Fx.s8), child: LinearProgressIndicator())
        else ...[
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'online', icon: Icon(Icons.mail_outline), label: Text('Online')),
              ButtonSegment(value: 'offline', icon: Icon(Icons.wifi), label: Text('Offline (same Wi-Fi)')),
            ],
            selected: {_choice},
            onSelectionChanged: _busy ? null : (picked) => _choose(picked.first),
          ),
          const SizedBox(height: Fx.s16),
          if (_choice == 'online') _online(s) else _offline(s),
          if (s.notices.isNotEmpty) ...[
            const SizedBox(height: Fx.s16),
            const SectionLabel('Last notices'),
            for (final n in s.notices) _NoticeRow(n),
          ],
        ],
      ]),
    );
  }

  Widget _online(NoticeSettings s) {
    final canTest = !_busy && s.passwordSet && !_formChanged && _testTo.text.contains('@');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('E-mail: notices are sent FROM a Gmail account made for HULI-KAMOTE (for example hulikamote.demo@gmail.com), TO each motorist\'s e-mail below.',
          style: Fx.caption(context)),
      Text('Get the app password: Google Account → Security → 2-Step Verification → App passwords.', style: Fx.caption(context)),
      const SizedBox(height: Fx.s12),
      Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _gmail,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(isDense: true, labelText: 'Sender Gmail (the HULI-KAMOTE account)', border: OutlineInputBorder()),
          ),
        ),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _password,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'App password',
              hintText: s.passwordSet ? 'Saved. Type to change it' : '16 letters',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        FilledButton(
          onPressed: _busy || !_formChanged
              ? null
              : () => _save(mode: 'online', gmail: _gmail.text.trim(), password: _password.text, done: 'Saved. Notices are e-mailed through Gmail.'),
          child: Text(s.online ? 'Save' : 'Save and switch on'),
        ),
      ]),
      const SizedBox(height: Fx.s12),
      Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _testTo,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(isDense: true, labelText: 'Send the test to (your own e-mail)', border: OutlineInputBorder()),
          ),
        ),
        OutlinedButton(onPressed: canTest ? _sendTest : null, child: const Text('Send test e-mail')),
      ]),
      const SizedBox(height: Fx.s16),
      Divider(height: 1, color: Fx.border(context)),
      const SizedBox(height: Fx.s12),
      Text('Phone app (works anywhere)', style: Fx.heading(context)),
      Text(
        'One click builds everything in your Supabase project (tables, photo bucket, demo accounts). Paste the project address and an '
        'access token once (supabase.com/dashboard/account/tokens, full access). The token is forgotten afterwards unless you tick "remember".',
        style: Fx.caption(context),
      ),
      const SizedBox(height: Fx.s12),
      Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _cloudUrl,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(isDense: true, labelText: 'Project address', hintText: 'https://your-project.supabase.co', border: OutlineInputBorder()),
          ),
        ),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _token,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Access token (secret)',
              hintText: s.tokenSaved ? 'Saved on this laptop' : 'sbp_...',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.cloud_done_outlined, size: 18),
          onPressed: _busy || _cloudUrl.text.trim().isEmpty || !(_token.text.trim().isNotEmpty || s.tokenSaved) ? null : _setUpCloud,
          label: Text(s.cloudReady ? 'Set up cloud again' : 'Set up cloud'),
        ),
      ]),
      Row(children: [
        Checkbox(value: _remember, onChanged: _busy ? null : (v) => setState(() => _remember = v ?? false)),
        Flexible(child: Text('Remember this token on this laptop (kept in backend/.env, never in git)', style: Fx.caption(context))),
      ]),
      if (_busy && _setup == null) const Padding(padding: EdgeInsets.symmetric(vertical: Fx.s8), child: LinearProgressIndicator()),
      if (_setup != null) ...[
        const SizedBox(height: Fx.s8),
        for (final step in _setup!.steps) _stepRow(step),
        if (_setup!.ok) ...[
          const SizedBox(height: Fx.s8),
          Text('Done. In the phone app, press Connect (it finds this laptop and the cloud by itself).', style: Fx.caption(context)),
        ],
      ],
      const SizedBox(height: Fx.s12),
      Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton(onPressed: _busy ? null : () => _push(send: false), child: const Text('Check push')),
        OutlinedButton(onPressed: _busy ? null : () => _push(send: true), child: const Text('Send test push')),
        OutlinedButton.icon(
          icon: const Icon(Icons.vpn_key_outlined, size: 18),
          onPressed: _busy ? null : _pickKeyFile,
          label: const Text('Choose Firebase key file'),
        ),
      ]),
      if (_pushDetail != null) ...[
        const SizedBox(height: Fx.s8),
        Text('Push: $_pushDetail', style: Fx.caption(context)),
      ],
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text('Advanced: type the service key myself', style: Fx.caption(context)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _cloudKey,
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Service key (secret)',
                      hintText: s.cloudKeySet ? 'Saved. Type to change it' : 'service_role key',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _busy || !_cloudChanged
                      ? null
                      : () => _save(mode: 'online', cloudUrl: _cloudUrl.text.trim(), cloudKey: _cloudKey.text, done: 'Cloud saved.'),
                  child: const Text('Save cloud'),
                ),
                OutlinedButton(
                  onPressed: _busy || !s.cloudKeySet || _cloudChanged ? null : _testCloud,
                  child: const Text('Test cloud'),
                ),
                OutlinedButton(
                  onPressed: _busy || !s.cloudKeySet || _cloudChanged ? null : _createDemoAccounts,
                  child: const Text('Create demo accounts'),
                ),
              ]),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _offline(NoticeSettings s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('No internet needed. Put the phone on the same Wi-Fi (or on this laptop\'s hotspot) and open this address in its browser:',
          style: Fx.caption(context)),
      const SizedBox(height: Fx.s8),
      if (s.mailboxUrls.isEmpty)
        const FxBanner(
          message: 'No Wi-Fi or hotspot address found. Connect this laptop to the phone\'s network first.',
          color: Fx.warning,
          icon: Icons.wifi_off,
        )
      else
        for (final url in s.mailboxUrls)
          Row(children: [
            SelectableText(url, style: Fx.plate.copyWith(fontSize: 16)),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy address',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                widget.onMessage('Address copied.');
              },
            ),
          ]),
    ]);
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow(this.notice);

  final NoticeRecord notice;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (notice.status) {
      'sent' => ('E-mailed', Fx.success, Icons.mark_email_read_outlined),
      'failed' => ('Failed', Fx.danger, Icons.error_outline),
      _ => ('In mailbox', Fx.accent, Icons.inbox_outlined),
    };
    final at = notice.createdAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: Fx.s4),
      child: Row(children: [
        SizedBox(width: 110, child: Align(alignment: Alignment.centerLeft, child: StatusPill(label: label, color: color, icon: icon, dense: true))),
        SizedBox(width: 130, child: Text(notice.userName, style: Fx.body(context), overflow: TextOverflow.ellipsis)),
        Expanded(
          child: Text(
            notice.status == 'failed' ? '${notice.subject} (${notice.detail})' : notice.subject,
            style: Fx.caption(context),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (at != null) Text('${two(at.hour)}:${two(at.minute)}:${two(at.second)}', style: Fx.caption(context)),
      ]),
    );
  }
}
