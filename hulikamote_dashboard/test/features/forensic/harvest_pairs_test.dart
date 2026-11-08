import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/harvest_labeling.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/harvest_labeling_models.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/harvest_categories_view.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/harvest_pair_labeler.dart';

import 'support/test_support.dart';

const _two = [
  PairItem(id: 'p1', kind: 'gap', reason: 'Car 1 vanished as car 2 appeared.', task: 't1'),
  PairItem(id: 'p2', kind: 'twin', reason: 'Two look-alikes.', task: 't1'),
];

/// Opens the questions as the app does (a full-screen route) from a plain button.
Future<void> _open(WidgetTester tester, FakeLabeling labeling, {String? taskId = 't1'}) async {
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('open'),
            onPressed: () => openPairLabeler(context, labeling: labeling, taskId: taskId),
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

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadRoboto);

  group('what the helper says is read as it is sent', () {
    test('a session carries the pairs and whether the clip was kept', () {
      final s = LabelSession.fromJson({
        'task': 't1',
        'collected': true,
        'protected': false,
        'has_video': true,
        'pairs': {'open': 3, 'same': 1, 'different': 2, 'skipped': 1},
        'collect': {'running': false},
        'models': [
          {'key': 'primary_anchor', 'title': 'Vehicles', 'classes': ['motorcycle', 'car'], 'counts': {'check': 8, 'label': 0}},
        ],
      });
      expect(s.hasVideo, isTrue);
      expect(s.pairs.open, 3);
      expect(s.pairs.total, 7);
      expect(s.models.single.tileName, 'Vehicles');
      expect(s.categories.single.toCheck, 8);
    });

    test('an older helper that says nothing about pairs or the video reads as none', () {
      final s = LabelSession.fromJson({'task': null, 'collected': true, 'models': []});
      expect(s.pairs.total, 0);
      expect(s.hasVideo, isNull);
    });

    test('questions and answers use the words the helper expects', () {
      final q = PairQueue.fromJson({
        'items': [
          {'id': 'p1', 'kind': 'twin', 'reason': 'x', 'task': 't1'},
          {'id': 'p2'},
        ],
      });
      expect(q.items.first.together, isTrue);
      expect(q.items.last.kind, 'gap');
      expect(PairAnswer.values.map((a) => a.wire), ['same', 'different', 'skip']);
    });
  });

  group('the questions: two cars, one answer, next', () {
    testWidgets('shows the first pair as two pictures with how far along it is; Enter says same', (tester) async {
      final l = FakeLabeling(pairItems: _two);
      await _open(tester, l);
      expect(find.byKey(const Key('pair-a')), findsOneWidget);
      expect(find.byKey(const Key('pair-b')), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('One after the other'), findsOneWidget);
      expect(l.asked, contains('t1')); // only the questions of that analysis
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 150));
      expect(l.answeredPairs, {'p1': PairAnswer.same});
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.text('On screen at the same time'), findsOneWidget);
    });

    testWidgets('N is different cars, S is not sure; then it says all done', (tester) async {
      final l = FakeLabeling(pairItems: _two);
      await _open(tester, l);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump(const Duration(milliseconds: 150));
      expect(l.answeredPairs, {'p1': PairAnswer.different, 'p2': PairAnswer.notSure});
      expect(find.byKey(const Key('labeler-done')), findsOneWidget);
      expect(find.text('All done'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('labeler-finish')));
      await _settle(tester);
      expect(find.byKey(const Key('open')), findsOneWidget);
    });

    testWidgets('the three buttons answer too', (tester) async {
      final l = FakeLabeling(pairItems: _two);
      await _open(tester, l);
      await _tap(tester, find.byKey(const Key('pair-same')));
      await _tap(tester, find.byKey(const Key('pair-different')));
      expect(l.answeredPairs, {'p1': PairAnswer.same, 'p2': PairAnswer.different});
    });

    testWidgets('an answer that fails says so and stays on the pair', (tester) async {
      final l = FakeLabeling(pairItems: _two, pairError: HarvestLabelingException('Could not save: the disk is full.'));
      await _open(tester, l);
      await _tap(tester, find.byKey(const Key('pair-same')));
      expect(find.text('Could not save: the disk is full.'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(l.answeredPairs, isEmpty);
    });

    testWidgets('a list that cannot be read is explained, and Try again asks again', (tester) async {
      final l = FakeLabeling(pairItems: _two, pairLoadError: HarvestLabelingException('The harvest helper stopped.'));
      await _open(tester, l);
      expect(find.text('The harvest helper stopped.'), findsOneWidget);
      l.pairLoadError = null;
      await _tap(tester, find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1 of 2'), findsOneWidget);
    });

    testWidgets('nothing to ask says so, and Esc closes the questions', (tester) async {
      final l = FakeLabeling();
      await _open(tester, l);
      expect(find.text('Nothing to check'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byKey(const Key('open')), findsOneWidget);
    });
  });

  group('the Harvest tab shows the new kinds as tiles too', () {
    Future<void> pump(WidgetTester tester, FakeLabeling l, {String? taskId = 't1'}) async {
      await pumpScreen(tester, HarvestCategoriesView(key: UniqueKey(), labeling: l, taskId: taskId), size: const Size(1200, 800));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('"Same car?" is a tile with the number open; it opens the questions and the number follows', (tester) async {
      final l = FakeLabeling(pairItems: _two);
      await pump(tester, l);
      expect(tester.widget<Text>(find.byKey(const Key('count-reid_pairs'))).data, '2');
      expect(find.text('Same car?'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('category-reid_pairs')));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('pair-a')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(tester.widget<Text>(find.byKey(const Key('count-reid_pairs'))).data, '1');
    });

    testWidgets('with every question answered the tile shows a tick and cannot be opened', (tester) async {
      final l = FakeLabeling(pairItems: _two)..answeredPairs.addAll({'p1': PairAnswer.same, 'p2': PairAnswer.different});
      await pump(tester, l);
      expect(tester.widget<Icon>(find.byKey(const Key('count-reid_pairs'))).icon, Icons.check_circle);
      await tester.tap(find.byKey(const Key('category-reid_pairs')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('pair-a')), findsNothing);
    });

    testWidgets('no questions, no tile; questions alone are enough to not say "nothing to harvest"', (tester) async {
      final none = FakeLabeling();
      await pump(tester, none);
      expect(find.byKey(const Key('category-reid_pairs')), findsNothing);

      final only = FakeLabeling(pairItems: _two);
      for (final m in only.pictures.keys) {
        only.pictures[m] = const [];
      }
      await pump(tester, only);
      expect(find.byKey(const Key('harvest-empty')), findsNothing);
      expect(find.byKey(const Key('category-reid_pairs')), findsOneWidget);
    });

    testWidgets('Vehicles is a tile of its own and opens the labeler with every kind of vehicle as a colour', (tester) async {
      final l = FakeLabeling(vehicles: true);
      await pump(tester, l);
      expect(tester.widget<Text>(find.byKey(const Key('count-primary_anchor'))).data, '2');
      expect(find.text('Vehicles'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('category-primary_anchor')));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      for (var k = 0; k < 6; k++) {
        expect(find.byKey(Key('class-$k')), findsOneWidget);
      }
      expect(find.textContaining('Rider'), findsOneWidget); // "person" is called what it is here
      expect(find.text('Box every vehicle and rider. Fix the guess.'), findsOneWidget);
    });

    testWidgets('an analysis whose video was not kept says so once, in a few words', (tester) async {
      final kept = FakeLabeling(hasVideo: true);
      await pump(tester, kept);
      expect(find.byKey(const Key('harvest-video-hint')), findsNothing);

      final lost = FakeLabeling(hasVideo: false);
      await pump(tester, lost);
      expect(find.byKey(const Key('harvest-video-hint')), findsOneWidget);

      final all = FakeLabeling(hasVideo: false);
      await pump(tester, all, taskId: null); // every analysis: the question does not apply
      expect(find.byKey(const Key('harvest-video-hint')), findsNothing);
    });
  });
}
