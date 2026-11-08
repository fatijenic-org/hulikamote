import 'package:flutter/material.dart';

import '../../domain/models/doc_block.dart';
import '../../domain/palette/doc_palette.dart';
import 'chips_widget.dart';
import 'scene_painter.dart';

class CardWidget extends StatelessWidget {
  final CardBlock block;
  final DocPalette palette;
  final Widget Function(DocBlock block) blockBuilder;

  const CardWidget({
    super.key,
    required this.block,
    required this.palette,
    required this.blockBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Name, key, and chips
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                block.name,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.codeBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  block.key,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12.5,
                    color: palette.muted,
                  ),
                ),
              ),
              ...block.chips.map(
                (c) => ChipPill(kind: c.kind, text: c.text, palette: palette),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // 2-column or 1-column layout
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 760;

              final leftColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: block.gridLeft.map(blockBuilder).toList(),
              );

              final rightColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (block.sketch != null) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: palette.border),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: AspectRatio(
                        aspectRatio: 330.0 / 170.0,
                        child: CustomPaint(
                          painter: DocScenePainter(
                            scene: block.sketch!,
                            palette: palette,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ...block.gridRight.map(blockBuilder),
                ],
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: leftColumn),
                    const SizedBox(width: 24),
                    SizedBox(width: 340, child: rightColumn),
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    leftColumn,
                    const SizedBox(height: 16),
                    rightColumn,
                  ],
                );
              }
            },
          ),
          // Bottom full-width sections (Heuristic numbers table, limits, code blocks)
          if (block.bottom.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...block.bottom.map(blockBuilder),
          ],
        ],
      ),
    );
  }
}
