import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
const _tmp = '$_a/aaaaaaaa_manual1';

/// A tiny stand-in for the dataset service's /api/reid/* routes.
class _FakeReid {
  final calls = <String, Map<String, dynamic>>{};
  Map<String, String> lastCarsQuery = const {};
  bool training = false;
  bool canUndo = false;

  static const _photos = <String, List<String>>{
    _car1: ['100.jpg', '101.jpg', '102.jpg'],
    _car2: ['200.jpg', '201.jpg'],
    _tmp: ['300.jpg'],
  };

  Map<String, dynamic> _carRow(String key) => {
    'key': key,
    'analysis': _a,
    'car': key.split('/').last,
    'photos': _photos[key]!.length,
    'thumb': _photos[key]![0],
    'jump': key == _car1
        ? [
            {'key': _car2, 'alike': 0.97},
          ]
        : key == _car2
        ? [
            {'key': _car1, 'alike': 0.97},
          ]
        : [],
    'mixed': null,
    'repeat_of': null,
    'repeats': [],
    'small': _photos[key]!.length < 2,
    'temporary': key == _tmp,
    'class': 'motorcycle',
    'class_source': key == _tmp ? 'you' : (key == _car2 ? 'model' : 'ticket'),
  };

  http.Response handle(http.Request request) {
    final path = request.url.path;
    final body = request.method == 'POST' && request.body.isNotEmpty
        ? jsonDecode(request.body) as Map<String, dynamic>
        : <String, dynamic>{};
    if (request.method == 'POST') {
      calls[path] = body;
      if (!training && path != '/api/reid/scan' && path != '/api/reid/suggest' && path != '/api/reid/similar') {
        canUndo = true;
      }
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
              'temporary': 1,
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
          'temporary': 1,
          'temporary_photos': 1,
          'classes': {'motorcycle': 2, 'unset': 1},
          'class_list': ['car', 'motorcycle', 'tricycle', 'jeepney', 'bus', 'truck', 'other'],
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
        lastCarsQuery = request.url.queryParameters;
        return _json({
          'analyses': [
            {'id': _a, 'short': 'aaaaaaaa', 'cars': 2, 'photos': 5, 'flagged': 2, 'temporary': 1},
          ],
          'cars': [_carRow(_car1), _carRow(_car2), _carRow(_tmp)],
        });
      case '/api/reid/car':
        final key = request.url.queryParameters['key']!;
        final row = _carRow(key);
        return _json({
          ...row,
          'photos': _photos[key],
          'siblings': [
            for (final other in [_car1, _car2, _tmp])
              if (other != key)
                {
                  'key': other,
                  'photos': _photos[other]!.length,
                  'thumb': _photos[other]![0],
                  'temporary': other == _tmp,
                  'class': 'motorcycle',
                  'alike': null,
                },
          ],
        });
      case '/api/reid/similar':
        final key = body['key'] as String;
        return _json({
          'key': key,
          'vehicles': [
            for (final other in [_car1, _car2, _tmp])
              if (other != key)
                {
                  'key': other,
                  'photos': _photos[other]!.length,
                  'thumb': _photos[other]![0],
                  'temporary': other == _tmp,
                  'class': 'motorcycle',
                  'alike': other == _tmp ? 0.4 : 0.9,
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
        return _json({
          'ok': true,
          'moved': 1,
          'to': _tmp,
          'temporary': body['temporary'] == true,
          'can_undo': true,
        });
      case '/api/reid/merge':
      case '/api/reid/remove':
      case '/api/reid/remove_cars':
      case '/api/reid/restore':
      case '/api/reid/dismiss':
      case '/api/reid/undo':
      case '/api/reid/class':
      case '/api/reid/hold':
      case '/api/reid/keep':
        return _json({'ok': true, 'moved': 1, 'changed': 1, 'can_undo': true});
      case '/api/reid/scan':
        return _json({'id': 'job1', 'kind': 'scan', 'state': 'running'});
      case '/api/reid/suggest':
        return _json({'id': 'job2', 'kind': 'suggest', 'state': 'running'});
      default:
        return _json({'error': 'unexpected request ${request.url}'}, status: 404);
    }
  }
}

Future<_FakeReid> _pump(WidgetTester tester, {bool training = false}) async {
  tester.view.physicalSize = const Size(1600, 1100);
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

Future<void> _open(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey('car-$key')));
  await tester.pumpAndSettle();
}

/// Click a photo (optionally holding a key, e.g. Shift for a range).
Future<void> _pick(WidgetTester tester, String name, {LogicalKeyboardKey? hold}) async {
  final tile = find.byKey(ValueKey('photo-$name'));
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  if (hold != null) await tester.sendKeyDownEvent(hold);
  await tester.tapAt(tester.getTopLeft(tile) + const Offset(12, 12)); // top-left: the zoom button is bottom-right
  if (hold != null) await tester.sendKeyUpEvent(hold);
  await tester.pumpAndSettle();
}

/// Click a vehicle in the list while holding a key (Ctrl / Shift).
Future<void> _clickVehicle(WidgetTester tester, String key, {LogicalKeyboardKey? hold}) async {
  if (hold != null) await tester.sendKeyDownEvent(hold);
  await tester.tap(find.byKey(ValueKey('car-$key')));
  if (hold != null) await tester.sendKeyUpEvent(hold);
  await tester.pumpAndSettle();
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

void main() {
  testWidgets('shows what the scan found, the temporary area and what training would use', (tester) async {
    await _pump(tester);
    expect(find.text('2 vehicles · 5 photos · 1 analyses'), findsOneWidget);
    expect(find.text('1 temporary (1 photos), not trained on'), findsOneWidget);
    expect(find.text('Training would use 2 different vehicles (5 photos).'), findsOneWidget);
    expect(find.textContaining('1 maybe the same vehicle'), findsOneWidget);
    expect(find.text('Maybe the same vehicle as another'), findsNWidgets(2));
    expect(find.text('Temporary · not trained on'), findsOneWidget);
    expect(find.text('Temporary (1)'), findsOneWidget);
    expect(find.text('motorcycle'), findsWidgets);                       // each vehicle shows its class
    expect(find.text('Removed (1)'), findsOneWidget);
    expect(find.textContaining('Pick a vehicle on the left'), findsOneWidget);
    expect(find.text('1 vehicles have no class yet.'), findsOneWidget);
    expect(find.text('motorcycle (suggested)'), findsOneWidget);          // a class the model suggested is marked
  });

  testWidgets('a tracker jump is fixed by merging the two vehicles', (tester) async {
    final fake = await _pump(tester);
    await _open(tester, _car1);
    expect(find.text('aaaaaaaa_car1  ·  3 photos'), findsOneWidget);
    expect(find.textContaining('Looks 97% like aaaaaaaa_car2'), findsOneWidget);
    await tester.tap(find.text('Same vehicle — merge'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/merge'], {'cars': [_car2], 'into': _car1}); // the one with more photos keeps the folder
    expect(find.text('Merged into aaaaaaaa_car1.'), findsOneWidget);
  });

  testWidgets('"not the same vehicle" is remembered', (tester) async {
    final fake = await _pump(tester);
    await _open(tester, _car1);
    await tester.tap(find.text('Not the same vehicle'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/dismiss'], {'a': _car1, 'b': _car2});
  });

  testWidgets('Shift+click picks a range of photos, which can be set aside as a temporary vehicle', (tester) async {
    final fake = await _pump(tester);
    await _open(tester, _car1);
    expect(find.text('0 selected'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'New vehicle')).onPressed, isNull); // nothing picked yet
    await _pick(tester, '100.jpg');
    expect(find.text('1 selected'), findsOneWidget);
    await _pick(tester, '102.jpg', hold: LogicalKeyboardKey.shiftLeft);
    expect(find.text('3 selected'), findsOneWidget);                        // 100, 101 and 102
    await tester.tap(find.text('Set aside (temporary)'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/move'], {
      'photos': [
        {'car': _car1, 'name': '100.jpg'},
        {'car': _car1, 'name': '101.jpg'},
        {'car': _car1, 'name': '102.jpg'},
      ],
      'to': null,
      'temporary': true,
    });
    expect(find.textContaining('Set 3 photo(s) aside as aaaaaaaa_manual1 (Temporary: not trained on)'), findsOneWidget);
  });

  testWidgets('photos become a new vehicle of their own, or are removed with a reason', (tester) async {
    final fake = await _pump(tester);
    await _open(tester, _car1);
    await _pick(tester, '101.jpg');
    await tester.tap(find.text('New vehicle'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/move'], {
      'photos': [
        {'car': _car1, 'name': '101.jpg'},
      ],
      'to': null,
      'temporary': false,
    });
    expect(find.textContaining('Moved 1 photo(s) into a new vehicle, aaaaaaaa_manual1.'), findsOneWidget);

    await _pick(tester, '100.jpg');
    await tester.tap(find.text('Remove photos'));
    await tester.pumpAndSettle();
    expect(find.text('Remove 1 photo(s)?'), findsOneWidget);
    await tester.tap(find.text('Not a vehicle'));
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

  testWidgets('moving photos offers the most alike vehicles first, plus a new or temporary vehicle', (tester) async {
    final fake = await _pump(tester);
    await _open(tester, _car1);
    await _pick(tester, '102.jpg');
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/similar'], {'key': _car1, 'photos': ['102.jpg']});
    expect(find.text('Move 1 photo(s) to…'), findsOneWidget);
    expect(find.text('A new vehicle'), findsOneWidget);
    expect(find.text('A temporary vehicle'), findsOneWidget);
    expect(find.textContaining('looks 90% alike'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('aaaaaaaa_car2')));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/move'], {
      'photos': [
        {'car': _car1, 'name': '102.jpg'},
      ],
      'to': _car2,
      'temporary': false,
    });

    await _pick(tester, '101.jpg');
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A temporary vehicle'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/move'], {
      'photos': [
        {'car': _car1, 'name': '101.jpg'},
      ],
      'to': null,
      'temporary': true,
    });
  });

  testWidgets('another vehicle can be merged into this one, or this one into a known vehicle', (tester) async {
    final fake = await _pump(tester);
    await _open(tester, _car1);
    await tester.tap(find.text('Merge another vehicle into this'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/similar'], {'key': _car1, 'photos': null});
    final merge = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge'));
    expect(merge.onPressed, isNull);                                      // nobody ticked yet
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/merge'], {'cars': [_car2], 'into': _car1});

    await tester.tap(find.text('Merge this into…'));
    await tester.pumpAndSettle();
    expect(find.text('Merge aaaaaaaa_car1 into…'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('aaaaaaaa_car2')));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/merge'], {'cars': [_car1], 'into': _car2});
  });

  testWidgets('the class of a vehicle is set from a menu and the list can be filtered by class', (tester) async {
    final fake = await _pump(tester);
    await _open(tester, _car1);
    expect(find.text('(from the ticket)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('class-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bus').last);
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/class'], {'cars': [_car1], 'class': 'bus'});
    expect(find.text('Class set to bus for 1 vehicle(s).'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('class-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('truck').last);
    await tester.pumpAndSettle();
    expect(fake.lastCarsQuery['class'], 'truck');
  });

  testWidgets('several vehicles are selected with Ctrl and Shift and handled together', (tester) async {
    final fake = await _pump(tester);
    expect(find.byKey(const ValueKey('bulk-bar')), findsNothing);
    await _clickVehicle(tester, _car1, hold: LogicalKeyboardKey.controlLeft);
    await _clickVehicle(tester, _car2, hold: LogicalKeyboardKey.controlLeft);
    expect(find.text('2 vehicles selected'), findsOneWidget);
    expect(find.text('aaaaaaaa_car1  ·  3 photos'), findsNothing);       // a Ctrl+click selects, it does not open
    expect(tester.widget<FilledButton>(_button('Keep (0)')).onPressed, isNull);
    await tester.tap(find.text('Merge into one…'));
    await tester.pumpAndSettle();
    expect(find.text('Merge 2 vehicles into one'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('aaaaaaaa_car2')));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/merge'], {'cars': [_car1], 'into': _car2});
    expect(find.byKey(const ValueKey('bulk-bar')), findsNothing);        // done: the selection is cleared

    await _open(tester, _car1);                                          // a plain click opens one vehicle ...
    await _clickVehicle(tester, _tmp, hold: LogicalKeyboardKey.shiftLeft); // ... and Shift+click selects the range down to here
    expect(find.text('3 vehicles selected'), findsOneWidget);
    expect(find.text('Set aside (2)'), findsOneWidget);
    expect(find.text('Keep (1)'), findsOneWidget);
    await tester.tap(find.text('Set aside (2)'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/hold'], {'cars': [_car1, _car2]});
    await _clickVehicle(tester, _tmp, hold: LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Keep (1)'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/keep'], {'cars': [_tmp]});
  });

  testWidgets('the class of several vehicles at once, and removing several vehicles', (tester) async {
    final fake = await _pump(tester);
    await _clickVehicle(tester, _car1, hold: LogicalKeyboardKey.controlLeft);
    await _clickVehicle(tester, _car2, hold: LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Set class…'));
    await tester.pumpAndSettle();
    expect(find.text('Class of 2 vehicles'), findsOneWidget);
    await tester.tap(find.text('truck'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/class'], {'cars': [_car1, _car2], 'class': 'truck'});

    expect(find.text('2 vehicles selected'), findsOneWidget);            // the selection stays after setting a class
    await tester.tap(find.text('Remove…'));
    await tester.pumpAndSettle();
    expect(find.text('Remove 2 whole vehicles?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/remove_cars'], {'cars': [_car1, _car2], 'reason': 'bad_photo'});
  });

  testWidgets('a temporary vehicle can be kept as its own vehicle; a trained-on one can be set aside', (tester) async {
    final fake = await _pump(tester);
    await _open(tester, _tmp);
    expect(find.textContaining('Set aside (Temporary): these photos are not trained on'), findsOneWidget);
    expect(find.text('Set this vehicle aside'), findsNothing);
    await tester.tap(find.text('Keep as its own vehicle'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/keep'], {'cars': [_tmp]});

    await _open(tester, _car1);
    expect(find.text('Keep as its own vehicle'), findsNothing);
    await tester.tap(find.text('Set this vehicle aside'));
    await tester.pumpAndSettle();
    expect(fake.calls['/api/reid/hold'], {'cars': [_car1]});
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
    expect(find.text('Scanning every vehicle (about a minute)…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // leave the poll timer behind cleanly
  });

  testWidgets('Suggest classes asks the vehicle model, and its guess is marked as a suggestion', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.text('Suggest classes'));
    await tester.pump();
    expect(fake.calls.containsKey('/api/reid/suggest'), isTrue);
    expect(find.text('Asking the vehicle model what each vehicle is (about a minute)…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // leave the poll timer behind cleanly
    final again = await _pump(tester);
    await _open(tester, _car2);
    expect(find.text('(suggested by the model)'), findsOneWidget);
    expect(again.calls, isEmpty);
  });

  testWidgets('nothing can be changed while the matcher trains', (tester) async {
    final fake = await _pump(tester, training: true);
    expect(find.textContaining('The car matcher is training'), findsOneWidget);
    await _open(tester, _car1);
    await _pick(tester, '101.jpg');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'New vehicle')).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Same vehicle — merge')).onPressed, isNull);
    expect(tester.widget<DropdownButton<String>>(find.byKey(const ValueKey('class-dropdown'))).onChanged, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Suggest classes')).onPressed, isNull);
    await _clickVehicle(tester, _car2, hold: LogicalKeyboardKey.controlLeft);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Set class…')).onPressed, isNull);
    expect(fake.calls, isEmpty);
  });

  testWidgets('the Datasets screen opens the manager for the car matcher entry', (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
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
    expect(find.text('5 photos · 2 vehicles'), findsOneWidget);
    expect(find.byType(DatasetReidManager), findsOneWidget);
    expect(find.text('Gallery'), findsNothing); // the box-label tabs are not for this data
    expect(find.text('Clean the vehicles before training'), findsOneWidget);
  });
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
