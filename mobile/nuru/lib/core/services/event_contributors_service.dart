import 'api_base.dart';

class EventContributorsService {
  static Future<Map<String, dynamic>> getUserContributors({String? search, int page = 1, int limit = 100}) {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (search != null && search.isNotEmpty) params['search'] = search;
    return ApiBase.get('/user-contributors/', queryParams: params, fallbackError: 'Unable to fetch contributors');
  }

  static Future<Map<String, dynamic>> getEventContributors(String eventId, {int page = 1, int limit = 5000}) {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    return ApiBase.get('/user-contributors/events/$eventId/contributors', queryParams: params, fallbackError: 'Unable to fetch event contributors');
  }

  /// Add a contributor to an event.
  ///
  /// Supported optional fields in [data]:
  ///   - `secondary_phone`: alternate phone to also notify (E.164 or local).
  ///   - `notify_target`: one of `'primary' | 'secondary' | 'both'`
  ///     (defaults to `'primary'` server-side).
  /// The secondary phone is comms-only; it will not be linked to a Nuru
  /// user account or used by other features.
  static Future<Map<String, dynamic>> addContributorToEvent(String eventId, Map<String, dynamic> data) {
    return ApiBase.postRaw('/user-contributors/events/$eventId/contributors', data);
  }

  static Future<Map<String, dynamic>> recordContributorPayment(String eventId, String ecId, Map<String, dynamic> data) {
    return ApiBase.postRaw('/user-contributors/events/$eventId/contributors/$ecId/payments', data);
  }

  static Future<Map<String, dynamic>> updateEventContributor(String eventId, String ecId, Map<String, dynamic> data) {
    return ApiBase.putRaw('/user-contributors/events/$eventId/contributors/$ecId', data);
  }

  static Future<Map<String, dynamic>> removeContributorFromEvent(String eventId, String ecId) {
    return ApiBase.deleteRaw('/user-contributors/events/$eventId/contributors/$ecId');
  }

  static Future<Map<String, dynamic>> getPaymentHistory(String eventId, String ecId) {
    return ApiBase.get('/user-contributors/events/$eventId/contributors/$ecId/payments', fallbackError: 'Unable to fetch payment history');
  }

  static Future<Map<String, dynamic>> deleteTransaction(String eventId, String ecId, String paymentId) {
    return ApiBase.deleteRaw('/user-contributors/events/$eventId/contributors/$ecId/payments/$paymentId');
  }

  static Future<Map<String, dynamic>> sendThankYou(String eventId, String ecId, Map<String, dynamic> data) {
    return ApiBase.postRaw('/user-contributors/events/$eventId/contributors/$ecId/thank-you', data);
  }

  static Future<Map<String, dynamic>> getPendingContributions(String eventId) {
    return ApiBase.get('/user-contributors/events/$eventId/pending-contributions', fallbackError: 'Unable to fetch pending contributions');
  }

  static Future<Map<String, dynamic>> confirmContributions(String eventId, List<String> contributionIds) {
    return ApiBase.postRaw('/user-contributors/events/$eventId/confirm-contributions', {'contribution_ids': contributionIds});
  }

  static Future<Map<String, dynamic>> rejectContributions(String eventId, List<String> contributionIds) {
    return ApiBase.postRaw('/user-contributors/events/$eventId/reject-contributions', {'contribution_ids': contributionIds});
  }

  static Future<Map<String, dynamic>> sendBulkReminder(String eventId, Map<String, dynamic> data) {
    return ApiBase.postRaw('/user-contributors/events/$eventId/bulk-message', data);
  }

  /// Fetch saved per-event messaging customisations keyed by case_type
  /// (`no_contribution` | `partial` | `completed`).
  static Future<Map<String, dynamic>> getMessagingTemplates(String eventId) {
    return ApiBase.get(
      '/user-contributors/events/$eventId/messaging-templates',
      fallbackError: 'Unable to load saved templates',
    );
  }

  /// Save (without sending) a per-event messaging customisation.
  static Future<Map<String, dynamic>> saveMessagingTemplate(
    String eventId,
    String caseType,
    Map<String, dynamic> data,
  ) {
    return ApiBase.putRaw(
      '/user-contributors/events/$eventId/messaging-templates/$caseType',
      data,
    );
  }

  /// Events where the logged-in user is listed as a contributor.
  static Future<Map<String, dynamic>> getMyContributions({String? search}) {
    final qp = <String, String>{};
    if (search != null && search.trim().isNotEmpty) qp['search'] = search.trim();
    return ApiBase.get(
      '/user-contributors/my-contributions',
      queryParams: qp.isEmpty ? null : qp,
      fallbackError: 'Unable to fetch your contributions',
    );
  }

  /// All payments (online, offline-claim or organiser-recorded) the
  /// current user has made towards a single event.
  static Future<Map<String, dynamic>> getMyPaymentsForEvent(String eventId) {
    return ApiBase.get(
      '/user-contributors/my-contributions/$eventId/payments',
      fallbackError: 'Unable to fetch your payments',
    );
  }

  /// Aggregate giving insights for the current user (summary, streak,
  /// monthly trend, method mix, top organisers, biggest gift, on-time
  /// rate, friendly impact line).
  static Future<Map<String, dynamic>> getMyContributionInsights() {
    return ApiBase.get(
      '/user-contributors/my-contributions/insights',
      fallbackError: 'Unable to fetch contribution insights',
    );
  }

  /// Issue a signed verification token for the user's aggregate
  /// contribution receipt for a given event. The token is embedded in
  /// the receipt's QR code so an organiser can scan and verify totals.
  static Future<Map<String, dynamic>> getAggregateVerifyToken(String eventId) {
    return ApiBase.get(
      '/user-contributors/my-contributions/$eventId/verify-token',
      fallbackError: 'Unable to issue verification token',
    );
  }

  /// Resolve a scanned verification token (by an organiser) and return
  /// the authoritative aggregate summary.
  static Future<Map<String, dynamic>> verifyAggregateContribution(String token) {
    return ApiBase.get(
      '/user-contributors/contributions/verify/$token',
      fallbackError: 'Unable to verify contribution token',
    );
  }

  /// Submit a pending self-contribution awaiting organiser approval.
  static Future<Map<String, dynamic>> selfContribute(String eventId, Map<String, dynamic> data) {
    return ApiBase.postRaw('/user-contributors/events/$eventId/self-contribute', data);
  }

  static Future<Map<String, dynamic>> addContributorsAsGuests(String eventId, Map<String, dynamic> data) {
    return ApiBase.postRaw('/user-events/$eventId/guests/from-contributors', data);
  }

  static Future<Map<String, dynamic>> bulkAddToEvent(String eventId, Map<String, dynamic> data) {
    return ApiBase.postRaw('/user-contributors/events/$eventId/contributors/bulk', data);
  }

  /// Poll a queued contributor-import job for progress and status.
  static Future<Map<String, dynamic>> getImportJobStatus(String eventId, String jobId) {
    return ApiBase.getRaw('/user-contributors/events/$eventId/contributor-imports/$jobId');
  }

  /// Fetch per-row errors for a completed/partially-completed job.
  static Future<Map<String, dynamic>> getImportJobErrors(String eventId, String jobId) {
    return ApiBase.getRaw('/user-contributors/events/$eventId/contributor-imports/$jobId/errors');
  }

  // ────────────────────────────────────────────────────────────────────
  // Guest payment links - host-side actions for the /c/:token web flow.
  // The plain token is returned ONCE; the server stores only its hash.
  // ────────────────────────────────────────────────────────────────────

  /// Generate (or rotate) a one-time guest payment link for one contributor.
  /// Pass `regenerate: true` to invalidate any existing link.
  static Future<Map<String, dynamic>> generateShareLink(
    String eventId,
    String ecId, {
    bool regenerate = false,
  }) {
    return ApiBase.postRaw(
      '/user-contributors/events/$eventId/contributors/$ecId/share-link',
      {'regenerate': regenerate},
    );
  }

  /// Send the freshly-issued share link to the contributor by SMS (TZ for now).
  static Future<Map<String, dynamic>> sendShareLinkSms(
    String eventId,
    String ecId, {
    String? customMessage,
  }) {
    return ApiBase.postRaw(
      '/user-contributors/events/$eventId/contributors/$ecId/send-share-sms',
      customMessage == null ? <String, dynamic>{} : {'custom_message': customMessage},
    );
  }

  /// Disable an existing share link so the URL stops working.
  static Future<Map<String, dynamic>> revokeShareLink(String eventId, String ecId) {
    return ApiBase.postRaw(
      '/user-contributors/events/$eventId/contributors/$ecId/revoke-share-link',
      <String, dynamic>{},
    );
  }
}
