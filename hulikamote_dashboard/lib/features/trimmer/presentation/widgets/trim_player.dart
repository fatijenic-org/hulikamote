import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:hulikamote_dashboard/core/theme/light_mode.dart';

import '../../data/trimmer_api.dart';

/// What the player is doing before the picture appears ("Making a smooth preview ... 40%"), or null.
final ValueNotifier<String?> trimPreviewStatus = ValueNotifier<String?>(null);

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
  MediaKitTrimPlayer({TrimmerApi? api}) : _api = api ?? TrimmerApi() {
    _subs.add(_player.stream.position.listen((p) => _position.value = p.inMilliseconds / 1000));
    _subs.add(_player.stream.duration.listen((d) => _duration.value = d.inMilliseconds / 1000));
    _subs.add(_player.stream.playing.listen((p) {
      _playing.value = p;
      if (p) _watchForStall();
    }));
    _subs.add(_player.stream.error.listen((_) => _fallBackToCopy()));
    final platform = _player.platform;
    if (platform is NativePlayer) {
      // The graphics card decodes the picture (a 4K file at 48 Mbps is too much for the processor); "-copy" hands the picture back to
      // the processor, which every renderer can show.
      platform.setProperty('hwdec', 'auto-copy');
      platform.setProperty('vd-lavc-threads', '0');
    }
  }

  final TrimmerApi _api;
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
    _usingCopy = false;
    _stallTimer?.cancel();
    await _player.open(Media(path), play: false);          // the video itself, like any player
  }

  bool _usingCopy = false;
  Timer? _stallTimer;

  /// Playing was pressed: if the picture has not moved after a few seconds, the video is too heavy for this player.
  void _watchForStall() {
    if (_usingCopy) return;
    _stallTimer?.cancel();
    final from = _position.value;
    final path = _openedPath;
    _stallTimer = Timer(const Duration(seconds: 6), () {
      if (_playing.value && _openedPath == path && (_position.value - from).abs() < 0.3) _fallBackToCopy();
    });
  }

  /// Plays a small copy made by the backend instead (once per video), at the same moment, if the original cannot be played.
  Future<void> _fallBackToCopy() async {
    final path = _openedPath;
    if (_usingCopy || path == null) return;
    _usingCopy = true;
    final at = _position.value, wasPlaying = _playing.value;
    final playable = await _playable(path);
    if (_openedPath != path || playable == path) return;   // the video changed meanwhile, or no copy could be made
    await _player.open(Media(playable), play: false);
    if (at > 0) await _player.seek(Duration(milliseconds: (at * 1000).round()));
    if (wasPlaying) await _player.play();
  }

  /// A big video (4K at 48 Mbps stalls the player) is played from a small copy the backend makes once; a light video as it is.
  /// If the backend cannot make the copy, the original is tried.
  Future<String> _playable(String path) async {
    try {
      final deadline = DateTime.now().add(const Duration(minutes: 40));
      while (DateTime.now().isBefore(deadline) && _openedPath == path) {
        final p = await _api.preview(path);
        if (p.state == 'ready') {
          trimPreviewStatus.value = null;
          return p.path;
        }
        if (p.state == 'failed') break;
        trimPreviewStatus.value = 'Making a smooth preview of this large video… ${(p.progress * 100).round()}%\n(done once, the cuts still come from the original)';
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    } catch (_) {
      // the backend did not answer: the original is tried
    }
    if (_openedPath == path) trimPreviewStatus.value = null;
    return path;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(double seconds) => _player.seek(Duration(milliseconds: (seconds * 1000).round()));

  @override
  Widget view() => KeepColors(child: Video(controller: _video, controls: NoVideoControls));   // the trimmer has its own controls

  @override
  void dispose() {
    _stallTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _position.dispose();
    _duration.dispose();
    _playing.dispose();
  }
}
