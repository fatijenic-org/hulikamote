import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/services/portal_api.dart';

/// A demo motorist as the laptop lists it (never with a password).
class DevAccount {
  const DevAccount({required this.id, required this.name, required this.email, required this.plates, required this.loginPlate});

  final String id;
  final String name;
  final String email;
  final List<String> plates;

  /// The plate this account signs in with (it cannot be removed).
  final String loginPlate;

  factory DevAccount.fromJson(Map<String, dynamic> json) => DevAccount(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        plates: [for (final p in json['plates'] as List? ?? const []) p as String],
        loginPlate: json['login_plate'] as String? ?? '',
      );
}

/// What a change did: the account now, and how the phone cloud took it ('off', 'ok' or 'failed: why').
class DevOutcome {
  const DevOutcome(this.account, this.cloud);

  final DevAccount? account;
  final String cloud;

  bool get cloudFailed => cloud.startsWith('failed');
}

/// The calls of the developer tools. They always go to the LAPTOP (even when the app itself is online), and the laptop
/// refuses them unless it was started with developer tools on (tools/run_demo_backend.bat).
class DevApi {
  DevApi({http.Client? client, String Function()? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? (() => AppConfig.baseUrl);

  final http.Client _client;
  final String Function() _baseUrl;

  static const _timeout = Duration(seconds: 60);       // a cloud change can take a while
  static const _headers = {'Content-Type': 'application/json', 'X-HK-Dev': '1'};

  Uri _u(String path) => Uri.parse('${_baseUrl()}$path');

  Future<Map<String, dynamic>> _call(Future<http.Response> Function() request, {Set<int> ok = const {200}}) async {
    final http.Response r;
    try {
      r = await request().timeout(_timeout);
    } catch (_) {
      throw PortalException('Cannot reach the laptop at ${Uri.parse(_baseUrl()).authority}. Is the phone on the same Wi-Fi, and is the backend running?');
    }
    if (ok.contains(r.statusCode)) return r.body.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    var detail = '';
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['detail'] is String) detail = body['detail'] as String;
    } catch (_) {}
    if (r.statusCode == 404 && detail == 'Not Found') detail = 'This laptop has no developer tools. Restart the backend with the latest update.';
    throw PortalException(detail.isNotEmpty ? detail : 'Something went wrong (HTTP ${r.statusCode}).');
  }

  Future<List<DevAccount>> accounts() async {
    final body = await _call(() => _client.get(_u('/dev/accounts'), headers: _headers));
    return [for (final a in body['accounts'] as List) DevAccount.fromJson(Map<String, dynamic>.from(a as Map))];
  }

  DevOutcome _outcome(Map<String, dynamic> body) => DevOutcome(
        body['account'] == null ? null : DevAccount.fromJson(Map<String, dynamic>.from(body['account'] as Map)),
        '${body['cloud'] ?? 'off'}',
      );

  Future<DevOutcome> create({required String name, required String plate, required String password, String email = ''}) async => _outcome(await _call(
        () => _client.post(_u('/dev/accounts'), headers: _headers, body: jsonEncode({'name': name, 'plate': plate, 'password': password, 'email': email})),
        ok: const {200, 201},
      ));

  Future<DevOutcome> change(String id, {String? name, String? email, String? password, List<String> addPlates = const [], List<String> removePlates = const []}) async =>
      _outcome(await _call(() => _client.put(
            _u('/dev/accounts/$id'),
            headers: _headers,
            body: jsonEncode({'name': name, 'email': email, 'password': password, 'add_plates': addPlates, 'remove_plates': removePlates}),
          )));

  Future<DevOutcome> delete(String id) async => _outcome(await _call(() => _client.delete(_u('/dev/accounts/$id'), headers: _headers)));

  /// Create Juan, Maria and Pedro in the phone cloud (the laptop must have the cloud set up).
  Future<String> createCloudDemoAccounts() async {
    final body = await _call(() => _client.post(_u('/notify/cloud-demo-accounts'), headers: _headers, body: '{}'));
    final results = [for (final r in body['results'] as List) Map<String, dynamic>.from(r as Map)];
    final made = results.where((r) => r['status'] == 'created').length;
    final had = results.where((r) => r['status'] == 'exists').length;
    final failed = results.where((r) => r['status'] == 'failed').toList();
    if (failed.isEmpty) return '$made created, $had already there.';
    throw PortalException('${failed.length} failed (${failed.first['plate']}: ${failed.first['detail']})');
  }
}
