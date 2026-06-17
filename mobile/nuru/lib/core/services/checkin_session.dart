import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds an active Check-In Mode session for the scanner-team flow.
///
/// When a team member redeems an access code via the entry screen, the
/// backend returns a `session_token` plus event metadata. We persist that
/// here so:
///   - every API call automatically attaches `X-Checkin-Session` (see
///     `ApiBase.headers`) so the backend can audit the scan to the team
///     member without them ever logging into the organizer's account
///   - the scanner shell survives a hot-restart and re-enters Check-In
///     Mode on relaunch (until the session is explicitly ended)
///   - every scan request carries a fresh `client_scan_id` so the backend
///     can de-dupe re-tries from a flaky network / double-tap.
class CheckinSession {
  static const _kSession = 'checkin_session_v1';

  static String? _token;
  static String? _sessionId;
  static String? _eventId;
  static Map<String, dynamic>? _event;
  static Map<String, dynamic>? _permissions;
  static DateTime? _startedAt;

  static String? get token => _token;
  static String? get sessionId => _sessionId;
  static String? get eventId => _eventId;
  static Map<String, dynamic>? get event => _event;
  static Map<String, dynamic>? get permissions => _permissions;
  static DateTime? get startedAt => _startedAt;
  static bool get isActive => _token != null && _token!.isNotEmpty;

  /// Restore a previously persisted session, if any. Call from app startup.
  static Future<void> hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSession);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      _token = m['token']?.toString();
      _sessionId = m['session_id']?.toString();
      _eventId = m['event_id']?.toString();
      _event = m['event'] is Map ? Map<String, dynamic>.from(m['event']) : null;
      _permissions = m['permissions'] is Map
          ? Map<String, dynamic>.from(m['permissions'])
          : null;
      final s = m['started_at']?.toString();
      _startedAt = s == null ? null : DateTime.tryParse(s);
    } catch (_) {/* corrupt cache - ignore */}
  }

  static Future<void> begin({
    required String token,
    required String sessionId,
    required String eventId,
    Map<String, dynamic>? event,
    Map<String, dynamic>? permissions,
  }) async {
    _token = token;
    _sessionId = sessionId;
    _eventId = eventId;
    _event = event;
    _permissions = permissions;
    _startedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kSession,
      jsonEncode({
        'token': token,
        'session_id': sessionId,
        'event_id': eventId,
        'event': event,
        'permissions': permissions,
        'started_at': _startedAt!.toIso8601String(),
      }),
    );
  }

  static Future<void> clear() async {
    _token = null;
    _sessionId = null;
    _eventId = null;
    _event = null;
    _permissions = null;
    _startedAt = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSession);
    } catch (_) {}
  }

  /// Random client-side scan id so the backend can drop duplicate
  /// retries within its idempotency window without double-counting.
  static String newScanId() {
    final r = Random.secure();
    final bytes = List<int>.generate(12, (_) => r.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
