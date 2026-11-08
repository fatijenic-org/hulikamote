import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/reference_data.dart';
import '../../domain/reference_models.dart';

/// "this + this = that": the small pieces a slice is made of, as chips. Tapping a piece jumps to it.
class RecipeStrip extends StatelessWidget {
  const RecipeStrip({super.key, required this.slice, required this.onJump});

  final Slice slice;
  final void Function(String id) onJump;

  @override
  Widget build(BuildContext context) {
    final parts = [for (final id in slice.recipe) ReferenceData.byId(id)].whereType<Slice>().toList();
    if (parts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MADE OF', style: Fx.label(context)),
        const SizedBox(height: Fx.s8),
        Wrap(
          spacing: Fx.s8,
          runSpacing: Fx.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) _sign(context, '+'),
              _Chip(label: parts[i].short, onTap: () => onJump(parts[i].id)),
            ],
            _sign(context, '='),
            _Chip(label: slice.makes ?? slice.title, result: true),
          ],
        ),
      ],
    );
  }

  Widget _sign(BuildContext context, String text) =>
      Text(text, style: Fx.heading(context).copyWith(color: Fx.muted(context), fontWeight: FontWeight.w400));
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.onTap, this.result = false});

  final String label;
  final VoidCallback? onTap;
  final bool result;

  @override
  Widget build(BuildContext context) {
    final accent = Fx.accent;
    return Material(
      color: result ? accent.withValues(alpha: 0.14) : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: result ? accent.withValues(alpha: 0.55) : Fx.border(context))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Fx.s12, vertical: 7),
          child: Text(
            label,
            style: Fx.body(context).copyWith(
              fontSize: 13,
              fontWeight: result ? FontWeight.w600 : FontWeight.w400,
              color: result ? accent : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
