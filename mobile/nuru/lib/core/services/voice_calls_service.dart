import 'api_base.dart';

/// Smart RSVP Calls (Nuru Voice Assistant) — mobile client.
/// Wraps the backend `/voice-calls/*` endpoints used by organisers to
/// place AI-powered Swahili-first RSVP calls to their guest list.
class VoiceCallsService {
  // ─── Campaigns ───
  static Future<Map<String, dynamic>> listCampaigns({
    String? eventId,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) {
    final qp = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
      if (eventId != null) 'event_id': eventId,
      if (status != null) 'status': status,
    };
    return ApiBase.get('/voice-calls/campaigns', queryParams: qp);
  }

  static Future<Map<String, dynamic>> getCampaign(String id) =>
      ApiBase.get('/voice-calls/campaigns/$id');

  static Future<Map<String, dynamic>> createCampaign({
    String? eventId,
    String purpose = 'rsvp',
    String language = 'sw',
    String? title,
    String? notes,
  }) {
    return ApiBase.post('/voice-calls/campaigns', {
      if (eventId != null) 'event_id': eventId,
      'purpose': purpose,
      'language': language,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
    });
  }

  static Future<Map<String, dynamic>> startCampaign(String id) =>
      ApiBase.post('/voice-calls/campaigns/$id/start', const {});

  static Future<Map<String, dynamic>> pauseCampaign(String id) =>
      ApiBase.post('/voice-calls/campaigns/$id/pause', const {});

  static Future<Map<String, dynamic>> cancelCampaign(String id) =>
      ApiBase.post('/voice-calls/campaigns/$id/cancel', const {});

  static Future<Map<String, dynamic>> deleteCampaign(String id) =>
      ApiBase.delete('/voice-calls/campaigns/$id');

  // ─── Jobs ───
  static Future<Map<String, dynamic>> listJobs(
    String campaignId, {
    String? status,
    int page = 1,
    int pageSize = 100,
  }) {
    final qp = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
      if (status != null) 'status': status,
    };
    return ApiBase.get(
      '/voice-calls/campaigns/$campaignId/jobs',
      queryParams: qp,
    );
  }

  /// recipients: list of {recipient_name, phone, recipient_type, recipient_ref_id?, language?, max_attempts?}
  static Future<Map<String, dynamic>> addJobs(
    String campaignId,
    List<Map<String, dynamic>> recipients, {
    bool enforceHours = true,
  }) {
    return ApiBase.post('/voice-calls/campaigns/$campaignId/jobs', {
      'recipients': recipients,
      'enforce_hours': enforceHours,
    });
  }

  static Future<Map<String, dynamic>> getJob(String jobId) =>
      ApiBase.get('/voice-calls/jobs/$jobId');

  static Future<Map<String, dynamic>> retryJob(String jobId) =>
      ApiBase.post('/voice-calls/jobs/$jobId/retry', const {});

  /// POST /voice-calls/jobs/{id}/place-call — actually dial via Twilio.
  /// Pass [force]=true to bypass the calling-hours guard.
  static Future<Map<String, dynamic>> placeCall(String jobId, {bool force = false}) {
    final qs = force ? '?force=true' : '';
    return ApiBase.post('/voice-calls/jobs/$jobId/place-call$qs', const {});
  }

  // ─── Opt-outs ───
  static Future<Map<String, dynamic>> listOptOuts({
    int page = 1,
    int pageSize = 50,
    String? q,
  }) {
    final qp = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
      if (q != null && q.isNotEmpty) 'q': q,
    };
    return ApiBase.get('/voice-calls/opt-outs', queryParams: qp);
  }

  static Future<Map<String, dynamic>> addOptOut(
    String phone, {
    String? reason,
    String source = 'organiser',
  }) {
    return ApiBase.post('/voice-calls/opt-outs', {
      'phone': phone,
      if (reason != null) 'reason': reason,
      'source': source,
    });
  }

  static Future<Map<String, dynamic>> removeOptOut(String phone) =>
      ApiBase.delete('/voice-calls/opt-outs/${Uri.encodeComponent(phone)}');

  // ─── Feature flag (admin-controlled on/off switch) ───
  /// Returns `{enabled, disabled_message_en, disabled_message_sw, ...}`.
  /// Web and mobile use this to render a polite "temporarily unavailable"
  /// banner when Nuru administrators have paused the Voice Assistant.
  static Future<Map<String, dynamic>> getFeatureStatus() =>
      ApiBase.get('/voice-calls/feature-status');
}
