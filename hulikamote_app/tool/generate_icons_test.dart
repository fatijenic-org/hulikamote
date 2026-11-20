// Draws the HULI-KAMOTE app icon at every size Android and iOS need, and writes the files into the app.
//
// The picture is the Material Icons "car_crash" symbol (Apache License 2.0, shipped inside the Flutter SDK, the same
// symbol the splash screen uses) in white on a blue gradient. Nothing is downloaded.
//
//   flutter test tool/generate_icons_test.dart
//
// The iOS App Store wants icons without a transparency channel; Flutter always writes one, so flatten the iOS files
// afterwards (e.g. with Pillow: Image.open(p).convert("RGB").save(p)).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _top = Color(0xFF16327A);
const _bottom = Color(0xFF2F6BFF);
const _gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_top, _bottom]);

/// The symbol's drawing sits off-centre inside its square, so it is nudged back to the middle.
Widget _glyph(double s, double fraction, Color color) {
  final size = s * fraction;
  return Center(
    child: Transform.translate(offset: Offset(-0.041 * size, 0.063 * size), child: Icon(Icons.car_crash, size: size, color: color)),
  );
}

/// A rounded (or, for iOS, full-bleed) blue tile with the white symbol: the old-style launcher icon.
Widget _tile(double s, {required double radius}) => Container(
      decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(s * radius)),
      child: _glyph(s, 0.70, Colors.white),
    );

Widget _background(double s) => Container(decoration: const BoxDecoration(gradient: _gradient));

/// Android 8+ icons are two layers of 108 units; only the middle 66 are always visible, so the symbol stays inside.
Widget _foreground(double s) => _glyph(s, 0.56, Colors.white);

/// The little white silhouette in the status bar next to a notification.
Widget _statusIcon(double s) => _glyph(s, 0.96, Colors.white);

Future<void> _loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final file = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

Future<Uint8List> _render(WidgetTester tester, Widget Function(double s) build, int px) async {
  tester.view.physicalSize = Size(px.toDouble(), px.toDouble());
  tester.view.devicePixelRatio = 1.0;
  final key = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(key: key, child: SizedBox(width: px.toDouble(), height: px.toDouble(), child: build(px.toDouble()))),
  ));
  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  return bytes!;
}

void _write(String path, Uint8List bytes) {
  final file = File(path)..createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

void main() {
  testWidgets('draw the app icon', (tester) async {
    await _loadMaterialIcons();
    addTearDown(tester.view.reset);
    const res = 'android/app/src/main/res';

    // Android: size in pixels of the old icon, of one adaptive layer (108 units) and of a status-bar icon (24 units)
    const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
    for (final d in densities.entries) {
      final k = d.value;
      _write('$res/mipmap-${d.key}/ic_launcher.png', await _render(tester, (s) => _tile(s, radius: 0.22), (48 * k).round()));
      _write('$res/mipmap-${d.key}/ic_launcher_background.png', await _render(tester, _background, (108 * k).round()));
      _write('$res/mipmap-${d.key}/ic_launcher_foreground.png', await _render(tester, _foreground, (108 * k).round()));
      _write('$res/mipmap-${d.key}/ic_launcher_monochrome.png', await _render(tester, _foreground, (108 * k).round()));
      _write('$res/drawable-${d.key}/ic_stat_hulikamote.png', await _render(tester, _statusIcon, (24 * k).round()));
    }
    _write(
      '$res/mipmap-anydpi-v26/ic_launcher.xml',
      Uint8List.fromList(utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
''')),
    );

    // iOS: every size listed in the app's own Contents.json
    const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final contents = jsonDecode(File('$iosDir/Contents.json').readAsStringSync()) as Map<String, dynamic>;
    for (final image in contents['images'] as List) {
      final size = double.parse((image['size'] as String).split('x').first);
      final scale = double.parse((image['scale'] as String).replaceAll('x', ''));
      _write('$iosDir/${image['filename']}', await _render(tester, (s) => _tile(s, radius: 0), (size * scale).round()));
    }
  });
}
