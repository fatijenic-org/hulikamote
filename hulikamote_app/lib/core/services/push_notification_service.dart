import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_config.dart';
import 'portal_api.dart';
import 'session.dart';

/// Phone notifications, two ways:
///  - Firebase push (needs internet on both the laptop and the phone), and
///  - local notifications that the app raises itself when it sees a new notice on the laptop (needs only the same
///    Wi-Fi or hotspot). The second works with no internet at all.
class PushNotificationService {
  // Singleton — only one instance ever exists
  static PushNotificationService? _instance;
  static PushNotificationService get instance {
    _instance ??= PushNotificationService._();
    return _instance!;
  }
  PushNotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  bool _firebaseReady = false;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// Goes up each time the motorist taps a notification, so the main page can open the Inbox.
  static final ValueNotifier<int> inboxRequests = ValueNotifier<int>(0);

  /// Call once in main(). [firebaseReady] = Firebase.initializeApp() worked; without it only local notifications run.
  static Future<void> init({bool firebaseReady = true}) => instance.initialize(firebaseReady: firebaseReady);

  /// Call after login so the laptop knows which phone belongs to this motorist.
  static Future<void> registerCurrentUser() async {
    if (!instance._firebaseReady) return;
    try {
      final token = await instance._messaging.getToken().timeout(const Duration(seconds: 10));
      if (token != null) await instance._uploadToken(token);
    } catch (e) {
      debugPrint('registerCurrentUser error: $e');
    }
  }

  /// Stop pushes to this phone for the signed-in account. Call it BEFORE the sign-in is cleared (the cloud needs it).
  static Future<void> forgetCurrentUser() async {
    if (!instance._firebaseReady) return;
    try {
      final token = await instance._messaging.getToken().timeout(const Duration(seconds: 5));
      if (token != null) await PortalApi().forgetPushToken(token).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('forgetCurrentUser: $e');           // signing out must work even when this does not
    }
  }

  /// This phone's push token (for the developer tools), or null when push is not available.
  Future<String?> currentToken() async {
    if (!_firebaseReady) return null;
    try {
      return await _messaging.getToken().timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  /// Can this app show notifications? null when the phone does not say.
  Future<bool?> notificationsAllowed() async {
    try {
      return await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
  }

  /// A notification made right here, to check that the phone lets this app show one.
  Future<void> showTestNotification() =>
      showLocalNotification('HULI-KAMOTE test', 'If you can read this, notifications work on this phone.');

  Future<void> initialize({bool firebaseReady = true}) async {
    if (_isInitialized) return;
    _isInitialized = true;
    _firebaseReady = firebaseReady;

    // 1. Local notification channel
    const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: initSettingsAndroid),
      onDidReceiveNotificationResponse: (_) => inboxRequests.value++,
    );

    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'hulikamote_alerts',
        'Traffic Violations',
        description: 'Alerts for traffic violations',
        importance: Importance.max,
        playSound: true,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();

    if (!firebaseReady) return;

    // 2. Firebase push: permission, token, and showing pushes that arrive while the app is open
    try {
      final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        debugPrint('Push notification permission denied.');
        return;
      }
      final token = await _messaging.getToken().timeout(const Duration(seconds: 10));
      if (token != null) await _uploadToken(token);
      _messaging.onTokenRefresh.listen(_uploadToken).onError((e) => debugPrint('Token refresh error: $e'));
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.notification != null) {
          showLocalNotification(message.notification!.title ?? 'New violation on your record', message.notification!.body ?? '');
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((_) => inboxRequests.value++);          // tapped while the app was in the background
      if (await _messaging.getInitialMessage() != null) inboxRequests.value++;            // tapped while the app was closed
    } catch (e) {
      debugPrint('Firebase push not available (no internet?): $e');
    }
  }

  Future<void> showLocalNotification(String title, String body) async {
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      payload: 'inbox',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'hulikamote_alerts',
          'Traffic Violations',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
    );
  }

  Future<void> _uploadToken(String token) async {
    try {
      final account = await Session.current();
      if (account == null || !AppConfig.ready) {
        debugPrint('[FCM] No user logged in, skipping token registration.');
        return;
      }
      await PortalApi().registerPushToken(token, account.userId);
      debugPrint('[FCM] Token registered for user ${account.userId}.');
    } catch (e) {
      debugPrint('[FCM] Upload error: $e');
    }
  }
}
