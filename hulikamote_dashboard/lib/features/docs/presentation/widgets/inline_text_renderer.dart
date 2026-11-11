import 'package:flutter/material.dart';

import '../../domain/doc_acronyms.dart';
import '../../domain/models/doc_inline.dart';
import '../../domain/palette/doc_palette.dart';
import 'acronym_text.dart';
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
        final parts = AcronymText.spans(inline.text, baseStyle, palette, glossary: glossary);
        return parts.length == 1 ? parts.first : TextSpan(children: parts);
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
            acronymMeaning(inline.key) ??
            acronymMeaning(inline.shown) ??
            '';
        if (def.isEmpty) {
          return TextSpan(text: inline.shown, style: baseStyle);
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: AcronymTooltip(shown: inline.shown, meaning: def, style: baseStyle, palette: palette),
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
