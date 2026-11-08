import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/models/doc_block.dart';
import '../../domain/models/doc_inline.dart';
import '../../domain/palette/doc_palette.dart';
import 'inline_text_renderer.dart';
import 'scene_painter.dart';

class FigureWidget extends StatelessWidget {
  final DocBlock block;
  final DocPalette palette;
  final Map<String, String> glossary;

  const FigureWidget({
    super.key,
    required this.block,
    required this.palette,
    required this.glossary,
  });

  @override
  Widget build(BuildContext context) {
    Widget chartWidget = const SizedBox.shrink();
    List<DocInline> caption = const [];

    if (block is FigureHbarBlock) {
      final b = block as FigureHbarBlock;
      caption = b.caption;
      chartWidget = HbarChartWidget(block: b, palette: palette);
    } else if (block is FigureLineBlock) {
      final b = block as FigureLineBlock;
      caption = b.caption;
      chartWidget = LineChartWidget(block: b, palette: palette);
    } else if (block is FigureSceneBlock) {
      final b = block as FigureSceneBlock;
      caption = b.caption;
      final scene = b.scene;
      final aspect = (scene.w > 0 && scene.h > 0) ? (scene.w / scene.h) : (760.0 / 240.0);
      chartWidget = AspectRatio(
        aspectRatio: aspect,
        child: CustomPaint(
          painter: DocScenePainter(scene: scene, palette: palette),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 18),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chartWidget,
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text.rich(
                TextSpan(
                  children: InlineTextRenderer.buildSpans(
                    inlines: caption,
                    palette: palette,
                    glossary: glossary,
                    baseStyle: TextStyle(
                      fontSize: 13.0,
                      color: palette.ink2,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HbarChartWidget extends StatelessWidget {
  final FigureHbarBlock block;
  final DocPalette palette;

  const HbarChartWidget({
    super.key,
    required this.block,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final seriesColors = [
      palette.s1, palette.s2, palette.s3, palette.s4,
      palette.s5, palette.s6, palette.s7, palette.s8,
    ];

    final vmax = block.vmax > 0 ? block.vmax : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Legend
        if (block.series.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: block.series.asMap().entries.map((entry) {
                final idx = entry.key;
                final name = entry.value;
                final color = seriesColors[idx % seriesColors.length];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        // Grouped bars
        ...block.groups.map((group) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Group label
                SizedBox(
                  width: math.min(180, block.labelW),
                  child: Text(
                    group.label,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: palette.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Axis line
                Container(
                  width: 1.5,
                  height: group.values.length * 18.0 + 4,
                  color: palette.axis,
                ),
                const SizedBox(width: 8),
                // Bars
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: group.values.asMap().entries.map((vEntry) {
                      final sIdx = vEntry.key;
                      final val = vEntry.value;
                      final ratio = (val / vmax).clamp(0.0, 1.0);
                      final color = seriesColors[sIdx % seriesColors.length];
                      final valText = val >= 1000
                          ? '${val.toInt()}'
                          : (val == val.toInt() ? '${val.toInt()}' : val.toStringAsFixed(1));

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.5),
                        child: Row(
                          children: [
                            Expanded(
                              flex: (ratio * 1000).toInt(),
                              child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: math.max(1, ((1.0 - ratio) * 1000).toInt()),
                              child: const SizedBox.shrink(),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              valText,
                              style: TextStyle(
                                fontSize: 12.0,
                                color: palette.ink,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class LineChartWidget extends StatelessWidget {
  final FigureLineBlock block;
  final DocPalette palette;

  const LineChartWidget({
    super.key,
    required this.block,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final seriesColors = [
      palette.s1, palette.s2, palette.s3, palette.s4,
      palette.s5, palette.s6, palette.s7, palette.s8,
    ];

    final lineBars = block.series.asMap().entries.map((entry) {
      final sIdx = entry.key;
      final series = entry.value;
      final color = seriesColors[sIdx % seriesColors.length];
      final spots = series.points.map((p) => FlSpot(p.x, p.y)).toList();

      return LineChartBarData(
        spots: spots,
        isCurved: false,
        color: color,
        barWidth: 2.2,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
      );
    }).toList();

    final extraLines = block.hlines.map((h) {
      return HorizontalLine(
        y: h.value,
        color: palette.muted,
        strokeWidth: 1.2,
        dashArray: [6, 4],
        label: HorizontalLineLabel(
          show: true,
          alignment: Alignment.topRight,
          padding: const EdgeInsets.only(right: 6, bottom: 2),
          style: TextStyle(
            color: palette.muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          labelResolver: (_) => h.name,
        ),
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Legend & end labels
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 16,
            children: block.series.asMap().entries.map((entry) {
              final sIdx = entry.key;
              final series = entry.value;
              final color = seriesColors[sIdx % seriesColors.length];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 3,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    series.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: palette.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        SizedBox(
          height: 280,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: block.xmax > 0 ? block.xmax : 100,
              minY: 0,
              maxY: block.ymax > 0 ? block.ymax : 1.0,
              extraLinesData: ExtraLinesData(horizontalLines: extraLines),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: palette.grid,
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  axisNameWidget: block.ylabel.isNotEmpty
                      ? Text(
                          block.ylabel,
                          style: TextStyle(fontSize: 11.5, color: palette.muted),
                        )
                      : null,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (val, meta) => Text(
                      val.toStringAsFixed(1),
                      style: TextStyle(color: palette.muted, fontSize: 11),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: Text(
                    block.xlabel,
                    style: TextStyle(fontSize: 11.5, color: palette.muted),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (val, meta) => Text(
                      val.toInt().toString(),
                      style: TextStyle(color: palette.muted, fontSize: 11),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(color: palette.axis, width: 1.2),
                  bottom: BorderSide(color: palette.axis, width: 1.2),
                ),
              ),
              lineBarsData: lineBars,
            ),
          ),
        ),
      ],
    );
  }
}
