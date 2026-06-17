import 'api_base.dart';
import 'checkin_session.dart';

class EventGuestsService {
  static Future<Map<String, dynamic>> getGuests(
    String eventId, {
    int page = 1,
    int limit = 50,
    String? search,
    String? rsvpStatus,
  }) {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (rsvpStatus != null && rsvpStatus != 'all') params['rsvp_status'] = rsvpStatus;
    return ApiBase.get('/user-events/$eventId/guests', queryParams: params, fallbackError: 'Unable to fetch guests');
  }

  static Future<Map<String, dynamic>> addGuest(String eventId, Map<String, dynamic> data) {
    return ApiBase.post('/user-events/$eventId/guests', data, fallbackError: 'Unable to add guest');
  }

  static Future<Map<String, dynamic>> updateGuest(String eventId, String guestId, Map<String, dynamic> data) {
    return ApiBase.put('/user-events/$eventId/guests/$guestId', data, fallbackError: 'Unable to update guest');
  }

  static Future<Map<String, dynamic>> deleteGuest(String eventId, String guestId) {
    return ApiBase.delete('/user-events/$eventId/guests/$guestId', fallbackError: 'Unable to remove guest');
  }

  static Future<Map<String, dynamic>> sendInvitation(
    String eventId,
    String guestId, {
    String method = 'whatsapp',
    String? customMessage,
  }) {
    final body = <String, dynamic>{'method': method};
    if (customMessage != null) body['custom_message'] = customMessage;
    return ApiBase.post('/user-events/$eventId/guests/$guestId/invite', body, fallbackError: 'Unable to send invitation');
  }

  static Future<Map<String, dynamic>> sendBulkInvitations(
    String eventId, {
    String method = 'whatsapp',
    List<String>? guestIds,
  }) {
    final body = <String, dynamic>{'method': method};
    if (guestIds != null) body['guest_ids'] = guestIds;
    return ApiBase.post('/user-events/$eventId/guests/invite-all', body, fallbackError: 'Unable to send invitations');
  }

  static Future<Map<String, dynamic>> checkinGuest(
    String eventId,
    String guestId, {
    int? plusOnes,
    String? notes,
  }) {
    final body = <String, dynamic>{};
    if (plusOnes != null) body['plus_ones_checked_in'] = plusOnes;
    if (notes != null) body['notes'] = notes;
    return ApiBase.post('/user-events/$eventId/guests/$guestId/checkin', body, fallbackError: 'Unable to check in guest');
  }

  static Future<Map<String, dynamic>> checkinByQR(String eventId, String qrCode) {
    // `client_scan_id` lets the backend de-dupe identical retries from a
    // flaky network or a double-tap within its idempotency window.
    return ApiBase.post(
      '/user-events/$eventId/guests/checkin-qr',
      {'qr_code': qrCode, 'client_scan_id': CheckinSession.newScanId()},
      fallbackError: 'Unable to check in',
    );
  }

  /// Premium scanner header data (event card + aggregate stats + recent scans).
  static Future<Map<String, dynamic>> getScanStats(String eventId, {int limit = 10}) {
    return ApiBase.get(
      '/user-events/$eventId/scan/stats',
      queryParams: {'limit': '$limit'},
      fallbackError: 'Unable to load scan stats',
    );
  }

  static Future<Map<String, dynamic>> undoCheckin(String eventId, String guestId) {
    return ApiBase.post('/user-events/$eventId/guests/$guestId/undo-checkin', {}, fallbackError: 'Unable to undo check-in');
  }

  static Future<Map<String, dynamic>> respondToInvitation(
    String eventId,
    String rsvpStatus, {
    String? mealPreference,
    String? dietaryRestrictions,
  }) {
    final body = <String, dynamic>{'rsvp_status': rsvpStatus};
    if (mealPreference != null) body['meal_preference'] = mealPreference;
    if (dietaryRestrictions != null) body['dietary_restrictions'] = dietaryRestrictions;
    return ApiBase.put('/user-events/invited/$eventId/rsvp', body, fallbackError: 'Unable to respond');
  }
}
