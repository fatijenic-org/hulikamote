import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/doc_block.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/doc_inline.dart';
import 'package:hulikamote_dashboard/features/docs/domain/palette/doc_palette.dart';
import 'package:hulikamote_dashboard/features/docs/presentation/widgets/callout_widget.dart';
import 'package:hulikamote_dashboard/features/docs/presentation/widgets/qa_view.dart';

void main() {
  group('CalloutWidget Collapsible Box', () {
    testWidgets('collapses when isCollapsible is true and isOpen is false, and toggles on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final palette = DocPalette.of(context);
                return CalloutWidget(
                  kind: 'info',
                  title: 'Collapsible Help Box',
                  blocks: const [
                    ParagraphBlock(inlines: [TextInline('Inner secret instructions.')]),
                  ],
                  isCollapsible: true,
                  isOpen: false,
                  palette: palette,
                  blockBuilder: (block) => const Text('Inner secret instructions.'),
                );
              },
            ),
          ),
        ),
      );

      // Title should be visible, but inner contents should be hidden
      expect(find.text('Collapsible Help Box'), findsOneWidget);
      expect(find.text('Inner secret instructions.'), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);

      // Tap header to expand
      await tester.tap(find.text('Collapsible Help Box'));
      await tester.pumpAndSettle();

      // Now inner contents should be visible
      expect(find.text('Inner secret instructions.'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });
  });

  group('QaView', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('qa_view_test_');
      final dataDir = Directory('${tempDir.path}/tools/doc_site/data')..createSync(recursive: true);
      final qaFile = File('${dataDir.path}/qa.json');
      qaFile.writeAsStringSync(jsonEncode({
        'version': 1,
        'items': [
          {
            'id': 'q-101',
            'q': 'What is the primary vehicle detector?',
            'a': 'It uses YOLOv8.',
            'tags': ['models', 'yolo'],
            'created': '2026-10-28T00:00:00.000Z',
            'updated': '2026-10-28T00:00:00.000Z',
          },
          {
            'id': 'q-102',
            'q': 'How does ALPR handle angles?',
            'a': '',
            'tags': ['plates'],
            'created': '2026-10-28T00:00:00.000Z',
            'updated': '2026-10-28T00:00:00.000Z',
          }
        ]
      }));
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('renders questions and allows adding a new question', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (context) {
                  final palette = DocPalette.of(context);
                  return QaView(
                    root: tempDir,
                    palette: palette,
                    glossary: const {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should display both questions
      expect(find.text('What is the primary vehicle detector?'), findsOneWidget);
      expect(find.text('How does ALPR handle angles?'), findsOneWidget);
      expect(find.text('Answered'), findsOneWidget);
      expect(find.text('Unanswered'), findsOneWidget);

      // Tap "+ Add Question"
      await tester.tap(find.widgetWithText(FilledButton, 'Add Question'));
      await tester.pumpAndSettle();

      // Editor should appear
      expect(find.text('New Question'), findsOneWidget);

      // Fill in question and answer
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(1), 'Can it run offline?'); // index 0 is search bar, 1 is Question
      await tester.enterText(textFields.at(2), 'Yes, everything runs on-device.'); // index 2 is Answer
      await tester.pumpAndSettle();

      // Tap save button (the filled button inside editor)
      final addButtons = find.widgetWithText(FilledButton, 'Add Question');
      await tester.ensureVisible(addButtons.last);
      await tester.tap(addButtons.last);
      await tester.pumpAndSettle();

      // The new question should now be visible in the list
      expect(find.text('Can it run offline?'), findsOneWidget);

      // Verify file on disk
      final qaFile = File('${tempDir.path}/tools/doc_site/data/qa.json');
      expect(qaFile.readAsStringSync().contains('Can it run offline?'), isTrue);
    });

    testWidgets('filters questions by tag and search text', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (context) {
                  final palette = DocPalette.of(context);
                  return QaView(
                    root: tempDir,
                    palette: palette,
                    glossary: const {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Filter by tag 'plates' (tap the one in the tag bar)
      await tester.tap(find.text('plates').first);
      await tester.pumpAndSettle();

      expect(find.text('How does ALPR handle angles?'), findsOneWidget);
      expect(find.text('What is the primary vehicle detector?'), findsNothing);

      // Clear tag filter by clicking again
      await tester.tap(find.text('plates').first);
      await tester.pumpAndSettle();

      expect(find.text('What is the primary vehicle detector?'), findsOneWidget);

      // Filter by search text
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'YOLO');
      await tester.pumpAndSettle();

      expect(find.text('What is the primary vehicle detector?'), findsOneWidget);
      expect(find.text('How does ALPR handle angles?'), findsNothing);
    });

    testWidgets('renders cleanly without overflow in a bounded container (e.g. 800x600)', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              width: 800,
              child: Builder(
                builder: (context) {
                  final palette = DocPalette.of(context);
                  return QaView(
                    root: tempDir,
                    palette: palette,
                    glossary: const {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('What is the primary vehicle detector?'), findsOneWidget);
    });
  });
}
