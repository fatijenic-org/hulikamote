import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../domain/appeal_models.dart';

/// Thrown when the backend refuses or cannot answer; [message] is safe to show.
class AppealsApiException implements Exception {
  AppealsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The calls of the Appeals page (backend: routers/appeals.py).
class AppealsApi {
  AppealsApi({http.Client? client, this.baseUrl = ApiConstants.baseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  static const _timeout = Duration(seconds: 30);

  /// The address of one evidence photo (a file under snapshots/evidence).
  String photoUrl(String name) => '$baseUrl/snapshots/evidence/${Uri.encodeComponent(name)}';

  Future<http.Response> _call(Future<http.Response> Function() request, String what) async {
    final http.Response r;
    try {
      r = await request().timeout(_timeout);
    } catch (_) {
      throw AppealsApiException('$what failed: the backend did not answer. Is it running?');
    }
    if (r.statusCode == 200) return r;
    var detail = '';
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['detail'] is String) detail = body['detail'] as String;
    } catch (_) {}
    if (r.statusCode == 404 && detail == 'Not Found') {
      detail = 'This backend cannot review appeals yet. Restart the backend with the latest update.';
    }
    throw AppealsApiException(detail.isNotEmpty ? detail : '$what failed (HTTP ${r.statusCode}).');
  }

  /// Every appeal (the cloud ones are pulled in first), newest first.
  Future<AppealList> appeals() async {
    final r = await _call(() => _client.get(Uri.parse('$baseUrl/appeals/review')), 'Loading the appeals');
    return AppealList.fromJson(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
  }

  /// Accept (the ticket is cancelled) or reject (it stays). The motorist is told either way.
  Future<AppealItem> decide(String appealId, {required bool accept, String note = ''}) async {
    final r = await _call(
      () => _client.post(
        Uri.parse('$baseUrl/appeals/${Uri.encodeComponent(appealId)}/decision'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'decision': accept ? 'accept' : 'reject', 'note': note}),
      ),
      'Saving the decision',
    );
    return AppealItem.fromJson(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
  }
}
