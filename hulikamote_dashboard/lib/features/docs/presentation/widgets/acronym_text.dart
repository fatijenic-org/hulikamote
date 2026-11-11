import 'package:flutter/material.dart';

import '../../domain/doc_acronyms.dart';
import '../../domain/palette/doc_palette.dart';

/// A word with a dotted underline that explains itself on hover.
class AcronymTooltip extends StatelessWidget {
  final String shown;
  final String meaning;
  final TextStyle style;
  final DocPalette palette;

  const AcronymTooltip({
    super.key,
    required this.shown,
    required this.meaning,
    required this.style,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: meaning,
      waitDuration: const Duration(milliseconds: 150),
      showDuration: const Duration(seconds: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 340),
      textStyle: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
      decoration: BoxDecoration(
        color: palette.isDark ? const Color(0xFF252525) : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Text(
        shown,
        style: style.copyWith(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: palette.accent,
        ),
      ),
    );
  }
}

class AcronymText {
  /// Splits [text] so every known acronym becomes a hover tooltip. Other text is untouched.
  /// [glossary] (from the docs site) is checked first; the built-in list is the fallback.
  static List<InlineSpan> spans(
    String text,
    TextStyle style,
    DocPalette palette, {
    Map<String, String> glossary = const {},
  }) {
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in acronymPattern.allMatches(text)) {
      final word = m.group(1)!;
      final meaning = glossary[word] ?? glossary[word.toLowerCase()] ?? acronymMeaning(word);
      if (meaning == null || meaning.isEmpty) continue;
      if (m.start > last) out.add(TextSpan(text: text.substring(last, m.start), style: style));
      out.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: AcronymTooltip(shown: word, meaning: meaning, style: style, palette: palette),
      ));
      last = m.end;
    }
    if (last == 0) return [TextSpan(text: text, style: style)];
    if (last < text.length) out.add(TextSpan(text: text.substring(last), style: style));
    return out;
  }
}
