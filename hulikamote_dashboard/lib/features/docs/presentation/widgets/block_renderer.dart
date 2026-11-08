import 'dart:io';
import 'package:flutter/material.dart';

import '../../domain/models/doc_block.dart';
import '../../domain/palette/doc_palette.dart';
import 'callout_widget.dart';
import 'card_widget.dart';
import 'chart_widgets.dart';
import 'chips_widget.dart';
import 'cmd_widget.dart';
import 'code_block_widget.dart';
import 'inline_text_renderer.dart';
import 'qa_view.dart';
import 'refs_widget.dart';
import 'table_widget.dart';

class BlockRenderer extends StatelessWidget {
  final DocBlock block;
  final DocPalette palette;
  final Map<String, String> glossary;
  final void Function(String href)? onLinkTap;
  final Directory? root;

  const BlockRenderer({
    super.key,
    required this.block,
    required this.palette,
    required this.glossary,
    this.onLinkTap,
    this.root,
  });

  @override
  Widget build(BuildContext context) {
    switch (block) {
      case HeadingBlock():
        return _buildHeading(block as HeadingBlock);
      case ParagraphBlock():
        return _buildParagraph(block as ParagraphBlock);
      case ListBlock():
        return _buildList(block as ListBlock);
      case StepsBlock():
        return _buildSteps(block as StepsBlock);
      case KvBlock():
        return _buildKv(block as KvBlock);
      case TableBlock():
        return TableWidget(
          block: block as TableBlock,
          palette: palette,
          glossary: glossary,
          onLinkTap: onLinkTap,
        );
      case CalloutBlock():
        final b = block as CalloutBlock;
        return CalloutWidget(
          kind: b.kind,
          title: b.title,
          blocks: b.blocks,
          isCollapsible: b.isCollapsible,
          isOpen: b.isOpen,
          palette: palette,
          blockBuilder: (child) => BlockRenderer(
            block: child,
            palette: palette,
            glossary: glossary,
            onLinkTap: onLinkTap,
            root: root,
          ),
        );
      case ChipsBlock():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ChipsWidget(chips: (block as ChipsBlock).chips, palette: palette),
        );
      case CmdBlock():
        return CmdWidget(text: (block as CmdBlock).text, palette: palette);
      case RefsBlock():
        return RefsWidget(items: (block as RefsBlock).items, palette: palette);
      case CodeBlock():
        return CodeBlockWidget(block: block as CodeBlock, palette: palette);
      case FigureHbarBlock():
      case FigureLineBlock():
      case FigureSceneBlock():
        return FigureWidget(
          block: block,
          palette: palette,
          glossary: glossary,
        );
      case CardBlock():
        return CardWidget(
          block: block as CardBlock,
          palette: palette,
          blockBuilder: (child) => BlockRenderer(
            block: child,
            palette: palette,
            glossary: glossary,
            onLinkTap: onLinkTap,
            root: root,
          ),
        );
      case MiniBlock():
        return _buildMini(block as MiniBlock);
      case QaPlaceholderBlock():
        return QaView(
          root: root,
          palette: palette,
          glossary: glossary,
        );
    }
  }

  Widget _buildHeading(HeadingBlock h) {
    final double fontSize = switch (h.level) {
      1 => 32.0,
      2 => 24.0,
      3 => 18.0,
      _ => 15.0,
    };

    final topMargin = switch (h.level) {
      1 => 24.0,
      2 => 32.0,
      3 => 20.0,
      _ => 14.0,
    };

    return Padding(
      padding: EdgeInsets.only(top: topMargin, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (h.kicker.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                h.kicker.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                  color: palette.muted,
                ),
              ),
            ),
          Text(
            h.text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: palette.ink,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParagraph(ParagraphBlock p) {
    final baseStyle = TextStyle(
      fontSize: p.isNote ? 13.5 : 15.0,
      color: p.isNote ? palette.ink2 : palette.ink,
      height: 1.55,
      fontStyle: p.isNote ? FontStyle.italic : FontStyle.normal,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text.rich(
        TextSpan(
          children: InlineTextRenderer.buildSpans(
            inlines: p.inlines,
            palette: palette,
            glossary: glossary,
            baseStyle: baseStyle,
            onLinkTap: onLinkTap,
          ),
        ),
      ),
    );
  }

  Widget _buildList(ListBlock l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: l.items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final bullet = l.ordered ? '${idx + 1}.' : '•';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: l.ordered ? 24 : 16,
                  child: Text(
                    bullet,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: l.ordered ? FontWeight.w600 : FontWeight.bold,
                      color: palette.ink2,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: InlineTextRenderer.buildSpans(
                        inlines: item,
                        palette: palette,
                        glossary: glossary,
                        baseStyle: TextStyle(
                          fontSize: 14.5,
                          color: palette.ink,
                          height: 1.5,
                        ),
                        onLinkTap: onLinkTap,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSteps(StepsBlock s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: s.items.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final item = entry.value;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.soft,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.accent),
                  ),
                  child: Text(
                    '$idx',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: InlineTextRenderer.buildSpans(
                        inlines: item,
                        palette: palette,
                        glossary: glossary,
                        baseStyle: TextStyle(
                          fontSize: 14.5,
                          color: palette.ink,
                          height: 1.5,
                        ),
                        onLinkTap: onLinkTap,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKv(KvBlock kv) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kv.items.map((it) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 180,
                  child: Text(
                    it.key,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.muted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: InlineTextRenderer.buildSpans(
                        inlines: it.value,
                        palette: palette,
                        glossary: glossary,
                        baseStyle: TextStyle(
                          fontSize: 14,
                          color: palette.ink,
                          height: 1.4,
                        ),
                        onLinkTap: onLinkTap,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMini(MiniBlock mini) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mini.title.isNotEmpty)
            Text(
              mini.title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: palette.ink,
              ),
            ),
          if (mini.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              mini.note,
              style: TextStyle(
                fontSize: 12.5,
                color: palette.muted,
              ),
            ),
          ],
          if (mini.items.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...mini.items.map((it) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: palette.muted, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: InlineTextRenderer.buildSpans(
                            inlines: it,
                            palette: palette,
                            glossary: glossary,
                            baseStyle: TextStyle(
                              fontSize: 12.5,
                              color: palette.ink2,
                            ),
                            onLinkTap: onLinkTap,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
