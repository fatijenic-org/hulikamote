import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/home/models/violation.dart';
import '../config/app_config.dart';
import '../models/account.dart';
import '../models/notice.dart';
import '../utils/plate.dart';
import 'portal_api.dart';
import 'session.dart';

/// The same calls as the laptop version, answered by the Supabase cloud: sign in with Supabase Auth, read the motorist's
/// own rows (the database rules only show their own), and file appeals and register the phone for push there.
class CloudPortalApi implements PortalApi {
  CloudPortalApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  /// The made-up e-mail a plate signs in with.
  static String emailFor(String plate) => '${normalizePlate(plate).toLowerCase()}@${AppConfig.plateEmailDomain}';

  /// Does this project answer to this public key? (For the connection window.) Throws [PortalException].
  static Future<void> checkProject(String url, String anonKey, {http.Client? client}) async {
    final http.Response r;
    try {
      r = await (client ?? http.Client()).get(Uri.parse('$url/auth/v1/settings'), headers: {'apikey': anonKey}).timeout(_timeout);
    } catch (_) {
      throw PortalException('Cannot reach $url. Is the phone online, and is the address right?');
    }
    if (r.statusCode == 401 || r.statusCode == 403) throw PortalException('The cloud refused that key. Use the "anon" key of the project.');
    if (r.statusCode != 200) throw PortalException('That address did not answer like a Supabase project (HTTP ${r.statusCode}).');
  }

  Uri _u(String path, [Map<String, String>? query]) => Uri.parse('${AppConfig.cloudUrl}$path').replace(queryParameters: query);

  Map<String, String> _h({String? token, Map<String, String> extra = const {}}) => {
        'apikey': AppConfig.cloudKey,
        'Authorization': 'Bearer ${token ?? AppConfig.cloudKey}',
        'Content-Type': 'application/json',
        ...extra,
      };

  Future<http.Response> _send(Future<http.Response> Function() request, {Set<int> ok = const {200}}) async {
    final http.Response r;
    try {
      r = await request().timeout(_timeout);
    } catch (_) {
      throw PortalException('Cannot reach the cloud. Is the phone online?');
    }
    if (ok.contains(r.statusCode)) return r;
    throw PortalException(_reason(r));
  }

  /// What went wrong, in words for the motorist.
  static String _reason(http.Response r) {
    try {
      final body = jsonDecode(r.body);
      if (body is Map) {
        final text = '${body['msg'] ?? body['error_description'] ?? body['message'] ?? ''}';
        final code = '${body['error_code'] ?? body['code'] ?? ''}';
        final lower = text.toLowerCase();
        if (code == 'user_already_exists' || lower.contains('already registered')) return 'That plate already has an account.';
        if (code == 'PGRST202' || code == 'PGRST205') return 'The cloud is not set up yet. Run supabase/schema.sql in Supabase.';
        if (lower.contains('database error')) return 'The cloud could not create the account. If this keeps happening, run supabase/schema.sql again.';
        if (code == 'invalid_credentials' || lower.contains('invalid login')) return 'Wrong plate number or password.';
        if (code == 'weak_password') return 'That password is too weak. Use a longer one.';
        if (code.startsWith('email_address') || lower.contains('invalid email')) {
          return 'The cloud refused the plate\'s made-up e-mail. See supabase/README.md.';
        }
        if (code == '23505') return 'You already appealed this ticket.';
        if (code == '42501') return 'That ticket is not yours.';
        if (lower.contains('jwt')) return 'Your sign-in ran out. Sign in again.';
        if (text.isNotEmpty) return text;
      }
    } catch (_) {}
    return 'Something went wrong (HTTP ${r.statusCode}).';
  }

  Map<String, dynamic> _map(http.Response r) => Map<String, dynamic>.from(jsonDecode(r.body) as Map);

  Future<void> _remember(Map<String, dynamic> session) => Session.saveTokens(
        access: session['access_token'] as String,
        refresh: session['refresh_token'] as String,
        expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + ((session['expires_in'] as num?)?.toInt() ?? 3600),
      );

  /// A sign-in token that still works: renewed when it is about to run out.
  Future<String> _token() async {
    final saved = await Session.tokens();
    if (saved == null) throw PortalException('Sign in again.');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (saved.expiresAt - now > 60) {
      Session.accessToken = saved.access;
      return saved.access;
    }
    final r = await _send(() => _client.post(_u('/auth/v1/token', {'grant_type': 'refresh_token'}), headers: _h(), body: jsonEncode({'refresh_token': saved.refresh})));
    final session = _map(r);
    await _remember(session);
    return session['access_token'] as String;
  }

  @override
  Future<void> ping() async {
    await _send(() => _client.get(_u('/auth/v1/settings'), headers: _h()));
  }

  @override
  Future<Account> login(String plate, String password) async {
    final r = await _send(() => _client.post(_u('/auth/v1/token', {'grant_type': 'password'}), headers: _h(), body: jsonEncode({'email': emailFor(plate), 'password': password})));
    final session = _map(r);
    await _remember(session);
    final userId = (session['user'] as Map)['id'] as String;
    final profile = await _send(() => _client.get(_u('/rest/v1/profiles', {'user_id': 'eq.$userId', 'select': '*'}), headers: _h(token: session['access_token'] as String)));
    final rows = jsonDecode(profile.body) as List;
    if (rows.isEmpty) throw PortalException('This account has no profile. Create the account again.');
    final p = Map<String, dynamic>.from(rows.first as Map);
    return Account(userId: userId, name: p['name'] as String? ?? '', plate: p['plate'] as String? ?? '', email: p['email'] as String? ?? '');
  }

  @override
  Future<Account> register({required String name, required String plate, required String password, String email = ''}) async {
    // Say "taken" before anything is created. The project makes the profile together with the account (a trigger), so a
    // sign-up can never be left half done.
    final check = await _send(() => _client.post(_u('/rest/v1/rpc/plate_taken'), headers: _h(), body: jsonEncode({'p_plate': plate})));
    if (jsonDecode(check.body) == true) throw PortalException('That plate already has an account.');

    final r = await _send(
      () => _client.post(
        _u('/auth/v1/signup'),
        headers: _h(),
        body: jsonEncode({'email': emailFor(plate), 'password': password, 'data': {'name': name, 'plate': plate, 'contact_email': email}}),
      ),
      ok: const {200, 201},
    );
    final session = _map(r);
    if (session['access_token'] == null) {
      throw PortalException('The cloud wants an e-mail confirmation. In Supabase turn off Authentication > Providers > Email > Confirm email.');
    }
    await _remember(session);
    return Account(userId: (session['user'] as Map)['id'] as String, name: name, plate: plate.trim().toUpperCase(), email: email);
  }

  @override
  Future<List<Violation>> tickets(String userId) async {
    final token = await _token();
    final r = await _send(() => _client.get(_u('/rest/v1/tickets', {'select': 'id,cls,confidence,occurred_at,frames,plate_key', 'order': 'occurred_at.desc', 'limit': '50'}), headers: _h(token: token)));
    return [
      for (final t in jsonDecode(r.body) as List)
        Violation(
          id: t['id'] as String,
          cls: t['cls'] as String,
          confidence: (t['confidence'] as num).toDouble(),
          timestamp: t['occurred_at'] as String,
          imagePath: '',
          plate: t['plate_key'] as String? ?? '',
          evidencePaths: [for (final f in t['frames'] as List) f as String],
        ),
    ];
  }

  @override
  Future<List<Notice>> notices(String userId, {String? after}) async {
    final token = await _token();
    final query = {
      'select': 'id,subject,body,frames,created_at',
      'order': 'created_at.desc',
      'limit': '50',
      if (after != null && after.isNotEmpty) 'created_at': 'gt.$after',
    };
    final r = await _send(() => _client.get(_u('/rest/v1/notices', query), headers: _h(token: token)));
    return [for (final n in jsonDecode(r.body) as List) Notice.fromJson(Map<String, dynamic>.from(n as Map))];
  }

  @override
  Future<Map<String, String>> appealStatuses(String userId) async {
    final token = await _token();
    final r = await _send(() => _client.get(_u('/rest/v1/appeals', {'select': 'ticket_id,status'}), headers: _h(token: token)));
    return {for (final a in jsonDecode(r.body) as List) (a as Map)['ticket_id'] as String: '${a['status']}'};
  }

  @override
  Future<void> fileAppeal({required String violationId, required String userId, required String reason}) async {
    final token = await _token();
    await _send(
      () => _client.post(_u('/rest/v1/appeals'), headers: _h(token: token, extra: {'Prefer': 'return=minimal'}), body: jsonEncode({'ticket_id': violationId, 'user_id': userId, 'reason': reason})),
      ok: const {200, 201, 204},
    );
  }

  @override
  Future<void> registerPushToken(String pushToken, String userId) async {
    // A function in the project: a phone that was used by another account moves to this one.
    final token = await _token();
    await _send(
      () => _client.post(_u('/rest/v1/rpc/register_device'), headers: _h(token: token), body: jsonEncode({'p_token': pushToken})),
      ok: const {200, 204},
    );
  }

  @override
  Future<void> forgetPushToken(String pushToken) async {
    final token = await _token();
    await _send(
      () => _client.post(_u('/rest/v1/rpc/forget_device'), headers: _h(token: token), body: jsonEncode({'p_token': pushToken})),
      ok: const {200, 204},
    );
  }
}
