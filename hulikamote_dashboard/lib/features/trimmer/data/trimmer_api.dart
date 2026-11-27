import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../domain/trimmer_models.dart';

/// Thrown when the backend refuses or cannot answer; [message] is safe to show.
class TrimmerApiException implements Exception {
  TrimmerApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The calls of the video trimmer (backend: routers/trimmer.py).
class TrimmerApi {
  TrimmerApi({http.Client? client, this.baseUrl = ApiConstants.baseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  static const _timeout = Duration(seconds: 30);
  static const _json = {'Content-Type': 'application/json'};

  Uri _u(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl/api/trimmer$path').replace(queryParameters: query);

  Future<http.Response> _call(Future<http.Response> Function() request, String what, {Set<int> ok = const {200}}) async {
    final http.Response r;
    try {
      r = await request().timeout(_timeout);
    } catch (_) {
      throw TrimmerApiException('$what failed: the backend did not answer. Is it running?');
    }
    if (ok.contains(r.statusCode)) return r;
    var detail = '';
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['detail'] is String) detail = body['detail'] as String;
    } catch (_) {}
    if (r.statusCode == 404 && detail == 'Not Found') {
      detail = 'This backend has no video trimmer yet. Restart the backend with the latest update.';
    }
    throw TrimmerApiException(detail.isNotEmpty ? detail : '$what failed (HTTP ${r.statusCode}).');
  }

  Map<String, dynamic> _map(http.Response r) => Map<String, dynamic>.from(jsonDecode(r.body) as Map);

  List<TrimJob> _jobs(http.Response r) => [for (final j in _map(r)['jobs'] as List) TrimJob.fromJson(Map<String, dynamic>.from(j as Map))];

  Future<ProbeInfo> probe(String path) async {
    final r = await _call(() => _client.get(_u('/probe', {'file_path': path})), 'Opening the video');
    return ProbeInfo.fromJson(_map(r));
  }

  /// The strip of pictures behind the timeline.
  String filmstripUrl(String path, {int count = 24}) => _u('/filmstrip', {'file_path': path, 'count': '$count'}).toString();

  /// Queues one cut per clip and returns at once. [outputDir] empty = next to the video.
  Future<List<TrimJob>> startJobs(String path, List<ClipRequest> clips, {bool exact = false, String outputDir = ''}) async {
    final r = await _call(
      () => _client.post(
        _u('/jobs'),
        headers: _json,
        body: jsonEncode({'file_path': path, 'clips': [for (final c in clips) c.toJson()], 'exact': exact, 'output_dir': outputDir}),
      ),
      'Starting the export',
      ok: const {200, 202},
    );
    return _jobs(r);
  }

  /// The benchmark labeller: every labelled slice becomes its own clip in the benchmark folder, with its events and settings in the
  /// registry. [slices] are all the labelled slices of the video; the ones with `export: false` are only counted as events.
  Future<BenchStart> startBenchmark(String path, List<Map<String, dynamic>> slices, {double pad = 3, String? setupId, bool reverseCounterflow = false, bool incomingTwoWheelers = false, int? overloadingMaxRiders}) async {
    final r = await _call(
      () => _client.post(_u('/benchmark'), headers: _json, body: jsonEncode({'file_path': path, 'slices': slices, 'pad': pad, 'setup_id': setupId, 'reverse_counterflow': reverseCounterflow, 'incoming_two_wheelers': incomingTwoWheelers, 'overloading_max_riders': overloadingMaxRiders})),
      'Starting the benchmark export',
      ok: const {200, 202},
    );
    final body = _map(r);
    return BenchStart(
      jobs: _jobs(r),
      skipped: [for (final s in (body['skipped'] as List? ?? const [])) '$s'],
      folder: '${body['folder'] ?? ''}',
      needsZone: [for (final s in (body['needs_zone'] as List? ?? const [])) '$s'],
      clipIds: [for (final s in (body['clip_ids'] as List? ?? const [])) '$s'],
    );
  }

  /// What the benchmark folder holds, per violation (clips, events, seconds, plates, clean clips).
  Future<BenchStats> benchStats() async {
    final r = await _call(() => _client.get(_u('/benchmark/stats')), 'Counting the benchmark clips');
    return BenchStats.fromJson(_map(r));
  }

  /// The saved setups (zones, signs and settings of a camera view), newest first.
  Future<List<SavedSetup>> setups() async {
    final r = await _call(() => _client.get(_u('/setups')), 'Reading the saved setups');
    return [for (final s in (_map(r)['setups'] as List? ?? const [])) SavedSetup.fromJson(Map<String, dynamic>.from(s as Map))];
  }

  /// Starts the benchmark on these clips (the Benchmark tab shows the progress and the report). Throws with the reason, for example
  /// when another run is already going.
  Future<void> startScoring(List<String> clipIds, {String label = 'labeller'}) async {
    await _call(
      () => _client.post(Uri.parse('$baseUrl/api/benchmark/run'), headers: _json, body: jsonEncode({'label': label, 'clips': clipIds})),
      'Starting the benchmark',
      ok: const {200, 202},
    );
  }

  /// What to PLAY for [path]: the video itself when it is light, else a small copy the backend makes once (state 'working' until
  /// it is 'ready'). The cuts always come from the original.
  Future<TrimPreview> preview(String path) async {
    final r = await _call(() => _client.get(_u('/preview', {'file_path': path})), 'Preparing the preview');
    final b = _map(r);
    return TrimPreview(
      state: '${b['state'] ?? 'failed'}',
      path: '${b['path'] ?? path}',
      progress: (b['progress'] as num?)?.toDouble() ?? 0,
      error: '${b['error'] ?? ''}',
      copy: b['copy'] == true,
    );
  }

  Future<List<TrimJob>> jobs() async => _jobs(await _call(() => _client.get(_u('/jobs')), 'Checking the exports'));

  Future<void> cancel(String jobId) async {
    await _call(() => _client.delete(_u('/jobs/${Uri.encodeComponent(jobId)}')), 'Stopping the export');
  }

  /// Forget the finished, failed and cancelled jobs (the files stay).
  Future<void> clearFinished() async {
    await _call(() => _client.post(_u('/jobs/clear')), 'Clearing the list');
  }
}
