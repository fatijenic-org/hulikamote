import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/core/theme/app_theme.dart';
import 'package:hulikamote_dashboard/features/blueprint/data/reference_data.dart';
import 'package:hulikamote_dashboard/features/blueprint/domain/reference_models.dart';
import 'package:hulikamote_dashboard/features/blueprint/domain/tests_index.dart';
import 'package:hulikamote_dashboard/features/blueprint/presentation/screens/blueprint_screen.dart';

import '../../support/screenshot.dart';

Directory get repoRoot => Directory.current.parent;

Future<void> pumpScreen(WidgetTester tester, {Directory? root}) async {
  await loadScreenshotFonts(); // real letter widths (the default test font is wide blocks); skipped if the SDK fonts are missing
  tester.view.physicalSize = const Size(1500, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: BlueprintScreen(root: root ?? repoRoot)));
  await tester.pump();
}

Slice slice(String id) => ReferenceData.byId(id)!;

void main() {
  testWidgets('opens on one small question, with its code and nothing else competing for attention', (tester) async {
    await pumpScreen(tester);
    final first = ReferenceData.inCategory(ReferenceCategory.violations).first;

    expect(find.text('Code reference'), findsOneWidget);
    for (final c in ReferenceCategory.values) {
      expect(find.text(c.title), findsOneWidget); // the four parts, as tabs
    }
    expect(find.text(first.title), findsNWidgets(2)); // the list on the left and the big title
    expect(find.text(first.says), findsOneWidget);
    expect(find.text('Open in VS Code'), findsOneWidget);
    expect(find.textContaining('def update_position'), findsOneWidget); // the real code, read from ledger.py
    expect(find.text('1 OF 34  ·  BUILDING BLOCKS'), findsOneWidget);
    expect(find.text('Back'), findsNothing); // nothing before the first slice
  });

  testWidgets('Next and Back (and the arrow keys) move one slice at a time', (tester) async {
    await pumpScreen(tester);
    final all = ReferenceData.inCategory(ReferenceCategory.violations);

    await tester.tap(find.textContaining('Next: '));
    await tester.pump();
    expect(find.text(all[1].says), findsOneWidget);
    expect(find.text('2 OF 34  ·  BUILDING BLOCKS'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text(all[2].says), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(find.text(all[0].says), findsOneWidget);
  });

  testWidgets('a part remembers where you were when you come back to it', (tester) async {
    await pumpScreen(tester);
    final violations = ReferenceData.inCategory(ReferenceCategory.violations);
    final pipelines = ReferenceData.inCategory(ReferenceCategory.pipelines);

    await tester.tap(find.textContaining('Next: '));
    await tester.pump();
    await tester.tap(find.text('Pipelines'));
    await tester.pump();
    expect(find.text(pipelines.first.says), findsOneWidget);
    expect(find.text('1 OF ${pipelines.length}  ·  FROM CAMERA TO ID'), findsOneWidget);

    await tester.tap(find.text('Violations'));
    await tester.pump();
    expect(find.text(violations[1].says), findsOneWidget);
  });

  testWidgets('what a slice is made of is shown as chips, and tapping one jumps to it', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('PUT TWO TOGETHER'));                  // open that group in the list
    await tester.pump();
    await tester.tap(find.text('Counterflow').first);
    await tester.pump();

    expect(find.text('MADE OF'), findsOneWidget);
    expect(find.text('inside a zone'), findsOneWidget);
    expect(find.text('its heading'), findsOneWidget);

    await tester.tap(find.text('its heading'));
    await tester.pump();
    expect(find.text(slice('v_heading').says), findsOneWidget);
    expect(find.text('MADE OF'), findsNothing);                        // a building block is made of nothing smaller
  });

  testWidgets('a chip can lead to another part (a rule that uses a pipeline step)', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('PUT TWO TOGETHER'));
    await tester.pump();
    await tester.tap(find.text(slice('r_autoflow').title).first);
    await tester.pump();

    await tester.tap(find.text('learned flow'));
    await tester.pump();
    expect(find.text(slice('p_flow').says), findsOneWidget);           // now in Pipelines
  });

  testWidgets('the last slice of a part leads on to the next part, and the very last has no Next', (tester) async {
    await pumpScreen(tester);
    final violations = ReferenceData.inCategory(ReferenceCategory.violations);
    for (var i = 0; i < violations.length - 1; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(find.text('Next: Pipelines'), findsOneWidget);
    await tester.ensureVisible(find.text('Next: Pipelines')); // the page scrolls: the tests section makes long slices taller
    await tester.pump();
    await tester.tap(find.text('Next: Pipelines'));
    await tester.pump();
    expect(find.text(ReferenceData.inCategory(ReferenceCategory.pipelines).first.says), findsOneWidget);

    await tester.tap(find.text('Features'));
    await tester.pump();
    final features = ReferenceData.inCategory(ReferenceCategory.features);
    for (var i = 0; i < features.length - 1; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(find.textContaining('Next: '), findsNothing);
  });

  testWidgets('only the open group lists its slices; the others show how many they hold', (tester) async {
    await pumpScreen(tester);
    final basics = ReferenceData.inCategory(ReferenceCategory.violations).where((s) => s.group == 'Building blocks');
    expect(find.text('Never trust one frame'), findsOneWidget);        // the open group
    expect(find.text('Illegal parking'), findsNothing);                 // a closed one
    expect(basics.length, 8);

    await tester.tap(find.text('PUT TWO TOGETHER'));
    await tester.pump();
    expect(find.text('Illegal parking'), findsOneWidget);
    expect(find.text('Never trust one frame'), findsNothing);
  });

  testWidgets('a slice with several places in the code has a tab for each', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Features'));
    await tester.pump();
    await tester.tap(find.textContaining('Next: ').first);              // Choose the camera: Dashboard + Backend
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Backend'), findsOneWidget);
    expect(find.textContaining('camera_input_dialog.dart'), findsOneWidget);
    await tester.tap(find.text('Backend'));
    await tester.pump();
    expect(find.textContaining('settings.py'), findsOneWidget);
  });

  testWidgets('long code starts folded and opens with Show all', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Pipelines'));
    await tester.pump();
    final whole = ReferenceData.inCategory(ReferenceCategory.pipelines).indexWhere((s) => s.id == 'p_whole');
    for (var i = 0; i < whole; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    final show = find.textContaining('Show all ');
    expect(show, findsOneWidget);
    await tester.ensureVisible(show);
    await tester.tap(show);
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets("under the code it says how that code is tested, when the tests index has been built", (tester) async {
    await pumpScreen(tester);

    expect(find.text("How it's tested"), findsOneWidget);
    expect(find.textContaining('Accuracy on real footage'), findsOneWidget);
  }, skip: TestsIndex.load(repoRoot) == null);

  testWidgets('without the repository it still teaches, and says why there is no code', (tester) async {
    final nowhere = Directory.systemTemp.createTempSync('no_repo_');
    addTearDown(() => nowhere.deleteSync(recursive: true));
    await pumpScreen(tester, root: nowhere);

    expect(find.text(ReferenceData.inCategory(ReferenceCategory.violations).first.says), findsOneWidget);
    expect(find.textContaining('Could not find'), findsOneWidget);
    expect(tester.widget<TextButton>(find.ancestor(of: find.text('Open in VS Code'), matching: find.byType(TextButton))).onPressed, isNull);
  });
}
