import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Generic key/value persistent cache for API responses.
///
/// Use this as a thin layer screens can adopt to make data survive app
/// close/reopen - the standard pattern is:
///
/// ```dart
/// // 1. on initState, read cache and render immediately:
/// MobileCache.readJson('cached_event_$id').then((v) {
///   if (v is Map) setState(() => _event = v);
/// });
/// // 2. fetch fresh in background and update on success:
/// final res = await api.get(...);
/// if (res['success'] == true) {
///   setState(() => _event = res['data']);
///   MobileCache.writeJson('cached_event_$id', res['data']);
/// }
/// // 3. on failure, keep cached data on screen - do NOT clear.
/// ```
///
/// Cache keys follow `cached_<resource>[_<id>]` convention used across the
/// app (e.g. `cached_dashboard`, `cached_event_42`, `cached_notifications`).
/// Sensitive data must be cleared via [clearAll] when the user signs out.
class MobileCache {
  static const String _prefix = 'mobilecache.v1.';
  static const String _tsSuffix = '.ts';

  /// Write a JSON-serializable value (Map / List / primitives).
  /// Silently swallows errors so cache failures never break the UI.
  static Future<void> writeJson(String key, Object? value) async {
    if (value == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', jsonEncode(value));
      await prefs.setInt('$_prefix$key$_tsSuffix',
          DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Read a previously cached JSON value, or `null` if missing / corrupt.
  static Future<dynamic> readJson(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null || raw.isEmpty) return null;
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// Milliseconds-since-epoch when the entry was last written, or 0.
  static Future<int> timestamp(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('$_prefix$key$_tsSuffix') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
      await prefs.remove('$_prefix$key$_tsSuffix');
    } catch (_) {}
  }

  /// Wipe every entry written through this cache.
  /// Call from sign-out flows - do NOT call on transient network errors.
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}
