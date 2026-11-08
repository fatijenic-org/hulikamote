import 'package:shared_preferences/shared_preferences.dart';

/// How the phone reaches the system, and where.
///  - online: through the Supabase cloud (works anywhere). The laptop copies confirmed tickets there.
///  - lan: straight to the laptop on the same Wi-Fi or hotspot (no internet needed).
/// Everything is typed in the app, so nothing is rebuilt when the network changes.
class AppConfig {
  AppConfig._();

  static const defaultPort = 8000;

  /// Cloud accounts sign in with the plate number, as this made-up e-mail address (the real one is optional).
  static const plateEmailDomain = 'plates.hulikamote.app';

  static const _serverKey = 'server_address';
  static const _modeKey = 'connection_mode';
  static const _cloudUrlKey = 'cloud_url';
  static const _cloudKeyKey = 'cloud_anon_key';

  // flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...  fills the cloud in at build time
  static const _buildCloudUrl = String.fromEnvironment('SUPABASE_URL');
  static const _buildCloudKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String _address = '';
  static String _mode = 'online';
  static String _cloudUrl = '';
  static String _cloudKey = '';

  // ── the laptop (same Wi-Fi) ──
  /// `192.168.68.109:8000`, or empty until the user sets it.
  static String get address => _address;
  static bool get hasServer => _address.isNotEmpty;
  static String get baseUrl => 'http://$_address';

  // ── the cloud ──
  static String get cloudUrl => _cloudUrl;
  static String get cloudKey => _cloudKey;
  static bool get hasCloud => _cloudUrl.isNotEmpty && _cloudKey.isNotEmpty;

  static bool get isOnline => _mode == 'online';

  /// The chosen way is set up, so the app can sign in.
  static bool get ready => isOnline ? hasCloud : hasServer;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _address = prefs.getString(_serverKey) ?? '';
    _cloudUrl = prefs.getString(_cloudUrlKey) ?? _buildCloudUrl;
    _cloudKey = prefs.getString(_cloudKeyKey) ?? _buildCloudKey;
    // Nothing chosen yet: online by default, but a phone that already knows a laptop and no cloud keeps using it.
    _mode = prefs.getString(_modeKey) ?? (hasCloud ? 'online' : (hasServer ? 'lan' : 'online'));
  }

  static Future<void> setMode(String mode) async {
    _mode = mode == 'lan' ? 'lan' : 'online';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, _mode);
  }

  /// Saves what the user typed. Returns false (and saves nothing) if it is not an address.
  static Future<bool> save(String input) async {
    final address = normalize(input);
    if (address.isEmpty) return false;
    _address = address;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, address);
    return true;
  }

  /// Saves the Supabase project (address + public "anon" key). False (and nothing saved) if either is not usable.
  static Future<bool> saveCloud(String url, String anonKey) async {
    final clean = normalizeCloudUrl(url);
    final key = anonKey.replaceAll(RegExp(r'\s'), '');
    if (clean.isEmpty || key.isEmpty) return false;
    _cloudUrl = clean;
    _cloudKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cloudUrlKey, clean);
    await prefs.setString(_cloudKeyKey, key);
    return true;
  }

  /// "192.168.68.109", "192.168.68.109:8000", "http://192.168.68.109:8000/mailbox" -> "192.168.68.109:8000".
  /// Empty when it cannot be an address.
  static String normalize(String input) {
    var text = input.trim().toLowerCase();
    text = text.replaceFirst(RegExp(r'^[a-z]+://'), '');
    final slash = text.indexOf('/');
    if (slash >= 0) text = text.substring(0, slash);
    if (text.isEmpty) return '';
    final parts = text.split(':');
    if (parts.length > 2) return '';
    final host = parts[0];
    if (!RegExp(r'^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$').hasMatch(host)) return '';
    final port = parts.length == 2 ? int.tryParse(parts[1]) : defaultPort;
    if (port == null || port < 1 || port > 65535) return '';
    return '$host:$port';
  }

  /// "abc.supabase.co" or "https://abc.supabase.co/rest/v1" -> "https://abc.supabase.co". Empty when unusable.
  static String normalizeCloudUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) return '';
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || !RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(uri.host)) return '';
    return 'https://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }
}
