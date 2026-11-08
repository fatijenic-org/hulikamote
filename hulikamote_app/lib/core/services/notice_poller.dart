import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/notice.dart';
import 'portal_api.dart';

/// Asks the laptop every few seconds whether a new notice arrived for this motorist, and hands each new one to
/// [onNew] once (the app turns it into a phone notification). It needs no internet, only the same network as the laptop.
class NoticePoller {
  NoticePoller({required this.api, required this.userId, required this.onNew, this.every = const Duration(seconds: 5)});

  final PortalApi api;
  final String userId;
  final void Function(Notice notice) onNew;
  final Duration every;

  Timer? _timer;
  String? _after;                // server time of the newest notice already seen
  bool _busy = false;

  String get _key => 'notices_seen_$userId';

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _after = prefs.getString(_key);
    await poll();
    _timer ??= Timer.periodic(every, (_) => poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final fresh = await api.notices(userId, after: _after);
      if (_after == null) {
        await _remember(fresh);          // first run on this phone: what is already there is not "new"
        return;
      }
      if (fresh.isEmpty) return;
      for (final notice in fresh.reversed) {
        onNew(notice);                   // oldest first
      }
      await _remember(fresh);
    } on PortalException {
      // the laptop is out of reach for now; try again on the next tick
    } finally {
      _busy = false;
    }
  }

  Future<void> _remember(List<Notice> newestFirst) async {
    _after = newestFirst.isEmpty ? '' : newestFirst.first.createdAt;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _after!);
  }
}
