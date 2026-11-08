import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../domain/registry_models.dart';

/// Thrown when the backend refuses or cannot answer; [message] is safe to show.
class RegistryApiException implements Exception {
  RegistryApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The calls of the Motorists tab: the registry (backend: routers/registry.py) and how motorists are notified
/// (routers/notify.py).
class RegistryApi {
  RegistryApi({http.Client? client, this.baseUrl = ApiConstants.baseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  static const _timeout = Duration(seconds: 20);
  static const _json = {'Content-Type': 'application/json'};

  Uri _registry(String path) => Uri.parse('$baseUrl/registry$path');
  Uri _notify(String path) => Uri.parse('$baseUrl/notify$path');

  /// Runs one request and turns every failure into a [RegistryApiException] with words a person can act on.
  Future<http.Response> _call(Future<http.Response> Function() request, String what, {Duration timeout = _timeout}) async {
    final http.Response r;
    try {
      r = await request().timeout(timeout);
    } catch (_) {
      throw RegistryApiException('$what failed: the backend did not answer. Is it running?');
    }
    if (r.statusCode == 200) return r;
    var detail = '';
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['detail'] is String) detail = body['detail'] as String;
    } catch (_) {}
    if (r.statusCode == 404 && detail == 'Not Found') {
      detail = 'This backend does not have this yet. Restart the backend with the latest update.';
    }
    throw RegistryApiException(detail.isNotEmpty ? detail : '$what failed (HTTP ${r.statusCode}).');
  }

  Map<String, dynamic> _map(http.Response r) => Map<String, dynamic>.from(jsonDecode(r.body) as Map);

  // ─── motorists, plates, e-mail addresses ────────────────────────────────────

  Future<List<Motorist>> motorists() async {
    final r = await _call(() => _client.get(_registry('')), 'Loading the motorists');
    return [for (final m in _map(r)['motorists'] as List) Motorist.fromJson(Map<String, dynamic>.from(m as Map))];
  }

  Future<void> setEmail(String userId, String email) => _call(
        () => _client.put(_registry('/motorists/${Uri.encodeComponent(userId)}/email'), headers: _json, body: jsonEncode({'email': email})),
        'Saving the e-mail address',
      );

  Future<void> registerPlate(String plate, String userId) => _call(
        () => _client.put(_registry('/plates/${Uri.encodeComponent(plate)}'), headers: _json, body: jsonEncode({'user_id': userId})),
        'Registering the plate',
      );

  Future<void> removePlate(String plate) =>
      _call(() => _client.delete(_registry('/plates/${Uri.encodeComponent(plate)}')), 'Removing the plate');

  // ─── online (Gmail) or offline (same Wi-Fi) ─────────────────────────────────

  Future<NoticeSettings> noticeSettings() async {
    final r = await _call(() => _client.get(_notify('/settings')), 'Loading the notification settings');
    return NoticeSettings.fromJson(_map(r));
  }

  /// Switch the way motorists are notified. Anything left empty keeps what is saved.
  Future<NoticeSettings> saveNoticeSettings({
    required String mode,
    String gmail = '',
    String appPassword = '',
    String supabaseUrl = '',
    String supabaseServiceKey = '',
  }) async {
    final r = await _call(
      () => _client.put(
        _notify('/settings'),
        headers: _json,
        body: jsonEncode({
          'mode': mode,
          'gmail': gmail,
          'app_password': appPassword,
          'supabase_url': supabaseUrl,
          'supabase_service_key': supabaseServiceKey,
        }),
      ),
      'Saving the notification settings',
    );
    return NoticeSettings.fromJson(_map(r));
  }

  /// Checks the saved Supabase project answers and has the HULI-KAMOTE tables and photo bucket.
  Future<CloudTestResult> testCloud() async {
    final r = await _call(() => _client.post(_notify('/cloud-test'), headers: _json, body: jsonEncode({})), 'Testing the cloud',
        timeout: const Duration(seconds: 45));
    return CloudTestResult.fromJson(_map(r));
  }

  /// Creates the demo motorists (Juan, Maria, Pedro) in the phone cloud with all the plates they own here.
  Future<List<CloudAccountResult>> createCloudDemoAccounts() async {
    final r = await _call(() => _client.post(_notify('/cloud-demo-accounts'), headers: _json, body: jsonEncode({})), 'Creating the demo accounts',
        timeout: const Duration(seconds: 90));
    return [for (final x in _map(r)['results'] as List) CloudAccountResult.fromJson(Map<String, dynamic>.from(x as Map))];
  }

  /// Is the Firebase key in place and for the same project as the phone app?
  Future<PushResult> pushCheck() async {
    final r = await _call(() => _client.get(_notify('/push-check')), 'Checking push');
    return PushResult.fromJson(_map(r));
  }

  /// Sends a test push to every phone that is signed in somewhere.
  Future<PushResult> sendTestPush() async {
    final r = await _call(() => _client.post(_notify('/push-test'), headers: _json, body: jsonEncode({})), 'Sending the test push',
        timeout: const Duration(seconds: 45));
    return PushResult.fromJson(_map(r));
  }

  /// Sends one real e-mail from the saved sender account to [to], to check the app password now.
  Future<TestEmailResult> sendTestEmail({String to = ''}) async {
    final r = await _call(() => _client.post(_notify('/test'), headers: _json, body: jsonEncode({'to': to})), 'Sending the test e-mail',
        timeout: const Duration(seconds: 30));
    return TestEmailResult.fromJson(_map(r));
  }
}
