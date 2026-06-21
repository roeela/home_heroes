import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color _primary = Color(0xFF2E7D32);
  static const Color _secondary = Color(0xFFF57C00);

  static ThemeData get theme {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primary,
        secondary: _secondary,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );
    return base.copyWith(
      textTheme: GoogleFonts.rubikTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.rubik(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _secondary,
        foregroundColor: Colors.white,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _primary.withValues(alpha: 0.1),
        labelStyle: GoogleFonts.rubik(color: _primary),
      ),
    );
  }
}
