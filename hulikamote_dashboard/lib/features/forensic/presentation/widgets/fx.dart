import 'package:flutter/material.dart';

import '../../domain/forensic_models.dart';
import '../../domain/violation_catalog.dart';

/// Design tokens and small shared pieces for the forensic feature.
/// One spacing scale (4/8/12/16/24/32), one radius, one set of status colours.
class Fx {
  Fx._();

  static const double s4 = 4, s8 = 8, s12 = 12, s16 = 16, s24 = 24, s32 = 32;
  static const double radius = 12, radiusSm = 8;

  /// Same accent as the app's navigation.
  static const Color accent = Colors.blueAccent;
  static const Color success = Color(0xFF4CC38A);
  static const Color danger = Color(0xFFFF6B6B);
  static const Color warning = Color(0xFFFFB454);

  static Color page(BuildContext c) => Theme.of(c).colorScheme.surfaceContainerLowest;
  static Color panel(BuildContext c) => Theme.of(c).colorScheme.surfaceContainerLow;
  static Color raised(BuildContext c) => Theme.of(c).colorScheme.surfaceContainer;
  static Color border(BuildContext c) => Theme.of(c).colorScheme.outlineVariant;
  static Color muted(BuildContext c) => Theme.of(c).colorScheme.onSurfaceVariant;

  static TextStyle title(BuildContext c) =>
      Theme.of(c).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2);
  static TextStyle heading(BuildContext c) =>
      Theme.of(c).textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w600, fontSize: 15);
  static TextStyle body(BuildContext c) => Theme.of(c).textTheme.bodyMedium!.copyWith(fontSize: 14);
  static TextStyle caption(BuildContext c) =>
      Theme.of(c).textTheme.bodySmall!.copyWith(fontSize: 12, color: muted(c));
  static TextStyle label(BuildContext c) => Theme.of(c).textTheme.labelSmall!.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: muted(c),
      );
  static const TextStyle plate = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: ['Courier New', 'monospace'],
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  static Color statusColor(ReviewStatus s) => switch (s) {
        ReviewStatus.pending => const Color(0xFF9AA5B1),
        ReviewStatus.confirmed => success,
        ReviewStatus.rejected => danger,
      };

  static IconData statusIcon(ReviewStatus s) => switch (s) {
        ReviewStatus.pending => Icons.radio_button_unchecked,
        ReviewStatus.confirmed => Icons.check_circle,
        ReviewStatus.rejected => Icons.cancel,
      };

  static String statusLabel(ReviewStatus s) => switch (s) {
        ReviewStatus.pending => 'To review',
        ReviewStatus.confirmed => 'Confirmed',
        ReviewStatus.rejected => 'False alarm',
      };
}

/// A bordered surface. [selected] gives it the accent outline used for the open item.
class FxCard extends StatelessWidget {
  const FxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Fx.s16),
    this.selected = false,
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Fx.radius),
      side: BorderSide(color: selected ? Fx.accent : Fx.border(context), width: selected ? 1.5 : 1),
    );
    return Material(
      color: color ?? (selected ? Fx.accent.withValues(alpha: 0.08) : Fx.panel(context)),
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Small tinted label: "Confirmed", "3 flags", a violation name...
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon, this.dense = false});

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: dense ? 12 : 14, color: color), const SizedBox(width: 4)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

/// A violation as a coloured pill with its icon.
class ViolationChip extends StatelessWidget {
  const ViolationChip(this.violationKey, {super.key, this.dense = false});

  final String violationKey;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final v = ViolationCatalog.of(violationKey);
    return StatusPill(label: v.label, color: v.color, icon: v.icon, dense: dense);
  }
}

/// Section heading used above groups of controls.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Fx.s8),
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: Fx.label(context))),
        ?trailing,
      ]),
    );
  }
}

/// Icon + title + one sentence + optional action, for empty lists and first-run screens.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Fx.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(Fx.s16),
              decoration: BoxDecoration(color: Fx.raised(context), shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: Fx.muted(context)),
            ),
            const SizedBox(height: Fx.s16),
            Text(title, style: Fx.heading(context), textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: Fx.s8),
              Text(message!, style: Fx.caption(context), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: Fx.s16), action!],
          ]),
        ),
      ),
    );
  }
}

/// A keyboard key cap, for shortcut hints.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Fx.raised(context),
        border: Border.all(color: Fx.border(context)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// A network / memory image that shows a skeleton while loading and a clear placeholder
/// when the file is gone (evidence can be cleaned up from disk).
class FxImage extends StatelessWidget {
  const FxImage({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.errorLabel = 'Photo unavailable',
    this.radius = 0,
  });

  final ImageProvider image;
  final BoxFit fit;
  final String errorLabel;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image(
        image: image,
        fit: fit,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) {
          if (sync) return child;
          return Stack(fit: StackFit.passthrough, children: [
            if (frame == null) const SkeletonBox(),
            AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: child,
            ),
          ]);
        },
        errorBuilder: (context, error, stack) => Container(
          color: Fx.raised(context),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.image_not_supported_outlined, size: 20, color: Fx.muted(context)),
            if (errorLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(errorLabel,
                  style: Fx.caption(context), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A softly pulsing block shown while content loads.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height, this.width, this.radius = 0});

  final double? height;
  final double? width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Fx.raised(context);
    final hi = Theme.of(context).colorScheme.surfaceContainerHigh;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(base, hi, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A one-line banner for errors and warnings that stays until dismissed or fixed.
class FxBanner extends StatelessWidget {
  const FxBanner({super.key, required this.message, this.color = Fx.danger, this.icon = Icons.error_outline, this.action});

  final String message;
  final Color color;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s12, vertical: Fx.s8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(Fx.radiusSm),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: Fx.s8),
        Expanded(child: Text(message, style: Fx.body(context))),
        ?action,
      ]),
    );
  }
}
