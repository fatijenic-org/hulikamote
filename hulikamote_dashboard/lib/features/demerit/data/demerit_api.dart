import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../domain/demerit_models.dart';

/// Thrown when the backend cannot answer; [message] is safe to show.
class DemeritApiException implements Exception {
  DemeritApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The two read-only calls of the Demerit Points tab (backend: routers/demerit.py).
class DemeritApi {
  DemeritApi({http.Client? client, this.baseUrl = ApiConstants.baseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> _get(String path, String what) async {
    final http.Response r;
    try {
      r = await _client.get(Uri.parse('$baseUrl/demerit$path')).timeout(_timeout);
    } catch (_) {
      throw DemeritApiException('$what failed: the backend did not answer. Is it running?');
    }
    if (r.statusCode == 404) {
      throw DemeritApiException('This backend has no demerit service yet. Restart the backend with the latest update.');
    }
    if (r.statusCode != 200) throw DemeritApiException('$what failed (HTTP ${r.statusCode}).');
    return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
  }

  /// Every plate with at least one confirmed violation, most points first.
  Future<List<DemeritEntry>> standings() async {
    final body = await _get('', 'Loading the demerit points');
    return [for (final p in body['plates'] as List) DemeritEntry.fromJson(Map<String, dynamic>.from(p as Map))];
  }

  /// One plate with its confirmed tickets.
  Future<DemeritDetail> plate(String plate) async =>
      DemeritDetail.fromJson(await _get('/${Uri.encodeComponent(plate)}', 'Loading $plate'));
}
