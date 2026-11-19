import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light look for the whole dashboard. The design stays dark; light mode flips every colour of the app
/// (invert, then turn the hue half way round so red stays red and blue stays blue).
/// Pictures and video are flipped a second time by [KeepColors], so they show their true colours.
class LightMode {
  LightMode._();

  static const _key = 'light_mode';

  /// true = light look. The app and every [KeepColors] listen to it.
  static final ValueNotifier<bool> on = ValueNotifier<bool>(false);

  /// Flipping twice gives the original colours back; that is how [KeepColors] works.
  static const ColorFilter flip = ColorFilter.matrix(<double>[
    0.574, -1.430, -0.144, 0, 255,
    -0.426, -0.430, -0.144, 0, 255,
    -0.426, -1.430, 0.856, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  static Future<void> load() async {
    try {
      on.value = (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {/* no saved choice: stay dark */}
  }

  static Future<void> set(bool value) async {
    on.value = value;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, value);
    } catch (_) {/* the choice just is not remembered */}
  }
}

/// Shows [child] with its true colours in light mode (use it around pictures, video and other things that must not flip).
class KeepColors extends StatelessWidget {
  const KeepColors({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: LightMode.on,
        child: child,
        builder: (_, light, kid) => light ? ColorFiltered(colorFilter: LightMode.flip, child: kid) : kid!,
      );
}
