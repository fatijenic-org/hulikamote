import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/violation_catalog.dart';
import 'package:hulikamote_dashboard/features/monitoring/data/camera_api.dart';
import 'package:hulikamote_dashboard/features/monitoring/domain/models/detection.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/screens/live_setup_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../forensic/support/test_support.dart';

/// A backend that answers without a network and records the rules sent to the Live Monitor.
class _Api extends ForensicApi {
  _Api() : super(baseUrl: 'http://test');

  Map<String, dynamic>? sent;

  @override
  Future<ModelChoices> models() async => ModelChoices.empty;

  @override
  Future<String> useForLive(Map<String, dynamic> config) async {
    sent = config;
    return 'ok';
  }
}

CameraApi _camera(Map<String, dynamic> setup) => CameraApi(
  baseUrl: 'http://test',
  client: MockClient((req) async {
    if (req.url.path == '/settings/live/setup') return http.Response(jsonEncode(setup), 200);
    return http.Response('{"detail":"unexpected ${req.url.path}"}', 404);
  }),
);

void main() {
  setUpAll(loadRoboto);

  Future<void> open(WidgetTester tester, CameraApi camera, _Api api) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push<int>(
              MaterialPageRoute(
                builder: (_) => LiveSetupScreen(
                  cameraApi: camera,
                  shot: const {'ok': true, 'version': 3, 'width': 1920, 'height': 1080, 'fps': 25.0},
                  api: api,
                  media: FakeMedia(),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(seconds: 1));      // the pushed page slides in
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the current live setup is loaded, set up on the frozen picture and sent to the Live Monitor', (tester) async {
    final api = _Api();
    final camera = _camera({
      'active_violations': ['swerving'],
      'per_violation_configs': {
        'swerving': {
          'rois': [
            {'polygon': [[100, 100], [900, 100], [900, 600]]},
          ],
        },
      },
    });
    await open(tester, camera, api);

    expect(find.text('Set up violations on the live camera'), findsOneWidget);
    expect(find.text('1 of ${ViolationCatalog.selectable.length} selected'), findsOneWidget);   // what was set up before
    expect(find.text('Your current live setup is loaded. Change it as you need.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Set up the rules'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Fine-tune the pipeline'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Review and apply'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-setup-apply')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(api.sent!['active_violations'], ['swerving']);
    expect(api.sent!['tracker'], 'deepsort');                       // ByteTrack leaves most boxes of a real clip without an ID
    expect(((api.sent!['per_violation_configs'] as Map)['swerving'] as Map)['rois'], hasLength(1));
    expect(find.text('open'), findsOneWidget);                      // back on the Live Monitor
  });

  testWidgets('a rule that needs a zone blocks Continue, and a solid line must be drawn on a live picture', (tester) async {
    final api = _Api();
    await open(tester, _camera({}), api);

    expect(find.text('Pick at least one violation.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNull);

    await tester.tap(find.text(ViolationCatalog.of('crossing_solid_line').label).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Still needs a zone: ${ViolationCatalog.of('crossing_solid_line').label}'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNull);
  });

  test('a zone the operator set up is drawn on the live picture with the rule name', () {
    final zone = RoadZone.fromJson({
      'violation': 'illegal_parking',
      'polygon': [[0, 0], [10, 0], [10, 10]],
      'line': [],
      'drawn': true,
    });
    expect(zone.drawn, isTrue);
    expect(zone.label, 'Illegal Parking');
    final learned = RoadZone.fromJson({'violation': 'pedestrian_lane', 'polygon': [[0, 0], [10, 0], [10, 10]]});
    expect(learned.label, 'Crosswalk (learned)');
  });
}
