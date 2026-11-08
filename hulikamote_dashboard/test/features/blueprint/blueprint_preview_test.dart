import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/core/theme/app_theme.dart';
import 'package:hulikamote_dashboard/features/blueprint/data/reference_data.dart';
import 'package:hulikamote_dashboard/features/blueprint/domain/reference_models.dart';
import 'package:hulikamote_dashboard/features/blueprint/presentation/screens/blueprint_screen.dart';

import '../../support/screenshot.dart';

/// A preview tool, not a check: saves pictures of the Code Reference so a layout can be looked at without
/// starting the app. It only runs when SCREENSHOT_DIR is set:
///
///   SCREENSHOT_DIR=C:/temp/shots flutter test test/features/blueprint/blueprint_preview_test.dart
void main() {
  final dir = Platform.environment['SCREENSHOT_DIR'];

  testWidgets('pictures of the Code Reference', (tester) async {
    await loadScreenshotFonts();
    final app = MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.darkTheme, home: BlueprintScreen(root: Directory.current.parent));
    await showForScreenshot(tester, app);
    await saveScreenshot(tester, '$dir/code_reference_1_first_slice.png');

    Future<void> next(int times) async {
      for (var i = 0; i < times; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
    }

    await next(12);
    await saveScreenshot(tester, '$dir/code_reference_2_a_recipe.png');
    for (final part in ['Pipelines', 'Training', 'Features']) {
      await tester.tap(find.text(part));
      await tester.pump();
      await next(1);
      await saveScreenshot(tester, '$dir/code_reference_3_${part.toLowerCase()}.png');
    }
  }, skip: dir == null || dir.isEmpty); // set SCREENSHOT_DIR to save pictures

  testWidgets("picture of \"How it's tested\" under the code of one rule", (tester) async {
    await loadScreenshotFonts();
    final app = MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.darkTheme, home: BlueprintScreen(root: Directory.current.parent));
    await showForScreenshot(tester, app, size: const Size(1500, 1250)); // tall enough for the code and the tests under it

    final target = ReferenceData.inCategory(ReferenceCategory.violations).indexWhere((s) => s.id == 'r_pedestrian');
    for (var i = 0; i < target; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await saveScreenshot(tester, '$dir/code_reference_4_how_its_tested.png');
  }, skip: dir == null || dir.isEmpty);
}
