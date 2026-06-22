import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors
  static const Color primary       = Color(0xFFC46B2A);
  static const Color secondary     = Color(0xFFF4E7D3);
  static const Color accent        = Color(0xFF7BA66A);
  static const Color background    = Color(0xFFFFF8EF);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color success       = Color(0xFF4CAF50);
  static const Color warning       = Color(0xFFFFB74D);
  static const Color textPrimary   = Color(0xFF3D2A1D);
  static const Color textSecondary = Color(0xFF7B6657);
  static const Color border        = Color(0xFFE7D8C6);

  // Spacing
  static const double spaceXS = 4;
  static const double spaceS  = 8;
  static const double spaceM  = 16;
  static const double spaceL  = 24;
  static const double spaceXL = 32;

  // Corner radius
  static const double radiusCard   = 20;
  static const double radiusButton = 16;
  static const double radiusInput  = 14;
  static const double radiusChip   = 24;

  // Elevation
  static const double elevationCard   = 2;
  static const double elevationDialog = 4;

  static ThemeData get theme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: secondary,
      onPrimaryContainer: textPrimary,
      secondary: accent,
      onSecondary: Colors.white,
      secondaryContainer: secondary,
      onSecondaryContainer: textPrimary,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: border,
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      textTheme: GoogleFonts.rubikTextTheme(base.textTheme).copyWith(
        displayLarge:   GoogleFonts.rubik(fontSize: 32, fontWeight: FontWeight.w700, color: textPrimary),
        headlineMedium: GoogleFonts.rubik(fontSize: 24, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium:    GoogleFonts.rubik(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        bodyMedium:     GoogleFonts.rubik(fontSize: 16, color: textPrimary),
        bodySmall:      GoogleFonts.rubik(fontSize: 14, color: textSecondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.rubik(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: elevationCard,
        shadowColor: primary.withValues(alpha: 0.12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.all(Radius.circular(radiusCard)),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.rubik(fontSize: 16, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadiusDirectional.all(Radius.circular(radiusButton)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: spaceL, vertical: spaceM),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadiusDirectional.all(Radius.circular(radiusButton)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: GoogleFonts.rubik(color: textSecondary, fontSize: 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: spaceM, vertical: spaceM),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: secondary,
        labelStyle: GoogleFonts.rubik(color: textPrimary, fontSize: 14),
        side: BorderSide.none,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.all(Radius.circular(radiusChip)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: spaceM, vertical: spaceS),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: elevationCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.all(Radius.circular(radiusButton)),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: elevationCard,
        selectedLabelStyle: GoogleFonts.rubik(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.rubik(fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: secondary,
        elevation: elevationCard,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? primary : textSecondary,
        )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => GoogleFonts.rubik(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? primary : textSecondary,
        )),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: elevationDialog,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.all(Radius.circular(radiusCard)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        space: 1,
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: secondary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: GoogleFonts.rubik(color: Colors.white, fontSize: 14),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.all(Radius.circular(radiusButton)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
