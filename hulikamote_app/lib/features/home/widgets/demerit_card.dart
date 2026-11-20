import 'package:flutter/material.dart';

import '../../../core/ui/app_theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets.dart';
import '../models/appeal_state.dart';
import '../models/demerit.dart';
import '../models/violation.dart';

/// The demerit points at the top of Records: the number, what they are made of, and what does not count.
class DemeritCard extends StatelessWidget {
  const DemeritCard({super.key, required this.demerit});

  final Demerit demerit;

  @override
  Widget build(BuildContext context) {
    final d = demerit;
    final clear = d.points == 0;
    final s = context.status;
    final (Color back, Color front) = clear ? (s.success, s.onSuccess) : (s.warning, s.onWarning);
    return Semantics(
      label: 'Demerit points: ${d.points}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Sp.x4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ExcludeSemantics(
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: back, shape: BoxShape.circle),
                  child: Text('${d.points}', style: context.text.headlineMedium?.copyWith(color: front, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: Sp.x4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Demerit points', style: context.text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    clear ? 'None. Nothing confirmed on your record.' : (d.points == 1 ? '1 confirmed ticket counts.' : '${d.points} confirmed tickets count.'),
                    style: context.text.bodyMedium?.copyWith(color: context.muted),
                  ),
                ]),
              ),
            ]),
            if (d.byClass.isNotEmpty) ...[
              const SizedBox(height: Sp.x3),
              Wrap(spacing: Sp.x2, runSpacing: Sp.x2, children: [
                for (final e in d.byClass.entries)
                  StatusChip(label: '${Violation.labelOf(e.key)} · ${e.value}', tone: Tone.neutral, icon: iconForViolation(e.key)),
              ]),
            ],
            if (d.byPlate.isNotEmpty) ...[
              const SizedBox(height: Sp.x3),
              Wrap(spacing: Sp.x2, runSpacing: Sp.x2, children: [
                for (final e in d.byPlate.entries) StatusChip(label: '${e.key} · ${e.value}', tone: Tone.info, icon: Icons.directions_car_outlined),
              ]),
            ],
            if (d.cancelled > 0) ...[
              const SizedBox(height: Sp.x3),
              Row(children: [
                Icon(Icons.check_circle_outline, size: 18, color: s.onSuccess),
                const SizedBox(width: Sp.x2),
                Expanded(
                  child: Text(
                    d.cancelled == 1 ? '1 ticket was cancelled after your appeal. It does not count.' : '${d.cancelled} tickets were cancelled after your appeals. They do not count.',
                    style: context.text.bodyMedium,
                  ),
                ),
              ]),
            ],
            const SizedBox(height: Sp.x3),
            Text('One point for each confirmed ticket. This is a prototype count and has no legal weight.', style: context.text.bodyMedium?.copyWith(color: context.muted)),
          ]),
        ),
      ),
    );
  }
}
