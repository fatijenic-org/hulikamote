import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hulikamote_dashboard/features/trimmer/data/trimmer_api.dart';
import 'package:hulikamote_dashboard/features/trimmer/domain/trimmer_models.dart';
import 'package:hulikamote_dashboard/features/trimmer/presentation/widgets/trim_player.dart';

/// A player that plays nothing: it only remembers what it was asked to do.
class FakeTrimPlayer implements TrimPlayer {
  FakeTrimPlayer({this.lengths = const {}, this.reportsLength = true});

  /// false: the player never says how long the video is (slow to open).
  bool reportsLength;

  /// Seconds of each video, by path; the length is announced when the video is opened.
  final Map<String, double> lengths;

  final _position = ValueNotifier<double>(0);
  final _duration = ValueNotifier<double>(0);
  final _playing = ValueNotifier<bool>(false);
  final opened = <String>[];
  final seeks = <double>[];
  int plays = 0, pauses = 0;
  bool disposed = false;
  String? _opened;

  @override
  String? get openedPath => _opened;

  @override
  ValueListenable<double> get position => _position;
  @override
  ValueListenable<double> get duration => _duration;
  @override
  ValueListenable<bool> get playing => _playing;

  /// Moves the playhead as if the video were playing.
  void moveTo(double seconds) => _position.value = seconds;

  @override
  Future<void> open(String path) async {
    opened.add(path);
    _opened = path;
    _position.value = 0;
    _duration.value = 0;
    if (reportsLength) _duration.value = lengths[path] ?? 100;
  }

  @override
  Future<void> play() async {
    plays++;
    _playing.value = true;
  }

  @override
  Future<void> pause() async {
    pauses++;
    _playing.value = false;
  }

  @override
  Future<void> seek(double seconds) async {
    seeks.add(seconds);
    _position.value = seconds;
  }

  @override
  Widget view() => const SizedBox.expand(key: ValueKey('fake-video'));

  @override
  void dispose() => disposed = true;
}

/// What the screen asked the backend to cut.
class StartCall {
  StartCall(this.path, this.clips, this.exact, this.outputDir);

  final String path;
  final List<ClipRequest> clips;
  final bool exact;
  final String outputDir;
}

/// A backend that answers from memory. Jobs stay "running" until the test finishes them.
class FakeTrimmerApi extends TrimmerApi {
  FakeTrimmerApi({this.lengths = const {}}) : super(baseUrl: 'http://test');

  final Map<String, double> lengths;
  final starts = <StartCall>[];
  final cancelled = <String>[];
  final List<Map<String, dynamic>> _jobs = [];
  int jobsCalls = 0;
  int clearCalls = 0;
  TrimmerApiException? probeError;
  TrimmerApiException? startError;

  /// When set, the answer to "how long is this video" waits until the test completes it.
  Completer<void>? probeGate;
  var _next = 1;

  @override
  Future<ProbeInfo> probe(String path) async {
    if (probeGate != null) await probeGate!.future;
    if (probeError != null) throw probeError!;
    return ProbeInfo(duration: lengths[path] ?? 100, fps: 25, width: 1280, height: 720);
  }

  @override
  String filmstripUrl(String path, {int count = 24}) => 'http://test/film.jpg';

  @override
  Future<List<TrimJob>> startJobs(String path, List<ClipRequest> clips, {bool exact = false, String outputDir = ''}) async {
    if (startError != null) throw startError!;
    starts.add(StartCall(path, clips, exact, outputDir));
    final made = [
      for (final c in clips)
        {
          'id': 'job${_next++}',
          'source': path,
          'output': '${outputDir.isEmpty ? 'C:/clips' : outputDir}/${path.split(RegExp(r'[\\/]')).last.replaceAll('.mp4', '')}_${c.label.isEmpty ? 'clip' : c.label}_${c.start.round()}-${c.end.round()}.mp4',
          'start': c.start,
          'end': c.end,
          'label': c.label,
          'exact': exact,
          'status': 'running',
          'progress': 0.0,
          'error': '',
        },
    ];
    _jobs.insertAll(0, made);
    return [for (final j in made) TrimJob.fromJson(j)];
  }

  @override
  Future<List<TrimJob>> jobs() async {
    jobsCalls++;
    return [for (final j in _jobs) TrimJob.fromJson(j)];
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
    setStatus(jobId, 'cancelled');
  }

  @override
  Future<void> clearFinished() async {
    clearCalls++;
    _jobs.removeWhere((j) => j['status'] != 'running' && j['status'] != 'queued');
  }

  /// Test control: move a job to another state.
  void setStatus(String id, String status, {double progress = 0, String error = ''}) {
    final job = _jobs.firstWhere((j) => j['id'] == id);
    job['status'] = status;
    job['progress'] = status == 'done' ? 1.0 : progress;
    job['error'] = error;
  }

  void finishAll() {
    for (final j in _jobs) {
      if (j['status'] == 'running' || j['status'] == 'queued') {
        j['status'] = 'done';
        j['progress'] = 1.0;
      }
    }
  }

  List<String> get jobIds => [for (final j in _jobs) j['id'] as String];
}
