import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What the phone last got from the system, so a page can still show it when the system cannot be reached.
class LocalCache {
  LocalCache._();

  static String _key(String name, String userId) => 'cache_${name}_$userId';

  static Future<void> save(String name, String userId, Object json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(name, userId), jsonEncode({'at': DateTime.now().toIso8601String(), 'data': json}));
    } catch (_) {
      // a cache that cannot be written only means no saved copy
    }
  }

  /// The saved copy and when it was saved, or null.
  static Future<({DateTime at, Object? data})?> load(String name, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(name, userId));
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map;
      final at = DateTime.tryParse('${map['at']}');
      return at == null ? null : (at: at, data: map['data']);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final name in ['tickets', 'notices', 'appeals']) {
      await prefs.remove(_key(name, userId));
    }
  }
}
