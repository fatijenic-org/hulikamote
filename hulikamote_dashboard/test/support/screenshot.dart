import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders a widget to a PNG without launching the app, so a screen can be looked at while it is being designed.
/// Real fonts are loaded (Roboto + the Material icons from the Flutter SDK, Consolas from Windows); a plain
/// widget test would draw every letter as a block.
///
///   await loadScreenshotFonts();
///   await takeScreenshot(tester, const MyScreen(), 'C:/temp/my_screen.png', size: const Size(1500, 900));
///
/// Not a test by itself; used by the screen tests that want a picture.
Future<void> loadScreenshotFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/${Platform.environment['USERNAME']}/develop/flutter';
  final fonts = '$sdk/bin/cache/artifacts/material_fonts';

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final path in files) {
      final file = File(path);
      if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Roboto', ['$fonts/Roboto-Regular.ttf', '$fonts/Roboto-Medium.ttf', '$fonts/Roboto-Bold.ttf']);
  await load('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
  await load('Consolas', ['C:/Windows/Fonts/consola.ttf', 'C:/Windows/Fonts/consolab.ttf']);
}

final GlobalKey _shotKey = GlobalKey();

/// Shows [app] at [size] and keeps it on screen, so a test can tap or press keys and take several pictures.
Future<void> showForScreenshot(WidgetTester tester, Widget app, {Size size = const Size(1500, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(key: _shotKey, child: app));
  await tester.pump(const Duration(milliseconds: 600));
}

/// Saves what is on screen right now as a PNG.
Future<void> saveScreenshot(WidgetTester tester, String path) async {
  await tester.pump(const Duration(milliseconds: 300));
  final boundary = _shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

/// Shows [app] and saves one picture of it.
Future<void> takeScreenshot(WidgetTester tester, Widget app, String path, {Size size = const Size(1500, 900)}) async {
  await showForScreenshot(tester, app, size: size);
  await saveScreenshot(tester, path);
}
