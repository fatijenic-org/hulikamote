import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/docs/domain/live_slides.dart';
import 'package:hulikamote_dashboard/features/docs/domain/palette/doc_palette.dart';
import 'package:hulikamote_dashboard/features/docs/presentation/widgets/present_view.dart';

void main() {
  group('Live camera slides', () {
    test('every slide is short: at most ${LiveSlide.maxWords} words, a short title', () {
      for (final s in liveSlides) {
        expect(s.wordCount, lessThanOrEqualTo(LiveSlide.maxWords), reason: '"${s.title}" has ${s.wordCount} words');
        expect(s.title.split(' ').length, lessThanOrEqualTo(6), reason: s.title);
        expect(s.text.trim(), isNotEmpty);
      }
    });

    test('starts with foundations and ends in our code', () {
      expect(liveSlides.first.section, 'Foundations');
      expect(liveSlides.last.section, 'Our code');
      final firstCode = liveSlides.indexWhere((s) => s.section == 'Our code');
      expect(liveSlides.skip(firstCode).every((s) => s.section == 'Our code'), isTrue);
      expect(liveSlides.length, greaterThan(20));
    });
  });

  group('PresentView', () {
    Future<void> pump(WidgetTester tester, {VoidCallback? onClose}) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: PresentView(
              slides: liveSlides,
              palette: DocPalette.of(context),
              onClose: onClose ?? () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows one slide at a time and moves with the arrow keys', (tester) async {
      await pump(tester);
      expect(find.text(liveSlides[0].title), findsOneWidget);
      expect(find.text(liveSlides[1].title), findsNothing);
      expect(find.text('1 / ${liveSlides.length}'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text(liveSlides[1].title), findsOneWidget);
      expect(find.text(liveSlides[0].title), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text(liveSlides[0].title), findsOneWidget);
    });

    testWidgets('tapping Next advances, Back is disabled on the first slide', (tester) async {
      await pump(tester);
      final back = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_back_rounded));
      expect(back.onPressed, isNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
      expect(find.text('2 / ${liveSlides.length}'), findsOneWidget);
    });

    testWidgets('Esc closes, and the last slide ends with a close button', (tester) async {
      var closed = 0;
      await pump(tester, onClose: () => closed++);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.end); // not bound: must not crash
      for (var i = 0; i < liveSlides.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.pumpAndSettle();
      expect(find.text('${liveSlides.length} / ${liveSlides.length}'), findsOneWidget);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check_rounded));
      expect(closed, 2);
    });
  });
}
