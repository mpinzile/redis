import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import '../utils/money_format.dart' as _money;

TextStyle appText({
  required double size,
  FontWeight weight = FontWeight.w500,
  Color color = AppColors.textPrimary,
  double height = 1.3,
  double letterSpacing = 0,
}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

String extractStr(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  if (v is String) return v.isEmpty ? fallback : v;
  if (v is Map) {
    return (v['name'] ?? v['title'] ?? v['label'] ?? v.values.first)
            ?.toString() ??
        fallback;
  }
  return v.toString();
}

/// Formats an amount with the active user currency (or [currency] override).
/// Name kept for backward compatibility - no longer hardcoded to TZS.
String formatTZS(dynamic amount, {String? currency}) {
  final code = (currency != null && currency.trim().isNotEmpty)
      ? currency.trim().toUpperCase()
      : _activeCurrencyOrDefault();
  if (amount == null) return '$code 0';
  final n =
      (amount is String ? double.tryParse(amount) : amount.toDouble()) ?? 0.0;
  return '$code ${n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
}

String _activeCurrencyOrDefault() => _money.getActiveCurrency();
