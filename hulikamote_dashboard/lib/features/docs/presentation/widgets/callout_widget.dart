import 'package:flutter/material.dart';

import '../../domain/models/doc_block.dart';
import '../../domain/palette/doc_palette.dart';

class CalloutWidget extends StatefulWidget {
  final String kind;
  final String title;
  final List<DocBlock> blocks;
  final bool isCollapsible;
  final bool isOpen;
  final DocPalette palette;
  final Widget Function(DocBlock block) blockBuilder;

  const CalloutWidget({
    super.key,
    required this.kind,
    required this.title,
    required this.blocks,
    this.isCollapsible = false,
    this.isOpen = true,
    required this.palette,
    required this.blockBuilder,
  });

  @override
  State<CalloutWidget> createState() => _CalloutWidgetState();
}

class _CalloutWidgetState extends State<CalloutWidget> {
  late bool _isOpen;

  @override
  void initState() {
    super.initState();
    _isOpen = widget.isOpen;
  }

  @override
  void didUpdateWidget(covariant CalloutWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isOpen != widget.isOpen) {
      _isOpen = widget.isOpen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final barColor = palette.chipColor(widget.kind);
    final iconData = switch (widget.kind) {
      'ok' => Icons.check_circle_outline,
      'warn' => Icons.warning_amber_rounded,
      'bad' => Icons.error_outline,
      _ => Icons.info_outline,
    };

    final headerRow = Row(
      children: [
        Icon(iconData, size: 18, color: barColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: palette.ink,
            ),
          ),
        ),
        if (widget.isCollapsible)
          Icon(
            _isOpen ? Icons.expand_less : Icons.expand_more,
            size: 20,
            color: palette.muted,
          ),
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: barColor, width: 5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.title.isNotEmpty)
                widget.isCollapsible
                    ? InkWell(
                        onTap: () => setState(() => _isOpen = !_isOpen),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: headerRow,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: headerRow,
                      ),
              if (!widget.isCollapsible || _isOpen) ...[
                if (widget.title.isNotEmpty) const SizedBox(height: 6),
                ...widget.blocks.map(widget.blockBuilder),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
