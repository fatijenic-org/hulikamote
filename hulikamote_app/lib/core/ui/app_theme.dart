import 'package:flutter/material.dart';

import 'tokens.dart';

/// Colours for "good / careful / bad / information" that Material's scheme does not have. Every use also carries an
/// icon and words, so colour is never the only signal.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success, required this.onSuccess,
    required this.warning, required this.onWarning,
    required this.danger, required this.onDanger,
    required this.info, required this.onInfo,
  });

  final Color success, onSuccess, warning, onWarning, danger, onDanger, info, onInfo;

  static const light = StatusColors(
    success: Color(0xFFE7F6EC), onSuccess: Color(0xFF05603A),
    warning: Color(0xFFFEF0C7), onWarning: Color(0xFF93370D),
    danger: Color(0xFFFEE4E2), onDanger: Color(0xFFB42318),
    info: Color(0xFFE0EAFF), onInfo: Color(0xFF1849A9),
  );

  static const dark = StatusColors(
    success: Color(0xFF12372A), onSuccess: Color(0xFF75E0A7),
    warning: Color(0xFF4A3410), onWarning: Color(0xFFFEC84B),
    danger: Color(0xFF4A1D1A), onDanger: Color(0xFFFDA29B),
    info: Color(0xFF17294F), onInfo: Color(0xFF84ADFF),
  );

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) => t < 0.5 ? this : (other as StatusColors? ?? this);
}

extension ThemeShortcuts on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  /// The status colours of the theme; a plain MaterialApp without them still gets the standard ones.
  StatusColors get status =>
      Theme.of(this).extension<StatusColors>() ?? (Theme.of(this).brightness == Brightness.dark ? StatusColors.dark : StatusColors.light);

  /// Secondary text.
  Color get muted => Theme.of(this).colorScheme.onSurfaceVariant;
}

class AppTheme {
  AppTheme._();

  static const Color brand = Color(0xFF1D4ED8);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness).copyWith(
      primary: dark ? const Color(0xFF84ADFF) : brand,
      onPrimary: dark ? const Color(0xFF0B1B45) : Colors.white,
      surface: dark ? const Color(0xFF151A22) : Colors.white,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final text = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.15),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14.5, height: 1.4),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    );
    final outline = scheme.outlineVariant;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(Rd.md), borderSide: BorderSide(color: color, width: width));

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: dark ? const Color(0xFF0E1116) : const Color(0xFFF5F6F8),
      extensions: [dark ? StatusColors.dark : StatusColors.light],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.lg), side: BorderSide(color: outline)),
      ),
      dividerTheme: DividerThemeData(color: outline, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x4),
        border: border(outline),
        enabledBorder: border(outline),
        focusedBorder: border(scheme.primary, 2),
        errorBorder: border(scheme.error),
        focusedErrorBorder: border(scheme.error, 2),
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTap, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.md)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTap, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.md)),
          side: BorderSide(color: outline),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(minTap, minTap), textStyle: text.labelLarge),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: outline),
        labelStyle: text.labelMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.md)),
        insetPadding: const EdgeInsets.all(Sp.x4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.xl)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.xl))),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: Sp.x3),
    );
  }
}
