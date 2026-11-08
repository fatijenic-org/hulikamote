import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'tokens.dart';

/// A short message at the bottom: what just happened. Errors stay a little longer. Always icon + words.
class AppToast {
  AppToast._();

  static void show(BuildContext context, String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final s = context.status;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: Duration(seconds: error ? 6 : 3),
        backgroundColor: error ? s.danger : context.colors.inverseSurface,
        content: Row(children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline, size: 20, color: error ? s.onDanger : context.colors.onInverseSurface),
          const SizedBox(width: Sp.x3),
          Expanded(child: Text(message, style: TextStyle(color: error ? s.onDanger : context.colors.onInverseSurface))),
        ]),
      ));
  }
}
