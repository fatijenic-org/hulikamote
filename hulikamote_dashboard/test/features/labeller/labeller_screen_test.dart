import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/harvest_labeling.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/harvest_labeling_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/harvest_models.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/harvest_labeler.dart';
import 'package:hulikamote_dashboard/features/labeller/presentation/screens/labeller_screen.dart';

import '../forensic/support/test_support.dart';

/// A helper that answers from memory: a folder with five pictures; labelling finishes them one by one.
class FakeFolderLabeling extends FakeLabeling implements FolderLabelling {
  HarvestCounts counts = const HarvestCounts();
  final List<String> calls = [];
  Object? scanError;
  Object? exportError;
  LabellerStatus exported = const LabellerStatus(
    task: 'folder_ab12cd34',
    summary: {'exported': 4, 'train': 3, 'val': 1, 'empty_labels': 1, 'duplicates': 1, 'unreadable': 0, 'missing': 0, 'dest': 'D:/labelled/plate_specialist', 'blurred_pictures': 2, 'blurred_regions': 3},
  );

  @override
  Future<LabellerStatus> scanFolder(String model, String folder) async {
    calls.add('scan $model $folder');
    if (scanError != null) throw scanError!;
    counts = const HarvestCounts(label: 5);
    return LabellerStatus(task: 'folder_ab12cd34', summary: const {'found': 5, 'new': 5}, counts: counts);
  }

  @override
  Future<LabellerStatus> folderStatus(String model, String taskId) async => LabellerStatus(task: taskId, counts: counts);

  @override
  Future<int> predraw(String model, String taskId, {int n = 40, bool heads = false, bool plates = false}) async {
    calls.add('predraw $model $taskId heads=$heads plates=$plates');
    return 3;
  }

  @override
  Future<LabellerStatus> exportFolder(String model, String taskId, String dest, {bool move = true}) async {
    calls.add('export $model $taskId $dest move=$move');
    if (exportError != null) throw exportError!;
    counts = const HarvestCounts(accepted: 4);
    return exported;
  }
}

Future<void> _open(WidgetTester tester, FakeFolderLabeling l, {String? picked}) async {
  tester.view.physicalSize = const Size(1400, 1900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: LabellerScreen(labeling: l, defaultFolder: 'C:/evidence', pickFolder: () async => picked),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _scan(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('labeller-scan')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(loadRoboto);

  testWidgets('shows the models to teach, the default folder and nothing else to press yet', (tester) async {
    final l = FakeFolderLabeling();
    await _open(tester, l);
    expect(find.byKey(const Key('labeller-model-plate_specialist')), findsOneWidget);
    expect(find.byKey(const Key('labeller-model-helmet_specialist')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('labeller-folder'))).controller!.text, 'C:/evidence');
    expect(tester.widget<FilledButton>(find.byKey(const Key('labeller-scan'))).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(find.byKey(const Key('labeller-start'))).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.byKey(const Key('labeller-export'))).onPressed, isNull);
  });

  testWidgets('finding the pictures shows how many there are and unlocks labelling', (tester) async {
    final l = FakeFolderLabeling();
    await _open(tester, l);
    await _scan(tester);
    expect(l.calls, ['scan plate_specialist C:/evidence']);
    expect(find.text('5 pictures found'), findsOneWidget);
    expect(find.byKey(const Key('labeller-counts')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('labeller-start'))).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(find.byKey(const Key('labeller-export'))).onPressed, isNull); // none finished, no destination
  });

  testWidgets('a different model has its own folder numbers', (tester) async {
    final l = FakeFolderLabeling();
    await _open(tester, l);
    await _scan(tester);
    await tester.tap(find.byKey(const Key('labeller-model-helmet_specialist')));
    await tester.pump();
    expect(find.byKey(const Key('labeller-counts')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('labeller-start'))).onPressed, isNull);
  });

  testWidgets('Browse puts the chosen folder in the box', (tester) async {
    await _open(tester, FakeFolderLabeling(), picked: 'A:/more pictures');
    await tester.tap(find.byKey(const Key('labeller-folder-browse')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('labeller-folder'))).controller!.text, 'A:/more pictures');
  });

  testWidgets('Start labelling draws the guesses first, then opens the full-screen labeller on this folder', (tester) async {
    final l = FakeFolderLabeling();
    await _open(tester, l);
    await _scan(tester);
    await tester.tap(find.byKey(const Key('labeller-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(l.calls, contains('predraw plate_specialist folder_ab12cd34 heads=true plates=false')); // the plate model keeps its plates
    expect(find.byType(HarvestLabeler), findsOneWidget);
    expect(l.asked.last, 'folder_ab12cd34'); // the labeller asked for this folder's pictures only
  });

  testWidgets('with the guess and the blur switched off nothing is pre-drawn', (tester) async {
    final l = FakeFolderLabeling();
    await _open(tester, l);
    await _scan(tester);
    await tester.tap(find.byKey(const Key('labeller-predraw')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('labeller-blur-heads')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('labeller-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(l.calls.where((c) => c.startsWith('predraw')), isEmpty);
    expect(find.byType(HarvestLabeler), findsOneWidget);
  });

  testWidgets('moving the finished pictures needs a destination, asks first, then reports what happened', (tester) async {
    final l = FakeFolderLabeling();
    await _open(tester, l);
    await _scan(tester);
    l.counts = const HarvestCounts(label: 1, ready: 4); // four finished
    await tester.tap(find.byKey(const Key('labeller-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(HarvestLabeler), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // leave the labeller: back on the Labeller page
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.widget<FilledButton>(find.byKey(const Key('labeller-export'))).onPressed, isNull); // no destination yet
    await tester.enterText(find.byKey(const Key('labeller-dest')), 'D:/labelled');
    await tester.pump();
    await tester.tap(find.byKey(const Key('labeller-export')));
    await tester.pumpAndSettle();
    expect(find.text('Move the finished pictures?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('labeller-cancel')));
    await tester.pumpAndSettle();
    expect(l.calls.where((c) => c.startsWith('export')), isEmpty); // Cancel moves nothing

    await tester.tap(find.byKey(const Key('labeller-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('labeller-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(l.calls.last, 'export plate_specialist folder_ab12cd34 D:/labelled move=true');
    expect(find.byKey(const Key('labeller-result')), findsOneWidget);
    expect(find.textContaining('4 pictures moved: 3 for training, 1 for checking.'), findsOneWidget);
    expect(find.textContaining('1 copies of a picture were left out.'), findsOneWidget);
    expect(find.textContaining('2 pictures were blurred (3 places).'), findsOneWidget);
    expect(find.textContaining('Dataset: D:/labelled/plate_specialist'), findsOneWidget);
  });

  testWidgets('a failure from the helper is shown in words, not as a crash', (tester) async {
    final l = FakeFolderLabeling()..scanError = HarvestLabelingException('not a folder: C:/evidence');
    await _open(tester, l);
    await _scan(tester);
    expect(find.byKey(const Key('labeller-error')), findsOneWidget);
    expect(find.text('not a folder: C:/evidence'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('labeller-start'))).onPressed, isNull);
  });

  testWidgets('the plate model keeps its plates: only heads can be blurred, and the plate switch is locked off', (tester) async {
    await _open(tester, FakeFolderLabeling());
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('labeller-blur-heads'))).value, isTrue);
    final plates = tester.widget<SwitchListTile>(find.byKey(const Key('labeller-blur-plates')));
    expect(plates.value, isFalse);
    expect(plates.onChanged, isNull);
    expect(find.text('Plates stay readable: this model learns plates.'), findsOneWidget);
  });

  testWidgets('the helmet model keeps its heads: only plates can be blurred', (tester) async {
    final l = FakeFolderLabeling();
    l.pictures['helmet_specialist'] = [FakeLabeling.item('h1')];
    await _open(tester, l);
    await tester.tap(find.byKey(const Key('labeller-model-helmet_specialist')));
    await tester.pump();
    final heads = tester.widget<SwitchListTile>(find.byKey(const Key('labeller-blur-heads')));
    expect(heads.value, isFalse);
    expect(heads.onChanged, isNull);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('labeller-blur-plates'))).value, isTrue);
    await _scan(tester);
    await tester.tap(find.byKey(const Key('labeller-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(l.calls, contains('predraw helmet_specialist folder_ab12cd34 heads=false plates=true'));
  });

  testWidgets('switching a blur off is passed on to the helper', (tester) async {
    final l = FakeFolderLabeling();
    await _open(tester, l);
    await _scan(tester);
    await tester.tap(find.byKey(const Key('labeller-blur-heads')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('labeller-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(l.calls, contains('predraw plate_specialist folder_ab12cd34 heads=false plates=false'));
  });

  test('every model has a rule for what may be blurred, and no model loses its own target', () {
    expect(piiAllowed('plate_specialist').plates, isFalse);
    expect(piiAllowed('helmet_specialist').heads, isFalse);
    expect(piiAllowed('cabin_specialist').heads && piiAllowed('cabin_specialist').plates, isTrue);
    expect(piiAllowed('primary_anchor').heads && piiAllowed('primary_anchor').plates, isTrue);
  });
}
