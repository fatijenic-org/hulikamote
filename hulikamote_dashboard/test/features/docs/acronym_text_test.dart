import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/docs/domain/doc_acronyms.dart';
import 'package:hulikamote_dashboard/features/docs/domain/live_slides.dart';
import 'package:hulikamote_dashboard/features/docs/domain/palette/doc_palette.dart';
import 'package:hulikamote_dashboard/features/docs/presentation/widgets/present_view.dart';

void main() {
  test('finds whole-word acronyms only', () {
    String found(String t) => acronymPattern.allMatches(t).map((m) => m.group(1)).join(',');
    expect(found('Send it over TCP, not UDP.'), 'TCP,UDP');
    expect(found('CCTV and H.264 and AI.'), 'CCTV,H.264,AI');
    expect(found('rtsp://192.168.1.20/ch1 is lowercase'), '');
    expect(found('MAIN AIR TCPX'), '');
    expect(found('FFmpeg and MediaMTX'), 'FFmpeg,MediaMTX');
  });

  test('every acronym in the pattern has a meaning', () {
    for (final key in acronymPattern.pattern.split('(')[2].split(')')[0].split('|')) {
      expect(acronymMeaning(key.replaceAll(r'\', '')), isNotNull, reason: key);
    }
  });

  test('every acronym used in the slides has a meaning', () {
    for (final s in liveSlides) {
      for (final m in acronymPattern.allMatches('${s.title} ${s.text}')) {
        expect(acronymMeaning(m.group(1)!), isNotNull, reason: m.group(1));
      }
    }
  });

  testWidgets('hovering an acronym in a slide shows its meaning', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final index = liveSlides.indexWhere((s) => s.title.contains('CCTV'));
    expect(index, greaterThan(-1));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: PresentView(
            slides: [liveSlides[index]],
            palette: DocPalette.of(context),
            onClose: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final target = find.text('CCTV').first;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Fixed cameras that send pictures'), findsOneWidget);
  });
}
