import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';

/// Who is logged in on this phone. Logging out forgets the account but keeps the connection (laptop or cloud).
class Session {
  Session._();

  static const _keys = {
    'user_id', 'name', 'plate', 'email', 'license_no', 'license_type', 'restrictions', 'expiry', 'address', 'notices_seen',
    'access_token', 'refresh_token', 'token_expires_at',
  };

  /// The cloud sign-in token, kept in memory too so photos can be loaded with it (see PhotoSource).
  static String? accessToken;

  static Future<Account?> current() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('access_token');
    final userId = prefs.getString('user_id');
    if (userId == null) return null;
    return Account(
      userId: userId,
      name: prefs.getString('name') ?? '',
      plate: prefs.getString('plate') ?? '',
      email: prefs.getString('email') ?? '',
      licenseNo: prefs.getString('license_no') ?? '',
      licenseType: prefs.getString('license_type') ?? '',
      restrictions: prefs.getString('restrictions') ?? '',
      expiry: prefs.getString('expiry') ?? '',
      address: prefs.getString('address') ?? '',
    );
  }

  static Future<void> save(Account a) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', a.userId);
    await prefs.setString('name', a.name);
    await prefs.setString('plate', a.plate);
    await prefs.setString('email', a.email);
    await prefs.setString('license_no', a.licenseNo);
    await prefs.setString('license_type', a.licenseType);
    await prefs.setString('restrictions', a.restrictions);
    await prefs.setString('expiry', a.expiry);
    await prefs.setString('address', a.address);
  }

  /// The cloud sign-in: the token, the one that renews it, and when the token stops working (seconds since 1970).
  static Future<void> saveTokens({required String access, required String refresh, required int expiresAt}) async {
    accessToken = access;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);
    await prefs.setInt('token_expires_at', expiresAt);
  }

  static Future<({String access, String refresh, int expiresAt})?> tokens() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString('access_token');
    final refresh = prefs.getString('refresh_token');
    if (access == null || refresh == null) return null;
    return (access: access, refresh: refresh, expiresAt: prefs.getInt('token_expires_at') ?? 0);
  }

  static Future<void> clear() async {
    accessToken = null;
    final prefs = await SharedPreferences.getInstance();
    for (final key in _keys) {
      await prefs.remove(key);
    }
  }
}
