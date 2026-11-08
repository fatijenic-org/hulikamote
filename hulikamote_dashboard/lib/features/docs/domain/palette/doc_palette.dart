import 'package:flutter/material.dart';

/// Semantic colour roles for the documentation pages, charts, and scenes.
/// Matches the CSS variables in `tools/doc_site/lib.py`.
class DocPalette {
  final bool isDark;
  final Color surface;
  final Color page;
  final Color ink;
  final Color ink2;
  final Color muted;
  final Color grid;
  final Color axis;
  final Color border;

  final Color s1;
  final Color s2;
  final Color s3;
  final Color s4;
  final Color s5;
  final Color s6;
  final Color s7;
  final Color s8;

  final Color good;
  final Color warn;
  final Color serious;
  final Color crit;
  final Color accent;
  final Color codeBg;
  final Color soft;

  final Color cStr;
  final Color cKw;
  final Color cNum;
  final Color cFn;

  const DocPalette._({
    required this.isDark,
    required this.surface,
    required this.page,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.grid,
    required this.axis,
    required this.border,
    required this.s1,
    required this.s2,
    required this.s3,
    required this.s4,
    required this.s5,
    required this.s6,
    required this.s7,
    required this.s8,
    required this.good,
    required this.warn,
    required this.serious,
    required this.crit,
    required this.accent,
    required this.codeBg,
    required this.soft,
    required this.cStr,
    required this.cKw,
    required this.cNum,
    required this.cFn,
  });

  factory DocPalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? DocPalette.dark : DocPalette.light;
  }

  static const DocPalette light = DocPalette._(
    isDark: false,
    surface: Color(0xFFFCFCFB),
    page: Color(0xFFF9F9F7),
    ink: Color(0xFF0B0B0B),
    ink2: Color(0xFF52514E),
    muted: Color(0xFF6F6D68),
    grid: Color(0xFFE1E0D9),
    axis: Color(0xFFC3C2B7),
    border: Color(0x1F0B0B0B), // rgba(11,11,11,.12)
    s1: Color(0xFF2A78D6),
    s2: Color(0xFFEB6834),
    s3: Color(0xFF1BAF7A),
    s4: Color(0xFFEDA100),
    s5: Color(0xFFE87BA4),
    s6: Color(0xFF008300),
    s7: Color(0xFF6250D6),
    s8: Color(0xFFE34948),
    good: Color(0xFF0CA30C),
    warn: Color(0xFFFAB219),
    serious: Color(0xFFEC835A),
    crit: Color(0xFFD03B3B),
    accent: Color(0xFF2A78D6),
    codeBg: Color(0xFFF3F2EE),
    soft: Color(0xFFEEF4FC),
    cStr: Color(0xFF0A7A55),
    cKw: Color(0xFF6250D6),
    cNum: Color(0xFFC4501F),
    cFn: Color(0xFF1C5CAB),
  );

  static const DocPalette dark = DocPalette._(
    isDark: true,
    surface: Color(0xFF1A1A19),
    page: Color(0xFF0D0D0D),
    ink: Color(0xFFF0EFEC),
    ink2: Color(0xFFC3C2B7),
    muted: Color(0xFFA09E97),
    grid: Color(0xFF2C2C2A),
    axis: Color(0xFF383835),
    border: Color(0x1FFFFFFF), // rgba(255,255,255,.12)
    s1: Color(0xFF3987E5),
    s2: Color(0xFFD95926),
    s3: Color(0xFF199E70),
    s4: Color(0xFFC98500),
    s5: Color(0xFFD55181),
    s6: Color(0xFF008300),
    s7: Color(0xFF9085E9),
    s8: Color(0xFFE66767),
    good: Color(0xFF0CA30C),
    warn: Color(0xFFFAB219),
    serious: Color(0xFFEC835A),
    crit: Color(0xFFD03B3B),
    accent: Color(0xFF6DA7EC),
    codeBg: Color(0xFF232322),
    soft: Color(0xFF18222F),
    cStr: Color(0xFF3ECF9C),
    cKw: Color(0xFF9085E9),
    cNum: Color(0xFFF0A070),
    cFn: Color(0xFF6DA7EC),
  );

  Color slotColor(String slot) {
    switch (slot) {
      case 's1':
      case 'c1':
      case 'f1':
        return s1;
      case 's2':
      case 'c2':
      case 'f2':
        return s2;
      case 's3':
      case 'c3':
      case 'f3':
        return s3;
      case 's4':
      case 'c4':
      case 'f4':
        return s4;
      case 's5':
      case 'c5':
      case 'f5':
        return s5;
      case 's6':
      case 'c6':
      case 'f6':
        return s6;
      case 's7':
      case 'c7':
      case 'f7':
        return s7;
      case 's8':
      case 'c8':
      case 'f8':
        return s8;
      default:
        return s1;
    }
  }

  Color tokenColor(String cls) {
    switch (cls) {
      case 'kw':
        return cKw;
      case 'str':
        return cStr;
      case 'num':
        return cNum;
      case 'fn':
      case 'cls':
      case 'bi':
        return cFn;
      case 'com':
      case 'doc':
        return muted;
      default:
        return ink;
    }
  }

  Color chipColor(String kind) {
    switch (kind) {
      case 'ok':
        return good;
      case 'warn':
        return isDark ? const Color(0xFFFAB219) : const Color(0xFFB07A00);
      case 'bad':
        return crit;
      case 'info':
        return s1;
      case 'off':
      default:
        return muted;
    }
  }

  Color colorMix(Color c1, double weight1, Color c2) {
    return Color.lerp(c2, c1, weight1) ?? c1;
  }
}
