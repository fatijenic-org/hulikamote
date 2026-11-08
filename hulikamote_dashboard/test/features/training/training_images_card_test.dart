import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/harvest_source.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/harvest_models.dart';
import 'package:hulikamote_dashboard/features/training/data/dataset_browser.dart';
import 'package:hulikamote_dashboard/features/training/presentation/widgets/training_images_card.dart';

import '../forensic/support/test_support.dart';

Map<String, dynamic> item(String id, String state, {String why = 'No-helmet ticket'}) => {
      'id': id,
      'image': 'helmet_specialist/images/$id.jpg',
      'state': state,
      'source': 'ticket',
      'why': '$why $id',
      'reason': 'Is every rider boxed?',
      'violation': 'no_helmet',
      'suggested': true,
      'boxes': [
        [0, 0.5, 0.5, 0.3, 0.4],
      ],
      'width': 640,
      'height': 480,
      'group': 'g-$id',
      'task': 'e4a858b6-7c74-40cb-ba31-9617dd6c81da',
      'ticket': 'abcdef1234567890',
      'created': 1761470000,
    };

Map<String, dynamic> galleryJson() => {
      'generated': 1761470000,
      'lab': 'C:/lab',
      'inbox': 'C:/lab/harvest_inbox',
      'protected': 0,
      'categories': [
        {
          'key': 'helmet_specialist',
          'kind': 'detector',
          'title': 'Helmet check',
          'used_for': 'Teaches the helmet check.',
          'fed_by': <String>[],
          'counts': {'check': 1, 'label': 0, 'ready': 1, 'skipped': 0, 'accepted': 1},
          'sources': [
            {'key': 'ticket', 'label': 'Vehicles from your forensic tickets', 'n': 3},
          ],
          'violations_seen': [
            {'violation': 'no_helmet', 'n': 3},
          ],
          'items': [item('h1', 'check'), item('h2', 'ready'), item('h3', 'accepted')],
        },
        {
          'key': 'plate_ocr',
          'kind': 'automatic',
          'title': 'Plate text reader',
          'count': 2,
          'need': 200,
          'unit': 'plate crops',
          'samples': [
            {'path': 'datasets/ocr/AB123_1.jpg', 'label': 'AB123', 'when': 1761470000},
            {'path': 'datasets/ocr/CD456_2.jpg', 'label': 'CD456', 'when': 1761470100},
          ],
        },
      ],
    };

class FakeHarvest implements HarvestSource {
  FakeHarvest(this.json, {this.error});

  Map<String, dynamic>? json;
  Object? error;
  int rebuilds = 0;

  @override
  Future<HarvestGallery?> load() async {
    if (error != null) throw error!;
    return json == null ? null : HarvestGallery.fromJson(json!);
  }

  @override
  Future<String?> rebuild() async {
    rebuilds++;
    return null;
  }

  @override
  ImageProvider inboxImage(String relative, {int? width}) => MemoryImage(kTinyPng);

  @override
  ImageProvider labImage(String relative, {int? width}) => MemoryImage(kTinyPng);
}

/// 25 + 40 original pictures from two sources, in three splits.
class FakeDatasets implements DatasetBrowser {
  FakeDatasets({this.empty = false});

  final bool empty;
  int lists = 0;

  @override
  Future<DatasetListing?> list(String modelKey, {bool refresh = false}) async {
    lists++;
    if (empty) return null;
    return DatasetListing({
      'train': [for (var i = 0; i < 40; i++) 'edgevision_helmet__e$i.jpg'],
      'val': [for (var i = 0; i < 10; i++) 'flashys_helmet__f$i.jpg'],
      'test': [for (var i = 0; i < 15; i++) 'flashys_helmet__g$i.jpg'],
    });
  }

  @override
  ImageProvider image(String modelKey, String split, String name, {int? width}) => MemoryImage(kTinyPng);

  @override
  Future<List<HarvestBox>> boxes(String modelKey, String split, String name) async =>
      const [HarvestBox(cls: 0, cx: 0.5, cy: 0.5, w: 0.4, h: 0.4)];

  @override
  Future<String?> text(String modelKey, String split, String name) async => null;
}

Future<void> _pump(
  WidgetTester tester, {
  String model = 'helmet_specialist',
  FakeHarvest? harvest,
  FakeDatasets? datasets,
  VoidCallback? onOpen,
}) async {
  await pumpScreen(
    tester,
    SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: TrainingImagesCard(
        modelKey: model,
        harvest: harvest ?? FakeHarvest(galleryJson()),
        datasets: datasets ?? FakeDatasets(),
        onOpenHarvest: onOpen,
      ),
    ),
    size: const Size(1400, 2200),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _pics() => find.byWidgetPredicate((w) => w is InkWell && w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('pic-'));

String _tip(WidgetTester tester, String key) =>
    tester.widget<Tooltip>(find.ancestor(of: find.byKey(Key(key)), matching: find.byType(Tooltip)).first).message!;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  setUpAll(loadRoboto);

  testWidgets('two tiles side by side, the original and the harvested, each with its number; the pictures are shown', (tester) async {
    await _pump(tester);
    expect(tester.widget<Text>(find.byKey(const Key('count-original'))).data, '65');
    expect(tester.widget<Text>(find.byKey(const Key('count-harvested'))).data, '3');
    expect(find.text('ORIGINAL'), findsOneWidget);
    expect(find.text('HARVESTED'), findsOneWidget);
    expect(_pics(), findsNWidgets(40)); // the first page of the original pictures
    expect(find.byKey(const Key('show-more')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('show-more')));
    expect(_pics(), findsNWidgets(65));
    expect(find.byKey(const Key('show-more')), findsNothing);
  });

  testWidgets('the harvested pictures are kept apart and can be narrowed by their state colour', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('tile-harvested')));
    expect(_pics(), findsNWidgets(3));
    expect(find.byKey(const Key('state-check')), findsOneWidget);
    expect(find.byKey(const Key('state-skipped')), findsNothing); // no picture is in that state
    await _tap(tester, find.byKey(const Key('state-ready')));
    expect(_pics(), findsNWidgets(1));
    expect(_tip(tester, 'pic-0'), contains('No-helmet ticket h2'));
    await _tap(tester, find.byKey(const Key('state-ready'))); // tap again: back to all
    expect(_pics(), findsNWidgets(3));
  });

  testWidgets('the original pictures can be narrowed by split or by where they come from', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('split-val')));
    expect(_pics(), findsNWidgets(10));
    await _tap(tester, find.byKey(const Key('split-val')));
    await _tap(tester, find.byKey(const Key('source-flashys_helmet')));
    expect(_pics(), findsNWidgets(25));
    expect(_tip(tester, 'pic-0'), contains('flashys_helmet'));
  });

  testWidgets('a picture opens large; the arrows and Esc work; its caption says where it came from', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('tile-harvested')));
    await _tap(tester, find.byKey(const Key('pic-0')));
    expect(find.byKey(const Key('viewer-title')), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('viewer-detail'))).data, allOf(contains('Vehicles from your forensic tickets'), contains('analysis e4a858b6'), contains('ticket abcdef12')));
    await _tap(tester, find.byKey(const Key('viewer-next')));
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('viewer-next'))).onPressed, isNull); // the last one
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100)); // the dialog fades out over a few frames
    }
    expect(find.byKey(const Key('viewer-title')), findsNothing);
  });

  testWidgets('shuffle shows other original pictures', (tester) async {
    await _pump(tester);
    List<String> firstFive() => [for (var i = 0; i < 5; i++) _tip(tester, 'pic-$i')];
    final before = firstFive();
    await _tap(tester, find.byKey(const Key('shuffle')));
    expect(firstFive(), isNot(before));
  });

  testWidgets('a model the harvest does not feed has an empty harvested tile that cannot be opened', (tester) async {
    await _pump(tester, model: 'primary_anchor');
    expect(tester.widget<Text>(find.byKey(const Key('count-harvested'))).data, '0');
    await _tap(tester, find.byKey(const Key('tile-harvested')));
    expect(_pics(), findsNWidgets(40)); // still the original ones
  });

  testWidgets('a model with no original folder opens on the harvested pictures', (tester) async {
    await _pump(tester, datasets: FakeDatasets(empty: true));
    expect(tester.widget<Text>(find.byKey(const Key('count-original'))).data, '0');
    expect(_pics(), findsNWidgets(3));
  });

  testWidgets('data the app collects by itself shows its pictures with their text', (tester) async {
    await _pump(tester, model: 'plate_ocr', datasets: FakeDatasets(empty: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<Text>(find.byKey(const Key('count-harvested'))).data, '2');
    expect(_pics(), findsNWidgets(2));
    expect(find.text('AB123'), findsOneWidget); // the plate text is drawn on the picture
  });

  testWidgets('a missing Training Lab folder is explained and can be retried; the harvest tab link works', (tester) async {
    var opened = 0;
    final harvest = FakeHarvest(galleryJson(), error: HarvestException('Could not find the training_lab folder.'));
    await _pump(tester, harvest: harvest, onOpen: () => opened++);
    expect(find.text('Could not find the training_lab folder.'), findsOneWidget);
    harvest.error = null;
    await _tap(tester, find.text('Retry'));
    expect(_pics(), findsNWidgets(40));
    await _tap(tester, find.byKey(const Key('open-harvest')));
    expect(opened, 1);
    await _tap(tester, find.byKey(const Key('pictures-update')));
    expect(harvest.rebuilds, 1);
  });
}
