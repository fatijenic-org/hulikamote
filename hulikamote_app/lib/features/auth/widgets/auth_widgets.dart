import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/ui/app_theme.dart';
import '../../../core/ui/tokens.dart';

/// The logo square with the app name, at the top of the sign-in pages.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 48.0 : 64.0;
    return Row(children: [
      ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.3),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [context.colors.primary, Color.lerp(context.colors.primary, Colors.black, 0.25)!]),
          ),
          child: Icon(Icons.shield_outlined, color: context.colors.onPrimary, size: size * 0.55),
        ),
      ),
      const SizedBox(width: Sp.x3),
      Semantics(
        header: true,
        child: Text('HULI-KAMOTE', style: context.text.titleLarge?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w800)),
      ),
    ]);
  }
}

/// Which way the phone reaches the system right now (Online or Same Wi-Fi), with a dot that says whether it is set up.
/// Tap to change it.
class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key, required this.onTap});

  final VoidCallback onTap;

  /// Just where: the cloud's name or the laptop's address.
  static String where() => AppConfig.isOnline ? (Uri.tryParse(AppConfig.cloudUrl)?.host ?? 'the cloud') : AppConfig.address;

  static String describe() {
    if (!AppConfig.ready) return 'Not connected yet';
    return AppConfig.isOnline ? 'Online · ${Uri.tryParse(AppConfig.cloudUrl)?.host ?? 'cloud'}' : 'Same Wi-Fi · ${AppConfig.address}';
  }

  @override
  Widget build(BuildContext context) {
    final ready = AppConfig.ready;
    final label = describe();
    return Semantics(
      button: true,
      label: 'Connection: $label. Tap to change.',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Rd.pill),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: minTap),
          padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
          decoration: BoxDecoration(border: Border.all(color: context.colors.outlineVariant), borderRadius: BorderRadius.circular(Rd.pill)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: ready ? context.status.onSuccess : context.status.onWarning)),
            const SizedBox(width: Sp.x2),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium)),
            const SizedBox(width: Sp.x2),
            Text('Change', style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
          ]),
        ),
      ),
    );
  }
}
