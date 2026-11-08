import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'tokens.dart';

// ─── buttons ────────────────────────────────────────────────────────────────────────────────────────────────────

enum AppButtonKind { primary, secondary, text, danger }

/// One button for the whole app: 52 high, shows a spinner while it works (and ignores taps then), says what it does.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.kind = AppButtonKind.primary,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final AppButtonKind kind;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final spinnerColor = kind == AppButtonKind.primary ? context.colors.onPrimary : context.colors.primary;
    final child = loading
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: spinnerColor))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: Sp.x2)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ]);
    final VoidCallback? tap = enabled ? onPressed : null;
    final Widget button = switch (kind) {
      AppButtonKind.primary => FilledButton(onPressed: tap, child: child),
      AppButtonKind.danger => FilledButton(
          onPressed: tap,
          style: FilledButton.styleFrom(backgroundColor: context.colors.error, foregroundColor: context.colors.onError),
          child: child,
        ),
      AppButtonKind.secondary => OutlinedButton(onPressed: tap, child: child),
      AppButtonKind.text => TextButton(onPressed: tap, child: child),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label, working' : label,
      excludeSemantics: true,
      child: SizedBox(width: expand ? double.infinity : null, child: button),
    );
  }
}

// ─── text field ─────────────────────────────────────────────────────────────────────────────────────────────────

/// A text field with a floating label, an optional help line, a show/hide toggle for passwords, and the right keyboard.
class AppField extends StatefulWidget {
  const AppField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.errorText,
    this.icon,
    this.password = false,
    this.keyboard,
    this.action,
    this.autofill,
    this.capitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.formatters,
    this.enabled = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final String? errorText;
  final IconData? icon;
  final bool password;
  final TextInputType? keyboard;
  final TextInputAction? action;
  final Iterable<String>? autofill;
  final TextCapitalization capitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? minLines;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? formatters;
  final bool enabled;
  final bool autofocus;

  @override
  State<AppField> createState() => _AppFieldState();
}

class _AppFieldState extends State<AppField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: widget.password && _hidden,
      keyboardType: widget.keyboard,
      textInputAction: widget.action,
      autofillHints: widget.autofill,
      textCapitalization: widget.capitalization,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      minLines: widget.password ? 1 : widget.minLines,
      maxLines: widget.password ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      inputFormatters: widget.formatters,
      decoration: InputDecoration(
        alignLabelWithHint: widget.maxLines > 1,
        floatingLabelBehavior: widget.maxLines > 1 ? FloatingLabelBehavior.always : null,
        labelText: widget.label,
        helperText: widget.helper,
        errorText: widget.errorText,
        counterText: '',
        prefixIcon: widget.icon == null ? null : Icon(widget.icon),
        suffixIcon: widget.password
            ? IconButton(
                tooltip: _hidden ? 'Show password' : 'Hide password',
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : null,
      ),
    );
  }
}

// ─── status chip ────────────────────────────────────────────────────────────────────────────────────────────────

enum Tone { success, warning, danger, info, neutral }

/// A small pill with an icon AND words, so the meaning never depends on colour alone.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone, this.icon});

  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final (Color back, Color front) = switch (tone) {
      Tone.success => (s.success, s.onSuccess),
      Tone.warning => (s.warning, s.onWarning),
      Tone.danger => (s.danger, s.onDanger),
      Tone.info => (s.info, s.onInfo),
      Tone.neutral => (context.colors.surfaceContainerHighest, context.colors.onSurfaceVariant),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: 5),
        decoration: BoxDecoration(color: back, borderRadius: BorderRadius.circular(Rd.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: front), const SizedBox(width: 5)],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: front, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

// ─── states: empty, error, loading ──────────────────────────────────────────────────────────────────────────────

/// Nothing here yet: say why, and what to do.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.x8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: context.colors.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: context.colors.onPrimaryContainer),
          ),
          const SizedBox(height: Sp.x5),
          Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: Sp.x2),
          Text(message, style: context.text.bodyMedium?.copyWith(color: context.muted), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: Sp.x5), action!],
        ]),
      ),
    );
  }
}

/// Something went wrong: say it in plain words and offer to try again.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry, this.title = 'Could not load this'});

  final String message;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        title: title,
        message: message,
        action: onRetry == null ? null : AppButton(label: 'Try again', icon: Icons.refresh, onPressed: onRetry, expand: false, kind: AppButtonKind.secondary),
      ),
    );
  }
}

/// A line of news at the top of a page: "you are offline", "saved copy", "this went wrong".
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.message, this.tone = Tone.info, this.icon, this.actionLabel, this.onAction});

  final String message;
  final Tone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final (Color back, Color front, IconData fallback) = switch (tone) {
      Tone.success => (s.success, s.onSuccess, Icons.check_circle_outline),
      Tone.warning => (s.warning, s.onWarning, Icons.info_outline),
      Tone.danger => (s.danger, s.onDanger, Icons.error_outline),
      _ => (s.info, s.onInfo, Icons.info_outline),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x2),
        decoration: BoxDecoration(color: back, borderRadius: BorderRadius.circular(Rd.md)),
        child: Row(children: [
          Icon(icon ?? fallback, size: 20, color: front),
          const SizedBox(width: Sp.x3),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: Sp.x2), child: Text(message, style: TextStyle(color: front, fontSize: 14, height: 1.3)))),
          if (actionLabel != null) TextButton(onPressed: onAction, style: TextButton.styleFrom(foregroundColor: front), child: Text(actionLabel!)),
        ]),
      ),
    );
  }
}

/// A grey block that shimmers while real content loads (it stays still when the phone asks for less motion).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = Rd.sm});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.surfaceContainerHighest;
    final calm = MediaQuery.of(context).disableAnimations;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = calm ? 0.5 : _c.value;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1.5 + 3 * t, 0),
                end: Alignment(-0.5 + 3 * t, 0),
                colors: [base, Color.lerp(base, context.colors.surface, 0.65)!, base],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Placeholder rows that look like the cards that will replace them.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: Column(children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.x3),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Sp.x3),
                child: Row(children: [
                  const Skeleton(height: 56, width: 56, radius: Rd.md),
                  const SizedBox(width: Sp.x3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Skeleton(height: 16, width: 160),
                      const SizedBox(height: Sp.x2),
                      Skeleton(height: 12, width: 100 + 20.0 * (i % 3)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

// ─── small pieces ───────────────────────────────────────────────────────────────────────────────────────────────

/// A heading above a group of things.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x2),
      child: Row(children: [
        Expanded(child: Semantics(header: true, child: Text(text, style: context.text.titleMedium))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// "Label ........ value" inside a card.
class FactRow extends StatelessWidget {
  const FactRow({super.key, required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.x2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 112, child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.muted))),
        Expanded(child: Text(value, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// A round badge with the person's initials.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 56});

  final String name;
  final double size;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: context.colors.primaryContainer, shape: BoxShape.circle),
        child: Text(initials(name), style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: context.colors.onPrimaryContainer)),
      ),
    );
  }
}
