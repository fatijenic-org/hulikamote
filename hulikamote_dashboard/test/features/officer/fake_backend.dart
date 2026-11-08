import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/features/demerit/data/demerit_api.dart';
import 'package:hulikamote_dashboard/features/overview/data/overview_api.dart';
import 'package:hulikamote_dashboard/features/registry/data/registry_api.dart';

/// A stand-in for the laptop's backend: it answers the few calls the officer pages make, and records the rest.
class FakeBackend {
  FakeBackend({this.sessions, this.violations = const [], this.plates = const [], this.motorists = 2});

  /// {source: {batch id: [tickets]}}; null means the Inbox call fails with a server error.
  Map<String, Map<String, List<Map<String, dynamic>>>>? sessions;
  List<Map<String, dynamic>> violations;
  List<Map<String, dynamic>> plates;
  int motorists;

  /// Every network call fails, as if the backend were not running.
  bool down = false;

  /// The PATCH that saves a decision fails.
  bool failDecisions = false;

  final decisions = <String, String>{}; // ticket id -> status saved
  final asked = <Uri>[];

  late final http.Client client = MockClient(_handle);
  late final OverviewApi overview = OverviewApi(
    client: client,
    demerit: DemeritApi(client: client),
    registry: RegistryApi(client: client),
  );

  Future<http.Response> _handle(http.Request r) async {
    asked.add(r.url);
    if (down) throw const SocketException('connection refused');
    final path = r.url.path;
    http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

    if (r.method == 'PATCH' && path.startsWith('/violations/')) {
      if (failDecisions) return http.Response('{}', 500);
      decisions[path.split('/').last] = (jsonDecode(r.body) as Map)['status'] as String;
      return ok({'ok': true});
    }
    if (path == '/violations/sessions') {
      final s = sessions;
      if (s == null) return http.Response('{}', 500);
      return ok({for (final e in s.entries) e.key: e.value});
    }
    if (path == '/violations') {
      final status = r.url.queryParameters['status'];
      final items = [for (final v in violations) if (status == null || v['status'] == status) v];
      return ok({'total': items.length, 'page': 1, 'size': 20, 'items': items});
    }
    if (path == '/demerit') return ok({'plates': plates});
    if (path == '/registry') {
      return ok({
        'motorists': [for (var i = 0; i < motorists; i++) {'id': 'u$i', 'name': 'Motorist $i', 'license_no': 'L$i', 'email': '', 'plates': <String>[]}],
      });
    }
    return http.Response('not found', 404);
  }
}

/// A ticket as the backend lists it in the Inbox.
Map<String, dynamic> pendingTicket(String id, {String cls = 'no_helmet', String? plate, DateTime? at}) => {
      'id': id,
      'cls': cls,
      'timestamp': (at ?? DateTime.now().subtract(const Duration(minutes: 12))).toUtc().toIso8601String(),
      'user_name': plate,
      'image_path': '',
      'evidence_paths': '[]',
    };

/// A violation as the records list returns it.
Map<String, dynamic> record(String id, {String cls = 'red_light', String? plate = 'ABC 1234', String status = 'approved', DateTime? at}) => {
      'id': id,
      'cls': cls,
      'confidence': 0.91,
      'timestamp': (at ?? DateTime.now().subtract(const Duration(hours: 2))).toUtc().toIso8601String(),
      'image_path': '',
      'user_name': plate,
      'status': status,
    };
