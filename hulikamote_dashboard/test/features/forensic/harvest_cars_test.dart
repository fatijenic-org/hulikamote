import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/harvest_labeling.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/harvest_labeling_models.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/harvest_car_viewer.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/harvest_cars_screen.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/harvest_categories_view.dart';

import 'support/test_support.dart';

const _cars = [
  CarSummary(uid: 'c1', track: 3, photos: 4, first: 'c1_0.jpg', state: CarState.open),
  CarSummary(uid: 'c2', track: 5, photos: 3, first: 'c2_0.jpg', state: CarState.checked),
  CarSummary(uid: 'c3', track: 8, photos: 6, first: 'c3_0.jpg', state: CarState.split),
];

const _questions = [PairItem(id: 'p1', kind: 'gap', reason: 'x', task: 't1')];

/// Opens something full-screen from a plain button, like the app does, and remembers what it returned.
Future<void> _open(WidgetTester tester, Future<Object?> Function(BuildContext) open, {List<Object?>? results}) async {
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('open'),
            onPressed: () async {
              final r = await open(context);
              results?.add(r);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const Key('open')));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1)); // let the page slide-in finish
}

Future<void> _viewer(WidgetTester tester, FakeLabeling l, {List<Object?>? results}) =>
    _open(tester, (c) => openCarViewer(c, labeling: l, taskId: 't1', car: _cars[0]), results: results);

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadRoboto);

  group('what the helper says about cars is read as it is sent', () {
    test('the list, one car, and the counts in a session', () {
      final list = CarList.fromJson({
        'evidence_dir': 'C:/ev',
        'counts': {'open': 1, 'checked': 1, 'split': 1},
        'items': [
          {'uid': 'a', 'track': 7, 'photos': 5, 'first': 'a_0.jpg', 'state': 'split'},
          {'uid': 'b'},
        ],
      });
      expect(list.evidenceDir, 'C:/ev');
      expect(list.counts.total, 3);
      expect(list.items.first.state, CarState.split);
      expect(list.items.last.state, CarState.open); // a state it does not know reads as not looked at

      final d = CarDetail.fromJson({'uid': 'a', 'track': 7, 'evidence_dir': 'C:/ev', 'photos': ['a_0.jpg', 'a_1.jpg'], 'marked': ['a_1.jpg']});
      expect(d.photos, ['a_0.jpg', 'a_1.jpg']);
      expect(d.marked, {'a_1.jpg'});

      final s = LabelSession.fromJson({'task': 't1', 'collected': true, 'models': [], 'cars': {'open': 2, 'checked': 1}});
      expect(s.cars.open, 2);
      expect(s.cars.total, 3);
      expect(LabelSession.fromJson({'task': null, 'models': []}).cars.total, 0);
    });
  });

  group('the cars of an analysis', () {
    testWidgets('one card per car by number, with how many photos and where it stands', (tester) async {
      final l = FakeLabeling(carItems: _cars);
      await _open(tester, (c) => openCarsScreen(c, labeling: l, taskId: 't1'));
      expect(find.byKey(const Key('car-card-c1')), findsOneWidget);
      expect(find.text('Car 3'), findsOneWidget);
      expect(find.text('Car 5'), findsOneWidget);
      expect(find.text('Car 8'), findsOneWidget);
      expect(find.byKey(const Key('car-state-c1')), findsNothing); // not looked at
      expect(tester.widget<Icon>(find.descendant(of: find.byKey(const Key('car-state-c2')), matching: find.byType(Icon))).icon, Icons.check);
      expect(tester.widget<Icon>(find.descendant(of: find.byKey(const Key('car-state-c3')), matching: find.byType(Icon))).icon, Icons.call_split);
      expect(find.text('2 of 3 checked'), findsOneWidget);
      expect(find.byKey(const Key('cars-questions')), findsNothing);
      expect(l.carsAsked, ['t1']);
    });

    testWidgets('the quick questions are the first card when there are some', (tester) async {
      final l = FakeLabeling(carItems: _cars, pairItems: _questions);
      await _open(tester, (c) => openCarsScreen(c, labeling: l, taskId: 't1'));
      expect(find.byKey(const Key('cars-questions')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('cars-questions')));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('pair-a')), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.enter); // same car: the one question is answered
      await _key(tester, LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(l.answeredPairs, {'p1': PairAnswer.same});
      expect(find.byKey(const Key('cars-questions')), findsNothing); // and it is gone from the list
    });

    testWidgets('opening a car and saving it marks it as checked in the list', (tester) async {
      final l = FakeLabeling(carItems: _cars);
      await _open(tester, (c) => openCarsScreen(c, labeling: l, taskId: 't1'));
      await _tap(tester, find.byKey(const Key('car-card-c1')));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('car-big')), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.enter);
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(l.checkedCars, {'c1': <String>[]});
      expect(find.byKey(const Key('car-card-c1')), findsOneWidget); // back on the list
      expect(find.byKey(const Key('car-state-c1')), findsOneWidget);
      expect(find.text('3 of 3 checked'), findsOneWidget);
    });

    testWidgets('"Rest are fine" files every car nobody opened, after asking; the ones already answered stay as they are', (tester) async {
      final l = FakeLabeling(carItems: [..._cars, const CarSummary(uid: 'c4', track: 9, photos: 5, first: 'c4_0.jpg', state: CarState.open)]);
      await _open(tester, (c) => openCarsScreen(c, labeling: l, taskId: 't1'));
      expect(find.text('Rest are fine (2)'), findsOneWidget); // c1 and c4 were never opened
      await _tap(tester, find.byKey(const Key('cars-fill')));
      expect(find.text('File 2 cars as one car each?'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('cars-fill-cancel')));
      expect(l.fills, 0);
      expect(find.byKey(const Key('cars-fill')), findsOneWidget);

      await _tap(tester, find.byKey(const Key('cars-fill')));
      await _tap(tester, find.byKey(const Key('cars-fill-ok')));
      await _settle(tester);
      expect(l.fills, 1);
      expect(l.checkedCars, {'c1': <String>[], 'c4': <String>[]});
      expect(find.byKey(const Key('cars-fill')), findsNothing); // nothing left to file
      expect(find.byKey(const Key('car-state-c1')), findsOneWidget);
      expect(find.byKey(const Key('car-state-c3')), findsOneWidget); // the split one is still a split
      expect(find.text('4 of 4 checked'), findsOneWidget);
    });

    testWidgets('no button when every car was opened; a failure is said and nothing changes', (tester) async {
      final done = FakeLabeling(carItems: [_cars[1], _cars[2]]);
      await _open(tester, (c) => openCarsScreen(c, labeling: done, taskId: 't1'));
      expect(find.byKey(const Key('cars-fill')), findsNothing);
      await _key(tester, LogicalKeyboardKey.escape);
      await _settle(tester);

      final l = FakeLabeling(carItems: _cars, fillError: HarvestLabelingException('The harvest helper stopped.'));
      await _open(tester, (c) => openCarsScreen(c, labeling: l, taskId: 't1'));
      await _tap(tester, find.byKey(const Key('cars-fill')));
      await _tap(tester, find.byKey(const Key('cars-fill-ok')));
      await _settle(tester);
      expect(find.text('The harvest helper stopped.'), findsOneWidget);
      expect(find.byKey(const Key('cars-fill')), findsOneWidget);
    });

    testWidgets('a list that cannot be read is explained, and nothing to check says so', (tester) async {
      final none = FakeLabeling();
      await _open(tester, (c) => openCarsScreen(c, labeling: none, taskId: 't1'));
      expect(find.byKey(const Key('cars-empty')), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byKey(const Key('open')), findsOneWidget);
    });
  });

  group('one car: big photo on top, a strip below, D marks a different car', () {
    testWidgets('starts on the original, with every photo in the strip', (tester) async {
      final l = FakeLabeling(carItems: _cars);
      await _viewer(tester, l);
      expect(find.text('Car 3'), findsOneWidget);
      expect(find.text('1 of 4'), findsOneWidget);
      expect(find.byKey(const Key('car-original-badge')), findsOneWidget);
      expect(find.byKey(const Key('car-original')), findsNothing); // the small copy of the original is for the other photos
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(Key('car-thumb-$i')), findsOneWidget);
      }
      final different = tester.widget<OutlinedButton>(find.byKey(const Key('car-different')));
      expect(different.onPressed, isNull); // the original cannot be a different car
    });

    testWidgets('arrow keys and the buttons walk along the photos; a click on the strip jumps', (tester) async {
      final l = FakeLabeling(carItems: _cars);
      await _viewer(tester, l);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('2 of 4'), findsOneWidget);
      expect(find.byKey(const Key('car-original')), findsOneWidget); // the original stays pinned in the corner
      await _tap(tester, find.byKey(const Key('car-next')));
      expect(find.text('3 of 4'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('car-prev')));
      expect(find.text('2 of 4'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('car-thumb-3')));
      expect(find.text('4 of 4'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.arrowRight); // the end is the end
      expect(find.text('4 of 4'), findsOneWidget);
    });

    testWidgets('D marks the photo as a different car and moves on; Done saves exactly those', (tester) async {
      final l = FakeLabeling(carItems: _cars);
      final results = <Object?>[];
      await _viewer(tester, l, results: results);
      await _key(tester, LogicalKeyboardKey.arrowRight); // photo 2
      await _key(tester, LogicalKeyboardKey.keyD); // marks photo 2, on to photo 3
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.byKey(const Key('car-marked-count')), findsOneWidget);
      expect(find.text('1 different'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.keyD); // photo 3 too, on to photo 4
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(find.text('2 of 4'), findsOneWidget);
      expect(find.byKey(const Key('car-marked-badge')), findsOneWidget); // marked photos say so on the big picture
      expect(find.text('2 different'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(l.checkedCars, {'c1': ['c1_1.jpg', 'c1_2.jpg']});
      expect(results, [true]);
    });

    testWidgets('D again on a marked photo takes the mark back', (tester) async {
      final l = FakeLabeling(carItems: _cars);
      await _viewer(tester, l);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      await _key(tester, LogicalKeyboardKey.keyD);
      expect(find.text('1 different'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(find.byKey(const Key('car-marked-badge')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('car-different'))); // the same button, now "Not different"
      expect(find.byKey(const Key('car-marked-count')), findsNothing);
    });

    testWidgets('nothing marked means all one car', (tester) async {
      final l = FakeLabeling(carItems: _cars);
      await _viewer(tester, l);
      await _tap(tester, find.byKey(const Key('car-done')));
      await _settle(tester);
      expect(l.checkedCars, {'c1': <String>[]});
    });

    testWidgets('what was marked before comes back marked, so it can be changed', (tester) async {
      final l = FakeLabeling(carItems: _cars)..checkedCars['c1'] = ['c1_2.jpg'];
      await _viewer(tester, l);
      expect(find.text('1 different'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('car-thumb-2')));
      expect(find.byKey(const Key('car-marked-badge')), findsOneWidget);
    });

    testWidgets('Esc leaves without saving', (tester) async {
      final l = FakeLabeling(carItems: _cars);
      final results = <Object?>[];
      await _viewer(tester, l, results: results);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      await _key(tester, LogicalKeyboardKey.keyD);
      await _key(tester, LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(l.checkedCars, isEmpty);
      expect(results, [false]);
      expect(find.byKey(const Key('open')), findsOneWidget);
    });

    testWidgets('a save that fails says so and stays on the car, marks kept', (tester) async {
      final l = FakeLabeling(carItems: _cars, carError: HarvestLabelingException('Could not save: the disk is full.'));
      await _viewer(tester, l);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      await _key(tester, LogicalKeyboardKey.keyD);
      await _tap(tester, find.byKey(const Key('car-done')));
      expect(find.text('Could not save: the disk is full.'), findsOneWidget);
      expect(find.text('1 different'), findsOneWidget);
      expect(l.checkedCars, isEmpty);
    });
  });

  group('the Harvest tab: one Same car? tile for the cars and the questions', () {
    Future<void> pump(WidgetTester tester, FakeLabeling l, {String? taskId = 't1'}) async {
      await pumpScreen(tester, HarvestCategoriesView(key: UniqueKey(), labeling: l, taskId: taskId), size: const Size(1200, 800));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('its number is the cars not looked at plus the questions; it opens the cars of the analysis', (tester) async {
      final l = FakeLabeling(carItems: _cars, pairItems: _questions);
      await pump(tester, l);
      expect(tester.widget<Text>(find.byKey(const Key('count-reid_pairs'))).data, '2'); // 1 car + 1 question
      await _tap(tester, find.byKey(const Key('category-reid_pairs')));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('car-card-c1')), findsOneWidget);
      expect(find.byKey(const Key('cars-questions')), findsOneWidget);
    });

    testWidgets('every car checked and no question left: a tick', (tester) async {
      final l = FakeLabeling(carItems: [_cars[1], _cars[2]]);
      await pump(tester, l);
      expect(tester.widget<Icon>(find.byKey(const Key('count-reid_pairs'))).icon, Icons.check_circle);
    });

    testWidgets('for every analysis at once only the quick questions open (a car belongs to one analysis)', (tester) async {
      final l = FakeLabeling(carItems: _cars, pairItems: _questions);
      await pump(tester, l, taskId: null);
      expect(tester.widget<Text>(find.byKey(const Key('count-reid_pairs'))).data, '1');
      await _tap(tester, find.byKey(const Key('category-reid_pairs')));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('pair-a')), findsOneWidget);
      expect(find.byKey(const Key('car-card-c1')), findsNothing);
    });
  });
}
