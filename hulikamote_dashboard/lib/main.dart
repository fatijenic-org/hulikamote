import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'core/di/injection.dart';
import 'core/routers/app_router.dart';
import 'core/shell/officer_mode.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  configureDependencies();
  await OfficerMode.load();
  runApp(const HuliKamoteDashboardApp());
}

class HuliKamoteDashboardApp extends StatelessWidget {
  const HuliKamoteDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HULI-KAMOTE Dashboard',
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
