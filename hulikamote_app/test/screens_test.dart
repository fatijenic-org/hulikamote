import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_app/core/config/app_config.dart';
import 'package:hulikamote_app/core/services/portal_api.dart';
import 'package:hulikamote_app/features/auth/screens/login_screen.dart';
import 'package:hulikamote_app/features/auth/screens/register_screen.dart';
import 'package:hulikamote_app/features/auth/widgets/connection_dialog.dart';
import 'package:hulikamote_app/features/main/screens/main_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const signedIn = {
  'server_address': '192.168.68.109:8000', 'user_id': 'user_9', 'name': 'Ana Cruz', 'plate': 'ANA 777', 'email': 'ana@example.test',
  'license_no': 'PLATE-ANA777', 'license_type': 'Not provided', 'restrictions': '', 'expiry': '-', 'address': '-',
};

/// A laptop that answers from memory.
class FakeLaptop {
  final calls = <String>[];
  int loginStatus = 200;
  String loginDetail = 'Invalid credentials';
  int registerStatus = 201;
  String registerDetail = '';
  final notices = <Map<String, dynamic>>[];
  final loginBodies = <Map<String, dynamic>>[];

  PortalApi get api => PortalApi(baseUrl: () => 'http://192.168.68.109:8000', client: MockClient(_answer));

  Future<http.Response> _answer(http.Request req) async {
    calls.add('${req.method} ${req.url.path}');
    final profile = jsonEncode({'user_id': 'user_9', 'name': 'Ana Cruz', 'plate': 'ANA 777', 'email': '', 'license_no': 'PLATE-ANA777',
        'license_type': 'Not provided', 'restrictions': '', 'expiry': '-', 'address': '-'});
    switch (req.url.path) {
      case '/auth/login':
        loginBodies.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
        return loginStatus == 200 ? http.Response(profile, 200) : http.Response(jsonEncode({'detail': loginDetail}), loginStatus);
      case '/auth/register':
        return registerStatus == 201 ? http.Response(profile, 201) : http.Response(jsonEncode({'detail': registerDetail}), registerStatus);
      case '/violations':
        return http.Response(jsonEncode({'total': 0, 'page': 1, 'size': 50, 'items': []}), 200);
      case '/notify/notices':
        final after = req.url.queryParameters['after'];
        final fresh = notices.where((n) => after == null || after.isEmpty || (n['created_at'] as String).compareTo(after) > 0).toList().reversed.toList();
        return http.Response(jsonEncode({'notices': fresh}), 200);
    }
    return http.Response('{}', 404);
  }
}

Future<void> pumpApp(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'server_address': '192.168.68.109:8000'});
    await AppConfig.load();
  });

  group('sign up', () {
    testWidgets('a form with a mistake says what is wrong and asks the laptop nothing', (tester) async {
      final laptop = FakeLaptop();
      await pumpApp(tester, RegisterScreen(api: laptop.api));
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(find.text('Enter your name.'), findsOneWidget);
      expect(laptop.calls, isEmpty);
    });

    testWidgets('the laptop\'s reason is shown when the plate already has an account', (tester) async {
      final laptop = FakeLaptop()
        ..registerStatus = 409
        ..registerDetail = 'That plate already has an account';
      await pumpApp(tester, RegisterScreen(api: laptop.api));
      await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Ana Cruz');
      await tester.enterText(find.widgetWithText(TextField, 'Plate number'), 'ana 777');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret1');
      await tester.enterText(find.widgetWithText(TextField, 'Repeat the password'), 'secret1');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(laptop.calls, ['POST /auth/register']);
      expect(find.text('That plate already has an account'), findsOneWidget);
    });
  });

  group('sign in', () {
    testWidgets('a demo account button signs in as that account straight away', (tester) async {
      final laptop = FakeLaptop();
      await pumpApp(tester, LoginScreen(api: laptop.api));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.widgetWithText(ActionChip, 'Maria'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(laptop.calls.first, 'POST /auth/login');
      expect(laptop.loginBodies.single, {'plate': 'DEF 5678', 'password': 'password123'});
      await tester.pumpWidget(const SizedBox());                                 // leave the page it moved to
    });

    testWidgets('empty fields are named, a wrong password is explained', (tester) async {
      final laptop = FakeLaptop()..loginStatus = 401;
      await pumpApp(tester, LoginScreen(api: laptop.api));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(find.text('Enter your plate number and password.'), findsOneWidget);
      expect(laptop.calls, isEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Plate number'), 'ANA 777');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Wrong plate number or password.'), findsOneWidget);
    });

    testWidgets('it shows which laptop it will talk to', (tester) async {
      await pumpApp(tester, LoginScreen(api: FakeLaptop().api));
      expect(find.text('Same Wi-Fi · 192.168.68.109:8000'), findsOneWidget);
    });
  });

  group('the connection window, same Wi-Fi', () {
    testWidgets('a laptop that answers is saved; one that does not is explained and nothing is saved', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig.load();
      var reachable = false;
      PortalApi apiFor(String url) => PortalApi(
            baseUrl: () => url,
            client: MockClient((req) async => reachable ? http.Response('{"total":0,"page":1,"size":1,"items":[]}', 200) : throw Exception('no route')),
          );
      late BuildContext context;
      await pumpApp(tester, Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }));
      final result = showConnectionDialog(context, lanApi: apiFor);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Same Wi-Fi'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '10.0.0.5');
      await tester.tap(find.text('Test and save'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Cannot reach the laptop at 10.0.0.5:8000'), findsOneWidget);
      expect(AppConfig.hasServer, isFalse);

      reachable = true;
      await tester.tap(find.text('Test and save'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(await result, isTrue);
      expect(AppConfig.address, '10.0.0.5:8000');
    });

    testWidgets('something that is not an address is refused before the laptop is asked', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig.load();
      late BuildContext context;
      await pumpApp(tester, Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }));
      showConnectionDialog(context);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Same Wi-Fi'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'not an address');
      await tester.tap(find.text('Test and save'));
      await tester.pump();
      expect(find.textContaining('Type the laptop'), findsOneWidget);
    });
  });

  group('while signed in', () {
    testWidgets('a notice that arrives on the laptop becomes a phone notification and a badge on Inbox', (tester) async {
      SharedPreferences.setMockInitialValues(signedIn);
      await AppConfig.load();
      final laptop = FakeLaptop();
      final shown = <String>[];
      await pumpApp(tester, MainScreen(api: laptop.api, showNotification: (title, body) async => shown.add('$title | $body')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(shown, isEmpty);

      laptop.notices.add({
        'id': 'n1', 'created_at': '2026-10-29T08:00:00+00:00',
        'subject': 'Traffic violation recorded: No Helmet (ANA 777)',
        'body': 'Hello Ana Cruz,\n\nA traffic violation was recorded for plate ANA 777.\n\n  Violation: No Helmet\n',
      });
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 100));

      expect(shown, ['No Helmet · ANA 777 | A traffic violation was recorded for plate ANA 777.']);               // the short title, then the first line
      expect(find.text('1'), findsOneWidget);                                      // the badge on Inbox
      await tester.tap(find.text('Inbox'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1'), findsNothing);                                        // opening the Inbox clears it
      expect(find.text('No Helmet · ANA 777'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());                                   // leaving the app stops the checks
    });
  });
}
