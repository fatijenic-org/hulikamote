import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/doc_block.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/doc_inline.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/doc_page.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/scene_primitive.dart';

void main() {
  group('DocPage JSON parsing', () {
    test('parses tiny sample page JSON with all block types', () {
      const sampleJson = '''
      {
        "slug": "sample.html",
        "number": "1",
        "title": "Sample Title",
        "lede": [
          {"type": "text", "text": "This is a lede with "},
          {"type": "b", "children": [{"type": "text", "text": "bold text"}]},
          {"type": "term", "key": "YOLO", "shown": "YOLO"}
        ],
        "toc": [
          {"id": "intro", "title": "Introduction", "level": 2},
          {"id": "details", "title": "Details", "level": 3}
        ],
        "blocks": [
          {
            "type": "heading",
            "level": 2,
            "id": "intro",
            "text": "Introduction",
            "kicker": "Kicker text"
          },
          {
            "type": "paragraph",
            "inlines": [
              {"type": "text", "text": "Hello "},
              {"type": "code", "text": "foo()"}
            ],
            "is_note": true
          },
          {
            "type": "list",
            "ordered": false,
            "items": [
              [{"type": "text", "text": "item 1"}],
              [{"type": "text", "text": "item 2"}]
            ]
          },
          {
            "type": "steps",
            "items": [
              [{"type": "text", "text": "step 1"}],
              [{"type": "text", "text": "step 2"}]
            ]
          },
          {
            "type": "kv",
            "items": [
              {"key": "Key1", "value": [{"type": "text", "text": "Val1"}]}
            ]
          },
          {
            "type": "table",
            "headers": [[{"type": "text", "text": "Col1"}], [{"type": "text", "text": "Col2"}]],
            "rows": [
              [[{"type": "text", "text": "A"}], [{"type": "text", "text": "B"}]]
            ],
            "widths": ["50%", "50%"],
            "cell_classes": [["", "n"]],
            "is_dense": true,
            "is_heat": false
          },
          {
            "type": "callout",
            "kind": "ok",
            "title": "Success",
            "blocks": [
              {"type": "paragraph", "inlines": [{"type": "text", "text": "Well done"}], "is_note": false}
            ]
          },
          {
            "type": "chips",
            "chips": [
              {"kind": "ok", "text": "Passed"},
              {"kind": "warn", "text": "Review"}
            ]
          },
          {
            "type": "cmd",
            "text": "echo hello"
          },
          {
            "type": "refs",
            "items": [
              {"path": "lib/main.dart", "line": 42, "label": "Main entry"}
            ]
          },
          {
            "type": "code",
            "path": "test.py",
            "first": 10,
            "last": 20,
            "title": "Code Sample",
            "lines": [
              {
                "n": 10,
                "tokens": [{"cls": "kw", "text": "def"}, {"cls": "", "text": " "}, {"cls": "fn", "text": "bar"}],
                "mark": 1,
                "is_gap": false,
                "is_hot": true
              }
            ],
            "notes": [
              {"mark": 1, "line": 10, "text": "Function definition"}
            ]
          },
          {
            "type": "figure",
            "kind": "hbar",
            "caption": [{"type": "text", "text": "Figure 1"}],
            "groups": [{"label": "G1", "values": [10.0, 20.0]}],
            "series": ["s1", "s2"],
            "vmax": 100.0,
            "label_w": 150.0,
            "w": 760.0,
            "aria": "Hbar chart"
          },
          {
            "type": "figure",
            "kind": "line",
            "caption": [{"type": "text", "text": "Figure 2"}],
            "series": [
              {"name": "mAP", "points": [{"x": 1.0, "y": 0.5}]}
            ],
            "xmax": 10.0,
            "ymax": 1.0,
            "xlabel": "epochs",
            "ylabel": "score",
            "hlines": [{"value": 0.8, "name": "target"}],
            "w": 760.0,
            "h": 300.0,
            "aria": "Line chart"
          },
          {
            "type": "figure",
            "kind": "scene",
            "caption": [{"type": "text", "text": "Figure 3"}],
            "scene": {
              "w": 760.0,
              "h": 200.0,
              "aria": "Scene",
              "primitives": [
                {"type": "rect", "x": 0.0, "y": 0.0, "w": 100.0, "h": 50.0, "rx": 5.0, "role": "bx", "dash": false},
                {"type": "line", "x1": 0.0, "y1": 0.0, "x2": 10.0, "y2": 10.0, "role": "ar", "arrow": true, "dash": false, "width": 1.6},
                {"type": "circle", "cx": 20.0, "cy": 20.0, "r": 5.0, "role": "per", "fill_surface": false},
                {"type": "polygon", "points": [[0.0, 0.0], [10.0, 0.0], [5.0, 10.0]], "role": "zone"},
                {"type": "polyline", "points": [[0.0, 0.0], [5.0, 5.0]], "role": "path", "dash": true},
                {"type": "path", "d": "M0 0 L10 10", "role": "path", "dash": false, "width": 2.0},
                {"type": "text", "x": 15.0, "y": 15.0, "text": "label", "role": "sk", "anchor": "middle"}
              ]
            }
          },
          {
            "type": "card",
            "id": "v-sample",
            "key": "sample_violation",
            "name": "Sample Violation",
            "chips": [{"kind": "info", "text": "Zone"}],
            "sketch": {
              "w": 330.0,
              "h": 170.0,
              "aria": "Sketch",
              "primitives": [
                {"type": "rect", "x": 6.0, "y": 6.0, "w": 318.0, "h": 158.0, "rx": 10.0, "role": "road", "dash": false}
              ]
            },
            "grid_left": [
              {"type": "paragraph", "inlines": [{"type": "text", "text": "Left desc"}], "is_note": false}
            ],
            "grid_right": [
              {"type": "mini", "title": "View", "note": "Fixed camera", "items": []}
            ],
            "bottom": [
              {"type": "paragraph", "inlines": [{"type": "text", "text": "Bottom desc"}], "is_note": false}
            ]
          },
          {
            "type": "qa_placeholder"
          }
        ]
      }
      ''';

      final page = DocPage.fromJson(jsonDecode(sampleJson));

      expect(page.slug, 'sample.html');
      expect(page.number, '1');
      expect(page.title, 'Sample Title');
      expect(page.lede.length, 3);
      expect(page.lede[0], isA<TextInline>());
      expect(page.lede[1], isA<BoldInline>());
      expect(page.lede[2], isA<TermInline>());
      expect((page.lede[2] as TermInline).key, 'YOLO');

      expect(page.toc.length, 2);
      expect(page.toc[0].id, 'intro');
      expect(page.toc[0].level, 2);
      expect(page.toc[1].id, 'details');
      expect(page.toc[1].level, 3);

      expect(page.blocks.length, 16);

      // Verify each block type
      expect(page.blocks[0], isA<HeadingBlock>());
      final h = page.blocks[0] as HeadingBlock;
      expect(h.level, 2);
      expect(h.kicker, 'Kicker text');
      expect(h.text, 'Introduction');

      expect(page.blocks[1], isA<ParagraphBlock>());
      expect((page.blocks[1] as ParagraphBlock).isNote, true);

      expect(page.blocks[2], isA<ListBlock>());
      expect((page.blocks[2] as ListBlock).ordered, false);

      expect(page.blocks[3], isA<StepsBlock>());
      expect((page.blocks[3] as StepsBlock).items.length, 2);

      expect(page.blocks[4], isA<KvBlock>());
      expect((page.blocks[4] as KvBlock).items.first.key, 'Key1');

      expect(page.blocks[5], isA<TableBlock>());
      final tbl = page.blocks[5] as TableBlock;
      expect(tbl.headers.length, 2);
      expect(tbl.rows.length, 1);
      expect(tbl.isDense, true);

      expect(page.blocks[6], isA<CalloutBlock>());
      final callout = page.blocks[6] as CalloutBlock;
      expect(callout.kind, 'ok');
      expect(callout.title, 'Success');
      expect(callout.blocks.length, 1);

      expect(page.blocks[7], isA<ChipsBlock>());
      expect((page.blocks[7] as ChipsBlock).chips.length, 2);

      expect(page.blocks[8], isA<CmdBlock>());
      expect((page.blocks[8] as CmdBlock).text, 'echo hello');

      expect(page.blocks[9], isA<RefsBlock>());
      final ref = (page.blocks[9] as RefsBlock).items.first;
      expect(ref.path, 'lib/main.dart');
      expect(ref.line, 42);

      expect(page.blocks[10], isA<CodeBlock>());
      final code = page.blocks[10] as CodeBlock;
      expect(code.path, 'test.py');
      expect(code.first, 10);
      expect(code.last, 20);
      expect(code.lines.first.n, 10);
      expect(code.lines.first.tokens.first.cls, 'kw');
      expect(code.notes.first.mark, 1);

      expect(page.blocks[11], isA<FigureHbarBlock>());
      expect((page.blocks[11] as FigureHbarBlock).groups.length, 1);

      expect(page.blocks[12], isA<FigureLineBlock>());
      expect((page.blocks[12] as FigureLineBlock).series.length, 1);

      expect(page.blocks[13], isA<FigureSceneBlock>());
      final scene = (page.blocks[13] as FigureSceneBlock).scene;
      expect(scene.primitives.length, 7);
      expect(scene.primitives[0], isA<RectPrimitive>());
      expect(scene.primitives[1], isA<LinePrimitive>());
      expect(scene.primitives[2], isA<CirclePrimitive>());
      expect(scene.primitives[3], isA<PolygonPrimitive>());
      expect(scene.primitives[4], isA<PolylinePrimitive>());
      expect(scene.primitives[5], isA<PathPrimitive>());
      expect(scene.primitives[6], isA<TextPrimitive>());

      expect(page.blocks[14], isA<CardBlock>());
      final card = page.blocks[14] as CardBlock;
      expect(card.key, 'sample_violation');
      expect(card.sketch, isNotNull);
      expect(card.gridLeft.length, 1);
      expect(card.gridRight.length, 1);
      expect(card.gridRight.first, isA<MiniBlock>());

      expect(page.blocks[15], isA<QaPlaceholderBlock>());
    });
  });
}
