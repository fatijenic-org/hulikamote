import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'core/di/injection.dart';
import 'core/routers/app_router.dart';
import 'core/shell/officer_mode.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/light_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  configureDependencies();
  await OfficerMode.load();
  await LightMode.load();
  runApp(const HuliKamoteDashboardApp());
}

class HuliKamoteDashboardApp extends StatelessWidget {
  const HuliKamoteDashboardApp({super.key});

  // Keeps the whole app (pages, dialogs, video) alive when the light switch moves it into or out of the colour flip.
  static final GlobalKey _appKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HULI-KAMOTE Dashboard',
      theme: AppTheme.darkTheme,
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: LightMode.on,
        child: KeyedSubtree(key: _appKey, child: child ?? const SizedBox.shrink()),
        builder: (_, light, app) => light ? ColorFiltered(colorFilter: LightMode.flip, child: app) : app!,
      ),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
