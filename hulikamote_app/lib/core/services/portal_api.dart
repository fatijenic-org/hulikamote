import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/home/models/violation.dart';
import '../config/app_config.dart';
import '../models/account.dart';
import '../models/notice.dart';
import 'cloud_portal_api.dart';

/// Thrown when the laptop cannot be reached or refuses; [message] is safe to show.
class PortalException implements Exception {
  PortalException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Every call the app makes to the system, in one place. There are two versions: [LanPortalApi] talks to the laptop on the
/// same Wi-Fi, [CloudPortalApi] to the Supabase cloud. `PortalApi()` gives the one the user chose (a given [baseUrl] means
/// the laptop).
abstract class PortalApi {
  factory PortalApi({http.Client? client, String Function()? baseUrl}) =>
      (baseUrl == null && AppConfig.isOnline) ? CloudPortalApi(client: client) : LanPortalApi(client: client, baseUrl: baseUrl);

  /// Throws [PortalException] when nothing answers.
  Future<void> ping();
  Future<Account> login(String plate, String password);
  Future<Account> register({required String name, required String plate, required String password, String email = ''});

  /// The confirmed tickets of this motorist, newest first.
  Future<List<Violation>> tickets(String userId);

  /// Notices of this motorist, newest first. [after] = only the ones written since that server time.
  Future<List<Notice>> notices(String userId, {String? after});

  /// The tickets this motorist has appealed, and how each appeal stands: ticket id -> pending | accepted | rejected.
  Future<Map<String, String>> appealStatuses(String userId);
  Future<void> fileAppeal({required String violationId, required String userId, required String reason});
  Future<void> registerPushToken(String token, String userId);

  /// Stop pushes to this phone for this account (when the motorist signs out). Best effort.
  Future<void> forgetPushToken(String token);
}

/// The laptop on the same Wi-Fi (or hotspot).
class LanPortalApi implements PortalApi {
  LanPortalApi({http.Client? client, String Function()? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? (() => AppConfig.baseUrl);

  final http.Client _client;
  final String Function() _baseUrl;

  static const _timeout = Duration(seconds: 8);
  static const _json = {'Content-Type': 'application/json'};

  Uri _u(String path, [Map<String, String>? query]) => Uri.parse('${_baseUrl()}$path').replace(queryParameters: query);

  Future<http.Response> _send(Future<http.Response> Function() request, {Set<int> ok = const {200}}) async {
    final http.Response r;
    try {
      r = await request().timeout(_timeout);
    } catch (_) {
      throw PortalException('Cannot reach the laptop at ${Uri.parse(_baseUrl()).authority}. Is the phone on the same Wi-Fi, and is the backend running?');
    }
    if (ok.contains(r.statusCode)) return r;
    var detail = '';
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['detail'] is String) detail = body['detail'] as String;
    } catch (_) {}
    throw PortalException(detail.isNotEmpty ? detail : 'Something went wrong (HTTP ${r.statusCode}).');
  }

  Map<String, dynamic> _map(http.Response r) => Map<String, dynamic>.from(jsonDecode(r.body) as Map);

  @override
  Future<void> ping() async {
    await _send(() => _client.get(_u('/violations', {'size': '1'})));
  }

  @override
  Future<Account> login(String plate, String password) async {
    try {
      final r = await _send(() => _client.post(_u('/auth/login'), headers: _json, body: jsonEncode({'plate': plate.trim(), 'password': password})));
      return Account.fromJson(_map(r));
    } on PortalException catch (e) {
      if (e.message == 'Invalid credentials') throw PortalException('Wrong plate number or password.');
      rethrow;
    }
  }

  @override
  Future<Account> register({required String name, required String plate, required String password, String email = ''}) async {
    final r = await _send(
      () => _client.post(_u('/auth/register'), headers: _json, body: jsonEncode({'name': name, 'plate': plate, 'password': password, 'email': email})),
      ok: const {200, 201},
    );
    return Account.fromJson(_map(r));
  }

  @override
  Future<List<Violation>> tickets(String userId) async {
    final r = await _send(() => _client.get(_u('/violations', {'page': '1', 'size': '50', 'user_id': userId, 'status': 'approved'})));
    return ViolationPage.fromJson(_map(r)).items;
  }

  @override
  Future<List<Notice>> notices(String userId, {String? after}) async {
    final r = await _send(() => _client.get(_u('/notify/notices', {'user_id': userId, if (after != null && after.isNotEmpty) 'after': after})));
    return [for (final n in _map(r)['notices'] as List) Notice.fromJson(Map<String, dynamic>.from(n as Map))];
  }

  @override
  Future<Map<String, String>> appealStatuses(String userId) async {
    final r = await _send(() => _client.get(_u('/appeals', {'user_id': userId})));
    return {for (final a in _map(r)['appeals'] as List) (a as Map)['violation_id'] as String: '${a['status']}'};
  }

  @override
  Future<void> fileAppeal({required String violationId, required String userId, required String reason}) async {
    await _send(
      () => _client.post(_u('/appeals'), headers: _json, body: jsonEncode({'violation_id': violationId, 'user_id': userId, 'reason': reason})),
      ok: const {200, 201},
    );
  }

  @override
  Future<void> registerPushToken(String token, String userId) async {
    await _send(() => _client.post(_u('/notifications/register-token'), headers: _json, body: jsonEncode({'token': token, 'user_id': userId})));
  }

  @override
  Future<void> forgetPushToken(String token) async {
    await _send(() => _client.post(_u('/notifications/forget-token'), headers: _json, body: jsonEncode({'token': token})));
  }
}
