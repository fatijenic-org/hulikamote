import 'package:flutter/material.dart';

import '../../features/forensic/presentation/widgets/fx.dart';

/// Pieces every officer page shares, so the pages read as one product: the same title block, the same number tiles,
/// the same loading and failure states. They are built on the [Fx] tokens (one spacing scale, one radius, one set of
/// status colours) that the Forensic Analyzer already uses.

/// Page title, one sentence of what the page is for, and the page's actions on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Fx.s16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: Fx.title(context))),
            if (subtitle != null) ...[
              const SizedBox(height: Fx.s4),
              Text(subtitle!, style: Fx.caption(context)),
            ],
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

/// One number with its name. A null [value] means "could not be loaded" and shows a dash, never a wrong zero.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = Fx.accent,
    this.hint,
    this.loading = false,
    this.onTap,
  });

  final String label;
  final int? value;
  final IconData icon;
  final Color color;

  /// A short line under the number ("waiting for a decision").
  final String? hint;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shown = loading ? '' : (value?.toString() ?? '—');
    return Semantics(
      container: true,
      button: onTap != null,
      label: '$label: ${loading ? 'loading' : (value?.toString() ?? 'not available')}${hint == null ? '' : ', $hint'}',
      excludeSemantics: true,
      child: FxCard(
        onTap: onTap,
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Fx.radiusSm)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: Fx.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              loading
                  ? const SkeletonBox(height: 26, width: 48, radius: 6)
                  : Text(shown, style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w700, height: 1.1)),
              const SizedBox(height: Fx.s4),
              Text(label, style: Fx.body(context), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (hint != null) Text(hint!, style: Fx.caption(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (onTap != null) Icon(Icons.chevron_right, color: Fx.muted(context)),
        ]),
      ),
    );
  }
}

/// A failure that fills the page: what went wrong in plain words and a way to try again.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, required this.onRetry, this.title = 'Could not load this page'});

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: title,
      message: message,
      action: FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Try again')),
    );
  }
}

/// Grey rows that pulse while a list loads, so the page does not jump when the data arrives.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 5, this.height = 64});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(height: Fx.s8),
          itemBuilder: (_, _) => SkeletonBox(height: height, radius: Fx.radius),
        ),
      ),
    );
  }
}

/// "5 minutes ago", "yesterday", or the date when it is older: what an officer scans for.
String ago(DateTime? at, {DateTime? now}) {
  if (at == null) return 'unknown time';
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)}';
}
