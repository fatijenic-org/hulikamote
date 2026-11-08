import 'package:flutter/material.dart';

/// One line (and a menu) about the road the Live Monitor learns by itself: "Learning the road 23/40 s", what it learned
/// ("Road learned: 1 crosswalk"), or why it could not. [road] is the `road` field of the backend's `/settings/video/status`
/// (or of a feed message). Re-learn and Forget act on the connected camera.
class RoadLearningChip extends StatelessWidget {
  const RoadLearningChip({super.key, required this.road, this.onRelearn, this.onForget});

  final Map<String, dynamic> road;
  final VoidCallback? onRelearn;
  final VoidCallback? onForget;

  @override
  Widget build(BuildContext context) {
    final state = (road['state'] ?? 'off') as String;
    final message = (road['message'] ?? '') as String;
    final bestEffort = (road['best_effort'] as List? ?? const []).isNotEmpty;
    final progress = ((road['progress_s'] ?? 0) as num).toDouble();
    final need = ((road['need_s'] ?? 40) as num).toDouble();

    final (colour, icon) = switch (state) {
      'learning' => (Colors.amber, Icons.school_outlined),
      'analysing' => (Colors.amber, Icons.hourglass_top),
      'ready' => (Colors.green, Icons.check_circle_outline),
      'empty' => (Colors.blueGrey, Icons.info_outline),
      'refused' || 'error' => (Colors.red, Icons.error_outline),
      _ => (Colors.grey, Icons.route_outlined),
    };
    final text = message.isEmpty ? (state == 'off' ? 'Road not learned yet' : state) : message;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: colour),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                bestEffort && state == 'ready' ? '$text (lines are best effort)' : text,
                key: const ValueKey('road-message'),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                style: TextStyle(fontSize: 12, color: colour),
              ),
            ),
            PopupMenuButton<String>(
              key: const ValueKey('road-menu'),
              tooltip: 'Road lines',
              padding: EdgeInsets.zero,
              iconSize: 16,
              icon: Icon(Icons.more_horiz, size: 16, color: colour),
              onSelected: (v) => v == 'relearn' ? onRelearn?.call() : onForget?.call(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'relearn', child: Text('Re-learn the road')),
                PopupMenuItem(value: 'forget', child: Text('Forget what was learned')),
              ],
            ),
          ],
        ),
        if (state == 'learning' && need > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 220,
              child: LinearProgressIndicator(
                key: const ValueKey('road-progress'),
                value: (progress / need).clamp(0.0, 1.0),
                minHeight: 3,
                color: colour,
              ),
            ),
          ),
      ],
    );
  }
}
