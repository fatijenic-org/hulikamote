import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../domain/benchmark_models.dart';

/// Thrown when the backend answers with an error; [message] is safe to show.
class BenchmarkApiException implements Exception {
  BenchmarkApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// All HTTP calls of the Benchmark tab (the backend side is tools/benchmark/api.py).
class BenchmarkApi {
  BenchmarkApi({http.Client? client, this.baseUrl = ApiConstants.baseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  static const _timeout = Duration(seconds: 30);
  static const _json = {'Content-Type': 'application/json'};

  Uri _u(String path) => Uri.parse('$baseUrl/api/benchmark$path');

  Never _fail(http.Response r, String what) {
    var detail = '';
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['detail'] is String) detail = body['detail'] as String;
    } catch (_) {}
    if (r.statusCode == 404 && detail == 'Not Found') {
      detail = 'This backend has no Benchmark service yet. Restart the backend with the latest update.';
    }
    throw BenchmarkApiException(detail.isNotEmpty ? detail : '$what failed (HTTP ${r.statusCode}).', statusCode: r.statusCode);
  }

  Map<String, dynamic> _map(http.Response r) => Map<String, dynamic>.from(jsonDecode(r.body) as Map);

  Future<BenchOverview> overview() async {
    final r = await _client.get(_u('/overview')).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) _fail(r, 'Loading the benchmark');
    return BenchOverview.fromJson(_map(r));
  }

  Future<RunSuggestions> suggestions(String taskId) async {
    final r = await _client.get(_u('/suggestions/$taskId')).timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'Reading that run');
    return RunSuggestions.fromJson(_map(r));
  }

  /// Adds a clip from a forensic run ([taskId]) or changes an existing clip's events / note. Returns what to warn about.
  Future<List<String>> saveClip({
    required String id,
    String? taskId,
    String? videoPath,
    String note = '',
    bool clean = false,
    List<BenchEvent> events = const [],
  }) async {
    final r = await _client
        .put(
          _u('/clips/$id'),
          headers: _json,
          body: jsonEncode({
            'task_id': taskId,
            'video_path': videoPath,
            'note': note,
            'clean': clean,
            'events': [for (final e in events) e.toJson()],
          }),
        )
        .timeout(const Duration(minutes: 5)); // copying a long video takes a moment
    if (r.statusCode != 200) _fail(r, 'Saving the clip');
    return [for (final p in (_map(r)['problems'] as List? ?? const [])) '$p'];
  }

  Future<void> deleteClip(String id) async {
    final r = await _client.delete(_u('/clips/$id')).timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'Deleting the clip');
  }

  /// Starts scoring in the background; returns the run id.
  Future<String> startRun({required String label, List<String>? clips}) async {
    final r = await _client
        .post(_u('/run'), headers: _json, body: jsonEncode({'label': label, 'clips': clips}))
        .timeout(_timeout);
    if (r.statusCode != 202 && r.statusCode != 200) _fail(r, 'Starting the benchmark');
    return '${_map(r)['run_id']}';
  }

  Future<RunProgress> runProgress(String runId) async {
    final r = await _client.get(_u('/run/$runId')).timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'Checking progress');
    return RunProgress.fromJson(_map(r));
  }

  Future<void> cancelRun(String runId) async {
    final r = await _client.post(_u('/run/$runId/cancel')).timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'Stopping the benchmark');
  }

  Future<ReportDetail> report(String name) async {
    final r = await _client.get(_u('/reports/$name')).timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'Loading the report');
    return ReportDetail.fromJson(_map(r));
  }
}
