import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/forensic_api.dart';
import 'forensic_models.dart';

enum RunPhase { idle, uploading, running, done, failed }

/// Starts an analysis and follows it until the backend is done.
/// Network hiccups are tolerated (a few failed polls in a row); the reviewer sees what stage
/// the work is in, how long it has taken, and a rough time left.
class AnalysisRunner extends ChangeNotifier {
  AnalysisRunner(
    this._api, {
    this.pollEvery = const Duration(seconds: 1),
    this.maxFailedPolls = 15,
  });

  final ForensicApi _api;
  final Duration pollEvery;
  final int maxFailedPolls;

  RunPhase _phase = RunPhase.idle;
  String? _taskId;
  double _progress = 0;
  String? _error;
  RunStatus? _result;
  DateTime? _startedAt;
  Timer? _timer;
  int _failedPolls = 0;
  bool _polling = false;
  String _message = ''; // what the backend says it is doing ("Reading plates: 12 of 340")
  bool _asking = false; // a Stop here / Cancel request is on its way
  String? _stopError;
  String? _notice; // shown on the start screen after a run that ended without a result (cancelled)
  int _ticketsReady = 0; // tickets the backend already released while it is still reading the video

  RunPhase get phase => _phase;

  /// Tickets that can already be opened and reviewed, while the analysis goes on.
  int get ticketsReady => _ticketsReady;
  bool get asking => _asking;

  /// Why the last Stop here / Cancel did not go through (e.g. an older backend without the stop endpoint).
  String? get stopError => _stopError;

  /// A one-line note for the start screen, e.g. that the last run was cancelled.
  String? get notice => _notice;
  String? get taskId => _taskId;
  double get progress => _progress;
  String? get error => _error;
  RunStatus? get result => _result;
  bool get active => _phase == RunPhase.uploading || _phase == RunPhase.running;

  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// Rough time left, once enough progress exists to extrapolate from.
  Duration? get remaining {
    if (_phase != RunPhase.running || _progress < 3 || _startedAt == null) {
      return null;
    }
    final perPercent = elapsed.inMilliseconds / _progress;
    return Duration(milliseconds: (perPercent * (100 - _progress)).round());
  }

  /// Plain-language stage. The backend spends 0-90 % on the frames, then encodes the
  /// evidence video, then reads the plates and builds the tickets.
  String get stage {
    switch (_phase) {
      case RunPhase.idle:
        return 'Ready';
      case RunPhase.uploading:
        return 'Sending the video to the analyzer…';
      case RunPhase.failed:
        return 'The analysis stopped';
      case RunPhase.done:
        return 'Finished';
      case RunPhase.running:
        if (_message.isNotEmpty) return _message; // the backend knows best (stopping, reading plates 12 of 340...)
        if (_progress < 90) return 'Watching the video and tracking vehicles';
        if (_progress < 96) return 'Preparing the evidence video';
        return 'Reading plates and building tickets';
    }
  }

  /// Uploads [videoPath] with [config] and starts following the task.
  Future<void> start(String videoPath, Map<String, dynamic> config) async {
    if (active) return;
    _reset();
    _phase = RunPhase.uploading;
    _startedAt = DateTime.now();
    notifyListeners();
    try {
      _taskId = await _api.submit(videoPath, config);
      _phase = RunPhase.running;
      notifyListeners();
      _timer = Timer.periodic(pollEvery, (_) => _poll());
      unawaited(_poll());
    } catch (e) {
      _fail('$e');
    }
  }

  Future<void> _poll() async {
    if (_polling || _taskId == null || _phase != RunPhase.running) return;
    _polling = true;
    try {
      final s = await _api.status(_taskId!);
      _failedPolls = 0;
      _progress = s.progress.clamp(0, 100).toDouble();
      _message = s.message;
      _ticketsReady = s.ticketCount;
      if (s.isCancelled) {
        _timer?.cancel();
        _reset();
        _notice = 'The last analysis was cancelled. Nothing was kept.';
        notifyListeners();
        return;
      }
      if (s.isDone) {
        _result = s;
        _finish(RunPhase.done);
        return;
      }
      if (s.isFailed) {
        _fail(s.error ?? 'The analysis failed on the server.');
        return;
      }
      notifyListeners();
    } catch (e) {
      _failedPolls++;
      if (_failedPolls >= maxFailedPolls) {
        _fail(
          'Lost the connection to the analyzer. It may still be running: check the Library in a minute.',
        );
      }
    } finally {
      _polling = false;
    }
  }

  /// "Stop here": the backend stops reading the video and keeps everything found so far. It then reads the plates
  /// of what it found; press it again during that to skip the plates not read yet.
  Future<void> stopHere() => _stop(keep: true);

  /// Cancel: the backend throws the whole run away (no tickets, no files).
  Future<void> cancel() => _stop(keep: false);

  Future<void> _stop({required bool keep}) async {
    if (_phase != RunPhase.running || _taskId == null || _asking) return;
    _asking = true;
    _stopError = null;
    notifyListeners();
    try {
      await _api.stopRun(_taskId!, keep: keep);
      unawaited(_poll()); // show the new status line at once
    } catch (e) {
      _stopError = e is ForensicApiException ? e.message : '$e';
    } finally {
      _asking = false;
      notifyListeners();
    }
  }

  void _finish(RunPhase phase) {
    _timer?.cancel();
    _timer = null;
    _phase = phase;
    if (phase == RunPhase.done) _progress = 100;
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    _finish(RunPhase.failed);
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    _taskId = null;
    _progress = 0;
    _error = null;
    _result = null;
    _failedPolls = 0;
    _message = '';
    _ticketsReady = 0;
    _asking = false;
    _stopError = null;
    _notice = null;
    _phase = RunPhase.idle;
  }

  /// Back to idle (after the result was opened, or to try again).
  void clear() {
    _reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
