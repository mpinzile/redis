import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'secure_token_storage.dart';

/// Buffers feed interaction events and flushes them to the backend in
/// batches. Powers the personalized ranking model (likes, dwell, clicks,
/// follows) without spamming the network.
///
/// Valid types: view, dwell, glow, unglow, comment, echo, spark, save,
/// unsave, click_image, click_profile, hide, report, expand.
class FeedInteractionTracker {
  FeedInteractionTracker._();

  static final List<Map<String, dynamic>> _buffer = [];
  static final Set<String> _viewedThisSession = {};
  static Timer? _flushTimer;
  static String _sessionId =
      DateTime.now().millisecondsSinceEpoch.toString();

  static String get sessionId => _sessionId;

  static void resetSession() {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _viewedThisSession.clear();
  }

  /// Log a single view at most once per post per session.
  static void logView(String postId) {
    if (postId.isEmpty || !_viewedThisSession.add(postId)) return;
    _enqueue(postId, 'view');
  }

  static void logDwell(String postId, int dwellMs) {
    if (postId.isEmpty || dwellMs < 1000) return;
    _enqueue(postId, 'dwell', dwellMs: dwellMs);
  }

  static void log(String postId, String type, {int? dwellMs}) {
    if (postId.isEmpty) return;
    _enqueue(postId, type, dwellMs: dwellMs);
  }

  static void _enqueue(String postId, String type, {int? dwellMs}) {
    _buffer.add({
      'post_id': postId,
      'interaction_type': type,
      if (dwellMs != null) 'dwell_time_ms': dwellMs,
    });
    if (_buffer.length >= 20) {
      _flush();
    } else {
      _flushTimer ??= Timer(const Duration(seconds: 8), _flush);
    }
  }

  static Future<void> _flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    try {
      final token = await SecureTokenStorage.getToken();
      final uri = Uri.parse('${ApiConfig.baseUrl}/posts/feed/interactions');
      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'interactions': batch,
          'session_id': _sessionId,
          'device_type': 'mobile',
        }),
      );
    } catch (_) {
      // Silently drop on failure - interactions are best-effort signals.
    }
  }

  /// Force-flush (e.g. on app pause / logout).
  static Future<void> flushNow() => _flush();
}
