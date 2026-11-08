import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/notice.dart';
import '../../../core/services/notice_poller.dart';
import '../../../core/services/portal_api.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/session.dart';
import '../../home/screens/home_screen.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../profile/screens/profile_screen.dart';

/// The three pages of the app: Records, Inbox, Profile. It also keeps watching for new notices while the app is open, and
/// opens the Inbox when the motorist taps a notification.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.api, this.showNotification});

  /// Injected by tests; the app talks to the system.
  final PortalApi? api;

  /// Raises a phone notification. Replaced in tests.
  final Future<void> Function(String title, String body)? showNotification;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _recordsTab = 0, _inboxTab = 1;

  PortalApi get _api => widget.api ?? PortalApi();
  final _newNotices = ValueNotifier<int>(0);       // counts notices that arrived while the app is open
  int _unread = 0;
  late int _currentIndex = PushNotificationService.inboxRequests.value > 0 ? _inboxTab : _recordsTab;
  NoticePoller? _poller;

  @override
  void initState() {
    super.initState();
    PushNotificationService.inboxRequests.addListener(_openInbox);
    _startPolling();
  }

  void _openInbox() => _select(_inboxTab);

  void _select(int index) {
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      if (index == _inboxTab) _unread = 0;
    });
  }

  /// While the app is open it checks every few seconds, so a confirmed ticket reaches the phone even with no push (on the
  /// same Wi-Fi it needs no internet at all).
  Future<void> _startPolling() async {
    final account = await Session.current();
    if (account == null || !mounted) return;
    _poller = NoticePoller(
      api: _api,
      userId: account.userId,
      onNew: _onNewNotice,
      every: AppConfig.isOnline ? const Duration(seconds: 10) : const Duration(seconds: 5),
    );
    await _poller!.start();
  }

  void _onNewNotice(Notice notice) {
    final show = widget.showNotification ?? PushNotificationService.instance.showLocalNotification;
    show(notice.title, notice.body.split('\n').skip(2).firstWhere((l) => l.trim().isNotEmpty, orElse: () => notice.body));
    _newNotices.value++;
    if (mounted && _currentIndex != _inboxTab) setState(() => _unread++);
  }

  @override
  void dispose() {
    PushNotificationService.inboxRequests.removeListener(_openInbox);
    _poller?.stop();
    _newNotices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(api: widget.api),
          NotificationsScreen(api: widget.api, newNotices: _newNotices),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _select,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Records'),
          NavigationDestination(
            icon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: const Icon(Icons.notifications_outlined)),
            selectedIcon: const Icon(Icons.notifications),
            label: 'Inbox',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
