import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../domain/models/doc_block.dart';
import '../../domain/palette/doc_palette.dart';
import 'inline_text_renderer.dart';

class TableWidget extends StatelessWidget {
  final TableBlock block;
  final DocPalette palette;
  final Map<String, String> glossary;
  final void Function(String href)? onLinkTap;

  const TableWidget({
    super.key,
    required this.block,
    required this.palette,
    required this.glossary,
    this.onLinkTap,
  });

  Map<int, TableColumnWidth> _computeColumnWidths(int numCols, double availableWidth) {
    final widths = <int, TableColumnWidth>{};

    // Check if block.widths provides valid percentage widths
    final parsedPercentages = <double>[];
    for (final w in block.widths) {
      final clean = w.trim().replaceAll('%', '');
      final val = double.tryParse(clean);
      if (val != null && w.contains('%')) {
        parsedPercentages.add(val / 100.0);
      }
    }

    if (parsedPercentages.length == numCols) {
      // Scale percentages so they sum to 1.0 if needed
      final sumPct = parsedPercentages.reduce((a, b) => a + b);
      final normalized = sumPct > 0
          ? parsedPercentages.map((p) => p / sumPct).toList()
          : parsedPercentages;

      // Minimum readable column widths to prevent words collapsing to single-word lines
      final minColWidths = normalized.map((pct) {
        if (pct <= 0.04) return 45.0;   // for '#' or index badge
        if (pct <= 0.08) return 75.0;   // for numbers, small tags
        if (pct <= 0.12) return 120.0;  // for short status / chips
        if (pct <= 0.20) return 150.0;  // for medium columns (dates, states, kinds)
        if (pct <= 0.35) return 180.0;  // for title / category / model
        return 240.0;                   // for descriptions / main content
      }).toList();

      final minTotal = minColWidths.reduce((a, b) => a + b);
      final targetWidth = math.max(availableWidth, minTotal);

      var sumW = 0.0;
      final rawWidths = <double>[];
      for (var i = 0; i < numCols; i++) {
        final calculated = targetWidth * normalized[i];
        final colW = math.max(minColWidths[i], calculated);
        rawWidths.add(colW);
        sumW += colW;
      }

      if (sumW < availableWidth && sumW > 0) {
        final scale = availableWidth / sumW;
        for (var i = 0; i < numCols; i++) {
          widths[i] = FixedColumnWidth(rawWidths[i] * scale);
        }
      } else {
        for (var i = 0; i < numCols; i++) {
          widths[i] = FixedColumnWidth(rawWidths[i]);
        }
      }
      return widths;
    }

    // Heuristic column distribution when block.widths is absent or mismatched
    final List<double> fractions;
    final List<double> minCols;

    if (numCols == 2) {
      fractions = [0.35, 0.65];
      minCols = [160.0, 260.0];
    } else if (numCols == 3) {
      fractions = [0.25, 0.45, 0.30];
      minCols = [130.0, 220.0, 160.0];
    } else if (numCols == 4) {
      fractions = [0.20, 0.40, 0.18, 0.22];
      minCols = [120.0, 220.0, 100.0, 120.0];
    } else {
      fractions = List.filled(numCols, 1.0 / numCols);
      minCols = List.filled(numCols, 120.0);
    }

    final minTotal = minCols.reduce((a, b) => a + b);
    final targetWidth = math.max(availableWidth, minTotal);

    var sumW = 0.0;
    final rawWidths = <double>[];
    for (var i = 0; i < numCols; i++) {
      final colW = math.max(minCols[i], targetWidth * fractions[i]);
      rawWidths.add(colW);
      sumW += colW;
    }

    if (sumW < availableWidth && sumW > 0) {
      final scale = availableWidth / sumW;
      for (var i = 0; i < numCols; i++) {
        widths[i] = FixedColumnWidth(rawWidths[i] * scale);
      }
    } else {
      for (var i = 0; i < numCols; i++) {
        widths[i] = FixedColumnWidth(rawWidths[i]);
      }
    }

    return widths;
  }

  double _computeTotalWidth(Map<int, TableColumnWidth> colWidths) {
    var total = 0.0;
    for (final w in colWidths.values) {
      if (w is FixedColumnWidth) {
        total += w.value;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final cellPadding = block.isDense
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    final fontSize = block.isDense ? 13.0 : 14.0;

    final numCols = block.headers.isNotEmpty
        ? block.headers.length
        : (block.rows.isNotEmpty ? block.rows.first.length : 0);
    if (numCols == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 800.0;

        final columnWidths = _computeColumnWidths(numCols, availableWidth);
        final totalTableWidth = _computeTotalWidth(columnWidths);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalTableWidth,
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: columnWidths,
                border: TableBorder(
                  horizontalInside: BorderSide(color: palette.grid, width: 1),
                ),
                children: [
                  if (block.headers.isNotEmpty)
                    TableRow(
                      decoration: BoxDecoration(
                        color: palette.page,
                        border: Border(bottom: BorderSide(color: palette.grid, width: 1.5)),
                      ),
                      children: block.headers.map((h) {
                        return Padding(
                          padding: cellPadding,
                          child: Text.rich(
                            TextSpan(
                              children: InlineTextRenderer.buildSpans(
                                inlines: h,
                                palette: palette,
                                glossary: glossary,
                                baseStyle: TextStyle(
                                  fontSize: fontSize - 1,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: palette.muted,
                                ),
                                onLinkTap: onLinkTap,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ...block.rows.asMap().entries.map((rowEntry) {
                    final rIdx = rowEntry.key;
                    final row = rowEntry.value;
                    final rowClasses = (rIdx < block.cellClasses.length)
                        ? block.cellClasses[rIdx]
                        : const <String>[];

                    return TableRow(
                      children: row.asMap().entries.map((cellEntry) {
                        final cIdx = cellEntry.key;
                        final cell = cellEntry.value;
                        final cClasses = (cIdx < rowClasses.length) ? rowClasses[cIdx] : '';

                        Color? cellBg;
                        TextAlign align = TextAlign.left;

                        if (cClasses.contains('n')) {
                          align = TextAlign.right;
                        }

                        if (block.isHeat) {
                          if (cClasses.contains('y')) {
                            cellBg = palette.colorMix(palette.s1, 0.22, palette.surface);
                            align = TextAlign.center;
                          } else if (cClasses.contains('m')) {
                            cellBg = palette.colorMix(palette.s4, 0.22, palette.surface);
                            align = TextAlign.center;
                          } else if (cClasses.contains('o')) {
                            align = TextAlign.center;
                          }
                        }

                        Widget content = Padding(
                          padding: cellPadding,
                          child: Text.rich(
                            TextSpan(
                              children: InlineTextRenderer.buildSpans(
                                inlines: cell,
                                palette: palette,
                                glossary: glossary,
                                baseStyle: TextStyle(
                                  fontSize: fontSize,
                                  color: cClasses.contains('o') ? palette.muted : palette.ink,
                                  fontWeight: cClasses.contains('y') ? FontWeight.bold : FontWeight.normal,
                                ),
                                onLinkTap: onLinkTap,
                              ),
                            ),
                            textAlign: align,
                          ),
                        );

                        if (cellBg != null) {
                          content = Container(color: cellBg, child: content);
                        }

                        return content;
                      }).toList(),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
