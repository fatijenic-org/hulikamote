import 'package:flutter/material.dart';

import '../../domain/review_controller.dart';
import '../../domain/violation_catalog.dart';
import 'fx.dart';

/// One chip per violation found in this analysis. Pick one or more to show only those: the ticket list, the video
/// timeline and the open ticket all follow (the same filter as the list's "Violation" menu). "All" shows everything again.
class ViolationFilterBar extends StatelessWidget {
  const ViolationFilterBar({super.key, required this.controller});

  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final counts = controller.violationCounts;
        if (counts.isEmpty) return const SizedBox.shrink();
        final active = controller.violationFilter;
        return Padding(
          padding: const EdgeInsets.only(top: Fx.s8),
          child: SingleChildScrollView(
            key: const ValueKey('violation-filter-bar'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  key: const ValueKey('violation-chip-all'),
                  label: Text('All (${controller.all.length})'),
                  selected: active.isEmpty,
                  onSelected: (_) => controller.clearViolationFilter(),
                ),
                for (final k in counts.keys)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: FilterChip(
                      key: ValueKey('violation-chip-$k'),
                      label: Text('${ViolationCatalog.of(k).label} (${counts[k]})'),
                      selected: active.contains(k),
                      onSelected: (_) => controller.toggleViolationFilter(k),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
