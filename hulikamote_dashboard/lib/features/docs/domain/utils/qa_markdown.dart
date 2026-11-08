import '../models/doc_block.dart';
import '../models/doc_inline.dart';

class QaMarkdown {
  static List<DocBlock> parse(String source) {
    if (source.trim().isEmpty) return [];
    final lines = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final blocks = <DocBlock>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // 1. Fenced code block
      final codeFenceMatch = RegExp(r'^```\s*(\w*)\s*$').firstMatch(line);
      if (codeFenceMatch != null) {
        final lang = codeFenceMatch.group(1) ?? '';
        final codeLines = <CodeLine>[];
        i++;
        var lineNum = 1;
        while (i < lines.length && !RegExp(r'^```\s*$').hasMatch(lines[i])) {
          codeLines.add(CodeLine(
            n: lineNum++,
            tokens: [CodeToken(cls: '', text: lines[i])],
          ));
          i++;
        }
        if (i < lines.length) i++; // skip closing ```
        blocks.add(CodeBlock(
          path: '',
          title: lang.isNotEmpty ? lang : 'code',
          first: 1,
          last: codeLines.length,
          lines: codeLines,
          notes: const [],
        ));
        continue;
      }

      // 2. Headings (#, ##, ###)
      final headingMatch = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length + 1; // # -> h2/h3
        final text = headingMatch.group(2)!.trim();
        blocks.add(HeadingBlock(
          level: level,
          id: '',
          kicker: '',
          text: text,
        ));
        i++;
        continue;
      }

      // 3. Quotes (> quote)
      if (line.startsWith('>')) {
        final quoteLines = <String>[];
        while (i < lines.length && lines[i].startsWith('>')) {
          quoteLines.add(lines[i].replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        final innerBlocks = parse(quoteLines.join('\n'));
        blocks.add(CalloutBlock(
          kind: 'info',
          title: '',
          blocks: innerBlocks,
        ));
        continue;
      }

      // 4. Bullet & Numbered lists (- item or 1. item)
      if (RegExp(r'^\s*([-*+]|\d+[.)])\s+').hasMatch(line)) {
        final isOrdered = RegExp(r'^\s*\d+[.)]').hasMatch(line);
        final items = <List<DocInline>>[];
        while (i < lines.length && RegExp(r'^\s*([-*+]|\d+[.)])\s+').hasMatch(lines[i])) {
          final itemText = lines[i].replaceFirst(RegExp(r'^\s*([-*+]|\d+[.)])\s+'), '');
          items.add(parseInlines(itemText));
          i++;
        }
        blocks.add(ListBlock(
          ordered: isOrdered,
          items: items,
        ));
        continue;
      }

      // 5. Paragraph (accumulate consecutive non-special lines)
      final paraLines = <String>[];
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !lines[i].startsWith('```') &&
          !RegExp(r'^(#{1,4})\s+').hasMatch(lines[i]) &&
          !lines[i].startsWith('>') &&
          !RegExp(r'^\s*([-*+]|\d+[.)])\s+').hasMatch(lines[i])) {
        paraLines.add(lines[i]);
        i++;
      }
      if (paraLines.isNotEmpty) {
        blocks.add(ParagraphBlock(
          inlines: parseInlines(paraLines.join('\n')),
        ));
      }
    }

    return blocks;
  }

  static List<DocInline> parseInlines(String text) {
    final inlines = <DocInline>[];
    final regex = RegExp(
      r'(`[^`\n]+`)'
      r'|(\*\*([^*\n]+)\*\*)'
      r'|(\*([^*\n]+)\*)'
      r'|(_([^_\n]+)_)'
      r'|(\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\))',
    );

    var lastIndex = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        inlines.add(TextInline(text.substring(lastIndex, match.start)));
      }

      if (match.group(1) != null) {
        final codeText = match.group(1)!;
        inlines.add(CodeInline(codeText.substring(1, codeText.length - 1)));
      } else if (match.group(2) != null) {
        inlines.add(BoldInline([TextInline(match.group(3)!)]));
      } else if (match.group(4) != null) {
        inlines.add(ItalicInline([TextInline(match.group(5)!)]));
      } else if (match.group(6) != null) {
        inlines.add(ItalicInline([TextInline(match.group(7)!)]));
      } else if (match.group(8) != null) {
        inlines.add(LinkInline(
          href: match.group(10)!,
          children: [TextInline(match.group(9)!)],
        ));
      }
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      inlines.add(TextInline(text.substring(lastIndex)));
    }

    return inlines.isEmpty ? [TextInline(text)] : inlines;
  }
}
