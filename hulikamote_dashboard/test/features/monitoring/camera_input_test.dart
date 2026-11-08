import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/monitoring/data/camera_api.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/camera_input_dialog.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/camera_status_chip.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake backend that records every request and answers like routers/settings.py.
class FakeBackend {
  final requests = <http.Request>[];
  List<Map<String, dynamic>> profiles = [
    {'name': 'Barangay CCTV', 'url': 'rtsp://admin:***@192.168.1.10/ch1', 'kind': 'rtsp'},
  ];
  Map<String, dynamic> testAnswer = {'ok': true, 'width': 1280, 'height': 720, 'fps': 15.0, 'first_frame_ms': 3500};

  CameraApi get api => CameraApi(
        baseUrl: 'http://test',
        client: MockClient((req) async {
          requests.add(req);
          switch (req.url.path) {
            case '/settings/camera-profiles':
              if (req.method == 'PUT') {
                profiles = [
                  for (final p in (jsonDecode(req.body)['profiles'] as List)) {...p as Map<String, dynamic>, 'kind': 'rtsp'},
                ];
                return http.Response(jsonEncode({'count': profiles.length}), 200);
              }
              return http.Response(jsonEncode({'profiles': profiles}), 200);
            case '/settings/video/test':
              return http.Response(jsonEncode(testAnswer), 200);
            case '/settings/video/source':
            case '/settings/camera-profiles/use':
              return http.Response(jsonEncode({'label': 'rtsp://cam/x'}), 200);
            case '/settings/video/status':
              return http.Response(jsonEncode({'state': 'live', 'label': 'x'}), 200);
          }
          return http.Response('{"detail":"unexpected ${req.url.path}"}', 404);
        }),
      );
}

Future<void> openDialog(WidgetTester tester, FakeBackend backend, {Future<bool?>? result}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<bool>(context: context, builder: (_) => CameraInputDialog(api: backend.api)),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('CameraApi', () {
    test('test() sends a typed address, or the profile name, and reads the answer', () async {
      final backend = FakeBackend();
      final byAddress = await backend.api.test(address: 'rtsp://1.2.3.4/x');
      final byName = await backend.api.test(profile: 'Barangay CCTV');
      expect(backend.requests[0].url.queryParameters, {'path': 'rtsp://1.2.3.4/x'});
      expect(backend.requests[1].url.queryParameters, {'name': 'Barangay CCTV'});
      expect(byAddress.ok, isTrue);
      expect(byName.summary, '1280x720 at 15 fps, first picture after 3.5 s');
    });

    test('a failed test explains why', () async {
      final backend = FakeBackend()..testAnswer = {'ok': false, 'error': 'No picture received'};
      expect((await backend.api.test(address: 'rtsp://x/y')).summary, 'No picture received');
    });

    test('a rejected address surfaces the backend message', () async {
      final api = CameraApi(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('{"detail":"Unsupported source type"}', 400)),
      );
      expect(api.use(address: 'file:///x'), throwsA(predicate((e) => '$e'.contains('Unsupported source type'))));
    });
  });

  group('CameraStatusChip', () {
    Future<void> show(WidgetTester tester, Map<String, dynamic> status) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: CameraStatusChip(status: status))));

    testWidgets('live shows size, speed and lag', (tester) async {
      await show(tester, {'state': 'live', 'width': 1280, 'height': 720, 'input_fps': 14.6, 'lag_ms': 120});
      expect(find.text('LIVE  1280x720  15 fps in  lag 120 ms'), findsOneWidget);
    });

    testWidgets('offline says it is reconnecting', (tester) async {
      await show(tester, {'state': 'offline', 'reconnects': 2});
      expect(find.text('OFFLINE - reconnecting (2 so far)'), findsOneWidget);
    });

    testWidgets('idle shows nothing', (tester) async {
      await show(tester, {'state': 'idle'});
      expect(find.byType(Text), findsNothing);
    });
  });

  group('CameraInputDialog', () {
    testWidgets('lists saved cameras, tests a typed address and shows the result', (tester) async {
      final backend = FakeBackend();
      await openDialog(tester, backend);

      await tester.enterText(find.byKey(const Key('camera-address')), 'rtsp://192.168.1.30:8554/cam1');
      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      final test = backend.requests.firstWhere((r) => r.url.path == '/settings/video/test');
      expect(test.url.queryParameters['path'], 'rtsp://192.168.1.30:8554/cam1');
      expect(find.textContaining('Works: 1280x720 at 15 fps'), findsOneWidget);
    });

    testWidgets('a saved camera whose address is untouched is tested and used by NAME (its password stays hidden)',
        (tester) async {
      final backend = FakeBackend();
      await openDialog(tester, backend);

      await tester.tap(find.byKey(const Key('profile-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Barangay CCTV  (rtsp)').last);
      await tester.pumpAndSettle();
      expect((tester.widget(find.byKey(const Key('camera-address'))) as TextField).controller!.text,
          'rtsp://admin:***@192.168.1.10/ch1');

      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this camera'));
      await tester.pumpAndSettle();

      final names = backend.requests.where((r) => r.url.queryParameters.containsKey('name')).toList();
      expect(names.map((r) => r.url.path), ['/settings/video/test', '/settings/camera-profiles/use']);
      expect(backend.requests.where((r) => r.url.queryParameters.containsKey('path')), isEmpty);
      expect(find.byType(CameraInputDialog), findsNothing); // closed after Use
    });

    testWidgets('a preset fills the name and address, and Save camera stores it', (tester) async {
      final backend = FakeBackend();
      await openDialog(tester, backend);

      await tester.tap(find.text('Laptop B (clip as a camera)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save camera'));
      await tester.pumpAndSettle();

      final put = backend.requests.firstWhere((r) => r.method == 'PUT');
      final saved = (jsonDecode(put.body)['profiles'] as List).cast<Map<String, dynamic>>();
      expect(saved.map((p) => p['name']), containsAll(['Barangay CCTV', 'Laptop B']));
      expect(saved.firstWhere((p) => p['name'] == 'Laptop B')['url'], 'rtsp://192.168.1.30:8554/cam1');
      expect(find.text('Saved "Laptop B"'), findsOneWidget);
    });

    testWidgets('an empty address is refused before asking the backend', (tester) async {
      final backend = FakeBackend();
      await openDialog(tester, backend);
      await tester.tap(find.text('Use this camera'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an address first'), findsOneWidget);
      expect(backend.requests.where((r) => r.url.path.contains('source') || r.url.path.contains('use')), isEmpty);
    });
  });
}
