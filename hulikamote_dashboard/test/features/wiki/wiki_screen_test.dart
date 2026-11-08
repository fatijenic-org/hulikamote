import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/wiki/domain/models/archived_resource.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/screens/wiki_screen.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/widgets/model_dissection_visualizer_view.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/widgets/training_pipeline_visualizer_view.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/widgets/wiki_clean_canvas.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/widgets/wiki_header.dart';

void main() {
  group('WikiScreen & Training Pipeline Visualizer Tests', () {
    testWidgets('WikiHeader renders Archive dropdown button and offline badge', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ArchivedResource? selectedArchive;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return WikiHeader(
                  searchQuery: '',
                  onSearchChanged: (_) {},
                  onClearSearch: () {},
                  selectedArchive: selectedArchive,
                  onSelectArchive: (res) => setState(() => selectedArchive = res),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Huli-Kamote System Wiki'), findsOneWidget);
      expect(find.text('Archive Dropdown'), findsOneWidget);
      expect(find.text('Offline Ready'), findsOneWidget);

      await tester.tap(find.text('Archive Dropdown'));
      await tester.pumpAndSettle();

      expect(find.text('Technical Documentation'), findsOneWidget);
      expect(find.text('Violation Logic & Physics Visualizer'), findsOneWidget);
      expect(find.text('System Architecture Blueprint'), findsOneWidget);
      expect(find.text('Progress Decks & Technical Audits'), findsOneWidget);
      expect(find.text('Defense Q&A Knowledge Base'), findsOneWidget);
      expect(find.text('Project Map & Risk Matrices'), findsOneWidget);

      await tester.tap(find.text('Technical Documentation'));
      await tester.pumpAndSettle();

      expect(selectedArchive, ArchivedResource.docs);
    });

    testWidgets('WikiCleanCanvas displays clean ready state and quick-access archive cards', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ArchivedResource? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WikiCleanCanvas(
              onSelectArchive: (res) => selected = res,
            ),
          ),
        ),
      );

      expect(find.text('Wiki Workspace Ready for Restructuring'), findsOneWidget);
      expect(find.text('Preserved Archive Resources'), findsOneWidget);
      expect(find.text('6 Modules Preserved'), findsOneWidget);

      await tester.tap(find.text('Violation Logic & Physics Visualizer'));
      await tester.pumpAndSettle();

      expect(selected, ArchivedResource.visualizer);
    });

    testWidgets('WikiScreen renders Visualization tab and switches to Model Dissection tab', (tester) async {
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

      expect(find.text('Visualization'), findsOneWidget);
      expect(find.text('1. Training Pipeline'), findsOneWidget);
      expect(find.text('4. Model Dissection'), findsOneWidget);

      // Switch to 4. Model Dissection
      await tester.tap(find.text('4. Model Dissection'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Model Anatomy Dissector'), findsOneWidget);
      expect(find.text('1. Input & Letterbox'), findsOneWidget);

      // Switch to 2. Violation Physics
      await tester.tap(find.text('2. Violation Physics'));
      await tester.pumpAndSettle();

      expect(find.text('VIOLATIONS'), findsOneWidget);
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
