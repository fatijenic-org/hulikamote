import 'package:flutter/material.dart';

import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/external_apps.dart';
import '../../domain/models/doc_block.dart';
import '../../domain/palette/doc_palette.dart';

class CodeBlockWidget extends StatelessWidget {
  final CodeBlock block;
  final DocPalette palette;

  const CodeBlockWidget({
    super.key,
    required this.block,
    required this.palette,
  });

  static const List<String> _badgeChars = [
    '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩', '⑪', '⑫'
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (block.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                block.title,
                style: TextStyle(
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: palette.codeBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header (file, lines range, Open in VS Code button)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    border: Border(bottom: BorderSide(color: palette.border)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        block.path,
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'lines ${block.first}-${block.last}',
                        style: TextStyle(
                          fontSize: 12.0,
                          color: palette.muted,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () async {
                          final err = await ExternalApps.openInVsCode(
                            block.path,
                            line: block.first,
                          );
                          if (err != null && context.mounted) {
                            AppToast.show(context, err, isError: true);
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Open in VS Code',
                                style: TextStyle(
                                  fontSize: 12.0,
                                  fontWeight: FontWeight.w600,
                                  color: palette.accent,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.open_in_new, size: 12, color: palette.accent),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Code body
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: block.lines.map((line) => _buildCodeLine(line)).toList(),
                    ),
                  ),
                ),
                // Numbered explanation notes list (ol.walk)
                if (block.notes.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      border: Border(top: BorderSide(color: palette.border)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: block.notes.map((note) => _buildNoteItem(note)).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeLine(CodeLine line) {
    final lineNumberText = line.n != null ? '${line.n}' : '';
    final badgeChar = (line.mark != null && line.mark! > 0 && line.mark! <= _badgeChars.length)
        ? _badgeChars[line.mark! - 1]
        : '';

    Color? lineBg;
    if (line.isHot) {
      lineBg = palette.colorMix(palette.s4, 0.14, Colors.transparent);
    }

    final lineContent = Container(
      color: lineBg,
      padding: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Line number gutter
          SizedBox(
            width: 44,
            child: Text(
              lineNumberText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12.5,
                color: palette.muted,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Code tokens
          if (line.isGap)
            Text(
              '    ...',
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12.5,
                color: palette.muted,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Text.rich(
              TextSpan(
                children: line.tokens.map((t) {
                  final color = palette.tokenColor(t.cls);
                  final isBold = t.cls == 'fn' || t.cls == 'cls' || t.cls == 'kw';
                  final isItalic = t.cls == 'com' || t.cls == 'doc';
                  return TextSpan(
                    text: t.text,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12.5,
                      color: color,
                      fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
                      fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                    ),
                  );
                }).toList(),
              ),
            ),
          if (badgeChar.isNotEmpty) ...[
            const SizedBox(width: 14),
            Text(
              badgeChar,
              style: TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.bold,
                color: palette.accent,
              ),
            ),
          ],
        ],
      ),
    );

    return lineContent;
  }

  Widget _buildNoteItem(CodeNote note) {
    final badgeChar = (note.mark > 0 && note.mark <= _badgeChars.length)
        ? _badgeChars[note.mark - 1]
        : '${note.mark}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            badgeChar,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: palette.accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'line ${note.line}',
            style: TextStyle(
              fontSize: 12.5,
              color: palette.muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note.text,
              style: TextStyle(
                fontSize: 14.0,
                color: palette.ink,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
