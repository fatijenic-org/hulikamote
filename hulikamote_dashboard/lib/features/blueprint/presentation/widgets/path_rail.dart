import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/reference_models.dart';

/// The ladder of one category: titles only, grouped, with the open group expanded. A dot shows where you are:
/// filled = already seen on the way up, ring = this one, hollow = still to come.
class PathRail extends StatelessWidget {
  const PathRail({
    super.key,
    required this.slices,
    required this.current,
    required this.openGroup,
    required this.onSelect,
    required this.onToggleGroup,
  });

  final List<Slice> slices;
  final int current;
  final String openGroup;
  final void Function(int index) onSelect;
  final void Function(String group) onToggleGroup;

  @override
  Widget build(BuildContext context) {
    final groups = <String>[];
    for (final s in slices) {
      if (!groups.contains(s.group)) groups.add(s.group);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Fx.s24, Fx.s16, Fx.s16, Fx.s24),
      children: [
        for (final g in groups) ...[
          _GroupHeader(
            title: g,
            count: slices.where((s) => s.group == g).length,
            open: g == openGroup,
            onTap: () => onToggleGroup(g),
          ),
          if (g == openGroup)
            for (var i = 0; i < slices.length; i++)
              if (slices[i].group == g)
                _Row(slice: slices[i], state: i < current ? _Dot.seen : (i == current ? _Dot.here : _Dot.todo), onTap: () => onSelect(i)),
          const SizedBox(height: Fx.s8),
        ],
      ],
    );
  }
}

enum _Dot { seen, here, todo }

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count, required this.open, required this.onTap});

  final String title;
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Fx.s8, horizontal: Fx.s4),
        child: Row(
          children: [
            Expanded(child: Text(title.toUpperCase(), style: Fx.label(context))),
            Text('$count', style: Fx.caption(context)),
            const SizedBox(width: Fx.s4),
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 16, color: Fx.muted(context)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.slice, required this.state, required this.onTap});

  final Slice slice;
  final _Dot state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final here = state == _Dot.here;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: here ? Fx.raised(context) : Colors.transparent,
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Fx.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: Fx.s8),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state == _Dot.seen ? Fx.accent.withValues(alpha: 0.7) : Colors.transparent,
                  border: Border.all(
                    color: state == _Dot.todo ? Fx.border(context) : Fx.accent,
                    width: here ? 2.5 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: Fx.s12),
              Expanded(
                child: Text(
                  slice.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Fx.body(context).copyWith(
                    fontSize: 13.5,
                    fontWeight: here ? FontWeight.w600 : FontWeight.w400,
                    color: here ? scheme.onSurface : (state == _Dot.seen ? Fx.muted(context) : scheme.onSurface.withValues(alpha: 0.85)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
