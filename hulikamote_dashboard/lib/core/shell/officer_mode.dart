import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Officer view": the menu shows only what an LTO officer needs to try the system (live feed, analysis, review,
/// violations, demerit points, motorists) and hides the developer tools. The switch is at the bottom of the menu, and
/// the choice is remembered between runs.
class OfficerMode {
  OfficerMode._();

  static const _key = 'officer_mode';

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_key) ?? false;
    } catch (_) {
      // no stored choice: stay in the full view
    }
  }

  static Future<void> set(bool on) async {
    enabled.value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (_) {
      // the choice still applies for this run
    }
  }
}
