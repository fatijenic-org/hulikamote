import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The one video player the trimmer uses (it opens whichever video is on screen). A small interface so tests can use a
/// stand-in: media_kit needs native libraries.
abstract class TrimPlayer {
  /// Seconds into the video.
  ValueListenable<double> get position;

  /// Length of the opened video in seconds (0 until it is known).
  ValueListenable<double> get duration;

  ValueListenable<bool> get playing;

  /// The video that is open now, if any (so coming back to it does not open it again).
  String? get openedPath;

  Future<void> open(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(double seconds);

  Widget view();

  void dispose();
}

typedef TrimPlayerFactory = TrimPlayer Function();

/// Seeks for a pointer that is dragging along a video: only the newest wish is kept while a seek is still running, so the
/// picture follows the pointer and requests never queue up behind a slow seek.
class ScrubSeeker {
  ScrubSeeker(this._seek);

  final Future<void> Function(double seconds) _seek;
  double? _pending;
  bool _busy = false;

  void request(double seconds) {
    _pending = seconds;
    if (!_busy) _drain();
  }

  Future<void> _drain() async {
    _busy = true;
    try {
      while (_pending != null) {
        final next = _pending!;
        _pending = null;
        await _seek(next);
      }
    } finally {
      _busy = false;
    }
  }
}

TrimPlayer defaultTrimPlayer() => MediaKitTrimPlayer();

class MediaKitTrimPlayer implements TrimPlayer {
  MediaKitTrimPlayer() {
    _subs.add(_player.stream.position.listen((p) => _position.value = p.inMilliseconds / 1000));
    _subs.add(_player.stream.duration.listen((d) => _duration.value = d.inMilliseconds / 1000));
    _subs.add(_player.stream.playing.listen((p) => _playing.value = p));
  }

  final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final _position = ValueNotifier<double>(0);
  final _duration = ValueNotifier<double>(0);
  final _playing = ValueNotifier<bool>(false);
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _openedPath;

  @override
  String? get openedPath => _openedPath;

  @override
  ValueListenable<double> get position => _position;
  @override
  ValueListenable<double> get duration => _duration;
  @override
  ValueListenable<bool> get playing => _playing;

  @override
  Future<void> open(String path) async {
    _openedPath = path;
    _position.value = 0;
    _duration.value = 0;                                  // the old video's length must not pass for this one's
    await _player.open(Media(path), play: false);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(double seconds) => _player.seek(Duration(milliseconds: (seconds * 1000).round()));

  @override
  Widget view() => Video(controller: _video, controls: NoVideoControls);   // the trimmer has its own controls

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _position.dispose();
    _duration.dispose();
    _playing.dispose();
  }
}
