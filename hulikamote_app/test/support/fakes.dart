import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_app/core/models/account.dart';
import 'package:hulikamote_app/core/models/notice.dart';
import 'package:hulikamote_app/core/services/portal_api.dart';
import 'package:hulikamote_app/core/ui/app_theme.dart';
import 'package:hulikamote_app/features/home/models/violation.dart';

/// What a signed-in phone has saved (the sign-in and the connection).
const signedInPrefs = {
  'server_address': '192.168.68.109:8000', 'user_id': 'user_9', 'name': 'Ana Cruz', 'plate': 'ANA 777', 'email': 'ana@example.test',
  'license_no': 'PLATE-ANA777', 'license_type': 'Not provided', 'restrictions': '', 'expiry': '-', 'address': '-',
};

Violation ticket(String id, {String cls = 'no_helmet', DateTime? at, String plate = 'ANA 777', List<String> frames = const []}) => Violation(
      id: id,
      cls: cls,
      confidence: 0.9,
      timestamp: (at ?? DateTime.now()).toUtc().toIso8601String(),
      imagePath: '',
      plate: plate,
      evidencePaths: frames,
    );

Notice notice(String id, String subject, DateTime at, {String body = 'Hello Ana,\n\nA traffic violation was recorded for plate ANA 777.\n'}) =>
    Notice(id: id, subject: subject, body: body, createdAt: at.toUtc().toIso8601String());

/// The whole system answering from memory. Set [failure] and every call fails with it.
class FakePortal implements PortalApi {
  FakePortal({List<Violation>? tickets, Map<String, String>? appeals, List<Notice>? notices})
      : ticketList = tickets ?? [],
        appealMap = appeals ?? {},
        noticeList = notices ?? [];

  List<Violation> ticketList;
  Map<String, String> appealMap;
  List<Notice> noticeList;
  PortalException? failure;

  /// How long every answer takes (to see the loading state).
  Duration delay = Duration.zero;
  final calls = <String>[];
  final appealsFiled = <Map<String, String>>[];
  final forgotten = <String>[];

  Future<T> _go<T>(String name, T Function() body) async {
    calls.add(name);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failure != null) throw failure!;
    return body();
  }

  @override
  Future<void> ping() => _go('ping', () {});

  @override
  Future<Account> login(String plate, String password) async => throw UnimplementedError();

  @override
  Future<Account> register({required String name, required String plate, required String password, String email = ''}) async => throw UnimplementedError();

  @override
  Future<List<Violation>> tickets(String userId) => _go('tickets', () => ticketList);

  @override
  Future<List<Notice>> notices(String userId, {String? after}) => _go('notices', () => noticeList);

  @override
  Future<Map<String, String>> appealStatuses(String userId) => _go('appeals', () => appealMap);

  @override
  Future<void> fileAppeal({required String violationId, required String userId, required String reason}) => _go('fileAppeal', () {
        appealsFiled.add({'violation': violationId, 'user': userId, 'reason': reason});
        appealMap = {...appealMap, violationId: 'pending'};
      });

  @override
  Future<void> registerPushToken(String token, String userId) => _go('registerPushToken', () {});

  @override
  Future<void> forgetPushToken(String token) => _go('forgetPushToken', () => forgotten.add(token));
}

/// A page in the real theme, in a tall window, with the routes a page may navigate to.
Future<void> pumpPage(WidgetTester tester, Widget page, {Map<String, WidgetBuilder> routes = const {}, ThemeData? theme}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: theme ?? AppTheme.light(), home: page, routes: routes));
  await tester.pump(const Duration(milliseconds: 100));
}
