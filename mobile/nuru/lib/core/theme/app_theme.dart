import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Nuru Typography System
/// Plus Jakarta Sans - unified font for all text across the app
class AppTheme {
  // ── Heading style ──
  static TextStyle heading({
    double fontSize = 24,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? AppColors.textPrimary,
        height: height,
        letterSpacing: letterSpacing ?? -0.3,
      );

  // ── Body style ──
  static TextStyle body({
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? AppColors.textSecondary,
        height: height ?? 1.6,
        letterSpacing: letterSpacing,
      );

  // ── Label/interactive style ──
  static TextStyle label({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? AppColors.textSecondary,
        height: height,
        letterSpacing: letterSpacing ?? 0.2,
      );

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      brightness: Brightness.light,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      // Apply Plus Jakarta Sans across the entire Material text system.
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.surface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        ).copyWith(
          elevation: WidgetStateProperty.all(0),
          shadowColor: WidgetStateProperty.all(Colors.transparent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ).copyWith(
          elevation: WidgetStateProperty.all(0),
          shadowColor: WidgetStateProperty.all(Colors.transparent),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: AppColors.border, width: 1),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        ).copyWith(
          elevation: WidgetStateProperty.all(0),
          shadowColor: WidgetStateProperty.all(Colors.transparent),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border, width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
        hintStyle: GoogleFonts.inter(color: AppColors.textHint, fontSize: 14, fontWeight: FontWeight.w400),
        errorStyle: GoogleFonts.inter(color: AppColors.error, fontSize: 12),
        prefixIconColor: AppColors.textTertiary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return Colors.transparent;
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
