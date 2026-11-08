import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A periodic callback that runs only while its page is on screen.
///
/// The app shell keeps every page alive when you switch tabs, so scroll positions and form
/// state survive. A plain `Timer.periodic` inside such a page keeps firing in the background:
/// the Training Studio kept asking the backend for a 1.5 MB training log every 2 seconds
/// while someone watched a video on another page, and every answer held the backend for
/// 100 to 600 ms. This poller follows [TickerMode], which the shell turns off for the pages
/// that are not shown, so a hidden page costs the backend nothing.
///
/// It also never starts a tick while the previous one is still running, so a slow backend is
/// not buried under a growing queue of requests.
class VisiblePoller {
  VisiblePoller({required this.interval, required this.onTick, bool initiallyActive = true}) : _active = initiallyActive;

  final Duration interval;
  final FutureOr<void> Function() onTick;

  bool _active;
  bool _inFlight = false;
  bool _disposed = false;
  Timer? _timer;
  ValueListenable<TickerModeData>? _shown;

  /// True while ticks are being delivered (switched on, and the page is on screen).
  bool get running => _timer != null;

  /// Switches the poll on or off, for example only while a training run exists.
  bool get active => _active;
  set active(bool value) {
    _active = value;
    _sync();
  }

  /// Call from `didChangeDependencies`: starts following the page's visibility.
  void attach(BuildContext context) {
    final notifier = TickerMode.getValuesNotifier(context);
    if (identical(notifier, _shown)) return;
    _shown?.removeListener(_sync);
    _shown = notifier..addListener(_sync);
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final shown = _shown?.value.enabled ?? true;
    if (_active && shown) {
      if (_timer == null) {
        _fire(); // catch up at once when the page comes back
        _timer = Timer.periodic(interval, (_) => _fire());
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _fire() async {
    if (_inFlight || _disposed) return;
    _inFlight = true;
    try {
      await onTick();
    } catch (_) {
      // a failed poll is simply tried again on the next tick
    } finally {
      _inFlight = false;
    }
  }

  void dispose() {
    _disposed = true;
    _shown?.removeListener(_sync);
    _shown = null;
    _timer?.cancel();
    _timer = null;
  }
}
