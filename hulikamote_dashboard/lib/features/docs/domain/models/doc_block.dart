import 'doc_inline.dart';
import 'scene_primitive.dart';

sealed class DocBlock {
  const DocBlock();

  static List<DocBlock> fromList(List<dynamic>? list) {
    if (list == null) return const [];
    final out = <DocBlock>[];
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final b = DocBlock.fromJson(item);
        if (b != null) out.add(b);
      }
    }
    return out;
  }

  static DocBlock? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    switch (type) {
      case 'heading':
        return HeadingBlock(
          level: json['level'] as int? ?? 2,
          id: json['id'] as String? ?? '',
          text: json['text'] as String? ?? '',
          kicker: json['kicker'] as String? ?? '',
        );
      case 'paragraph':
        return ParagraphBlock(
          inlines: DocInline.fromList(json['inlines'] as List<dynamic>?),
          isNote: json['is_note'] as bool? ?? false,
        );
      case 'list':
        final rawItems = (json['items'] as List<dynamic>?) ?? [];
        final items = <List<DocInline>>[];
        for (final it in rawItems) {
          items.add(DocInline.fromList(it as List<dynamic>?));
        }
        return ListBlock(
          ordered: json['ordered'] as bool? ?? false,
          items: items,
        );
      case 'steps':
        final rawItems = (json['items'] as List<dynamic>?) ?? [];
        final items = <List<DocInline>>[];
        for (final it in rawItems) {
          items.add(DocInline.fromList(it as List<dynamic>?));
        }
        return StepsBlock(items: items);
      case 'kv':
        final rawItems = (json['items'] as List<dynamic>?) ?? [];
        final items = <KvItem>[];
        for (final it in rawItems) {
          if (it is Map<String, dynamic>) {
            items.add(KvItem(
              key: it['key'] as String? ?? '',
              value: DocInline.fromList(it['value'] as List<dynamic>?),
            ));
          }
        }
        return KvBlock(items: items);
      case 'table':
        final rawHeaders = (json['headers'] as List<dynamic>?) ?? [];
        final headers = rawHeaders.map((h) => DocInline.fromList(h as List<dynamic>?)).toList();
        final rawRows = (json['rows'] as List<dynamic>?) ?? [];
        final rows = <List<List<DocInline>>>[];
        for (final row in rawRows) {
          final cells = (row as List<dynamic>).map((c) => DocInline.fromList(c as List<dynamic>?)).toList();
          rows.add(cells);
        }
        final rawWidths = (json['widths'] as List<dynamic>?) ?? [];
        final widths = rawWidths.map((w) => w.toString()).toList();
        final rawCellClasses = (json['cell_classes'] as List<dynamic>?) ?? [];
        final cellClasses = <List<String>>[];
        for (final cr in rawCellClasses) {
          cellClasses.add((cr as List<dynamic>).map((c) => c.toString()).toList());
        }
        return TableBlock(
          headers: headers,
          rows: rows,
          widths: widths,
          cellClasses: cellClasses,
          isDense: json['is_dense'] as bool? ?? false,
          isHeat: json['is_heat'] as bool? ?? false,
        );
      case 'callout':
        return CalloutBlock(
          kind: json['kind'] as String? ?? 'info',
          title: json['title'] as String? ?? '',
          blocks: DocBlock.fromList(json['blocks'] as List<dynamic>?),
          isCollapsible: json['is_collapsible'] as bool? ?? false,
          isOpen: json['is_open'] as bool? ?? true,
        );
      case 'chips':
        final rawChips = (json['chips'] as List<dynamic>?) ?? [];
        final chips = rawChips.map((c) => ChipItem.fromJson(c as Map<String, dynamic>)).toList();
        return ChipsBlock(chips: chips);
      case 'cmd':
        return CmdBlock(json['text'] as String? ?? '');
      case 'refs':
        final rawItems = (json['items'] as List<dynamic>?) ?? [];
        final items = rawItems.map((r) => RefItem.fromJson(r as Map<String, dynamic>)).toList();
        return RefsBlock(items: items);
      case 'code':
        final rawLines = (json['lines'] as List<dynamic>?) ?? [];
        final lines = rawLines.map((l) => CodeLine.fromJson(l as Map<String, dynamic>)).toList();
        final rawNotes = (json['notes'] as List<dynamic>?) ?? [];
        final notes = rawNotes.map((n) => CodeNote.fromJson(n as Map<String, dynamic>)).toList();
        return CodeBlock(
          path: json['path'] as String? ?? '',
          first: json['first'] as int? ?? 1,
          last: json['last'] as int? ?? 1,
          title: json['title'] as String? ?? '',
          lines: lines,
          notes: notes,
        );
      case 'figure':
        final kind = json['kind'] as String? ?? '';
        final caption = DocInline.fromList(json['caption'] as List<dynamic>?);
        if (kind == 'hbar') {
          final rawGroups = (json['groups'] as List<dynamic>?) ?? [];
          final groups = rawGroups.map((g) => HbarGroup.fromJson(g as Map<String, dynamic>)).toList();
          final rawSeries = (json['series'] as List<dynamic>?) ?? [];
          final series = rawSeries.map((s) => s.toString()).toList();
          return FigureHbarBlock(
            caption: caption,
            groups: groups,
            series: series,
            vmax: (json['vmax'] as num?)?.toDouble() ?? 100.0,
            labelW: (json['label_w'] as num?)?.toDouble() ?? 190.0,
            w: (json['w'] as num?)?.toDouble() ?? 760.0,
            aria: json['aria'] as String? ?? '',
          );
        } else if (kind == 'line') {
          final rawSeries = (json['series'] as List<dynamic>?) ?? [];
          final series = rawSeries.map((s) => LineSeries.fromJson(s as Map<String, dynamic>)).toList();
          final rawHlines = (json['hlines'] as List<dynamic>?) ?? [];
          final hlines = rawHlines.map((h) => Hline.fromJson(h as Map<String, dynamic>)).toList();
          return FigureLineBlock(
            caption: caption,
            series: series,
            xmax: (json['xmax'] as num?)?.toDouble() ?? 100.0,
            ymax: (json['ymax'] as num?)?.toDouble() ?? 1.0,
            xlabel: json['xlabel'] as String? ?? 'epoch',
            ylabel: json['ylabel'] as String? ?? '',
            hlines: hlines,
            w: (json['w'] as num?)?.toDouble() ?? 760.0,
            h: (json['h'] as num?)?.toDouble() ?? 330.0,
            aria: json['aria'] as String? ?? '',
          );
        } else {
          final sceneJson = json['scene'] as Map<String, dynamic>? ?? {};
          return FigureSceneBlock(
            caption: caption,
            scene: DocScene.fromJson(sceneJson),
          );
        }
      case 'card':
        final rawChips = (json['chips'] as List<dynamic>?) ?? [];
        final chips = rawChips.map((c) => ChipItem.fromJson(c as Map<String, dynamic>)).toList();
        final sketchJson = json['sketch'] as Map<String, dynamic>?;
        final sketch = sketchJson != null ? DocScene.fromJson(sketchJson) : null;
        return CardBlock(
          id: json['id'] as String? ?? '',
          key: json['key'] as String? ?? '',
          name: json['name'] as String? ?? '',
          chips: chips,
          sketch: sketch,
          gridLeft: DocBlock.fromList(json['grid_left'] as List<dynamic>?),
          gridRight: DocBlock.fromList(json['grid_right'] as List<dynamic>?),
          bottom: DocBlock.fromList(json['bottom'] as List<dynamic>?),
        );
      case 'mini':
        final rawItems = (json['items'] as List<dynamic>?) ?? [];
        final items = <List<DocInline>>[];
        for (final it in rawItems) {
          items.add(DocInline.fromList(it as List<dynamic>?));
        }
        return MiniBlock(
          title: json['title'] as String? ?? '',
          note: json['note'] as String? ?? '',
          items: items,
        );
      case 'qa_placeholder':
        return const QaPlaceholderBlock();
      default:
        return null;
    }
  }
}

class HeadingBlock extends DocBlock {
  final int level;
  final String id;
  final String text;
  final String kicker;

  const HeadingBlock({
    required this.level,
    required this.id,
    required this.text,
    this.kicker = '',
  });
}

class ParagraphBlock extends DocBlock {
  final List<DocInline> inlines;
  final bool isNote;

  const ParagraphBlock({
    required this.inlines,
    this.isNote = false,
  });
}

class ListBlock extends DocBlock {
  final bool ordered;
  final List<List<DocInline>> items;

  const ListBlock({
    required this.ordered,
    required this.items,
  });
}

class StepsBlock extends DocBlock {
  final List<List<DocInline>> items;

  const StepsBlock({required this.items});
}

class KvItem {
  final String key;
  final List<DocInline> value;

  const KvItem({required this.key, required this.value});
}

class KvBlock extends DocBlock {
  final List<KvItem> items;

  const KvBlock({required this.items});
}

class TableBlock extends DocBlock {
  final List<List<DocInline>> headers;
  final List<List<List<DocInline>>> rows;
  final List<String> widths;
  final List<List<String>> cellClasses;
  final bool isDense;
  final bool isHeat;

  const TableBlock({
    required this.headers,
    required this.rows,
    required this.widths,
    required this.cellClasses,
    this.isDense = false,
    this.isHeat = false,
  });
}

class CalloutBlock extends DocBlock {
  final String kind;
  final String title;
  final List<DocBlock> blocks;
  final bool isCollapsible;
  final bool isOpen;

  const CalloutBlock({
    required this.kind,
    required this.title,
    required this.blocks,
    this.isCollapsible = false,
    this.isOpen = true,
  });
}

class ChipItem {
  final String kind;
  final String text;

  const ChipItem({required this.kind, required this.text});

  factory ChipItem.fromJson(Map<String, dynamic> json) {
    return ChipItem(
      kind: json['kind'] as String? ?? 'info',
      text: json['text'] as String? ?? '',
    );
  }
}

class ChipsBlock extends DocBlock {
  final List<ChipItem> chips;

  const ChipsBlock({required this.chips});
}

class CmdBlock extends DocBlock {
  final String text;

  const CmdBlock(this.text);
}

class RefItem {
  final String path;
  final int line;
  final String label;

  const RefItem({required this.path, required this.line, required this.label});

  factory RefItem.fromJson(Map<String, dynamic> json) {
    return RefItem(
      path: json['path'] as String? ?? '',
      line: json['line'] as int? ?? 1,
      label: json['label'] as String? ?? '',
    );
  }
}

class RefsBlock extends DocBlock {
  final List<RefItem> items;

  const RefsBlock({required this.items});
}

class CodeToken {
  final String cls;
  final String text;

  const CodeToken({required this.cls, required this.text});

  factory CodeToken.fromJson(Map<String, dynamic> json) {
    return CodeToken(
      cls: json['cls'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}

class CodeLine {
  final int? n;
  final List<CodeToken> tokens;
  final int? mark;
  final bool isGap;
  final bool isHot;

  const CodeLine({
    required this.n,
    required this.tokens,
    this.mark,
    this.isGap = false,
    this.isHot = false,
  });

  factory CodeLine.fromJson(Map<String, dynamic> json) {
    final rawTokens = (json['tokens'] as List<dynamic>?) ?? [];
    final tokens = rawTokens.map((t) => CodeToken.fromJson(t as Map<String, dynamic>)).toList();
    return CodeLine(
      n: json['n'] as int?,
      tokens: tokens,
      mark: json['mark'] as int?,
      isGap: json['is_gap'] as bool? ?? false,
      isHot: json['is_hot'] as bool? ?? false,
    );
  }
}

class CodeNote {
  final int mark;
  final int line;
  final String text;

  const CodeNote({required this.mark, required this.line, required this.text});

  factory CodeNote.fromJson(Map<String, dynamic> json) {
    return CodeNote(
      mark: json['mark'] as int? ?? 1,
      line: json['line'] as int? ?? 1,
      text: json['text'] as String? ?? '',
    );
  }
}

class CodeBlock extends DocBlock {
  final String path;
  final int first;
  final int last;
  final String title;
  final List<CodeLine> lines;
  final List<CodeNote> notes;

  const CodeBlock({
    required this.path,
    required this.first,
    required this.last,
    required this.title,
    required this.lines,
    required this.notes,
  });
}

class HbarGroup {
  final String label;
  final List<double> values;

  const HbarGroup({required this.label, required this.values});

  factory HbarGroup.fromJson(Map<String, dynamic> json) {
    final rawVals = (json['values'] as List<dynamic>?) ?? [];
    return HbarGroup(
      label: json['label'] as String? ?? '',
      values: rawVals.map((v) => (v as num).toDouble()).toList(),
    );
  }
}

class FigureHbarBlock extends DocBlock {
  final List<DocInline> caption;
  final List<HbarGroup> groups;
  final List<String> series;
  final double vmax;
  final double labelW;
  final double w;
  final String aria;

  const FigureHbarBlock({
    required this.caption,
    required this.groups,
    required this.series,
    required this.vmax,
    required this.labelW,
    required this.w,
    required this.aria,
  });
}

class Point2D {
  final double x;
  final double y;

  const Point2D({required this.x, required this.y});

  factory Point2D.fromJson(Map<String, dynamic> json) {
    return Point2D(
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class LineSeries {
  final String name;
  final List<Point2D> points;

  const LineSeries({required this.name, required this.points});

  factory LineSeries.fromJson(Map<String, dynamic> json) {
    final rawPts = (json['points'] as List<dynamic>?) ?? [];
    return LineSeries(
      name: json['name'] as String? ?? '',
      points: rawPts.map((p) => Point2D.fromJson(p as Map<String, dynamic>)).toList(),
    );
  }
}

class Hline {
  final double value;
  final String name;

  const Hline({required this.value, required this.name});

  factory Hline.fromJson(Map<String, dynamic> json) {
    return Hline(
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      name: json['name'] as String? ?? '',
    );
  }
}

class FigureLineBlock extends DocBlock {
  final List<DocInline> caption;
  final List<LineSeries> series;
  final double xmax;
  final double ymax;
  final String xlabel;
  final String ylabel;
  final List<Hline> hlines;
  final double w;
  final double h;
  final String aria;

  const FigureLineBlock({
    required this.caption,
    required this.series,
    required this.xmax,
    required this.ymax,
    required this.xlabel,
    required this.ylabel,
    required this.hlines,
    required this.w,
    required this.h,
    required this.aria,
  });
}

class FigureSceneBlock extends DocBlock {
  final List<DocInline> caption;
  final DocScene scene;

  const FigureSceneBlock({required this.caption, required this.scene});
}

class CardBlock extends DocBlock {
  final String id;
  final String key;
  final String name;
  final List<ChipItem> chips;
  final DocScene? sketch;
  final List<DocBlock> gridLeft;
  final List<DocBlock> gridRight;
  final List<DocBlock> bottom;

  const CardBlock({
    required this.id,
    required this.key,
    required this.name,
    required this.chips,
    this.sketch,
    required this.gridLeft,
    required this.gridRight,
    required this.bottom,
  });
}

class MiniBlock extends DocBlock {
  final String title;
  final String note;
  final List<List<DocInline>> items;

  const MiniBlock({
    required this.title,
    required this.note,
    required this.items,
  });
}

class QaPlaceholderBlock extends DocBlock {
  const QaPlaceholderBlock();
}
