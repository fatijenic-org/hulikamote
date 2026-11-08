import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/models_hub/data/models_hub_api.dart';
import 'package:hulikamote_dashboard/features/models_hub/presentation/screens/models_hub_screen.dart';

import '../features/models_hub/models_hub_screen_test.dart' show Backend, vehicles;
import '../support/screenshot.dart';

/// Pictures of the Models page for looking at while designing it. Writes nothing unless MODELS_HUB_SHOTS names a folder:
///   MODELS_HUB_SHOTS=C:/temp/hub flutter test test/visual/models_hub_screenshots_test.dart
void main() {
  final out = Platform.environment['MODELS_HUB_SHOTS'];
  const classes = {
    'split': 'test',
    'map50': 0.715,
    'classes': [
      {'name': 'tricycle', 'score': 0.915, 'boxes': 124},
      {'name': 'bus', 'score': 0.833, 'boxes': 290},
      {'name': 'truck', 'score': 0.707, 'boxes': 301},
      {'name': 'car', 'score': 0.700, 'boxes': 824},
      {'name': 'motorcycle', 'score': 0.663, 'boxes': 487},
      {'name': 'person', 'score': 0.472, 'boxes': 1082},
    ],
  };

  testWidgets('pictures of the Models page', (tester) async {
    await loadScreenshotFonts();
    final backend = Backend(() => vehicles(v3Classes: classes));
    await showForScreenshot(
      tester,
      MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(brightness: Brightness.dark, useMaterial3: true, fontFamily: 'Roboto', colorSchemeSeed: Colors.blueAccent), home: ModelsHubScreen(api: ModelsHubApi(client: backend.client))),
      size: const Size(1400, 900),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await saveScreenshot(tester, '$out/1_overview.png');

    await tester.tap(find.text('Version 3'));
    await tester.pump();
    await saveScreenshot(tester, '$out/2_details.png');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Use this').first);
    await tester.pump();
    await saveScreenshot(tester, '$out/3_confirm.png');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }, skip: out == null);
}
