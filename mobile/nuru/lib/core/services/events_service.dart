import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:nuru/core/services/event_committee_service.dart';
import 'package:nuru/core/services/event_contributors_service.dart';
import 'package:nuru/core/services/event_extras_service.dart';
import 'package:nuru/core/services/event_finance_service.dart';
import 'package:nuru/core/services/event_guests_service.dart';
import 'package:nuru/core/services/event_schedule_service.dart';
import 'api_base.dart';
import 'api_config.dart';
import 'secure_token_storage.dart';

export 'event_guests_service.dart';
export 'event_finance_service.dart';
export 'event_schedule_service.dart';
export 'event_contributors_service.dart';
export 'event_committee_service.dart';
export 'event_extras_service.dart';

class EventsService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authOnlyHeaders() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> getProfile() {
    return ApiBase.get(
      '/users/profile',
      fallbackError: 'Unable to fetch profile',
    );
  }

  static Future<Map<String, dynamic>> getUserById(String userId) {
    return ApiBase.getRaw('/users/$userId');
  }

  static Future<Map<String, dynamic>> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? bio,
    String? location,
    String? avatarPath,
    String? coverPath,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/users/profile');
      final request = http.MultipartRequest('PUT', uri);
      request.headers.addAll(await _authOnlyHeaders());
      if (firstName != null) request.fields['first_name'] = firstName;
      if (lastName != null) request.fields['last_name'] = lastName;
      if (phone != null) request.fields['phone'] = phone;
      if (bio != null) request.fields['bio'] = bio;
      if (location != null) request.fields['location'] = location;
      // Backend validates `avatar.content_type` against an allowlist of
      // image/* mime types (see profile.py). MultipartFile.fromPath without
      // an explicit contentType falls back to application/octet-stream,
      // which made the upload fail with "Validation failed". Derive the
      // mime from the file extension and pass it explicitly.
      if (avatarPath != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'avatar',
            avatarPath,
            contentType: _imageMediaType(avatarPath),
          ),
        );
      }
      if (coverPath != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'cover_image',
            coverPath,
            contentType: _imageMediaType(coverPath),
          ),
        );
      }
      final streamedRes = await request.send();
      final body = await streamedRes.stream.bytesToString();
      final fakeResponse = http.Response(body, streamedRes.statusCode);
      return ApiBase.normalizeResponse(
        fakeResponse,
        fallbackError: 'Unable to update profile',
      );
    } catch (_) {
      return {
        'success': false,
        'message': 'Unable to update profile',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) {
    return ApiBase.postRaw('/users/change-password', {
      'current_password': currentPassword,
      'new_password': newPassword,
      'confirm_password': confirmPassword,
    });
  }

  static Future<Map<String, dynamic>> getMyEvents({
    int page = 1,
    int limit = 20,
    String? status,
    String? search,
    // The mobile "My Events" tab is strictly the events I created. Without
    // this flag the backend also returns events somebody else recorded
    // against me via event_owner_user_id, which leaks invitations/owned-on-
    // behalf-of rows into the creator list.
    bool createdOnly = true,
  }) {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (status != null && status != 'all') params['status'] = status;
    if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();
    if (createdOnly) params['created_only'] = 'true';
    return ApiBase.get(
      '/user-events/',
      queryParams: params,
      fallbackError: 'Unable to fetch events',
    );
  }

  static Future<Map<String, dynamic>> getInvitedEvents({
    int page = 1,
    int limit = 20,
  }) {
    return ApiBase.getRaw('/user-events/invited?page=$page&limit=$limit');
  }

  static Future<Map<String, dynamic>> getCommitteeEvents({
    int page = 1,
    int limit = 20,
  }) {
    return ApiBase.getRaw('/user-events/committee?page=$page&limit=$limit');
  }

  /// fields: 'essential' (default - fast, includes inline permissions) or 'full'.
  static Future<Map<String, dynamic>> getEventById(String eventId, {String fields = 'essential'}) {
    return ApiBase.getRaw('/user-events/$eventId?fields=$fields');
  }

  static Future<Map<String, dynamic>> getMyPermissions(String eventId) {
    return ApiBase.getRaw('/user-events/$eventId/my-permissions');
  }

  static Future<Map<String, dynamic>> createEvent({
    required String title,
    required String eventType,
    String? description,
    String? startDate,
    String? endDate,
    String? location,
    String? venue,
    String? imagePath,
    String visibility = 'private',
    int? expectedGuests,
    double? budget,
    bool sellsTickets = false,
    bool isPublic = false,
    String? dressCode,
    String? specialInstructions,
    String? time,
    double? venueLatitude,
    double? venueLongitude,
    String? venueAddress,
    String? reminderContactPhone,
    String? contributionPaymentInstructions,
    List<Map<String, dynamic>>? whatToExpect,
    String? whatToExpectNotes,
    List<Map<String, dynamic>>? extraDetails,
    String? guestOfHonor,
    String status = 'published',
    bool createdForSomeoneElse = false,
    String? eventOwnerUserId,
    String? recognizableEventOwnerName,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/user-events/');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authOnlyHeaders());
      request.fields['title'] = title;
      request.fields['event_type_id'] = eventType;
      request.fields['is_public'] = isPublic ? 'true' : 'false';
      request.fields['sells_tickets'] = sellsTickets ? 'true' : 'false';
      request.fields['status'] = status;
      if (description != null && description.isNotEmpty)
        request.fields['description'] = description;
      if (startDate != null) request.fields['start_date'] = startDate;
      if (endDate != null) request.fields['end_date'] = endDate;
      if (time != null && time.isNotEmpty) request.fields['time'] = time;
      if (location != null && location.isNotEmpty)
        request.fields['location'] = location;
      if (venue != null && venue.isNotEmpty) request.fields['venue'] = venue;
      if (expectedGuests != null)
        request.fields['expected_guests'] = '$expectedGuests';
      if (budget != null) request.fields['budget'] = '$budget';
      if (dressCode != null && dressCode.isNotEmpty)
        request.fields['dress_code'] = dressCode;
      if (specialInstructions != null && specialInstructions.isNotEmpty)
        request.fields['special_instructions'] = specialInstructions;
      if (venueLatitude != null)
        request.fields['venue_latitude'] = '$venueLatitude';
      if (venueLongitude != null)
        request.fields['venue_longitude'] = '$venueLongitude';
      if (venueAddress != null && venueAddress.isNotEmpty)
        request.fields['venue_address'] = venueAddress;
      if (reminderContactPhone != null)
        request.fields['reminder_contact_phone'] = reminderContactPhone;
      if (contributionPaymentInstructions != null)
        request.fields['contribution_payment_instructions'] = contributionPaymentInstructions;
      if (whatToExpect != null)
        request.fields['what_to_expect'] = jsonEncode(whatToExpect);
      if (whatToExpectNotes != null)
        request.fields['what_to_expect_notes'] = whatToExpectNotes;
      if (extraDetails != null)
        request.fields['extra_details'] = jsonEncode(extraDetails);
      if (guestOfHonor != null && guestOfHonor.isNotEmpty)
        request.fields['guest_of_honor'] = guestOfHonor;
      request.fields['created_for_someone_else'] = createdForSomeoneElse ? 'true' : 'false';
      if (createdForSomeoneElse && eventOwnerUserId != null && eventOwnerUserId.isNotEmpty) {
        request.fields['event_owner_user_id'] = eventOwnerUserId;
      }
      if (createdForSomeoneElse && recognizableEventOwnerName != null && recognizableEventOwnerName.trim().isNotEmpty) {
        request.fields['recognizable_event_owner_name'] = recognizableEventOwnerName.trim();
      }
      if (imagePath != null)
        request.files.add(
          await http.MultipartFile.fromPath('cover_image', imagePath),
        );
      final streamedRes = await request.send();
      final body = await streamedRes.stream.bytesToString();
      return jsonDecode(body);
    } catch (_) {
      return {
        'success': false,
        'message': 'Unable to create event',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> updateEvent(
    String eventId, {
    String? title,
    String? description,
    String? eventTypeId,
    String? startDate,
    String? endDate,
    String? location,
    String? venue,
    String? imagePath,
    String? visibility,
    int? expectedGuests,
    double? budget,
    bool? sellsTickets,
    bool? isPublic,
    String? dressCode,
    String? specialInstructions,
    String? time,
    double? venueLatitude,
    double? venueLongitude,
    String? venueAddress,
    String? reminderContactPhone,
    String? contributionPaymentInstructions,
    List<Map<String, dynamic>>? whatToExpect,
    String? whatToExpectNotes,
    List<Map<String, dynamic>>? extraDetails,
    String? guestOfHonor,
    String? invitationTemplateId,
    String? invitationAccentColor,
    Map<String, dynamic>? invitationContent,
    bool? createdForSomeoneElse,
    String? eventOwnerUserId,
    String? recognizableEventOwnerName,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/user-events/$eventId');
      final request = http.MultipartRequest('PUT', uri);
      request.headers.addAll(await _authOnlyHeaders());
      if (title != null) request.fields['title'] = title;
      if (description != null) request.fields['description'] = description;
      if (eventTypeId != null) request.fields['event_type_id'] = eventTypeId;
      if (startDate != null) request.fields['start_date'] = startDate;
      if (endDate != null) request.fields['end_date'] = endDate;
      if (time != null && time.isNotEmpty) request.fields['time'] = time;
      if (location != null) request.fields['location'] = location;
      if (venue != null) request.fields['venue'] = venue;
      if (expectedGuests != null)
        request.fields['expected_guests'] = '$expectedGuests';
      if (budget != null) request.fields['budget'] = '$budget';
      if (sellsTickets != null)
        request.fields['sells_tickets'] = sellsTickets ? 'true' : 'false';
      if (isPublic != null)
        request.fields['is_public'] = isPublic ? 'true' : 'false';
      if (dressCode != null) request.fields['dress_code'] = dressCode;
      if (specialInstructions != null)
        request.fields['special_instructions'] = specialInstructions;
      if (venueLatitude != null)
        request.fields['venue_latitude'] = '$venueLatitude';
      if (venueLongitude != null)
        request.fields['venue_longitude'] = '$venueLongitude';
      if (venueAddress != null && venueAddress.isNotEmpty)
        request.fields['venue_address'] = venueAddress;
      if (reminderContactPhone != null)
        request.fields['reminder_contact_phone'] = reminderContactPhone;
      if (contributionPaymentInstructions != null)
        request.fields['contribution_payment_instructions'] = contributionPaymentInstructions;
      if (whatToExpect != null)
        request.fields['what_to_expect'] = jsonEncode(whatToExpect);
      if (whatToExpectNotes != null)
        request.fields['what_to_expect_notes'] = whatToExpectNotes;
      if (extraDetails != null)
        request.fields['extra_details'] = jsonEncode(extraDetails);
      if (guestOfHonor != null)
        request.fields['guest_of_honor'] = guestOfHonor;
      if (invitationTemplateId != null)
        request.fields['invitation_template_id'] = invitationTemplateId;
      if (invitationAccentColor != null)
        request.fields['invitation_accent_color'] = invitationAccentColor;
      if (invitationContent != null)
        request.fields['invitation_content'] = jsonEncode(invitationContent);
      if (createdForSomeoneElse != null) {
        request.fields['created_for_someone_else'] = createdForSomeoneElse ? 'true' : 'false';
      }
      if (eventOwnerUserId != null) {
        request.fields['event_owner_user_id'] = eventOwnerUserId;
      }
      if (recognizableEventOwnerName != null) {
        request.fields['recognizable_event_owner_name'] = recognizableEventOwnerName.trim();
      }
      if (imagePath != null && imagePath.isNotEmpty) {
        request.files.add(
          await http.MultipartFile.fromPath('cover_image', imagePath),
        );
      }
      final streamedRes = await request.send();
      final body = await streamedRes.stream.bytesToString();
      return jsonDecode(body);
    } catch (_) {
      return {
        'success': false,
        'message': 'Unable to update event',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> deleteEvent(String eventId) {
    return ApiBase.deleteRaw('/user-events/$eventId');
  }

  static Future<Map<String, dynamic>> updateEventStatus(
    String eventId,
    String status,
  ) {
    return ApiBase.putRaw('/user-events/$eventId/status', {'status': status});
  }

  // Backward-compatible delegates to sub-services
  static Future<Map<String, dynamic>> getGuests(
    String eventId, {
    int page = 1,
    int limit = 50,
    String? search,
    String? rsvpStatus,
  }) => EventGuestsService.getGuests(
    eventId,
    page: page,
    limit: limit,
    search: search,
    rsvpStatus: rsvpStatus,
  );
  static Future<Map<String, dynamic>> addGuest(
    String eventId,
    Map<String, dynamic> data,
  ) => EventGuestsService.addGuest(eventId, data);
  static Future<Map<String, dynamic>> updateGuest(
    String eventId,
    String guestId,
    Map<String, dynamic> data,
  ) => EventGuestsService.updateGuest(eventId, guestId, data);
  static Future<Map<String, dynamic>> deleteGuest(
    String eventId,
    String guestId,
  ) => EventGuestsService.deleteGuest(eventId, guestId);
  static Future<Map<String, dynamic>> sendInvitation(
    String eventId,
    String guestId, {
    String method = 'whatsapp',
    String? customMessage,
  }) => EventGuestsService.sendInvitation(
    eventId,
    guestId,
    method: method,
    customMessage: customMessage,
  );
  static Future<Map<String, dynamic>> sendBulkInvitations(
    String eventId, {
    String method = 'whatsapp',
    List<String>? guestIds,
  }) => EventGuestsService.sendBulkInvitations(
    eventId,
    method: method,
    guestIds: guestIds,
  );
  static Future<Map<String, dynamic>> checkinGuest(
    String eventId,
    String guestId, {
    int? plusOnes,
    String? notes,
  }) => EventGuestsService.checkinGuest(
    eventId,
    guestId,
    plusOnes: plusOnes,
    notes: notes,
  );
  static Future<Map<String, dynamic>> checkinByQR(
    String eventId,
    String qrCode,
  ) => EventGuestsService.checkinByQR(eventId, qrCode);
  static Future<Map<String, dynamic>> getScanStats(String eventId, {int limit = 10}) =>
      EventGuestsService.getScanStats(eventId, limit: limit);
  static Future<Map<String, dynamic>> undoCheckin(
    String eventId,
    String guestId,
  ) => EventGuestsService.undoCheckin(eventId, guestId);
  static Future<Map<String, dynamic>> respondToInvitation(
    String eventId,
    String rsvpStatus, {
    String? mealPreference,
    String? dietaryRestrictions,
  }) => EventGuestsService.respondToInvitation(
    eventId,
    rsvpStatus,
    mealPreference: mealPreference,
    dietaryRestrictions: dietaryRestrictions,
  );

  static Future<Map<String, dynamic>> getCommittee(String eventId) =>
      EventCommitteeService.getCommittee(eventId);
  static Future<Map<String, dynamic>> addCommitteeMember(
    String eventId,
    Map<String, dynamic> data,
  ) => EventCommitteeService.addCommitteeMember(eventId, data);
  static Future<Map<String, dynamic>> removeCommitteeMember(
    String eventId,
    String memberId,
  ) => EventCommitteeService.removeCommitteeMember(eventId, memberId);
  static Future<Map<String, dynamic>> updateCommitteeMember(
    String eventId,
    String memberId,
    Map<String, dynamic> data,
  ) => EventCommitteeService.updateCommitteeMember(eventId, memberId, data);
  static Future<Map<String, dynamic>> resendCommitteeInvitation(
    String eventId,
    String memberId,
  ) => EventCommitteeService.resendCommitteeInvitation(eventId, memberId);
  static Future<Map<String, dynamic>> getAssignableMembers(String eventId) =>
      EventCommitteeService.getAssignableMembers(eventId);

  static Future<Map<String, dynamic>> getUserContributors({
    String? search,
    int page = 1,
    int limit = 100,
  }) => EventContributorsService.getUserContributors(
    search: search,
    page: page,
    limit: limit,
  );
  static Future<Map<String, dynamic>> getEventContributors(
    String eventId, {
    int page = 1,
    int limit = 5000,
  }) => EventContributorsService.getEventContributors(
    eventId,
    page: page,
    limit: limit,
  );
  static Future<Map<String, dynamic>> addContributorToEvent(
    String eventId,
    Map<String, dynamic> data,
  ) => EventContributorsService.addContributorToEvent(eventId, data);
  static Future<Map<String, dynamic>> recordContributorPayment(
    String eventId,
    String ecId,
    Map<String, dynamic> data,
  ) => EventContributorsService.recordContributorPayment(eventId, ecId, data);
  static Future<Map<String, dynamic>> updateEventContributor(
    String eventId,
    String ecId,
    Map<String, dynamic> data,
  ) => EventContributorsService.updateEventContributor(eventId, ecId, data);
  static Future<Map<String, dynamic>> removeContributorFromEvent(
    String eventId,
    String ecId,
  ) => EventContributorsService.removeContributorFromEvent(eventId, ecId);

  static Future<Map<String, dynamic>> getPaymentHistory(
    String eventId, String ecId,
  ) => EventContributorsService.getPaymentHistory(eventId, ecId);

  static Future<Map<String, dynamic>> deleteTransaction(
    String eventId, String ecId, String paymentId,
  ) => EventContributorsService.deleteTransaction(eventId, ecId, paymentId);

  static Future<Map<String, dynamic>> sendThankYou(
    String eventId, String ecId, Map<String, dynamic> data,
  ) => EventContributorsService.sendThankYou(eventId, ecId, data);

  static Future<Map<String, dynamic>> getPendingContributions(
    String eventId,
  ) => EventContributorsService.getPendingContributions(eventId);

  static Future<Map<String, dynamic>> confirmContributions(
    String eventId, List<String> contributionIds,
  ) => EventContributorsService.confirmContributions(eventId, contributionIds);

  static Future<Map<String, dynamic>> rejectContributions(
    String eventId, List<String> contributionIds,
  ) => EventContributorsService.rejectContributions(eventId, contributionIds);

  static Future<Map<String, dynamic>> sendBulkReminder(
    String eventId, Map<String, dynamic> data,
  ) => EventContributorsService.sendBulkReminder(eventId, data);

  /// Saved per-event SMS templates (mirrors web Contributor Messaging).
  static Future<Map<String, dynamic>> getMessagingTemplates(String eventId) =>
      EventContributorsService.getMessagingTemplates(eventId);

  static Future<Map<String, dynamic>> saveMessagingTemplate(
    String eventId, String caseType, Map<String, dynamic> data,
  ) => EventContributorsService.saveMessagingTemplate(eventId, caseType, data);

  static Future<Map<String, dynamic>> addContributorsAsGuests(
    String eventId, Map<String, dynamic> data,
  ) => EventContributorsService.addContributorsAsGuests(eventId, data);

  static Future<Map<String, dynamic>> bulkAddContributors(
    String eventId, Map<String, dynamic> data,
  ) => EventContributorsService.bulkAddToEvent(eventId, data);

  static Future<Map<String, dynamic>> getBudget(String eventId) =>
      EventFinanceService.getBudget(eventId);
  static Future<Map<String, dynamic>> addBudgetItem(
    String eventId,
    Map<String, dynamic> data,
  ) => EventFinanceService.addBudgetItem(eventId, data);
  static Future<Map<String, dynamic>> updateBudgetItem(
    String eventId,
    String itemId,
    Map<String, dynamic> data,
  ) => EventFinanceService.updateBudgetItem(eventId, itemId, data);
  static Future<Map<String, dynamic>> deleteBudgetItem(
    String eventId,
    String itemId,
  ) => EventFinanceService.deleteBudgetItem(eventId, itemId);
  static Future<Map<String, dynamic>> getExpenses(String eventId) =>
      EventFinanceService.getExpenses(eventId);
  static Future<Map<String, dynamic>> addExpense(
    String eventId,
    Map<String, dynamic> data,
  ) => EventFinanceService.addExpense(eventId, data);
  static Future<Map<String, dynamic>> deleteExpense(
    String eventId,
    String expenseId,
  ) => EventFinanceService.deleteExpense(eventId, expenseId);
  static Future<Map<String, dynamic>> getContributions(
    String eventId, {
    int page = 1,
    int limit = 50,
  }) => EventFinanceService.getContributions(eventId, page: page, limit: limit);

  static Future<Map<String, dynamic>> getRecentActivity(
    String eventId, {
    int limit = 10,
  }) => ApiBase.get('/user-events/$eventId/recent-activity', queryParams: {'limit': '$limit'});

  /// Unified Event Management overview - KPIs, ticket sales, contribution
  /// status, revenue summary and sponsor totals in a single call. The
  /// numbers are authoritative - never recompute or hardcode them on the client.
  static Future<Map<String, dynamic>> getManagementOverview(String eventId) =>
      ApiBase.getRaw('/user-events/$eventId/management-overview');

  // ── Event sponsors ──
  static Future<Map<String, dynamic>> getSponsors(String eventId) =>
      ApiBase.getRaw('/user-events/$eventId/sponsors');
  static Future<Map<String, dynamic>> inviteSponsor(
    String eventId,
    Map<String, dynamic> body,
  ) => ApiBase.postRaw('/user-events/$eventId/sponsors', body);
  static Future<Map<String, dynamic>> cancelSponsor(
    String eventId,
    String sponsorId,
  ) => ApiBase.deleteRaw('/user-events/$eventId/sponsors/$sponsorId');
  static Future<Map<String, dynamic>> addContribution(
    String eventId,
    Map<String, dynamic> data,
  ) => EventFinanceService.addContribution(eventId, data);
  static Future<Map<String, dynamic>> updateContribution(
    String eventId,
    String contributionId,
    Map<String, dynamic> data,
  ) => EventFinanceService.updateContribution(eventId, contributionId, data);
  static Future<Map<String, dynamic>> deleteContribution(
    String eventId,
    String contributionId,
  ) => EventFinanceService.deleteContribution(eventId, contributionId);

  static Future<Map<String, dynamic>> getSchedule(String eventId) =>
      EventScheduleService.getSchedule(eventId);
  static Future<Map<String, dynamic>> addScheduleItem(
    String eventId,
    Map<String, dynamic> data,
  ) => EventScheduleService.addScheduleItem(eventId, data);
  static Future<Map<String, dynamic>> updateScheduleItem(
    String eventId,
    String itemId,
    Map<String, dynamic> data,
  ) => EventScheduleService.updateScheduleItem(eventId, itemId, data);
  static Future<Map<String, dynamic>> deleteScheduleItem(
    String eventId,
    String itemId,
  ) => EventScheduleService.deleteScheduleItem(eventId, itemId);
  static Future<Map<String, dynamic>> getChecklist(String eventId) =>
      EventScheduleService.getChecklist(eventId);
  static Future<Map<String, dynamic>> addChecklistItem(
    String eventId,
    Map<String, dynamic> data,
  ) => EventScheduleService.addChecklistItem(eventId, data);
  static Future<Map<String, dynamic>> updateChecklistItem(
    String eventId,
    String itemId,
    Map<String, dynamic> data,
  ) => EventScheduleService.updateChecklistItem(eventId, itemId, data);
  static Future<Map<String, dynamic>> deleteChecklistItem(
    String eventId,
    String itemId,
  ) => EventScheduleService.deleteChecklistItem(eventId, itemId);
  static Future<Map<String, dynamic>> getTemplates({String? eventTypeId}) =>
      EventScheduleService.getTemplates(eventTypeId: eventTypeId);
  static Future<Map<String, dynamic>> applyTemplate(
    String eventId,
    String templateId, {
    bool clearExisting = false,
  }) => EventScheduleService.applyTemplate(
    eventId,
    templateId,
    clearExisting: clearExisting,
  );

  static Future<Map<String, dynamic>> getSettings() =>
      EventExtrasService.getSettings();
  static Future<Map<String, dynamic>> updateNotificationSettings(
    Map<String, dynamic> data,
  ) => EventExtrasService.updateNotificationSettings(data);
  static Future<Map<String, dynamic>> updatePrivacySettings(
    Map<String, dynamic> data,
  ) => EventExtrasService.updatePrivacySettings(data);
  static Future<Map<String, dynamic>> getVerificationStatus() =>
      EventExtrasService.getVerificationStatus();
  static Future<Map<String, dynamic>> submitVerification({
    String? documentNumber,
    required String idFrontPath,
    String? idBackPath,
    String? selfiePath,
  }) => EventExtrasService.submitVerification(
    documentNumber: documentNumber,
    idFrontPath: idFrontPath,
    idBackPath: idBackPath,
    selfiePath: selfiePath,
  );
  static Future<Map<String, dynamic>> searchUsers(
    String query, {
    int limit = 20,
  }) => EventExtrasService.searchUsers(query, limit: limit);
  static Future<Map<String, dynamic>> getInvitationCard(
    String eventId, {
    String? guestId,
  }) => EventExtrasService.getInvitationCard(eventId, guestId: guestId);
  static Future<Map<String, dynamic>> getEventServices(String eventId) =>
      EventExtrasService.getEventServices(eventId);
  static Future<Map<String, dynamic>> addEventService(
    String eventId,
    Map<String, dynamic> data,
  ) => EventExtrasService.addEventService(eventId, data);
  static Future<Map<String, dynamic>> addManualVendor(
    String eventId,
    Map<String, dynamic> data,
  ) => EventExtrasService.addManualVendor(eventId, data);
  static Future<Map<String, dynamic>> downloadVendorsReport(
    String eventId, {
    String format = 'pdf',
  }) => EventExtrasService.downloadVendorsReport(eventId, format: format);
  static Future<Map<String, dynamic>> getServiceCategories() =>
      EventExtrasService.getServiceCategories();
  static Future<Map<String, dynamic>> removeEventService(
    String eventId,
    String serviceId,
  ) => EventExtrasService.removeEventService(eventId, serviceId);
  static Future<Map<String, dynamic>> searchServicesPublic(
    String query, {
    String? eventTypeId,
    int limit = 10,
  }) => EventExtrasService.searchServicesPublic(
    query,
    eventTypeId: eventTypeId,
    limit: limit,
  );
  static Future<Map<String, dynamic>> getServices({
    int limit = 20,
    String? category,
    String? search,
  }) => EventExtrasService.getServices(
    limit: limit,
    category: category,
    search: search,
  );
  static Future<Map<String, dynamic>> getEventTypes() =>
      EventExtrasService.getEventTypes();
  static Future<Map<String, dynamic>> downloadReport(
    String eventId, {
    String format = 'pdf',
    String section = 'full',
  }) => EventExtrasService.downloadReport(
    eventId,
    format: format,
    section: section,
  );
}

/// Map a local image file path to a valid `image/*` MediaType, defaulting
/// to `image/jpeg` for unknown extensions. Backend allows jpeg/jpg/png/webp.
MediaType _imageMediaType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return MediaType('image', 'png');
  if (lower.endsWith('.webp')) return MediaType('image', 'webp');
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    // Backend rejects HEIC; still send a real image/* type so the server
    // returns a clear "Only jpg/png/webp" error instead of generic failure.
    return MediaType('image', 'heic');
  }
  return MediaType('image', 'jpeg');
}
