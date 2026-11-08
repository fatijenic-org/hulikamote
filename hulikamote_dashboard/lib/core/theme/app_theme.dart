import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get darkTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF3B82F6),
      scaffoldBackgroundColor: const Color(0xFF0B0F17),
    );
    return base.copyWith(
      textTheme: GoogleFonts.lexendTextTheme(base.textTheme),
    );
  }
}
