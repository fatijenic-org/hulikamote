import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/app_toast.dart';
import '../../domain/palette/doc_palette.dart';

class CmdWidget extends StatelessWidget {
  final String text;
  final DocPalette palette;

  const CmdWidget({
    super.key,
    required this.text,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.codeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 13,
                color: palette.ink,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy, size: 16, color: palette.muted),
            tooltip: 'Copy command',
            splashRadius: 18,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              AppToast.show(context, 'Command copied to clipboard');
            },
          ),
        ],
      ),
    );
  }
}
