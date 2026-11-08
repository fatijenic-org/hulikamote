import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/core/utils/external_apps.dart';
import 'package:hulikamote_dashboard/features/datasets/data/dataset_viewer_api.dart';
import 'package:hulikamote_dashboard/features/datasets/presentation/screens/dataset_viewer_screen.dart';
import 'package:hulikamote_dashboard/features/datasets/presentation/widgets/dataset_reid_manager.dart';

const _a = 'aaaaaaaa-1111';
const _car1 = '$_a/aaaaaaaa_car1';
const _car2 = '$_a/aaaaaaaa_car2';

/// A tiny stand-in for the dataset service's /api/reid/* routes.
class _FakeReid {
  final calls = <String, Map<String, dynamic>>{};
  bool training = false;
  bool canUndo = false;

  http.Response handle(http.Request request) {
    final path = request.url.path;
    final body = request.method == 'POST' && request.body.isNotEmpty
        ? jsonDecode(request.body) as Map<String, dynamic>
        : <String, dynamic>{};
    if (request.method == 'POST') {
      calls[path] = body;
      if (!training && path != '/api/reid/scan') canUndo = true;
    }
    switch (path) {
      case '/api/datasets':
        return _json({
          'datasets': [
            {
              'name': 'reid',
              'kind': 'reid',
              'title': 'Car matcher (ReID)',
              'classes': [],
              'training': training,
              'index': {'state': 'ready'},
              'images': null,
              'total': 5,
              'cars': 2,
              'ph_share': null,
              'warnings': [],
              'card_stale': false,
            },
          ],
        });
      case '/api/reid/summary':
        return _json({
          'analyses': 1,
          'cars': 2,
          'photos': 5,
          'small': 0,
          'removed': 1,
          'training': training,
          'can_undo': canUndo,
          'job': null,
          'scan': {
            'used': 2,
            'photos_used': 5,
            'jumps': 1,
            'mixed': 0,
            'repeats': 0,
            'stale': false,
            'edits': 0,
          },
        });
      case '/api/reid/cars':
        return _json({
          'analyses': [
            {'id': _a, 'short': 'aaaaaaaa', 'cars': 2, 'photos': 5, 'flagged': 2},
          ],
          'cars': [
            {
              'key': _car1,
              'analysis': _a,
              'car': 'aaaaaaaa_car1',
              'photos': 3,
              'thumb': '101.jpg',
              'jump': [
                {'key': _car2, 'alike': 0.97},
              ],
              'mixed': null,
              'repeat_of': null,
              'repeats': [],
              'small': false,
            },
            {
              'key': _car2,
              'analysis': _a,
              'car': 'aaaaaaaa_car2',
              'photos': 2,
              'thumb': '201.jpg',
              'jump': [
                {'key': _car1, 'alike': 0.97},
              ],
              'mixed': null,
              'repeat_of': null,
              'repeats': [],
              'small': false,
            },
          ],
        });
      case '/api/reid/car':
        final key = request.url.queryParameters['key'];
        final first = key == _car1;
        return _json({
          'key': key,
          'analysis': _a,
          'car': first ? 'aaaaaaaa_car1' : 'aaaaaaaa_car2',
          'photos': first ? ['100.jpg', '101.jpg', '102.jpg'] : ['200.jpg', '201.jpg'],
          'jump': [
            {'key': first ? _car2 : _car1, 'alike': 0.97},
          ],
          'mixed': null,
          'repeat_of': null,
          'repeats': [],
          'siblings': [
            {
              'key': first ? _car2 : _car1,
              'photos': first ? 2 : 3,
              'thumb': '201.jpg',
              'alike': 0.97,
            },
          ],
        });
      case '/api/reid/removed':
        return _json({
          'items': [
            {'reason': 'bad_photo', 'analysis': _a, 'car': 'aaaaaaaa_car1', 'name': '100.jpg'},
          ],
        });
      case '/api/reid/move':
        if (training) {
          return _json({'error': 'The car matcher is training right now.', 'training': true}, status: 409);
        }
        return _json({'ok': true, 'moved': 1, 'to': '$_a/aaaaaaaa_manual1', 'can_undo': true});
      case '/api/reid/merge':
      case '/api/reid/remove':
      case '/api/reid/remove_cars':
      case '/api/reid/restore':
      case '/api/reid/dismiss':
      case '/api/reid/undo':
        return _json({'ok': true, 'moved': 1, 'can_undo': true});
      case '/api/reid/scan':
        return _json({'id': 'job1', 'state': 'running'});
      default:
        return _json({'error': 'unexpected request ${request.url}'}, status: 404);
    }
  }
}

Future<_FakeReid> _pump(WidgetTester tester, {bool training = false}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = _FakeReid()..training = training;
  final api = DatasetViewerApi(
    const DatasetViewerEndpoint('http://127.0.0.1:8766', 'test-token'),
    client: MockClient((request) async => fake.handle(request)),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DatasetReidManager(api: api, onChanged: () async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _pick(WidgetTester tester, String name) async {
  final tile = find.byKey(ValueKey('photo-$name'));
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getTopLeft(tile) + const Offset(12, 12));      // the top-left corner: the zoom button is bottom-right
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows what the scan found and what training would use', (tester) async {
    await _pump(tester);
    expect(find.text('2 car folders · 5 photos · 1 analyses'), findsOneWidget);
    expect(find.text('Training would use 2 different cars (5 photos).'), findsOneWidget);
    expect(find.textContaining('1 maybe the same car'), findsOneWidget);
    expect(find.text('Maybe the same car as another'), findsNWidgets(2));
    expect(find.text('Removed (1)'), findsOneWidget);
    expect(find.textContaining('Pick a car on the left'), findsOneWidget);
  });

  testWidgets('a tracker jump is fixed by merging the two cars', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('car-$_car1')));
    await tester.pumpAndSettle();
    expect(find.text('aaaaaaaa_car1  ·  3 photos'), findsOneWidget);
    expect(find.textContaining('Looks 97% like aaaaaaaa_car2'), findsOneWidget);
    await tester.tap(find.text('Same car — merge'));
    await tester.pumpAndSettle();
    // the car with more photos keeps the folder
    expect(fake.calls['/api/reid/merge'], {'cars': [_car2], 'into': _car1});
    expect(find.text('Merged into aaaaaaaa_car1.'), findsOneWidget);
  });

  testWidgets('"not the same car" is remembered', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('car-$_car1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not the same car'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/dismiss'], {'a': _car1, 'b': _car2});
  });

  testWidgets('photos are picked, moved to a new car and removed with a reason', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('car-$_car1')));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    final newCar = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'New car from selection'));
    expect(newCar.onPressed, isNull);                                   // nothing picked yet
    await _pick(tester, '101.jpg');
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('New car from selection'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/move'], {
      'photos': [
        {'car': _car1, 'name': '101.jpg'},
      ],
      'to': null,
    });
    expect(find.text('Moved 1 photo(s) into a new car.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('car-$_car1')));                // the fake keeps showing car 1's photos
    await tester.pumpAndSettle();
    await _pick(tester, '100.jpg');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photos'));
    await tester.pumpAndSettle();
    expect(find.text('Remove 1 photo(s)?'), findsOneWidget);
    await tester.tap(find.text('Not a car'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/remove'], {
      'photos': [
        {'car': _car1, 'name': '100.jpg'},
      ],
      'reason': 'not_a_car',
    });
  });

  testWidgets('moving to another car and merging pick from the cars of the analysis', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('car-$_car1')));
    await tester.pumpAndSettle();
    await _pick(tester, '102.jpg');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    expect(find.text('Move 1 photo(s) to…'), findsOneWidget);
    expect(find.text('A new car'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('aaaaaaaa_car2')));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/move'], {
      'photos': [
        {'car': _car1, 'name': '102.jpg'},
      ],
      'to': _car2,
    });

    await tester.tap(find.text('Merge another car into this'));
    await tester.pumpAndSettle();
    final merge = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge'));
    expect(merge.onPressed, isNull);                                    // nobody ticked yet
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/merge'], {'cars': [_car2], 'into': _car1});
  });

  testWidgets('removed photos can be restored and the last change undone', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.text('Removed (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Removed photos (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('removed-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore 1'));
    await tester.pumpAndSettle();
    expect((fake.calls['/api/reid/restore']!['items'] as List).single['name'], '100.jpg');
    expect(find.text('Restored 1 photo(s).'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(fake.calls.containsKey('/api/reid/undo'), isTrue);
    expect(find.text('Undone.'), findsOneWidget);
  });

  testWidgets('scanning starts a job', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.text('Scan again'));
    await tester.pump();
    expect(fake.calls.containsKey('/api/reid/scan'), isTrue);
    expect(find.text('Scanning every car (about a minute)…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());                           // leave the poll timer behind cleanly
  });

  testWidgets('nothing can be changed while the matcher trains', (tester) async {
    final fake = await _pump(tester, training: true);
    expect(find.textContaining('The car matcher is training'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('car-$_car1')));
    await tester.pumpAndSettle();
    await _pick(tester, '101.jpg');
    await tester.pumpAndSettle();
    final move = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'New car from selection'));
    expect(move.onPressed, isNull);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Same car — merge')).onPressed, isNull);
    expect(fake.calls, isEmpty);
  });

  testWidgets('the Datasets screen opens the manager for the car matcher entry', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = _FakeReid();
    await tester.pumpWidget(
      MaterialApp(
        home: DatasetViewerScreen(
          connect: () async => DatasetViewerApi(
            const DatasetViewerEndpoint('http://127.0.0.1:8766', 'test-token'),
            client: MockClient((request) async => fake.handle(request)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Car matcher (ReID)'), findsWidgets);
    expect(find.text('5 photos · 2 cars'), findsOneWidget);
    expect(find.byType(DatasetReidManager), findsOneWidget);
    expect(find.text('Gallery'), findsNothing);                          // the box-label tabs are not for this data
    expect(find.text('Clean the cars before training'), findsOneWidget);
  });
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
