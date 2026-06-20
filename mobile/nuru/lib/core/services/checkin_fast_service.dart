import 'api_base.dart';
import 'checkin_session.dart';

/// Thin client for the new Redis-backed check-in fast lane.
///
/// One request per scan. The backend returns a tiny payload sourced
/// entirely from Redis — no Postgres on the response path — so the
/// success tick can render in well under 700ms.
///
/// Endpoints:
///   POST /events/{id}/checkin/fast       — scan (QR)
///   POST /events/{id}/checkin/manual     — manual check-in by id/token
///   GET  /events/{id}/checkin/readiness  — is the gate state preloaded?
///   POST /events/{id}/checkin/preload    — build/refresh the gate state
class CheckinFastService {
  static Future<Map<String, dynamic>> scan(
    String eventId,
    String code, {
    String method = 'qr',
    String? deviceRef,
  }) {
    final body = <String, dynamic>{
      'code': code,
      'method': method,
      'client_scan_id': CheckinSession.newScanId(),
    };
    if (deviceRef != null && deviceRef.isNotEmpty) body['device_ref'] = deviceRef;
    return ApiBase.post(
      '/events/$eventId/checkin/fast',
      body,
      fallbackError: 'Unable to check in',
    );
  }

  static Future<Map<String, dynamic>> manual(
    String eventId, {
    String? attendeeId,
    String? ticketId,
    String? token,
    String? deviceRef,
  }) {
    final body = <String, dynamic>{
      'client_scan_id': CheckinSession.newScanId(),
    };
    if (attendeeId != null) body['attendee_id'] = attendeeId;
    if (ticketId != null) body['ticket_id'] = ticketId;
    if (token != null) body['token'] = token;
    if (deviceRef != null && deviceRef.isNotEmpty) body['device_ref'] = deviceRef;
    return ApiBase.post(
      '/events/$eventId/checkin/manual',
      body,
      fallbackError: 'Unable to check in',
    );
  }

  static Future<Map<String, dynamic>> readiness(String eventId) {
    return ApiBase.get(
      '/events/$eventId/checkin/readiness',
      fallbackError: 'Unable to query readiness',
    );
  }

  static Future<Map<String, dynamic>> preload(String eventId, {bool force = false}) {
    return ApiBase.post(
      '/events/$eventId/checkin/preload',
      {'force': force},
      fallbackError: 'Unable to preload check-in',
    );
  }
}