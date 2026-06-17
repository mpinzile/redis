import 'api_base.dart';

/// Thin client for the universal `POST /scan/resolve` endpoint.
///
/// Used by the Check-In Mode scanner to inspect any QR payload BEFORE
/// attempting the actual check-in mutation. The resolver tells us whether
/// the code is a ticket, guest, contribution link, access code, etc. and
/// — when the scanner is in an event context — provides an `actions[]`
/// list pointing at the right follow-up endpoint.
///
/// The mobile UI doesn't change shape: callers branch on `route` and
/// `payload.cross_event` to show the existing success/failure screens
/// with smarter messages.
class ScanResolveService {
  static Future<Map<String, dynamic>> resolve(String code, {String? eventId}) {
    final body = <String, dynamic>{'code': code.trim()};
    if (eventId != null && eventId.isNotEmpty) body['event_id'] = eventId;
    return ApiBase.post('/scan/resolve', body,
        fallbackError: 'Could not read this QR code');
  }
}
