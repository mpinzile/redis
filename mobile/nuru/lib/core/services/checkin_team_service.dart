import 'api_base.dart';

/// Endpoints for the Check-In Team workflow: redeeming an access code,
/// keeping the session alive, and explicitly ending it.
class CheckinTeamService {
  /// Exchange a `NRU-XXXX-XXXX` access code for a scoped scanner session.
  ///
  /// Returns the normalized API envelope. On success `data` contains:
  ///   - `session_token` (String)
  ///   - `session_id` (String)
  ///   - `event` (Map: id, title, date, location, cover_image, ...)
  ///   - `permissions` (Map: can_checkin_guests, can_checkin_tickets, ...)
  static Future<Map<String, dynamic>> redeem(String code, {String? deviceRef}) {
    final body = <String, dynamic>{'code': code.trim()};
    if (deviceRef != null && deviceRef.isNotEmpty) {
      body['device_ref'] = deviceRef;
    }
    return ApiBase.post(
      '/checkin/redeem',
      body,
      fallbackError: 'Invalid or expired code',
    );
  }

  static Future<Map<String, dynamic>> heartbeat() {
    return ApiBase.post(
      '/checkin/session/heartbeat',
      const {},
      fallbackError: 'Session lost',
    );
  }

  static Future<Map<String, dynamic>> endSession() {
    return ApiBase.post(
      '/checkin/session/end',
      const {},
      fallbackError: 'Unable to end session',
    );
  }
}
