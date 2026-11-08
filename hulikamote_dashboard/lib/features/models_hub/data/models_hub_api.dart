import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:hulikamote_dashboard/core/constants/api_constants.dart';

import '../domain/hub_models.dart';

/// The Models page's three calls. Tests give it a fake client.
class ModelsHubApi {
  ModelsHubApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<HubJob>> fetch() async {
    final res = await _client.get(Uri.parse('${ApiConstants.baseUrl}/models/hub'));
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return [for (final j in json['jobs'] as List) HubJob.fromJson((j as Map).cast<String, dynamic>())];
  }

  /// Makes one version the live one. A run that was never exported is prepared first, which takes about half a minute.
  /// Returns the backend's plain-language confirmation.
  Future<String> use(String job, String id) async {
    final res = await _post('/models/hub/use', {'job': job, 'id': id});
    return (jsonDecode(res.body) as Map)['detail']?.toString() ?? 'Done.';
  }

  /// Starts the per-type check of a finished run; the page follows it by reloading.
  Future<void> check(String job, String id) => _post('/models/hub/check', {'job': job, 'id': id});

  Future<http.Response> _post(String path, Map<String, String> body) async {
    final res = await _client.post(
      Uri.parse('${ApiConstants.baseUrl}$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      String detail;
      try {
        detail = (jsonDecode(res.body) as Map)['detail'].toString();
      } catch (_) {
        detail = 'HTTP ${res.statusCode}';
      }
      throw detail;
    }
    return res;
  }
}
