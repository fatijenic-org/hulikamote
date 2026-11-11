import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/screens/wiki_screen.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/widgets/model_dissection_visualizer_view.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/widgets/training_pipeline_visualizer_view.dart';

void main() {
  group('WikiScreen & Training Pipeline Visualizer Tests', () {
    testWidgets('WikiScreen shows every page as one row of tabs and switches between them', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WikiScreen(),
          ),
        ),
      );

      for (final page in WikiPage.values) {
        expect(find.text(page.label), findsWidgets, reason: page.label);
      }

      await tester.tap(find.text('Model Dissection').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Model Anatomy Dissector'), findsOneWidget);
      expect(find.text('1. Input & Letterbox'), findsOneWidget);

      await tester.tap(find.text('Violation Physics').first);
      await tester.pumpAndSettle();
      expect(find.text('Counterflow'), findsWidgets);
      expect(find.text('2. Naive Simulation'), findsOneWidget);
      await tester.tap(find.text('2. Naive Simulation'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('WikiScreen tabs use only the theme colors', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final theme = ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF3B82F6));
      await tester.pumpWidget(MaterialApp(theme: theme, home: const Scaffold(body: WikiScreen())));

      final selected = tester.widget<Text>(find.text('Detection Pipeline').first);
      final other = tester.widget<Text>(find.text('Docs').first);
      expect(selected.style?.color, theme.colorScheme.onSurface);
      expect(other.style?.color, theme.colorScheme.onSurfaceVariant);
    });

    testWidgets('TrainingPipelineVisualizerView switches across all 4 training pipelines and 7 models', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrainingPipelineVisualizerView(),
          ),
        ),
      );

      await tester.tap(find.text('Plate Specialist').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('plate_specialist'), findsWidgets);
      expect(find.textContaining('Vehicle registration plate → 0: license_plate'), findsOneWidget);

      await tester.tap(find.text('Plate OCR').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('plate_ocr'), findsWidgets);
      expect(find.text('1. Pop Quiz Harvest'), findsOneWidget);
      expect(find.text('5. OCR Export & Hot-Swap'), findsOneWidget);

      await tester.tap(find.text('Vehicle ReID').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('reid'), findsWidgets);
      expect(find.text('1. Identity Tracklets'), findsOneWidget);
      expect(find.text('5. Full Retrain & Head Graft'), findsOneWidget);

      await tester.tap(find.text('Plate Enhancer (SR)').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('plate_enhancer'), findsWidgets);
      expect(find.text('1. Sharpness & Aspect Gate'), findsOneWidget);
      expect(find.text('5. EMA ONNX Deployment'), findsOneWidget);
    });

    testWidgets('ModelDissectionVisualizerView dissects all 7 models down to their internal blocks', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ModelDissectionVisualizerView(),
          ),
        ),
      );

      // Default: Primary Anchor (5 YOLO blocks)
      expect(find.text('Model Anatomy Dissector'), findsOneWidget);
      expect(find.text('1. Input & Letterbox'), findsOneWidget);
      expect(find.text('2. CSPDarknet Backbone'), findsOneWidget);
      expect(find.text('3. PANet Multi-Scale Neck'), findsOneWidget);
      expect(find.text('4. Decoupled Anchor-Free Head'), findsOneWidget);
      expect(find.text('5. Un-Letterbox & NMS Filter'), findsOneWidget);

      // Switch to Helmet Specialist
      await tester.tap(find.text('Helmet Specialist').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Stage 2A · Rider Safety Magnifier'), findsWidgets);

      // Switch to Vehicle ReID (DeepSORT Net)
      await tester.tap(find.text('Vehicle ReID (DeepSORT Net)').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('1. 192×96 Crop & Stem'), findsOneWidget);
      expect(find.text('2. 4-Stage Residual Body'), findsOneWidget);
      expect(find.text('3. 512-D Unit Hypersphere'), findsOneWidget);
      expect(find.text('4. Kalman + Hungarian Match'), findsOneWidget);

      // Switch to Plate Enhancer (Real-ESRGAN / LapSRN)
      await tester.tap(find.text('Plate Enhancer (Real-ESRGAN / LapSRN)').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('1. Shallow Feature Extraction'), findsOneWidget);
      expect(find.text('2. 6-Block RRDB Trunk'), findsOneWidget);
      expect(find.text('3. Two-Stage ×4 Upsampler'), findsOneWidget);
      expect(find.text('4. LapSRN ×8 Pyramid Alternative'), findsOneWidget);

      // Switch to Plate OCR (EasyOCR CRNN / Paddle SVTR)
      await tester.tap(find.text('Plate OCR (EasyOCR CRNN / Paddle SVTR)').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('1. TPS Spatial Un-Warping'), findsOneWidget);
      expect(find.text('2. Vertical Column Slicing'), findsOneWidget);
      expect(find.text('3. BiLSTM / SVTR Sequence'), findsOneWidget);
      expect(find.text('4. CTC Collapse & Syntax Vote'), findsOneWidget);
    });
  });
}
