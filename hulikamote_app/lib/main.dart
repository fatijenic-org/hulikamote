import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'core/config/app_config.dart';
import 'core/services/dev_mode.dart';
import 'core/services/push_notification_service.dart';
import 'core/ui/app_theme.dart';
import 'core/ui/tokens.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A mistake inside one screen must never end as a red error page in front of a motorist (or an officer).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Screen error: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error');
    return true;                                    // handled: the app carries on
  };
  ErrorWidget.builder = (details) => kDebugMode ? ErrorWidget(details.exception) : const _CalmError();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await AppConfig.load();
  await DevMode.load();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    firebaseReady = true;
  } catch (e) {
    debugPrint("Firebase init failed: $e");
  }
  // Phone notifications also work without Firebase (the app raises them itself when it sees a new notice).
  await PushNotificationService.init(firebaseReady: firebaseReady);

  runApp(const HuliKamoteApp());
}

class HuliKamoteApp extends StatelessWidget {
  const HuliKamoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HULI-KAMOTE',
      navigatorKey: navigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      debugShowCheckedModeBanner: false,
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}

/// What a part of a screen shows if building it failed: a quiet note instead of the red error page.
class _CalmError extends StatelessWidget {
  const _CalmError();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(Sp.x6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline_rounded, size: 40, color: Colors.grey),
            SizedBox(height: Sp.x3),
            Text('This part did not load.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
            SizedBox(height: Sp.x1),
            Text('Go back and open it again.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
          ]),
        ),
      ),
    );
  }
}
