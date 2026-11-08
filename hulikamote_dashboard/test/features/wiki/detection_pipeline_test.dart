import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/wiki/domain/detection_pipeline_content.dart';
import 'package:hulikamote_dashboard/features/wiki/domain/detection_pipeline_rules.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/widgets/detection_pipeline_visualizer_view.dart';

void main() {
  group('rules mirror the Python engine', () {
    test('voteVerdict: share of the last 10 looks and a minimum number of looks', () {
      // helmet: 60% of last 10, min 3
      expect(voteVerdict([true, true], minLooks: 3, share: 0.6), isFalse);
      expect(voteVerdict([true, true, false], minLooks: 3, share: 0.6), isTrue); // ceil(1.8)=2
      expect(voteVerdict([true, false, false], minLooks: 3, share: 0.6), isFalse);
      // seatbelt: 80%, min 4
      expect(voteVerdict([true, true, true, false], minLooks: 4, share: 0.8), isFalse);
      expect(voteVerdict([true, true, true, true], minLooks: 4, share: 0.8), isTrue);
      // only the last 10 count
      final old = [for (var i = 0; i < 20; i++) i < 10];
      expect(voteVerdict(old, minLooks: 3, share: 0.6), isFalse);
    });

    test('keepsDetection: motorcycles have their own lower cutoff', () {
      expect(keepsDetection(cls: 'car', confidence: 0.40), isFalse);
      expect(keepsDetection(cls: 'motorcycle', confidence: 0.31), isTrue);
      expect(keepsDetection(cls: 'motorcycle', confidence: 0.20), isFalse);
      expect(keepsDetection(cls: 'car', confidence: 0.40, cutoff: 0.3), isTrue);
    });

    test('countSwings ignores small moves and counts reversals', () {
      expect(countSwings([0, 0.1, 0.05, 0.1], 0.5), 0);
      expect(countSwings([0, 1, 0, 1, 0], 0.5), 3);
      expect(countSwings([0, 1, 2, 3], 0.5), 0); // one direction only
    });

    test('isBlinking needs a steady rhythm; constant amber does not blink', () {
      final blink = [for (var i = 0; i <= 50; i++) (i / 10, (i / 10 * 1.25) % 1.0 < 0.5 ? 0.30 : 0.04)];
      final flat = [for (var i = 0; i <= 50; i++) (i / 10, 0.3)];
      expect(isBlinking(blink), isTrue);
      expect(isBlinking(flat), isFalse);
      expect(isBlinking(blink.take(5).toList()), isFalse);
    });

    test('pointInPolygon and the fair plate look', () {
      const sq = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)];
      expect(pointInPolygon(0.5, 0.5, sq), isTrue);
      expect(pointInPolygon(1.5, 0.5, sq), isFalse);
      expect(isFairPlateLook(classSettled: true, boxWidthPx: 59, isMotorcycle: false, movingUp: false), isFalse);
      expect(isFairPlateLook(classSettled: true, boxWidthPx: 80, isMotorcycle: true, movingUp: false), isFalse);
      expect(isFairPlateLook(classSettled: true, boxWidthPx: 80, isMotorcycle: true, movingUp: true), isTrue);
    });

    test('cleanPhPlate swaps look-alikes by slot', () {
      expect(cleanPhPlate('A8C1Z34'), 'ABC1234');
      expect(cleanPhPlate('ABC1234'), 'ABC1234');
    });
  });

  group('content', () {
    test('14 recipes cover the 25 violation modules (29 labels with sign types)', () {
      expect(kRecipes.length, 14);
      expect(kRecipes.expand((r) => r.covers).toSet().length, 29);
      expect(recipesIn(JudgeFamily.zone).length, 7);
      expect(recipesIn(JudgeFamily.frame).length, 2);
      expect(recipesIn(JudgeFamily.model).length, 5);
    });

    test('every recipe builds nine ordered steps', () {
      for (final r in kRecipes) {
        final steps = buildSteps(r);
        expect([for (final s in steps) s.index], [0, 1, 2, 3, 4, 5, 6, 7, 8]);
      }
    });
  });

  group('DetectionPipelineVisualizerView', () {
    Future<void> pump(WidgetTester tester, {Size size = const Size(1280, 900)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DetectionPipelineVisualizerView()),
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('shows the nine steps and opens the three families in on-demand dialog', (tester) async {
      await pump(tester);
      expect(find.text('Detection Pipeline'), findsOneWidget);
      expect(find.text('A frame arrives'), findsOneWidget);
      expect(find.text('Zone rules'), findsOneWidget);

      // Open the 14-recipe / 25-violation picker dialog on demand
      await tester.tap(find.byKey(const ValueKey('open-recipe-picker')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Zone rules'), findsWidgets);
      expect(find.text('Frame checks'), findsOneWidget);
      expect(find.text('Specialist checks'), findsOneWidget);
      expect(find.text('Rider without a helmet'), findsOneWidget);
    });

    testWidgets('every recipe renders without layout errors when selected from dialog', (tester) async {
      await pump(tester);
      for (final r in kRecipes) {
        await tester.ensureVisible(find.byKey(const ValueKey('open-recipe-picker')));
        await tester.tap(find.byKey(const ValueKey('open-recipe-picker')));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.ensureVisible(find.text(r.name).last);
        await tester.tap(find.text(r.name).last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: r.id);
      }
    });

    testWidgets('step details & specs open on demand in a modal dialog', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('step-details-0')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('TECHNICAL SPECIFICATIONS & CODE PARAMETERS'), findsOneWidget);
      expect(find.text('routers/stream.py + engine/pipeline.py'), findsOneWidget);
    });

    testWidgets('narrow width does not overflow', (tester) async {
      await pump(tester, size: const Size(760, 800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('vote simulator follows the engine rule', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('open-recipe-picker')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Rider without a helmet').last);
      await tester.tap(find.text('Rider without a helmet').last);
      await tester.pump(const Duration(milliseconds: 600));
      final verdict = find.byKey(const ValueKey('vote-verdict'));
      await tester.ensureVisible(verdict);
      // default: 3 bad of 6 looks, helmet needs ceil(0.6*6)=4
      expect((tester.widget(verdict) as Text).data, startsWith('No ticket'));
      await tester.ensureVisible(find.byKey(const ValueKey('look-1')));
      await tester.tap(find.byKey(const ValueKey('look-1')));
      await tester.pump();
      await tester.ensureVisible(verdict);
      expect((tester.widget(verdict) as Text).data, startsWith('TICKET'));
    });
  });
}
