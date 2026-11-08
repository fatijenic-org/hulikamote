import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_app/core/config/app_config.dart';
import 'package:hulikamote_app/core/services/demo_accounts.dart';
import 'package:hulikamote_app/core/services/dev_mode.dart';
import 'package:hulikamote_app/core/services/portal_api.dart';
import 'package:hulikamote_app/features/dev/dev_api.dart';
import 'package:hulikamote_app/features/dev/dev_tools_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

const juan = DevAccount(id: 'user_001', name: 'Juan Dela Cruz', email: '', plates: ['ABC 1234', 'LP14LJA'], loginPlate: 'ABC 1234');
const maria = DevAccount(id: 'user_002', name: 'Maria Santos', email: 'maria@example.test', plates: ['DEF 5678'], loginPlate: 'DEF 5678');

/// The laptop's developer tools answering from memory.
class FakeDev extends DevApi {
  FakeDev(this.items) : super(baseUrl: () => 'http://test');

  List<DevAccount> items;
  final calls = <String>[];
  String cloud = 'ok';
  PortalException? failure;

  @override
  Future<List<DevAccount>> accounts() async {
    if (failure != null) throw failure!;
    return items;
  }

  @override
  Future<DevOutcome> create({required String name, required String plate, required String password, String email = ''}) async {
    calls.add('create $name | $plate | $password | $email');
    final made = DevAccount(id: 'new', name: name, email: email, plates: [plate], loginPlate: plate);
    items = [...items, made];
    return DevOutcome(made, cloud);
  }

  @override
  Future<DevOutcome> change(String id, {String? name, String? email, String? password, List<String> addPlates = const [], List<String> removePlates = const []}) async {
    calls.add('change $id | name=$name | email=$email | password=${password ?? '-'} | +$addPlates | -$removePlates');
    return DevOutcome(items.firstWhere((a) => a.id == id), cloud);
  }

  @override
  Future<DevOutcome> delete(String id) async {
    calls.add('delete $id');
    items = [for (final a in items) if (a.id != id) a];
    return DevOutcome(null, cloud);
  }

  @override
  Future<String> createCloudDemoAccounts() async {
    calls.add('cloud-demo');
    return '1 created, 2 already there.';
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(signedInPrefs);
    await AppConfig.load();
    DevMode.enabled.value = true;
  });

  group('the laptop\'s developer tools, as the app calls them', () {
    DevApi api(Future<http.Response> Function(http.Request) handler) => DevApi(client: MockClient(handler), baseUrl: () => 'http://192.168.68.109:8000');

    test('every call says it comes from the tools, and the list is read', () async {
      late http.Request seen;
      final dev = api((req) async {
        seen = req;
        return http.Response(jsonEncode({'accounts': [{'id': 'u1', 'name': 'Juan', 'email': '', 'plates': ['ABC 1234'], 'login_plate': 'ABC 1234'}]}), 200);
      });
      final list = await dev.accounts();
      expect(seen.headers['X-HK-Dev'], '1');
      expect((list.single.name, list.single.loginPlate), ('Juan', 'ABC 1234'));
    });

    test('a change sends only what is given, and the cloud\'s answer comes back', () async {
      late http.Request seen;
      final dev = api((req) async {
        seen = req;
        return http.Response(jsonEncode({'account': {'id': 'u1', 'name': 'New', 'email': '', 'plates': [], 'login_plate': ''}, 'cloud': 'failed: Cannot reach Supabase: down'}), 200);
      });
      final outcome = await dev.change('u1', name: 'New', password: 'pass1234', addPlates: ['XYZ 1']);
      expect(seen.method, 'PUT');
      expect(jsonDecode(seen.body), {'name': 'New', 'email': null, 'password': 'pass1234', 'add_plates': ['XYZ 1'], 'remove_plates': []});
      expect(outcome.cloudFailed, isTrue);
    });

    test('a laptop that is not in developer mode says how to start it', () async {
      final off = api((req) async => http.Response(jsonEncode({'detail': 'Developer tools are off on this laptop. Start the backend with tools\\run_demo_backend.bat.'}), 404));
      expect(off.accounts(), throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('run_demo_backend.bat'))));
      final old = api((req) async => http.Response('{"detail":"Not Found"}', 404));
      expect(old.accounts(), throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('no developer tools'))));
    });

    test('a laptop that does not answer is explained with the address that was tried', () async {
      final dead = api((req) async => throw Exception('refused'));
      expect(dead.accounts(), throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('192.168.68.109:8000'))));
    });
  });

  group('the developer tools page', () {
    testWidgets('lists the demo accounts with their plates and the sign-in shortcuts', (tester) async {
      await pumpPage(tester, DevToolsScreen(api: FakeDev([juan, maria])));
      await settle(tester);
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(find.textContaining('ABC 1234, LP14LJA'), findsOneWidget);
      expect(find.textContaining('maria@example.test'), findsOneWidget);
      expect(find.text('Temporary'), findsOneWidget);
      expect(find.text('Juan'), findsOneWidget);                                      // a sign-in shortcut
    });

    testWidgets('without a saved laptop it asks for the address first, then loads the accounts', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig.load();
      final dev = FakeDev([juan]);
      await pumpPage(tester, DevToolsScreen(api: dev));
      await settle(tester);
      expect(find.text('Connect to the laptop to see its accounts.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Laptop address'), '192.168.68.109');
      await tester.tap(find.text('Connect'));
      await settle(tester);
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(AppConfig.address, '192.168.68.109:8000');
    });

    testWidgets('a laptop that refuses is explained on the page', (tester) async {
      final dev = FakeDev([])..failure = PortalException('Developer tools are off on this laptop.');
      await pumpPage(tester, DevToolsScreen(api: dev));
      await settle(tester);
      expect(find.text('Developer tools are off on this laptop.'), findsOneWidget);
    });

    testWidgets('a new account is created with a plate and password, and a sign-in shortcut is kept', (tester) async {
      final dev = FakeDev([juan]);
      await pumpPage(tester, DevToolsScreen(api: dev));
      await settle(tester);

      await tester.tap(find.text('Add account'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Ana Cruz');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret1');
      await tester.enterText(find.widgetWithText(TextField, 'Add a plate'), 'ana 777');
      await tester.tap(find.byTooltip('Add plate'));
      await tester.pump();
      await tester.tap(find.text('Create account'));
      await settle(tester);

      expect(dev.calls, ['create Ana Cruz | ANA 777 | secret1 | ']);
      expect(find.textContaining('Account created. Also in the cloud.'), findsOneWidget);
      expect((await DemoAccounts.load()).any((a) => a.name == 'Ana' && a.plate == 'ANA 777' && a.password == 'secret1'), isTrue);
    });

    testWidgets('an account can be renamed, given a new password and another plate, and the shortcut follows', (tester) async {
      final dev = FakeDev([juan, maria]);
      await pumpPage(tester, DevToolsScreen(api: dev));
      await settle(tester);

      await tester.tap(find.text('Juan Dela Cruz'));
      await settle(tester);
      expect(find.byTooltip('Remove LP14LJA'), findsOneWidget);                       // an extra plate can go
      expect(find.byTooltip('Remove ABC 1234'), findsNothing);                        // the one it signs in with cannot
      await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Juan D.');
      await tester.enterText(find.widgetWithText(TextField, 'New password (leave empty to keep)'), 'newpass1');
      await tester.enterText(find.widgetWithText(TextField, 'Add a plate'), 'new 999');
      await tester.tap(find.byTooltip('Add plate'));
      await tester.pump();
      await tester.tap(find.byTooltip('Remove LP14LJA'));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await settle(tester);

      expect(dev.calls.single, 'change user_001 | name=Juan D. | email=null | password=newpass1 | +[NEW 999] | -[LP14LJA]');
      final shortcut = (await DemoAccounts.load()).firstWhere((a) => a.plate == 'ABC 1234');
      expect((shortcut.name, shortcut.password), ('Juan', 'newpass1'));
    });

    testWidgets('a cloud problem is reported, but the change on the laptop stands', (tester) async {
      final dev = FakeDev([juan])..cloud = 'failed: Cannot reach Supabase: down';
      await pumpPage(tester, DevToolsScreen(api: dev));
      await settle(tester);
      await tester.tap(find.text('Juan Dela Cruz'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'E-mail (optional)'), 'juan@example.test');
      await tester.tap(find.text('Save changes'));
      await settle(tester);
      expect(find.textContaining('the cloud change failed: Cannot reach Supabase: down'), findsOneWidget);
    });

    testWidgets('deleting asks first, then removes the account and its shortcut', (tester) async {
      final dev = FakeDev([juan, maria]);
      await pumpPage(tester, DevToolsScreen(api: dev));
      await settle(tester);
      await tester.tap(find.text('Juan Dela Cruz'));
      await settle(tester);
      await tester.tap(find.text('Delete account'));
      await settle(tester);
      expect(find.text('Delete this account?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);
      expect(dev.calls, ['delete user_001']);
      expect(find.text('Juan Dela Cruz'), findsNothing);
      expect((await DemoAccounts.load()).any((a) => a.plate == 'ABC 1234'), isFalse);
    });

    testWidgets('the demo accounts can be created in the cloud with one tap', (tester) async {
      final dev = FakeDev([juan]);
      await pumpPage(tester, DevToolsScreen(api: dev));
      await settle(tester);
      await tester.tap(find.text('Create the demo accounts in the cloud'));
      await settle(tester);
      expect(dev.calls, ['cloud-demo']);
      expect(find.textContaining('1 created, 2 already there.'), findsOneWidget);
    });

    testWidgets('a sign-in shortcut can be edited, and the shortcuts can be reset', (tester) async {
      await pumpPage(tester, DevToolsScreen(api: FakeDev([juan])));
      await settle(tester);
      await tester.tap(find.text('Maria'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'maria-new');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      expect((await DemoAccounts.load()).firstWhere((a) => a.name == 'Maria').password, 'maria-new');

      await tester.ensureVisible(find.text('Reset shortcuts to the three demo accounts'));
      await tester.tap(find.text('Reset shortcuts to the three demo accounts'));
      await settle(tester);
      expect((await DemoAccounts.load()).firstWhere((a) => a.name == 'Maria').password, 'password123');
    });

    testWidgets('developer mode can be switched off from the page', (tester) async {
      await pumpPage(tester, Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DevToolsScreen(api: FakeDev([juan])))), child: const Text('open')))));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.ensureVisible(find.text('Turn developer mode off'));
      await tester.tap(find.text('Turn developer mode off'));
      await tester.pumpAndSettle();                                                   // the page slides away
      expect(DevMode.enabled.value, isFalse);
      expect(find.text('Developer tools'), findsNothing);
    });
  });
}
