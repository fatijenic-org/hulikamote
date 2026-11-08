import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/account.dart';
import '../../../core/models/notice.dart';
import '../../../core/services/friendly_error.dart';
import '../../../core/services/local_cache.dart';
import '../../../core/services/portal_api.dart';
import '../../../core/services/session.dart';
import '../../../core/ui/app_theme.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/widgets/frame_gallery.dart';

/// The Inbox: the notices written when the motorist's tickets were confirmed (the same text the e-mail has), newest
/// first, grouped by day, with a dot on the ones not opened yet. Shows what was saved last time when offline.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.api, this.newNotices});

  /// Injected by tests; the app talks to the system.
  final PortalApi? api;

  /// Changes whenever the app saw a new notice arrive, so the list reloads by itself.
  final ValueListenable<int>? newNotices;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with AutomaticKeepAliveClientMixin {
  PortalApi get _api => widget.api ?? PortalApi();

  Account? _account;
  List<Notice>? _notices;
  Set<String> _read = {};
  DateTime? _savedAt;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.newNotices?.addListener(_load);
    _start();
  }

  @override
  void dispose() {
    widget.newNotices?.removeListener(_load);
    super.dispose();
  }

  String get _readKey => 'inbox_read_${_account?.userId}';

  Future<void> _start() async {
    final account = await Session.current();
    if (account == null || !mounted) return;
    _account = account;
    _read = ((await SharedPreferences.getInstance()).getStringList(_readKey) ?? const []).toSet();
    await _load();
  }

  Future<void> _load() async {
    final account = _account;
    if (account == null) return;
    try {
      final notices = await _api.notices(account.userId);
      await LocalCache.save('notices', account.userId, [for (final n in notices) n.toJson()]);
      if (mounted) {
        setState(() {
          _notices = notices;
          _savedAt = null;
          _error = null;
        });
      }
    } catch (e) {
      if (_notices != null && _savedAt == null) {
        if (mounted) AppToast.show(context, 'Could not refresh. ${friendlyMessage(e)}', error: true);
        return;
      }
      final saved = await LocalCache.load('notices', account.userId);
      if (!mounted) return;
      setState(() {
        if (saved == null) {
          _error = friendlyMessage(e);
        } else {
          _notices = [for (final n in saved.data as List) Notice.fromJson(Map<String, dynamic>.from(n as Map))];
          _savedAt = saved.at;
          _error = null;
        }
      });
    }
  }

  Future<void> _markRead(Notice n) async {
    if (_read.contains(n.id)) return;
    setState(() => _read = {..._read, n.id});
    (await SharedPreferences.getInstance()).setStringList(_readKey, _read.toList());
  }

  void _open(Notice n) {
    _markRead(n);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.title, style: context.text.headlineSmall),
            const SizedBox(height: Sp.x1),
            Text(dateTimeOf(n.time), style: context.text.bodyMedium?.copyWith(color: context.muted)),
            const SizedBox(height: Sp.x5),
            Card(child: Padding(padding: const EdgeInsets.all(Sp.x4), child: SelectableText(n.body, style: context.text.bodyLarge))),
            if (n.frames.isNotEmpty) ...[const SizedBox(height: Sp.x5), FrameGallery(names: n.frames)],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final notices = _notices;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x6, Sp.page, Sp.x4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Semantics(header: true, child: Text('Inbox', style: context.text.headlineMedium)),
                    const SizedBox(height: Sp.x1),
                    Text('Notices about your tickets', style: context.text.bodyLarge?.copyWith(color: context.muted)),
                    if (_savedAt != null) ...[
                      const SizedBox(height: Sp.x4),
                      InfoBanner(
                        tone: Tone.warning,
                        icon: Icons.cloud_off_outlined,
                        message: 'Cannot reach the system. Showing what was saved ${ago(_savedAt!, DateTime.now())}.',
                        actionLabel: 'Retry',
                        onAction: _load,
                      ),
                    ],
                  ]),
                ),
              ),
              if (notices == null && _error == null)
                const SliverPadding(padding: EdgeInsets.symmetric(horizontal: Sp.page), sliver: SliverToBoxAdapter(child: SkeletonList(count: 3)))
              else if (_error != null)
                SliverFillRemaining(hasScrollBody: false, child: ErrorState(message: _error!, onRetry: _load))
              else if (notices!.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.mark_email_unread_outlined,
                    title: 'No notices yet',
                    message: 'You will get a notice here, and a notification, when a ticket is confirmed for your plate.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x6),
                  sliver: SliverList.list(children: _items(context, notices)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _items(BuildContext context, List<Notice> notices) {
    final now = DateTime.now();
    final items = <Widget>[];
    String? lastDay;
    for (final n in notices) {
      final t = n.time;
      final day = t == null ? '' : dayHeader(t, now);
      if (day != lastDay) {
        items.add(Padding(
          padding: EdgeInsets.only(top: lastDay == null ? 0 : Sp.x5, bottom: Sp.x2),
          child: Semantics(header: true, child: Text(day, style: context.text.labelLarge?.copyWith(color: context.muted))),
        ));
        lastDay = day;
      }
      items.add(Padding(padding: const EdgeInsets.only(bottom: Sp.x3), child: _NoticeTile(notice: n, unread: !_read.contains(n.id), onTap: () => _open(n))));
    }
    return items;
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({required this.notice, required this.unread, required this.onTap});

  final Notice notice;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = notice.time == null ? '' : timeOf(notice.time!);
    return Semantics(
      button: true,
      label: '${unread ? 'Unread. ' : ''}${notice.title}, $time',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Sp.x4),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: context.colors.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.notifications_none_rounded, color: context.colors.onPrimaryContainer),
              ),
              const SizedBox(width: Sp.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(notice.title, style: context.text.titleMedium?.copyWith(fontWeight: unread ? FontWeight.w700 : FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(time, style: context.text.bodyMedium?.copyWith(color: context.muted)),
                ]),
              ),
              if (unread) Container(width: 10, height: 10, decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle)),
              const SizedBox(width: Sp.x2),
              Icon(Icons.chevron_right_rounded, color: context.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
