/// Draws every screen to a PNG so the design can be looked at without a phone. It only runs when SHOTS_DIR is set:
///   SHOTS_DIR=some/folder flutter test test/visual/screenshots_test.dart
/// Nothing is written otherwise, and the images are never part of the repository.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_app/core/config/app_config.dart';
import 'package:hulikamote_app/core/services/dev_mode.dart';
import 'package:hulikamote_app/core/services/portal_api.dart';
import 'package:hulikamote_app/core/ui/app_theme.dart';
import 'package:hulikamote_app/features/appeals/screens/appeal_screen.dart';
import 'package:hulikamote_app/features/auth/screens/login_screen.dart';
import 'package:hulikamote_app/features/auth/screens/register_screen.dart';
import 'package:hulikamote_app/features/dev/dev_api.dart';
import 'package:hulikamote_app/features/dev/dev_tools_screen.dart';
import 'package:hulikamote_app/features/home/screens/home_screen.dart';
import 'package:hulikamote_app/features/home/screens/violation_detail_screen.dart';
import 'package:hulikamote_app/features/main/screens/main_screen.dart';
import 'package:hulikamote_app/features/notifications/screens/notifications_screen.dart';
import 'package:hulikamote_app/features/profile/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

final _out = Platform.environment['SHOTS_DIR'];
final _key = GlobalKey();

/// The fonts the Flutter SDK ships, so text and icons are drawn like on a phone (the test font is a row of squares).
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  Future<ByteData>? read(String name) {
    final f = File('${dir.path}/$name');
    return f.existsSync() ? Future.value(ByteData.sublistView(f.readAsBytesSync())) : null;
  }

  final roboto = FontLoader('Roboto');
  for (final name in const ['Regular', 'Medium', 'Bold']) {
    final data = read('Roboto-$name.ttf');
    if (data != null) roboto.addFont(data);
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons');
  final data = read('MaterialIcons-Regular.otf');
  if (data != null) icons.addFont(data);
  await icons.load();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// A phone-sized window with the page in the real theme.
Future<void> _show(WidgetTester tester, Widget page, {bool dark = false, Map<String, WidgetBuilder> routes = const {}}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: _key,
    child: MaterialApp(debugShowCheckedModeBanner: false, theme: dark ? AppTheme.dark() : AppTheme.light(), home: page, routes: routes),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  final skip = _out == null ? 'set SHOTS_DIR to draw the screens' : null;

  setUpAll(() async {
    await _loadFonts();
    if (_out != null) Directory(_out!).createSync(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(signedInPrefs);
    await AppConfig.load();
    DevMode.enabled.value = true;
  });

  final now = DateTime.now();
  FakePortal portal() => FakePortal(
        tickets: [
          ticket('ab12cd34-0001', cls: 'counterflow', at: now.subtract(const Duration(hours: 2))),
          ticket('ab12cd34-0002', cls: 'no_helmet', at: now.subtract(const Duration(days: 1, hours: 3))),
          ticket('ab12cd34-0003', cls: 'red_light', at: now.subtract(const Duration(days: 5))),
          ticket('ab12cd34-0004', cls: 'illegal_parking', at: now.subtract(const Duration(days: 12))),
        ],
        appeals: {'ab12cd34-0002': 'pending', 'ab12cd34-0003': 'accepted'},
        notices: [
          notice('n1', 'Traffic violation recorded: Counterflow (ANA 777)', now.subtract(const Duration(hours: 2))),
          notice('n2', 'Traffic violation recorded: No Helmet (ANA 777)', now.subtract(const Duration(days: 1, hours: 3))),
          notice('n3', 'Traffic violation recorded: Red Light (ANA 777)', now.subtract(const Duration(days: 5))),
        ],
      );

  testWidgets('sign in', (tester) async {
    await _show(tester, LoginScreen(api: portal()));
    await _shoot(tester, '01_sign_in');
  }, skip: skip != null);

  testWidgets('sign in with a problem', (tester) async {
    await _show(tester, LoginScreen(api: portal()));
    await tester.tap(find.text('Sign in'));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, '02_sign_in_error');
  }, skip: skip != null);

  testWidgets('create account with mistakes', (tester) async {
    await _show(tester, RegisterScreen(api: portal()));
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, '03_register_errors');
  }, skip: skip != null);

  testWidgets('records', (tester) async {
    await _show(tester, MainScreen(api: portal()));
    await _shoot(tester, '04_records');
  }, skip: skip != null);

  testWidgets('records, dark', (tester) async {
    await _show(tester, MainScreen(api: portal()), dark: true);
    await _shoot(tester, '05_records_dark');
  }, skip: skip != null);

  testWidgets('records, offline with a saved copy', (tester) async {
    final p = portal();
    await _show(tester, HomeScreen(api: p));
    await tester.pumpWidget(const SizedBox());
    final offline = FakePortal()..failure = PortalException('Cannot reach the laptop at 192.168.68.109:8000.');
    await _show(tester, HomeScreen(key: UniqueKey(), api: offline));
    await _shoot(tester, '06_records_offline');
  }, skip: skip != null);

  testWidgets('records, loading', (tester) async {
    await _show(tester, HomeScreen(api: portal()..delay = const Duration(seconds: 5)));
    await _shoot(tester, '07_records_loading');
    await tester.pump(const Duration(seconds: 12));      // let the slow answers finish
  }, skip: skip != null);

  testWidgets('ticket', (tester) async {
    await _show(tester, ViolationDetailScreen(violation: ticket('ab12cd34-0001', cls: 'counterflow', at: now.subtract(const Duration(hours: 2))), api: portal()));
    await _shoot(tester, '08_ticket');
  }, skip: skip != null);

  testWidgets('ticket with an appeal', (tester) async {
    await _show(tester, ViolationDetailScreen(violation: ticket('ab12cd34-0002', at: now.subtract(const Duration(days: 1))), appealStatus: 'pending', api: portal()));
    await _shoot(tester, '09_ticket_appealed');
  }, skip: skip != null);

  testWidgets('appeal', (tester) async {
    await _show(tester, AppealScreen(violation: ticket('ab12cd34-0001', cls: 'counterflow', at: now.subtract(const Duration(hours: 2))), api: portal()));
    await tester.tap(find.text('I was not the one driving.'));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, '10_appeal');
  }, skip: skip != null);

  testWidgets('appeal sent', (tester) async {
    await _show(tester, AppealScreen(violation: ticket('ab12cd34-0001', cls: 'counterflow'), api: portal()));
    await tester.enterText(find.widgetWithText(TextField, 'Your reason'), 'I was not the one driving.');
    await tester.tap(find.text('Send appeal'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));
    await _shoot(tester, '11_appeal_sent');
  }, skip: skip != null);

  testWidgets('inbox', (tester) async {
    await _show(tester, NotificationsScreen(api: portal()));
    await _shoot(tester, '12_inbox');
  }, skip: skip != null);

  testWidgets('profile', (tester) async {
    await _show(tester, const ProfileScreen());
    await _shoot(tester, '13_profile');
  }, skip: skip != null);

  testWidgets('developer tools', (tester) async {
    const juan = DevAccount(id: 'user_001', name: 'Juan Dela Cruz', email: '', plates: ['ABC 1234', 'LP14LJA', 'AF65JKV'], loginPlate: 'ABC 1234');
    const maria = DevAccount(id: 'user_002', name: 'Maria Santos', email: 'maria@example.test', plates: ['DEF 5678'], loginPlate: 'DEF 5678');
    await _show(tester, DevToolsScreen(api: _Dev([juan, maria])));
    await _shoot(tester, '14_dev_tools');
  }, skip: skip != null);
}

class _Dev extends DevApi {
  _Dev(this.items) : super(baseUrl: () => 'http://test');

  final List<DevAccount> items;

  @override
  Future<List<DevAccount>> accounts() async => items;
}
