import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';

/// The traffic-flow controls over the live picture: show / hide the arrows of the flow the camera has learned, the Counterflow demo
/// reversal (the opposite direction counts as legal, so ordinary traffic is flagged), and "learn the flow again".
/// [flow] is what the backend reports in the camera status: `learning`, `counterflow`, `reversed`, `cells`.
class FlowControls extends StatelessWidget {
  const FlowControls({
    super.key,
    required this.flow,
    required this.showArrows,
    required this.busy,
    required this.onShowArrows,
    required this.onReverse,
    required this.onRelearn,
  });

  final Map flow;
  final bool showArrows;
  final bool busy;
  final ValueChanged<bool> onShowArrows;
  final ValueChanged<bool> onReverse;
  final VoidCallback onRelearn;

  @override
  Widget build(BuildContext context) {
    final learning = flow['learning'] == true;
    final counterflow = flow['counterflow'] == true;
    final reversed = flow['reversed'] == true;
    final cells = (flow['cells'] as num?)?.toInt() ?? 0;
    if (!learning && !counterflow) return const SizedBox.shrink();
    const note = TextStyle(color: Colors.white70, fontSize: 12);
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Fx.s8, vertical: Fx.s4),
        child: Wrap(spacing: Fx.s8, runSpacing: Fx.s4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (learning)
            FilterChip(
              key: const ValueKey('flow-arrows-toggle'),
              avatar: const Icon(Icons.alt_route, size: 16),
              label: const Text('Flow arrows'),
              tooltip: 'Show or hide the arrows of the traffic direction the camera has learned',
              selected: showArrows,
              onSelected: onShowArrows,
            ),
          if (counterflow)
            FilterChip(
              key: const ValueKey('flow-reverse-toggle'),
              avatar: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Reverse flow (demo)'),
              tooltip: 'Demo: the opposite direction counts as legal, so ordinary traffic is flagged as counterflow. '
                  'Tickets made now are tests: do not confirm or send them.',
              selected: reversed,
              onSelected: busy ? null : onReverse,
            ),
          if (learning) Text(cells == 0 ? 'Learning the flow…' : 'Flow learned', style: note),
          if (learning)
            IconButton(
              key: const ValueKey('flow-relearn'),
              tooltip: 'Learn the flow again',
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : onRelearn,
            ),
          if (reversed)
            const Text('Test on: tickets made now are tests', style: TextStyle(color: Color(0xFFFFB04D), fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
