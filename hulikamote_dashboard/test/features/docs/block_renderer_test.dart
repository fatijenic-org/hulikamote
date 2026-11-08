import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/doc_block.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/doc_inline.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/scene_primitive.dart';
import 'package:hulikamote_dashboard/features/docs/domain/palette/doc_palette.dart';
import 'package:hulikamote_dashboard/features/docs/presentation/widgets/block_renderer.dart';

void main() {
  const glossary = {
    'YOLO': 'You Only Look Once neural network',
    'DeepSORT': 'Deep Simple Online and Realtime Tracking',
  };

  Widget buildTestable(Widget child, {bool isDark = false}) {
    return MaterialApp(
      theme: ThemeData(brightness: isDark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  group('BlockRenderer tests for every block type', () {
    testWidgets('renders HeadingBlock with kicker and level', (tester) async {
      final block = const HeadingBlock(
        level: 2,
        id: 'overview',
        text: 'Overview Heading',
        kicker: 'The project',
      );

      await tester.pumpWidget(buildTestable(
        BlockRenderer(block: block, palette: DocPalette.light, glossary: glossary),
      ));

      expect(find.text('THE PROJECT'), findsOneWidget);
      expect(find.text('Overview Heading'), findsOneWidget);
    });

    testWidgets('renders ParagraphBlock with term tooltip text', (tester) async {
      final block = const ParagraphBlock(
        inlines: [
          TextInline('Using '),
          TermInline(key: 'YOLO', shown: 'YOLO'),
          TextInline(' detector for vehicles.'),
        ],
        isNote: false,
      );

      await tester.pumpWidget(buildTestable(
        BlockRenderer(block: block, palette: DocPalette.light, glossary: glossary),
      ));

      expect(find.text('YOLO'), findsOneWidget);

      // Verify Tooltip widget has exact glossary meaning
      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsOneWidget);
      final tooltip = tester.widget<Tooltip>(tooltipFinder);
      expect(tooltip.message, 'You Only Look Once neural network');

      // Verify surrounding rich text spans
      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsWidgets);
      final hasMatchingSpan = tester.widgetList<RichText>(richTextFinder).any(
        (rt) => rt.text.toPlainText().contains('detector for vehicles'),
      );
      expect(hasMatchingSpan, isTrue);
    });

    testWidgets('renders ListBlock and StepsBlock', (tester) async {
      final listBlock = const ListBlock(
        ordered: false,
        items: [
          [TextInline('Unordered item 1')],
          [TextInline('Unordered item 2')],
        ],
      );

      final stepsBlock = const StepsBlock(
        items: [
          [TextInline('Step one description')],
          [TextInline('Step two description')],
        ],
      );

      await tester.pumpWidget(buildTestable(
        Column(
          children: [
            BlockRenderer(block: listBlock, palette: DocPalette.light, glossary: glossary),
            BlockRenderer(block: stepsBlock, palette: DocPalette.light, glossary: glossary),
          ],
        ),
      ));

      expect(find.text('Unordered item 1'), findsOneWidget);
      expect(find.text('Step one description'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('renders TableBlock with horizontal scroll and cells', (tester) async {
      final block = const TableBlock(
        headers: [
          [TextInline('Dataset')],
          [TextInline('Count')],
        ],
        rows: [
          [
            [TextInline('Vehicles')],
            [TextInline('24,763')],
          ]
        ],
        widths: ['50%', '50%'],
        cellClasses: [['', 'n']],
        isDense: true,
        isHeat: false,
      );

      await tester.pumpWidget(buildTestable(
        BlockRenderer(block: block, palette: DocPalette.light, glossary: glossary),
      ));

      expect(find.text('Dataset'), findsOneWidget);
      expect(find.text('Count'), findsOneWidget);
      expect(find.text('Vehicles'), findsOneWidget);
      expect(find.text('24,763'), findsOneWidget);
    });

    testWidgets('table cell with long prose text has generous readable width and does not collapse to single words', (tester) async {
      const sentence = 'A bullet list or a numbered list makes a checklist';
      final block = const TableBlock(
        headers: [
          [TextInline('Type this')],
          [TextInline('To get')],
        ],
        rows: [
          [
            [TextInline('- [x] done')],
            [TextInline(sentence)],
          ]
        ],
        widths: ['46%', '54%'],
        cellClasses: [['', '']],
        isDense: true,
        isHeat: false,
      );

      await tester.pumpWidget(buildTestable(
        SizedBox(
          width: 800,
          child: BlockRenderer(block: block, palette: DocPalette.light, glossary: glossary),
        ),
      ));

      final textFinder = find.text(sentence);
      expect(textFinder, findsOneWidget);
      final renderBox = tester.renderObject(textFinder) as RenderBox;
      expect(renderBox.size.width, greaterThan(250.0));
    });

    testWidgets('renders CalloutBlock and ChipsBlock', (tester) async {
      final callout = const CalloutBlock(
        kind: 'warn',
        title: 'Important Warning',
        blocks: [
          ParagraphBlock(inlines: [TextInline('Be cautious.')]),
        ],
      );

      final chips = const ChipsBlock(
        chips: [
          ChipItem(kind: 'ok', text: 'Ready'),
          ChipItem(kind: 'bad', text: 'Error'),
        ],
      );

      await tester.pumpWidget(buildTestable(
        Column(
          children: [
            BlockRenderer(block: callout, palette: DocPalette.light, glossary: glossary),
            BlockRenderer(block: chips, palette: DocPalette.light, glossary: glossary),
          ],
        ),
      ));

      expect(find.text('Important Warning'), findsOneWidget);
      expect(find.text('Be cautious.'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);
    });

    testWidgets('renders CmdBlock and RefsBlock', (tester) async {
      final cmd = const CmdBlock('python test.py --run');
      final refs = const RefsBlock(
        items: [
          RefItem(path: 'engine/counterflow.py', line: 15, label: 'Counterflow rule'),
        ],
      );

      await tester.pumpWidget(buildTestable(
        Column(
          children: [
            BlockRenderer(block: cmd, palette: DocPalette.light, glossary: glossary),
            BlockRenderer(block: refs, palette: DocPalette.light, glossary: glossary),
          ],
        ),
      ));

      expect(find.text('python test.py --run'), findsOneWidget);
      expect(find.text('Counterflow rule'), findsOneWidget);
      expect(find.text('engine/counterflow.py:15'), findsOneWidget);
    });

    testWidgets('renders CodeBlock with file, true line numbers, tokens, notes and VS Code button', (tester) async {
      final code = const CodeBlock(
        path: 'engine/violations/counterflow.py',
        first: 42,
        last: 44,
        title: 'Zone mode: the rule',
        lines: [
          CodeLine(
            n: 42,
            tokens: [CodeToken(cls: 'kw', text: 'def'), CodeToken(cls: '', text: ' evaluate():')],
            mark: 1,
            isHot: true,
          ),
          CodeLine(
            n: 43,
            tokens: [CodeToken(cls: 'com', text: '    # check flow')],
          ),
          CodeLine(
            n: 44,
            tokens: [CodeToken(cls: 'kw', text: '    return False')],
          ),
        ],
        notes: [
          CodeNote(mark: 1, line: 42, text: 'Evaluation entry point'),
        ],
      );

      await tester.pumpWidget(buildTestable(
        BlockRenderer(block: code, palette: DocPalette.light, glossary: glossary),
      ));

      expect(find.text('Zone mode: the rule'), findsOneWidget);
      expect(find.text('engine/violations/counterflow.py'), findsOneWidget);
      expect(find.text('lines 42-44'), findsOneWidget);
      expect(find.text('Open in VS Code'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('43'), findsOneWidget);
      expect(find.text('44'), findsOneWidget);
      expect(find.text('Evaluation entry point'), findsOneWidget);
    });

    testWidgets('renders CardBlock with sketch and layout', (tester) async {
      final card = const CardBlock(
        id: 'v-counterflow',
        key: 'counterflow',
        name: 'Counterflow',
        chips: [ChipItem(kind: 'info', text: 'Zone rule')],
        sketch: DocScene(
          w: 330,
          h: 170,
          aria: 'Sketch',
          primitives: [
            RectPrimitive(x: 6, y: 6, w: 318, h: 158, rx: 10, role: 'road'),
          ],
        ),
        gridLeft: [
          ParagraphBlock(inlines: [TextInline('Drives opposite way.')]),
        ],
        gridRight: [
          MiniBlock(title: 'Camera view', note: 'Fixed view', items: []),
        ],
        bottom: [
          ParagraphBlock(inlines: [TextInline('Honest limits.')]),
        ],
      );

      await tester.pumpWidget(buildTestable(
        BlockRenderer(block: card, palette: DocPalette.light, glossary: glossary),
      ));

      expect(find.text('Counterflow'), findsOneWidget);
      expect(find.text('counterflow'), findsOneWidget);
      expect(find.text('Zone rule'), findsOneWidget);
      expect(find.text('Drives opposite way.'), findsOneWidget);
      expect(find.text('Camera view'), findsOneWidget);
      expect(find.text('Honest limits.'), findsOneWidget);
    });

    testWidgets('renders Figures: hbar, line, and scene', (tester) async {
      final hbar = const FigureHbarBlock(
        caption: [TextInline('Hbar caption')],
        groups: [
          HbarGroup(label: 'Vehicles', values: [100.0, 50.0]),
        ],
        series: ['train', 'val'],
        vmax: 200,
        labelW: 100,
        w: 760,
        aria: 'Hbar',
      );

      final line = const FigureLineBlock(
        caption: [TextInline('Line caption')],
        series: [
          LineSeries(name: 'mAP50', points: [Point2D(x: 1, y: 0.5), Point2D(x: 2, y: 0.8)]),
        ],
        xmax: 10,
        ymax: 1.0,
        xlabel: 'epoch',
        ylabel: 'mAP',
        hlines: [Hline(value: 0.75, name: 'Target')],
        w: 760,
        h: 280,
        aria: 'Line',
      );

      await tester.pumpWidget(buildTestable(
        Column(
          children: [
            BlockRenderer(block: hbar, palette: DocPalette.light, glossary: glossary),
            BlockRenderer(block: line, palette: DocPalette.light, glossary: glossary),
          ],
        ),
      ));

      expect(find.text('Hbar caption'), findsOneWidget);
      expect(find.text('Vehicles'), findsOneWidget);
      expect(find.text('Line caption'), findsOneWidget);
      expect(find.text('mAP50'), findsOneWidget);
    });
  });
}
