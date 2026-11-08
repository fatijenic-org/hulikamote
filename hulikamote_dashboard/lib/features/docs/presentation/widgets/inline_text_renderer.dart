import 'package:flutter/material.dart';

import '../../domain/models/doc_inline.dart';
import '../../domain/palette/doc_palette.dart';
import 'chips_widget.dart';

class InlineTextRenderer {
  static List<InlineSpan> buildSpans({
    required List<DocInline> inlines,
    required DocPalette palette,
    required Map<String, String> glossary,
    required TextStyle baseStyle,
    void Function(String href)? onLinkTap,
  }) {
    final spans = <InlineSpan>[];

    for (final inline in inlines) {
      spans.add(_buildSpan(
        inline: inline,
        palette: palette,
        glossary: glossary,
        baseStyle: baseStyle,
        onLinkTap: onLinkTap,
      ));
    }

    return spans;
  }

  static InlineSpan _buildSpan({
    required DocInline inline,
    required DocPalette palette,
    required Map<String, String> glossary,
    required TextStyle baseStyle,
    void Function(String href)? onLinkTap,
  }) {
    switch (inline) {
      case TextInline():
        return TextSpan(text: inline.text, style: baseStyle);
      case BoldInline():
        return TextSpan(
          children: buildSpans(
            inlines: inline.children,
            palette: palette,
            glossary: glossary,
            baseStyle: baseStyle.copyWith(fontWeight: FontWeight.bold),
            onLinkTap: onLinkTap,
          ),
        );
      case ItalicInline():
        return TextSpan(
          children: buildSpans(
            inlines: inline.children,
            palette: palette,
            glossary: glossary,
            baseStyle: baseStyle.copyWith(fontStyle: FontStyle.italic),
            onLinkTap: onLinkTap,
          ),
        );
      case StrikeInline():
        return TextSpan(
          children: buildSpans(
            inlines: inline.children,
            palette: palette,
            glossary: glossary,
            baseStyle: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
            onLinkTap: onLinkTap,
          ),
        );
      case CodeInline():
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: palette.codeBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: palette.border, width: 0.5),
            ),
            child: Text(
              inline.text,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: (baseStyle.fontSize ?? 14.0) * 0.92,
                color: palette.ink,
              ),
            ),
          ),
        );
      case LinkInline():
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: InkWell(
            onTap: onLinkTap != null ? () => onLinkTap(inline.href) : null,
            child: Text.rich(
              TextSpan(
                children: buildSpans(
                  inlines: inline.children,
                  palette: palette,
                  glossary: glossary,
                  baseStyle: baseStyle.copyWith(
                    color: palette.accent,
                    decoration: TextDecoration.underline,
                  ),
                  onLinkTap: onLinkTap,
                ),
              ),
            ),
          ),
        );
      case TermInline():
        final def = glossary[inline.key] ??
            glossary[inline.key.toLowerCase()] ??
            glossary[inline.shown] ??
            '';
        if (def.isEmpty) {
          return TextSpan(text: inline.shown, style: baseStyle);
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Tooltip(
            message: def,
            waitDuration: const Duration(milliseconds: 150),
            showDuration: const Duration(seconds: 5),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            decoration: BoxDecoration(
              color: palette.isDark ? const Color(0xFF252525) : const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))
              ],
            ),
            child: Text(
              inline.shown,
              style: baseStyle.copyWith(
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
                decorationColor: palette.accent,
              ),
            ),
          ),
        );
      case ChipInline():
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ChipPill(kind: inline.kind, text: inline.text, palette: palette),
          ),
        );
      case BrInline():
        return const TextSpan(text: '\n');
    }
  }
}
