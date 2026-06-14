import 'package:flutter/material.dart';

/// Nuru Design System 2026
/// Post-onboarding palette: Blue, Green, Orange, Dark. No gradients.
class AppColors {
  // ─── Brand Core ─── (Nuru Amber #E7A622)
  static const Color primary = Color(0xFFE7A622); // Nuru Amber
  static const Color primaryLight = Color(0xFFF0BD4F);
  static const Color primaryDark = Color(0xFFB8841A);
  static const Color primarySoft = Color(0x14E7A622);

  // Secondary - matches primary brand
  static const Color secondary = Color(0xFFE7A622);
  static const Color secondaryLight = Color(0xFFF0BD4F);
  static const Color secondarySoft = Color(0x14E7A622);

  // Accent - Green for success/positive
  static const Color accent = Color(0xFF71E07E);
  static const Color accentLight = Color(0xFF95E99F);
  static const Color accentSoft = Color(0x0A71E07E);

  // Blue - Info, links (same as primary)
  static const Color blue = Color(0xFF2471E7);
  static const Color blueSoft = Color(0x0A2471E7);

  // ─── Surfaces (crisp, no noise) ───
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFFFFFFF);
  static const Color card = Color(0xFFFFFFFF);

  // Dark surfaces
  static const Color surfaceDark = Color(0xFF0A1C40);
  static const Color surfaceDarkElevated = Color(0xFF12284F);
  static const Color surfaceDarkMuted = Color(0xFF1A3460);

  // ─── Borders (minimal, structural) ───
  static const Color border = Color(0xFFE5E5EA);
  static const Color borderLight = Color(0xFFF0F0F4);
  static const Color borderSubtle = Color(0x06000000);
  static const Color divider = Color(0xFFF0F0F4);

  // ─── Text (clean hierarchy) ───
  static const Color textPrimary = Color(0xFF0A1C40);
  static const Color textSecondary = Color(0xFF5A6B85);
  static const Color textTertiary = Color(0xFF8E9BB0);
  static const Color textHint = Color(0xFFB8C2D0);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnDark = Color(0xFFF5F5F7);
  static const Color textOnDarkMuted = Color(0x99F5F5F7);

  // ─── Status ───
  static const Color success = Color(0xFF71E07E);
  static const Color successSoft = Color(0x1A71E07E);
  static const Color error = Color(0xFFDC2626);
  static const Color errorSoft = Color(0x1ADC2626);
  static const Color warning = Color(0xFFFECA08);
  static const Color warningSoft = Color(0x1AFECA08);
  static const Color info = Color(0xFF2471E7);
  static const Color infoSoft = Color(0x1A2471E7);

  // ─── Overlay ───
  static const Color overlay = Color(0x40000000);
  static const Color splashBg = Color(0xFFFFFFFF);

  // ─── Minimal shadows (use sparingly) ───
  static List<BoxShadow> get subtleShadow => [
    const BoxShadow(
      color: Color(0x08000000),
      blurRadius: 8,
      offset: Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get softShadow => subtleShadow;

  static List<BoxShadow> get cardShadow => [
    const BoxShadow(
      color: Color(0x06000000),
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    const BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  static List<BoxShadow> primaryGlow(double opacity) => [];
}
