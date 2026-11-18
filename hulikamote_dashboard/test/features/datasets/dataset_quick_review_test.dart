import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/core/utils/external_apps.dart';
import 'package:hulikamote_dashboard/features/datasets/data/dataset_viewer_api.dart';
import 'package:hulikamote_dashboard/features/datasets/presentation/widgets/dataset_quick_review.dart';
import 'package:hulikamote_dashboard/features/datasets/presentation/widgets/dataset_relabel_tab.dart';

const _classes = ['motorcycle', 'car', 'bus', 'truck', 'person', 'tricycle', 'jeepney'];

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A viewer helper that answers from memory: six truck boxes (two of them on the validation split), one page of them.
class FakeViewer {
  FakeViewer({this.hasTarget = true, this.training = false, int boxes = 6}) {
    pending = [
      for (var i = 0; i < boxes; i++)
        {
          'split': i % 3 == 2 ? 'val' : 'train',
          'name': 'img$i.jpg',
          'index': 0,
          'class_id': 3,
          'class_name': 'truck',
          'box': [0.5, 0.5, 0.4, 0.4],
          'source': 'src',
          'width': 100,
          'height': 80,
          'harvest': false,
          'relabeled': false,
          'decision': null,
          'score': null,
        },
    ];
    total = boxes;
  }

  bool hasTarget;
  bool training;
  late List<Map<String, dynamic>> pending;
  late int total;
  int reviewed = 0;
  int moved = 0;
  int kept = 0;
  bool needsHarvestConfirm = false;
  final List<String> calls = [];
  final List<Map<String, dynamic>> decides = [];
  Map<String, dynamic> suggest = {'state': 'idle', 'min_each': 100, 'marked_moved': 0, 'marked_kept': 0, 'can_start': false};
  List<Map<String, dynamic>> suggested = [];

  List<String> get classes => [..._classes, if (hasTarget) 'pickup'];

  Map<String, dynamic> get review =>
      {'class': 'truck', 'class_id': 3, 'reviewed': reviewed, 'moved': moved, 'kept': kept, 'total': total};

  http.Response handle(http.Request r) {
    final path = r.url.path;
    calls.add('${r.method} $path');
    switch (path) {
      case '/api/review':
        return _json({
          'classes': classes,
          'target': 'pickup',
          'target_id': hasTarget ? 7 : null,
          'counts': {'truck': review},
          'training': training,
        });
      case '/api/class/add':
        hasTarget = true;
        return _json({'ok': true, 'added': true, 'class_id': 7, 'classes': classes});
      case '/api/labels':
        final q = r.url.queryParameters;
        final list = q['order'] == 'suggest' ? suggested : pending;
        final offset = int.parse(q['offset'] ?? '0');
        final limit = int.parse(q['limit'] ?? '100');
        return _json({
          'items': list.skip(offset).take(limit).toList(),
          'total': list.length,
          'offset': offset,
          'size_pending': false,
          'sources': ['src'],
          'review': review,
        });
      case '/api/decide':
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        if (needsHarvestConfirm && body['confirm_harvest'] != true) {
          return _json({'error': 'harvest', 'needs_confirm': 'harvest', 'detail': []}, status: 409);
        }
        decides.add(body);
        final page = (body['page'] as List).map((e) => (e as Map)['name']).toSet();
        final picked = (body['picked'] as List).length;
        pending = [for (final i in pending) if (!page.contains(i['name'])) i];
        suggested = [for (final i in suggested) if (!page.contains(i['name'])) i];
        reviewed += page.length;
        moved += picked;
        kept += page.length - picked;
        return _json({'ok': true, 'action': 'a${decides.length}', 'moved': picked, 'kept': page.length - picked, 'review': review});
      case '/api/undo':
        return _json({'ok': true, 'undone': {'type': 'relabel'}});
      case '/api/suggest':
        return _json(suggest);
      case '/api/suggest/start':
        suggest = {...suggest, 'state': 'ready', 'accuracy': 0.94, 'scored': suggested.length};
        return _json(suggest);
      case '/api/decisions/reapply':
        return _json({'ok': true, 'applied': 4, 'already': 1, 'image_missing': 0, 'box_missing': 1, 'different_class': 0});
      default:
        return _json({'error': 'unexpected $path'}, status: 404);
    }
  }
}

Future<void> _open(WidgetTester tester, FakeViewer fake, {Future<void> Function()? onChanged, bool training = false}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final api = DatasetViewerApi(const DatasetViewerEndpoint('http://127.0.0.1:8766', 't'), client: MockClient((r) async => fake.handle(r)));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DatasetQuickReview(
        api: api,
        dataset: 'primary_anchor',
        classNames: fake.classes,
        training: training,
        onChanged: onChanged ?? () async {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without a pickup class the page offers to add it first, asks, and then shows the boxes', (tester) async {
    final fake = FakeViewer(hasTarget: false);
    await _open(tester, fake);
    expect(find.text("Step 1: add the class 'pickup'"), findsOneWidget);
    expect(find.byKey(const Key('quick-tile-0')), findsNothing);

    await tester.tap(find.byKey(const Key('quick-add-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-add-cancel')));
    await tester.pumpAndSettle();
    expect(fake.calls, isNot(contains('POST /api/class/add'))); // Cancel adds nothing

    await tester.tap(find.byKey(const Key('quick-add-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-add-confirm')));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('POST /api/class/add'));
    expect(find.byKey(const Key('quick-tile-0')), findsOneWidget);
  });

  testWidgets('shows one page of boxes with how far the review is, and the split of each box', (tester) async {
    await _open(tester, FakeViewer());
    for (var i = 0; i < 6; i++) {
      expect(find.byKey(Key('quick-tile-$i')), findsOneWidget);
    }
    expect(find.text('Reviewed 0 of 6 truck boxes · 0 marked as pickup'), findsOneWidget);
    expect(find.text('val'), findsNWidgets(2)); // validation boxes are in the review too
    expect(find.byKey(const Key('quick-left')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('quick-pickups'))).onPressed, isNull); // nothing picked yet
  });

  testWidgets('picking boxes and pressing the button changes those, writes the rest down as looked at, and shows the next boxes', (tester) async {
    final fake = FakeViewer(boxes: 40);
    await _open(tester, fake);
    await tester.tap(find.byKey(const Key('quick-tile-0')));
    await tester.tap(find.byKey(const Key('quick-tile-2')));
    await tester.pump();
    expect(find.text('2 are pickups  (Enter)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-pickups')));
    await tester.pumpAndSettle();

    final sent = fake.decides.single;
    expect(sent['to_class'], 7);
    expect(sent['from_class'], 3);
    expect((sent['picked'] as List).map((e) => (e as Map)['name']), ['img0.jpg', 'img2.jpg']);
    expect((sent['page'] as List).length, 30); // the whole page: 6 x 5
    expect(find.text('Reviewed 30 of 40 truck boxes · 2 marked as pickup'), findsOneWidget);
    expect(find.byKey(const Key('quick-note')), findsOneWidget);
    expect(find.byKey(const Key('quick-tile-9')), findsOneWidget); // the next page has the boxes nobody looked at
    expect(find.text('img30.jpg'), findsNothing);
  });

  testWidgets('"No pickups here" keeps nothing picked and still writes the page down as looked at', (tester) async {
    final fake = FakeViewer();
    await _open(tester, fake);
    await tester.tap(find.byKey(const Key('quick-none')));
    await tester.pumpAndSettle();
    expect((fake.decides.single['picked'] as List), isEmpty);
    expect((fake.decides.single['page'] as List).length, 6);
    expect(find.byKey(const Key('quick-done')), findsOneWidget);
    expect(find.text('Everything is reviewed.'), findsOneWidget);
  });

  testWidgets('keys do it all: A picks the page, Enter confirms; N says none; C clears', (tester) async {
    final fake = FakeViewer(boxes: 70);
    await _open(tester, fake);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(find.text('30 are pickups  (Enter)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(find.byKey(const Key('quick-clear')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect((fake.decides.last['picked'] as List).length, 30);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect((fake.decides.last['picked'] as List), isEmpty);
    expect(fake.decides.length, 2);
  });

  testWidgets('Shift-click picks a range', (tester) async {
    await _open(tester, FakeViewer());
    await tester.tap(find.byKey(const Key('quick-tile-1')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('quick-tile-4')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('4 are pickups  (Enter)'), findsOneWidget);
  });

  testWidgets('Undo asks the helper to undo the last page and reloads the boxes', (tester) async {
    final fake = FakeViewer();
    await _open(tester, fake);
    await tester.tap(find.byKey(const Key('quick-undo')));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('POST /api/undo'));
    expect(find.text('Undid the last page.'), findsOneWidget);
  });

  testWidgets('during a training nothing can be changed', (tester) async {
    final fake = FakeViewer(training: true);
    await _open(tester, fake);
    expect(find.text('Writes disabled during training'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-tile-0')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('quick-pickups'))).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('quick-none'))).onPressed, isNull);
    expect(tester.widget<TextButton>(find.byKey(const Key('quick-undo'))).onPressed, isNull);
  });

  testWidgets('your own harvest pictures need an extra yes, and the page is only decided after it', (tester) async {
    final fake = FakeViewer()..needsHarvestConfirm = true;
    await _open(tester, fake);
    await tester.tap(find.byKey(const Key('quick-tile-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-pickups')));
    await tester.pumpAndSettle();
    expect(find.text('Some of these are your own pictures'), findsOneWidget);
    expect(fake.decides, isEmpty);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(fake.decides, isEmpty);

    await tester.tap(find.byKey(const Key('quick-pickups')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, change them'));
    await tester.pumpAndSettle();
    expect(fake.decides.single['confirm_harvest'], true);
  });

  testWidgets('a helper error is shown in words and nothing changes on the page', (tester) async {
    final fake = FakeViewer();
    await _open(tester, fake);
    final api = DatasetViewerApi(const DatasetViewerEndpoint('http://127.0.0.1:8766', 't'),
        client: MockClient((r) async => r.url.path == '/api/decide' ? _json({'error': 'truck is training'}, status: 409) : fake.handle(r)));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DatasetQuickReview(key: const ValueKey('again'), api: api, dataset: 'primary_anchor', classNames: fake.classes, training: false, onChanged: () async {})),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-tile-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-pickups')));
    await tester.pumpAndSettle();
    expect(find.text('truck is training'), findsOneWidget);
    expect(find.byKey(const Key('quick-tile-0')), findsOneWidget);
  });

  testWidgets('Re-apply my pickup decisions asks first, then reports what was put back', (tester) async {
    final fake = FakeViewer();
    await _open(tester, fake);
    await tester.tap(find.byKey(const Key('quick-reapply')));
    await tester.pumpAndSettle();
    expect(find.text('Re-apply my pickup decisions?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-reapply-confirm')));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('POST /api/decisions/reapply'));
    expect(find.textContaining('Put back 4 (pickup). 1 were already right, 1 could not be placed.'), findsOneWidget);
  });

  group('suggestions', () {
    testWidgets('they say how many more boxes to mark first, and the button waits', (tester) async {
      final fake = FakeViewer()..suggest = {'state': 'idle', 'min_each': 100, 'marked_moved': 12, 'marked_kept': 40, 'can_start': false};
      await _open(tester, fake);
      expect(find.text('For suggestions, mark at least 100 pickups and 100 that are not (now 12 and 40).'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('quick-find'))).onPressed, isNull);
    });

    testWidgets('once enough is marked they can be asked for; then the boxes come best first and nothing is picked for you', (tester) async {
      final fake = FakeViewer()
        ..suggest = {'state': 'idle', 'min_each': 100, 'marked_moved': 120, 'marked_kept': 130, 'can_start': true}
        ..suggested = [
          for (final s in [0.97, 0.9, 0.4, 0.1]) {...FakeViewer(boxes: 1).pending.first, 'name': 's$s.jpg', 'score': s},
        ];
      await _open(tester, fake);
      await tester.tap(find.byKey(const Key('quick-find')));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('POST /api/suggest/start'));
      expect(find.textContaining('right 94% of the time'), findsOneWidget);

      await tester.tap(find.text('Suggested pickups'));
      await tester.pumpAndSettle();
      expect(find.text('97%'), findsOneWidget);
      expect(find.text('10%'), findsOneWidget);
      expect(find.text('2 are pickups  (Enter)'), findsNothing); // nothing is picked by itself
      expect(tester.widget<FilledButton>(find.byKey(const Key('quick-pickups'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('quick-likely')));
      await tester.pump();
      expect(find.text('2 are pickups  (Enter)'), findsOneWidget); // the 97% and the 90% box
      await tester.tap(find.byKey(const Key('quick-pickups'))); // only now is anything changed
      await tester.pumpAndSettle();
      expect(fake.decides.single['picked'], hasLength(2));
    });

    testWidgets('a suggestion that is being prepared shows its progress', (tester) async {
      final fake = FakeViewer()..suggest = {'state': 'embedding', 'done': 30, 'total': 60, 'message': 'Reading the pictures...', 'min_each': 100, 'marked_moved': 120, 'marked_kept': 130, 'can_start': true};
      await _open(tester, fake);
      expect(find.text('Reading the pictures...'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // leave: the poll timer stops with the page
      await tester.pump();
    });
  });

  group('inside the Relabel tab', () {
    Future<void> openTab(WidgetTester tester, FakeViewer fake, {String dataset = 'primary_anchor', List<String>? classes}) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final client = MockClient((r) async {
        if (r.url.path == '/api/facets') return _json({'classes': {}, 'sources': {}, 'counts': {}});
        if (r.url.path == '/api/sizes') return _json({'state': 'ready', 'done': 0, 'total': 0});
        return fake.handle(r);
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DatasetRelabelTab(
            api: DatasetViewerApi(const DatasetViewerEndpoint('http://127.0.0.1:8766', 't'), client: client),
            dataset: dataset,
            classNames: classes ?? fake.classes,
            training: false,
            onChanged: () async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the vehicle dataset opens on the quick review, and All tools is one press away', (tester) async {
      await openTab(tester, FakeViewer());
      expect(find.byKey(const Key('relabel-mode')), findsOneWidget);
      expect(find.byKey(const Key('quick-tile-0')), findsOneWidget);
      await tester.tap(find.text('All tools'));
      await tester.pumpAndSettle();
      expect(find.text('Review individual boxes and correct their class labels.'), findsOneWidget);
      expect(find.byKey(const Key('quick-tile-0')), findsNothing);
    });

    testWidgets('another dataset has no quick review: the Relabel tab is as it was', (tester) async {
      await openTab(tester, FakeViewer(), dataset: 'helmet_specialist', classes: ['rider_with_helmet', 'rider_without_helmet']);
      expect(find.byKey(const Key('relabel-mode')), findsNothing);
      expect(find.text('Review individual boxes and correct their class labels.'), findsOneWidget);
    });
  });
}
