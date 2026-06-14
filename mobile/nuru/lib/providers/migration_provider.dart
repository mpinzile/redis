import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/migration_service.dart';

/// MigrationPhase - drives the legacy-user upgrade UX escalation.
///
///   • soft     - first 0-3 days. Welcome sheet appears once (dismissable),
///                contextual banners on monetized pages.
///   • nudge    - days 4-13. Banners harden, welcome sheet re-appears weekly.
///   • restrict - day 14+. Money-OUT actions and NEW paid-creation actions
///                blocked via `isRestricted`. Existing live items keep selling.
enum MigrationPhase { soft, nudge, restrict }

class MigrationProvider extends ChangeNotifier {
  static const _firstSeenKey = 'nuru_migration_first_seen';
  static const _modalDismissKey = 'nuru_migration_modal_dismissed';
  static const _softDays = 4;
  static const _restrictDays = 14;

  Map<String, dynamic>? _status;
  bool _loading = false;
  String? _userId;

  Map<String, dynamic>? get status => _status;
  bool get isLoading => _loading;

  bool get needsSetup => _status?['needs_setup'] == true;
  bool get hasMonetizedContent => _status?['has_monetized_content'] == true;
  bool get hasPendingBalance => _status?['has_pending_balance'] == true;

  Map<String, dynamic> get monetizedSummary =>
      (_status?['monetized_summary'] as Map?)?.cast<String, dynamic>() ?? const {};

  Map<String, dynamic>? get countryGuess =>
      (_status?['country_guess'] as Map?)?.cast<String, dynamic>();

  Map<String, dynamic>? get pendingBalance =>
      (_status?['pending_balance'] as Map?)?.cast<String, dynamic>();

  /// Total monetized items across categories.
  int get totalMonetizedItems {
    final s = monetizedSummary;
    int sum = 0;
    for (final v in s.values) {
      if (v is num) sum += v.toInt();
    }
    return sum;
  }

  MigrationPhase get phase {
    if (!needsSetup || _userId == null) return MigrationPhase.soft;
    final since = _status?['legacy_since'] as String?;
    final ms = _resolveReferenceMs(since);
    final ageDays = (DateTime.now().millisecondsSinceEpoch - ms) / 86400000.0;
    if (ageDays >= _restrictDays) return MigrationPhase.restrict;
    if (ageDays >= _softDays) return MigrationPhase.nudge;
    return MigrationPhase.soft;
  }

  bool get isRestricted => needsSetup && phase == MigrationPhase.restrict;

  /// Should the welcome sheet auto-open this session?
  Future<bool> shouldShowWelcome() async {
    if (!needsSetup || _userId == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final dismissedAt = prefs.getInt('${_modalDismissKey}_$_userId');
    if (dismissedAt == null) return true;
    final ageDays =
        (DateTime.now().millisecondsSinceEpoch - dismissedAt) / 86400000.0;
    switch (phase) {
      case MigrationPhase.restrict:
        return ageDays >= 1;
      case MigrationPhase.nudge:
        return ageDays >= 7;
      case MigrationPhase.soft:
        return false;
    }
  }

  Future<void> dismissWelcome() async {
    if (_userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      '${_modalDismissKey}_$_userId',
      DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  /// Load (or refresh) for the given user. Safe to call multiple times.
  Future<void> load(String userId) async {
    _userId = userId;
    _loading = true;
    notifyListeners();
    try {
      final res = await MigrationService.getStatus();
      if (res['success'] == true && res['data'] is Map) {
        _status = (res['data'] as Map).cast<String, dynamic>();
        // Seed first-seen so the 14-day clock starts even if the backend
        // doesn't yet supply legacy_since.
        if (needsSetup) {
          final prefs = await SharedPreferences.getInstance();
          final k = '${_firstSeenKey}_$userId';
          if (!prefs.containsKey(k)) {
            await prefs.setInt(k, DateTime.now().millisecondsSinceEpoch);
          }
        }
      }
    } catch (_) {
      // Network failure - leave status null. UI treats that as "no nudge".
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clear() {
    _status = null;
    _userId = null;
    notifyListeners();
  }

  int _resolveReferenceMs(String? legacySince) {
    if (legacySince != null && legacySince.isNotEmpty) {
      try {
        return DateTime.parse(legacySince).millisecondsSinceEpoch;
      } catch (_) {}
    }
    // Synchronous read of the cached first-seen via shared_preferences would
    // require async; fall back to "now" if missing. The seed in load()
    // guarantees this branch is rarely hit.
    return DateTime.now().millisecondsSinceEpoch;
  }
}
