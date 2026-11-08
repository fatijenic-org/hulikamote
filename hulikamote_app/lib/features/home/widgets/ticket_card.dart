import 'package:flutter/material.dart';

import '../../../core/services/photo_source.dart';
import '../../../core/ui/app_theme.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets.dart';
import '../models/appeal_state.dart';
import '../models/violation.dart';

/// A small picture of the ticket: its first photo, or an icon for the violation when there is none (or it cannot load).
class TicketThumb extends StatelessWidget {
  const TicketThumb(this.violation, {super.key, this.size = 56});

  final Violation violation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: context.colors.primaryContainer,
      child: Icon(iconForViolation(violation.cls), color: context.colors.onPrimaryContainer, size: size * 0.45),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Rd.md),
        child: SizedBox(
          width: size,
          height: size,
          child: violation.evidencePaths.isEmpty
              ? fallback
              : Image.network(
                  PhotoSource.url(violation.evidencePaths.first),
                  headers: PhotoSource.headers,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 3).round(),
                  errorBuilder: (_, __, ___) => fallback,
                  loadingBuilder: (context, child, progress) => progress == null ? child : Skeleton(height: size, width: size, radius: 0),
                ),
        ),
      ),
    );
  }
}

/// One ticket in the list: photo, what it is, when, and where its appeal stands.
class TicketCard extends StatelessWidget {
  const TicketCard({super.key, required this.violation, required this.appealStatus, required this.onTap});

  final Violation violation;
  final String? appealStatus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = AppealState.of(appealStatus);
    final when = dateTimeOf(violation.time, violation.timestamp);
    final detail = violation.plate.isEmpty ? when : '$when · ${violation.plate}';
    return Semantics(
      button: true,
      label: '${violation.displayClass}, $detail, ${state.label}',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Sp.x3),
            child: Row(children: [
              TicketThumb(violation),
              const SizedBox(width: Sp.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(violation.displayClass, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(detail, style: context.text.bodyMedium?.copyWith(color: context.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: Sp.x2),
                  StatusChip(label: state.label, tone: state.tone, icon: state.icon),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: context.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
