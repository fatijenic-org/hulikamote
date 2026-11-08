import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Developer mode (temporary): a hidden set of tools to manage accounts while testing. It is switched on by tapping the
/// version line on the Profile page seven times, and off again from the tools page. All of it lives in features/dev, so
/// removing that folder and the one line that opens it removes the feature.
class DevMode {
  DevMode._();

  static const _key = 'dev_mode';
  static const tapsToUnlock = 7;

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      enabled.value = (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      enabled.value = false;
    }
  }

  static Future<void> set(bool on) async {
    enabled.value = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {
      // it still applies for this run
    }
  }
}
