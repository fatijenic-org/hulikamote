import 'package:flutter/material.dart';

import '../../domain/models/doc_block.dart';
import '../../domain/palette/doc_palette.dart';

class ChipPill extends StatelessWidget {
  final String kind;
  final String text;
  final DocPalette palette;

  const ChipPill({
    super.key,
    required this.kind,
    required this.text,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final color = palette.chipColor(kind);
    final iconChar = switch (kind) {
      'ok' => '✓',
      'warn' => '!',
      'bad' => '✕',
      'info' => 'i',
      _ => '–',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Text(
              iconChar,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChipsWidget extends StatelessWidget {
  final List<ChipItem> chips;
  final DocPalette palette;

  const ChipsWidget({
    super.key,
    required this.chips,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: chips
          .map((c) => ChipPill(kind: c.kind, text: c.text, palette: palette))
          .toList(),
    );
  }
}
