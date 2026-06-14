import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the chronological feed list across app launches so the feed
/// screen can render instantly from disk while a fresh fetch runs in the
/// background. Keeps the same ordering returned by the server - we never
/// resort locally.
class FeedPersistentCache {
  static const _kFeedKey = 'nuru.feed.cache.v1';
  static const _kFeedPageKey = 'nuru.feed.cache.page.v1';
  static const _kFeedPagesKey = 'nuru.feed.cache.pages.v1';
  static const _kFeedTsKey = 'nuru.feed.cache.ts.v1';
  static const _kGlimpsesKey = 'nuru.glimpses.cache.v1';
  static const int _maxItems = 60;

  static Future<void> saveFeed({
    required List<dynamic> posts,
    required int page,
    required int totalPages,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = posts.length > _maxItems ? posts.sublist(0, _maxItems) : posts;
      await prefs.setString(_kFeedKey, jsonEncode(trimmed));
      await prefs.setInt(_kFeedPageKey, page);
      await prefs.setInt(_kFeedPagesKey, totalPages);
      await prefs.setInt(_kFeedTsKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<({List<dynamic> posts, int page, int totalPages, int ts})?> readFeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kFeedKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return (
        posts: decoded,
        page: prefs.getInt(_kFeedPageKey) ?? 1,
        totalPages: prefs.getInt(_kFeedPagesKey) ?? 1,
        ts: prefs.getInt(_kFeedTsKey) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveGlimpses(List<dynamic> glimpses) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = glimpses.length > 30 ? glimpses.sublist(0, 30) : glimpses;
      await prefs.setString(_kGlimpsesKey, jsonEncode(trimmed));
    } catch (_) {}
  }

  static Future<List<dynamic>?> readGlimpses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kGlimpsesKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kFeedKey);
      await prefs.remove(_kFeedPageKey);
      await prefs.remove(_kFeedPagesKey);
      await prefs.remove(_kFeedTsKey);
      await prefs.remove(_kGlimpsesKey);
    } catch (_) {}
  }
}
