import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/app_info.dart';
import '../../../core/models/account.dart';
import '../../../core/services/dev_mode.dart';
import '../../../core/services/local_cache.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/session.dart';
import '../../../core/ui/app_theme.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets.dart';
import '../../auth/widgets/auth_widgets.dart';
import '../../auth/widgets/connection_dialog.dart';
import '../../dev/dev_tools_screen.dart';

/// The account, how the phone connects, notification settings, and sign out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with AutomaticKeepAliveClientMixin {
  Account? _account;
  bool? _notificationsOn;
  int _versionTaps = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = await Session.current();
    if (mounted) setState(() => _account = account);              // show the person first
    final allowed = await PushNotificationService.instance.notificationsAllowed();   // the phone may be slow to answer this
    if (mounted) setState(() => _notificationsOn = allowed);
  }

  Future<void> _changeConnection() async {
    await showConnectionDialog(context);
    if (mounted) setState(() {});
  }

  Future<void> _testNotification() async {
    try {
      await PushNotificationService.instance.showTestNotification();
      if (mounted) AppToast.show(context, 'Test notification sent. Look at the top of your screen.');
    } catch (_) {
      if (mounted) AppToast.show(context, 'This phone would not show a notification. Check the app\'s notification settings.', error: true);
    }
  }

  /// Seven taps on the version line switch on the developer tools (temporary).
  void _versionTapped() {
    if (DevMode.enabled.value) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DevToolsScreen()));
      return;
    }
    _versionTaps++;
    final left = DevMode.tapsToUnlock - _versionTaps;
    if (left <= 0) {
      _versionTaps = 0;
      DevMode.set(true);
      AppToast.show(context, 'Developer mode is on.');
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DevToolsScreen()));
    } else if (left <= 3) {
      AppToast.show(context, '$left more taps for developer mode.');
    }
  }

  Future<void> _signOut() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will stop getting notifications on this phone until you sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final account = _account;
    await PushNotificationService.forgetCurrentUser();           // needs the sign-in, so before it is cleared
    if (account != null) await LocalCache.clear(account.userId);
    await Session.clear();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final a = _account;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x6, Sp.page, Sp.x8),
          children: [
            Semantics(header: true, child: Text('Profile', style: context.text.headlineMedium)),
            const SizedBox(height: Sp.x5),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Sp.x4),
                child: Row(children: [
                  InitialsAvatar(a?.name ?? ''),
                  const SizedBox(width: Sp.x4),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a?.name ?? '', style: context.text.titleLarge),
                      const SizedBox(height: Sp.x1),
                      if (a != null && a.plate.isNotEmpty) StatusChip(label: 'Plate ${a.plate}', tone: Tone.neutral, icon: Icons.directions_car_outlined),
                      if (a != null && a.email.isNotEmpty) ...[
                        const SizedBox(height: Sp.x2),
                        Text(a.email, style: context.text.bodyMedium?.copyWith(color: context.muted)),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: Sp.x6),
            const SectionTitle('Connection'),
            Card(
              child: ListTile(
                leading: Icon(AppConfig.isOnline ? Icons.cloud_outlined : Icons.wifi),
                title: Text(AppConfig.isOnline ? 'Online' : 'Same Wi-Fi'),
                subtitle: Text(AppConfig.ready ? ConnectionPill.where() : 'Not connected yet'),
                trailing: TextButton(onPressed: _changeConnection, child: const Text('Change')),
              ),
            ),
            const SizedBox(height: Sp.x6),
            const SectionTitle('Notifications'),
            Card(
              child: Column(children: [
                ListTile(
                  leading: Icon(_notificationsOn == false ? Icons.notifications_off_outlined : Icons.notifications_active_outlined),
                  title: const Text('Notifications on this phone'),
                  subtitle: Text(_notificationsOn == null ? 'Not known' : (_notificationsOn! ? 'On' : 'Off. Turn them on in the phone\'s settings.')),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.send_outlined),
                  title: const Text('Send a test notification'),
                  subtitle: const Text('Checks that this phone shows them.'),
                  onTap: _testNotification,
                ),
              ]),
            ),
            const SizedBox(height: Sp.x6),
            AppButton(label: 'Sign out', icon: Icons.logout_rounded, kind: AppButtonKind.secondary, onPressed: _signOut),
            const SizedBox(height: Sp.x6),
            Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(Rd.sm),
                onTap: _versionTapped,
                child: Padding(
                  padding: const EdgeInsets.all(Sp.x3),
                  child: Text('${AppInfo.name} · version ${AppInfo.version}', style: context.text.bodyMedium?.copyWith(color: context.muted)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
