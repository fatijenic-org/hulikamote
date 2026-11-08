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

  Future<List<TrimJob>> jobs() async => _jobs(await _call(() => _client.get(_u('/jobs')), 'Checking the exports'));

  Future<void> cancel(String jobId) async {
    await _call(() => _client.delete(_u('/jobs/${Uri.encodeComponent(jobId)}')), 'Stopping the export');
  }

  /// Forget the finished, failed and cancelled jobs (the files stay).
  Future<void> clearFinished() async {
    await _call(() => _client.post(_u('/jobs/clear')), 'Clearing the list');
  }
}
