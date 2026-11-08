import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/session.dart';
import '../../../core/ui/app_theme.dart';
import '../../main/screens/main_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _next();
  }

  /// Signed in before: straight to the records. Otherwise to the sign-in page.
  Future<void> _next() async {
    final shown = Future<void>.delayed(const Duration(milliseconds: 1200));
    final account = await Session.current();
    await shown;
    if (!mounted) return;
    final signedIn = account != null && AppConfig.ready;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => signedIn ? const MainScreen() : const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fore = context.colors.onPrimary;
    return Scaffold(
      backgroundColor: context.colors.primary,
      body: Center(
        child: Semantics(
          label: 'HULI-KAMOTE, loading',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: fore.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(26)),
              child: Icon(Icons.shield_outlined, size: 46, color: fore),
            ),
            const SizedBox(height: 20),
            Text('HULI-KAMOTE', style: context.text.headlineSmall?.copyWith(color: fore, letterSpacing: 2, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Your traffic records, in your pocket', style: context.text.bodyMedium?.copyWith(color: fore.withValues(alpha: 0.8))),
            const SizedBox(height: 40),
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fore)),
          ]),
        ),
      ),
    );
  }
}
