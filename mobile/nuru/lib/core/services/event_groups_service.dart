import 'api_base.dart';
import 'secure_token_storage.dart';

/// Event Groups service - workspace, chat, scoreboard, members & invites.
/// Supports BOTH authenticated Nuru users and group-scoped guest tokens
/// stored under `eg_guest_token` in secure storage.
class EventGroupsService {
  static const _guestKey = 'eg_guest_token';

  static Future<String?> getGuestToken() async {
    return SecureTokenStorage.read(_guestKey);
  }

  static Future<void> saveGuestToken(String token) =>
      SecureTokenStorage.write(_guestKey, token);

  static Future<void> clearGuestToken() =>
      SecureTokenStorage.deleteKey(_guestKey);

  static Future<Map<String, String>> _headers() async {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final tok = await SecureTokenStorage.getToken();
    if (tok != null) h['Authorization'] = 'Bearer $tok';
    final guest = await getGuestToken();
    if (guest != null) h['X-Guest-Token'] = guest;
    return h;
  }

  // ─── Discovery ─────────────────────────────
  static Future<Map<String, dynamic>> listMyGroups({String? search}) {
    return ApiBase.get(
      '/event-groups/',
      queryParams: search != null && search.isNotEmpty ? {'search': search} : null,
      fallbackError: 'Unable to load groups',
    );
  }

  static Future<Map<String, dynamic>> getGroup(String groupId) async {
    return ApiBase.requestWithHeaders(
      method: 'GET',
      endpoint: '/event-groups/$groupId',
      headers: await _headers(),
      fallbackError: 'Unable to load group',
    );
  }

  static Future<Map<String, dynamic>> getForEvent(String eventId) async {
    return ApiBase.requestWithHeaders(
      method: 'GET',
      endpoint: '/event-groups/events/$eventId',
      headers: await _headers(),
      fallbackError: 'Unable to load event group',
    );
  }

  static Future<Map<String, dynamic>> createForEvent(String eventId,
      {Map<String, dynamic>? body}) {
    return ApiBase.post(
      '/event-groups/events/$eventId',
      body ?? {},
      fallbackError: 'Unable to create group',
    );
  }

  static Future<Map<String, dynamic>> openOrCreateForEvent(String eventId) async {
    final got = await getForEvent(eventId);
    if (got['success'] == true && (got['data']?['id'] != null)) return got;
    return createForEvent(eventId);
  }

  // ─── Members ───────────────────────────────
  static Future<Map<String, dynamic>> members(String groupId) async {
    return ApiBase.requestWithHeaders(
      method: 'GET',
      endpoint: '/event-groups/$groupId/members',
      headers: await _headers(),
      fallbackError: 'Unable to load members',
    );
  }

  static Future<Map<String, dynamic>> syncMembers(String groupId) {
    return ApiBase.post('/event-groups/$groupId/sync-members', {},
        fallbackError: 'Unable to sync members');
  }

  static Future<Map<String, dynamic>> createInvite(
      String groupId, {String? contributorId, String? phone, String? name}) {
    final body = <String, dynamic>{};
    if (contributorId != null) body['contributor_id'] = contributorId;
    if (phone != null) body['phone'] = phone;
    if (name != null) body['name'] = name;
    return ApiBase.post('/event-groups/$groupId/invite-link', body,
        fallbackError: 'Unable to create invite');
  }

  // ─── Invites (guest flow) ───────────────────
  static Future<Map<String, dynamic>> previewInvite(String token) {
    return ApiBase.get('/event-groups/invites/$token',
        auth: false, fallbackError: 'Invite unavailable');
  }

  static Future<Map<String, dynamic>> claimInvite(String token,
      {required String name, String? phone}) {
    final body = <String, dynamic>{'name': name};
    if (phone != null && phone.isNotEmpty) body['phone'] = phone;
    return ApiBase.post('/event-groups/invites/$token/claim', body,
        auth: false, fallbackError: 'Unable to join group');
  }

  // ─── Messages ──────────────────────────────
  static Future<Map<String, dynamic>> messages(String groupId,
      {int limit = 50, String? after}) async {
    final qp = <String, String>{'limit': '$limit'};
    if (after != null) qp['after'] = after;
    return ApiBase.requestWithHeaders(
      method: 'GET',
      endpoint: '/event-groups/$groupId/messages',
      queryParams: qp,
      headers: await _headers(),
      fallbackError: 'Unable to load messages',
    );
  }

  static Future<Map<String, dynamic>> sendMessage(String groupId,
      {String? content, String? imageUrl, String? replyToId}) async {
    final body = <String, dynamic>{};
    if (content != null && content.isNotEmpty) body['content'] = content;
    if (imageUrl != null) body['image_url'] = imageUrl;
    if (replyToId != null) body['reply_to_id'] = replyToId;
    return ApiBase.requestWithHeaders(
      method: 'POST',
      endpoint: '/event-groups/$groupId/messages',
      body: body,
      headers: await _headers(),
      fallbackError: 'Unable to send',
    );
  }

  static Future<Map<String, dynamic>> deleteMessage(String groupId, String messageId) async {
    return ApiBase.requestWithHeaders(
      method: 'DELETE',
      endpoint: '/event-groups/$groupId/messages/$messageId',
      headers: await _headers(),
      fallbackError: 'Unable to delete',
    );
  }

  /// Edit an existing text message. Backend enforces 15-minute window.
  static Future<Map<String, dynamic>> editMessage(
      String groupId, String messageId, String content) async {
    return ApiBase.requestWithHeaders(
      method: 'PATCH',
      endpoint: '/event-groups/$groupId/messages/$messageId',
      body: {'content': content},
      headers: await _headers(),
      fallbackError: 'Unable to edit',
    );
  }

  static Future<Map<String, dynamic>> markRead(String groupId) async {
    return ApiBase.requestWithHeaders(
      method: 'POST',
      endpoint: '/event-groups/$groupId/read',
      body: const {},
      headers: await _headers(),
      fallbackError: 'Unable to mark read',
    );
  }

  static Future<Map<String, dynamic>> react(String groupId, String messageId, String emoji) async {
    return ApiBase.requestWithHeaders(
      method: 'POST',
      endpoint: '/event-groups/$groupId/messages/$messageId/reactions',
      body: {'emoji': emoji},
      headers: await _headers(),
      fallbackError: 'Unable to react',
    );
  }

  // ─── Scoreboard ────────────────────────────
  static Future<Map<String, dynamic>> scoreboard(String groupId) async {
    return ApiBase.requestWithHeaders(
      method: 'GET',
      endpoint: '/event-groups/$groupId/scoreboard',
      headers: await _headers(),
      fallbackError: 'Unable to load scoreboard',
    );
  }
}
