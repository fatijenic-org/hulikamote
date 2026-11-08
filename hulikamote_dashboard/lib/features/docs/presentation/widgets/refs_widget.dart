import 'package:flutter/material.dart';

import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/external_apps.dart';
import '../../domain/models/doc_block.dart';
import '../../domain/palette/doc_palette.dart';

class RefsWidget extends StatelessWidget {
  final List<RefItem> items;
  final DocPalette palette;

  const RefsWidget({
    super.key,
    required this.items,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((r) => _buildRefTile(context, r)).toList(),
      ),
    );
  }

  Widget _buildRefTile(BuildContext context, RefItem r) {
    return InkWell(
      onTap: () async {
        final err = await ExternalApps.openInVsCode(r.path, line: r.line);
        if (err != null && context.mounted) {
          AppToast.show(context, err, isError: true);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r.label,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.open_in_new, size: 12, color: palette.muted),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${r.path}:${r.line}',
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 10.5,
                color: palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
