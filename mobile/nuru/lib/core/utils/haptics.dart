import 'package:flutter/services.dart';

/// Centralised haptic feedback helper.
///
/// Wrap primary actions (purchase, RSVP, send, refresh, swipe-archive) so the
/// whole app shares one tactile vocabulary. Calls are silently no-op on
/// platforms that don't support haptics.
class Haptics {
  Haptics._();

  /// Light tap - selection changes, tab switches, toggles.
  static Future<void> selection() async {
    try { await HapticFeedback.selectionClick(); } catch (_) {}
  }

  /// Light impact - small confirmations, dismissible actions.
  static Future<void> light() async {
    try { await HapticFeedback.lightImpact(); } catch (_) {}
  }

  /// Medium impact - primary actions: send message, RSVP, refresh complete.
  static Future<void> medium() async {
    try { await HapticFeedback.mediumImpact(); } catch (_) {}
  }

  /// Heavy impact - destructive or major confirmations: purchase, delete.
  static Future<void> heavy() async {
    try { await HapticFeedback.heavyImpact(); } catch (_) {}
  }

  /// Success pattern - light + medium for celebratory completions.
  static Future<void> success() async {
    try {
      await HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 60));
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }
}
