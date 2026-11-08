import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/docs/data/docs_loader.dart';
import 'package:hulikamote_dashboard/features/docs/presentation/screens/docs_screen.dart';

Directory get repoRoot => Directory.current.parent;

void main() {
  group('DocsScreen', () {
    testWidgets('shows build command message when docs data is missing', (tester) async {
      final tempEmpty = Directory.systemTemp.createTempSync('empty_repo');
      addTearDown(() => tempEmpty.deleteSync(recursive: true));

      await tester.pumpWidget(MaterialApp(
        home: DocsScreen(root: tempEmpty),
      ));
      await tester.pump();

      expect(find.text('Technical Documentation Not Built Yet'), findsOneWidget);
      expect(find.text(DocsLoader.buildCommand), findsOneWidget);
      expect(find.text('Refresh / Check Again'), findsOneWidget);
    });

    testWidgets('loads real Start page and switches tabs cleanly', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: DocsScreen(root: repoRoot),
      ));
      await tester.pump();

      // Top header and tabs
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Datasets'), findsOneWidget);
      expect(find.text('Models'), findsOneWidget);
      expect(find.text('Training pipeline'), findsOneWidget);
      expect(find.text('Violations'), findsOneWidget);
      expect(find.text('Q&A'), findsOneWidget);

      // Start page content loaded
      expect(find.text('HULI-KAMOTE technical documentation'), findsOneWidget);
      expect(find.text('ON THIS PAGE'), findsOneWidget);

      // Switch to Datasets tab
      await tester.tap(find.text('Datasets'));
      await tester.pump();

      expect(find.text('Datasets'), findsWidgets);
      expect(find.text('PAGE 1'), findsOneWidget);

      // Switch to Models tab
      await tester.tap(find.text('Models'));
      await tester.pump();

      expect(find.text('Models'), findsWidgets);
      expect(find.text('PAGE 2'), findsOneWidget);

      // Switch to Training pipeline tab
      await tester.tap(find.text('Training pipeline'));
      await tester.pump();

      expect(find.text('Training pipeline'), findsWidgets);
      expect(find.text('PAGE 3'), findsOneWidget);

      // Switch to Violations tab
      await tester.tap(find.text('Violations'));
      await tester.pump();

      expect(find.text('Violations'), findsWidgets);
      expect(find.text('PAGE 4'), findsOneWidget);
      expect(find.text('How a violation is decided'), findsOneWidget);

      // Verify TOC contains Counterflow link
      expect(find.textContaining('Counterflow'), findsWidgets);

      // Switch to Q&A tab
      await tester.tap(find.text('Q&A'));
      await tester.pump();

      expect(find.text('Q&A'), findsWidgets);
      expect(find.text('PAGE 5'), findsOneWidget);
    });
  });
}
