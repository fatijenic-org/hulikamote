import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/features/models_hub/data/models_hub_api.dart';
import 'package:hulikamote_dashboard/features/models_hub/domain/hub_models.dart';
import 'package:hulikamote_dashboard/features/models_hub/presentation/hub_format.dart';
import 'package:hulikamote_dashboard/features/models_hub/presentation/screens/models_hub_screen.dart';

import '../forensic/support/test_support.dart';

Map<String, dynamic> version(String id, String name,
        {double? score, bool live = false, String kind = 'run', String origin = 'trained', String? file, Map<String, dynamic>? classes, String? checking}) =>
    {
      'id': id,
      'name': name,
      'kind': kind,
      'origin': origin,
      'run': kind == 'run' ? id : null,
      'when': 1793000000.0,
      'stats': score == null ? {} : {'score': score, 'trust': 0.75, 'coverage': 0.64},
      'epochs_done': 30,
      'epochs_planned': 30,
      'settings': {'epochs': 30, 'imgsz': 640},
      'classes': classes,
      'size_mb': 6.3,
      'file': file,
      'live': live,
      'usable': true,
      'checking': checking,
    };

Map<String, dynamic> vehicles({String live = 'yolo11_primary.onnx', Map<String, dynamic>? v3Classes, String? v3Checking}) => {
      'job': 'vehicles',
      'key': 'primary_anchor',
      'label': 'Vehicles',
      'kind': 'yolo',
      'purpose': 'Finds cars, motorcycles, buses, trucks and people in every frame.',
      'applies': 'Used from the next analysis.',
      'score_format': 'decimal',
      'can_switch': true,
      'live_id': live,
      'stats': [
        {'key': 'score', 'label': 'Score', 'hint': 'How often it gets it right'},
        {'key': 'trust', 'label': 'Trust', 'hint': 'When it points at something, it is right'},
        {'key': 'coverage', 'label': 'Coverage', 'hint': 'Share of the real ones it finds'},
      ],
      'versions': [
        version('train-3', 'Version 3', score: 0.712, live: live == 'train-3', file: live == 'train-3' ? 'primary_anchor_train-3_20261101.onnx' : null, classes: v3Classes, checking: v3Checking),
        version('train', 'Version 1', score: 0.68),
        version('yolo11_primary.onnx', 'yolo11_primary', kind: 'file', origin: 'stock', file: 'yolo11_primary.onnx', live: live == 'yolo11_primary.onnx'),
      ],
    };

Map<String, dynamic> reader() => {
      'job': 'reader',
      'key': 'plate_ocr',
      'label': 'Plate reader',
      'kind': 'ocr',
      'purpose': 'Reads the characters on a plate crop.',
      'applies': '',
      'score_format': 'decimal',
      'can_switch': false,
      'note': 'Training here puts the new model to work by itself. Choosing between versions is not available for this job yet.',
      'live_id': null,
      'stats': [],
      'versions': [],
    };

class Backend {
  Backend(this.jobs);

  Map<String, dynamic> Function() jobs;
  final posts = <String, Map<String, dynamic>>{};
  void Function()? afterUse;

  late final http.Client client = MockClient((req) async {
    if (req.method == 'GET' && req.url.path == '/models/hub') {
      return http.Response(jsonEncode({'jobs': [jobs(), reader()]}), 200);
    }
    if (req.method == 'POST') {
      posts[req.url.path] = jsonDecode(req.body) as Map<String, dynamic>;
      if (req.url.path == '/models/hub/use') afterUse?.call();
      return http.Response(jsonEncode({'detail': 'Vehicles is now Version 3. Used from the next analysis.'}), 200);
    }
    return http.Response('{}', 404);
  });
}

Future<void> pump(WidgetTester tester, Backend backend) async {
  tester.view.physicalSize = const Size(1500, 1500);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ModelsHubScreen(api: ModelsHubApi(client: backend.client))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6)); // the toast and the state bar's timers finish
}

void main() {
  setUpAll(loadRoboto);

  testWidgets('every job is on the left with what is live, and the open job lists its versions with how they compare', (tester) async {
    await pump(tester, Backend(vehicles));
    expect(find.text('Vehicles'), findsWidgets);
    expect(find.text('Plate reader'), findsOneWidget);
    expect(find.text('yolo11_primary'), findsWidgets); // the live one: in the rail, the live card and the list
    expect(find.text('Live now'), findsOneWidget);
    expect(find.text('Version 3'), findsOneWidget);
    expect(find.text('0.71'), findsOneWidget);
    expect(find.text('0.68'), findsOneWidget);
    // the live model has no score, so there is nothing to compare against yet
    expect(find.textContaining('vs live'), findsNothing);
    expect(find.text('Use this'), findsNWidgets(2)); // not on the live one
    await dispose(tester);
  });

  testWidgets('a score is compared with the live one once the live one has a score', (tester) async {
    await pump(tester, Backend(() => vehicles(live: 'train-3')));
    expect(find.text('−0.03 vs live'), findsOneWidget); // Version 1 (0.68) against the live Version 3 (0.71)
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Trust'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('Use this asks once in the row, then switches and reloads', (tester) async {
    var live = 'yolo11_primary.onnx';
    final backend = Backend(() => vehicles(live: live))..afterUse = () => live = 'train-3';
    await pump(tester, backend);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Use this').first);
    await tester.pump();
    expect(find.textContaining('Switch vehicles from yolo11_primary to Version 3?'), findsOneWidget);
    expect(find.textContaining('prepared first'), findsOneWidget); // a run nobody exported yet
    expect(backend.posts, isEmpty); // nothing happens before the answer

    await tester.tap(find.text('Switch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(backend.posts['/models/hub/use'], {'job': 'vehicles', 'id': 'train-3'});
    expect(find.textContaining('Switch vehicles from'), findsNothing);
    expect(find.text('Live'), findsOneWidget); // now Version 3
    await dispose(tester);
  });

  testWidgets('Cancel leaves everything as it was', (tester) async {
    final backend = Backend(vehicles);
    await pump(tester, backend);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Use this').first);
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.textContaining('Switch vehicles from'), findsNothing);
    expect(backend.posts, isEmpty);
    await dispose(tester);
  });

  testWidgets('opening a version shows its per-type scores; without them it offers to check', (tester) async {
    final classes = {
      'split': 'test',
      'map50': 0.715,
      'classes': [
        {'name': 'tricycle', 'score': 0.915, 'boxes': 124},
        {'name': 'person', 'score': 0.472, 'boxes': 1082},
      ],
    };
    final backend = Backend(() => vehicles(v3Classes: classes));
    await pump(tester, backend);
    await tester.tap(find.text('Version 3'));
    await tester.pump();
    expect(find.text('tricycle'), findsOneWidget);
    expect(find.text('0.92'), findsOneWidget);
    expect(find.text('124 boxes'), findsOneWidget);

    await tester.tap(find.text('Version 1'));
    await tester.pump();
    expect(find.textContaining('have not been checked'), findsOneWidget);
    await tester.tap(find.text('Check per type'));
    await tester.pump();
    expect(backend.posts['/models/hub/check'], {'job': 'vehicles', 'id': 'train'});
    await dispose(tester);
  });

  testWidgets('a check that is running says so', (tester) async {
    await pump(tester, Backend(() => vehicles(v3Checking: 'running')));
    await tester.tap(find.text('Version 3'));
    await tester.pump();
    expect(find.textContaining('Checking each type'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('Train new version opens the training panel for this job beside the list, and Close hides it', (tester) async {
    await pump(tester, Backend(vehicles));
    expect(find.text('Train a new vehicles version'), findsNothing);
    await tester.tap(find.text('Train new version'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Train a new vehicles version'), findsOneWidget);
    expect(find.text('Version 3'), findsOneWidget); // the list is still there
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.text('Train a new vehicles version'), findsNothing);
    await dispose(tester);
  });

  testWidgets('a job that cannot switch explains it and has no Use this', (tester) async {
    await pump(tester, Backend(vehicles));
    await tester.tap(find.text('Plate reader').first);
    await tester.pump();
    expect(find.text('Nothing to switch here'), findsOneWidget);
    expect(find.textContaining('not available for this job yet'), findsWidgets);
    expect(find.text('Use this'), findsNothing);
    await dispose(tester);
  });

  test('scores are shown in each job\'s own unit and compared in it', () {
    final job = HubJob.fromJson(vehicles());
    final matcher = HubJob.fromJson({...vehicles(), 'score_format': 'percent'});
    expect(fmtScore(job, 0.7123), '0.71');
    expect(fmtScore(matcher, 0.7123), '71%');
    expect(fmtDelta(job, 0.712, 0.68), '−0.03 vs live');
    expect(fmtDelta(matcher, 0.80, 0.85), '+5 pts vs live');
    expect(fmtDelta(job, 0.712, 0.712), 'same as live');
    expect(fmtDelta(job, null, 0.7), isNull);
  });
}
