import 'dart:convert';
import 'package:http/http.dart' as http;
import 'secure_token_storage.dart';
import 'api_config.dart';

/// Messages API service - mirrors src/lib/api/messages.ts
class MessagesService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /messages/ - list conversations (optional ``search``)
  static Future<Map<String, dynamic>> getConversations({String? search}) async {
    try {
      final qp = <String, String>{};
      if (search != null && search.isNotEmpty) qp['search'] = search;
      final uri = Uri.parse('$_baseUrl/messages/').replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to fetch conversations'};
    }
  }

  /// GET /messages/:id - get messages for a conversation
  static Future<Map<String, dynamic>> getMessages(String conversationId, {int page = 1, int limit = 50}) async {
    try {
      final uri = Uri.parse('$_baseUrl/messages/$conversationId').replace(
        queryParameters: {'page': '$page', 'limit': '$limit'},
      );
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to fetch messages'};
    }
  }

  /// POST /messages/:id - send a message
  ///
  /// [encryptionVersion] is sent as `'plain'` by default for backward compatibility
  /// with older servers. Pass `'v1'` once the client uses the transport-framed envelope.
  static Future<Map<String, dynamic>> sendMessage(String conversationId, {
    required String content,
    String? replyToId,
    List<String>? attachments,
    String encryptionVersion = 'plain',
  }) async {
    try {
      final body = <String, dynamic>{
        'content': content,
        'encryption_version': encryptionVersion,
      };
      if (replyToId != null) body['reply_to_id'] = replyToId;
      if (attachments != null && attachments.isNotEmpty) {
        body['attachments'] = attachments;
      }
      final res = await http.post(
        Uri.parse('$_baseUrl/messages/$conversationId'),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to send message'};
    }
  }

  /// POST /messages/start - start a new conversation
  static Future<Map<String, dynamic>> startConversation({
    required String recipientId,
    String? message,
    String? serviceId,
  }) async {
    try {
      final body = <String, dynamic>{'recipient_id': recipientId};
      if (message != null) body['message'] = message;
      if (serviceId != null) body['service_id'] = serviceId;
      final res = await http.post(
        Uri.parse('$_baseUrl/messages/start'),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to start conversation'};
    }
  }

  /// PUT /messages/:id/read - mark as read
  static Future<Map<String, dynamic>> markAsRead(String conversationId) async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/messages/$conversationId/read'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to mark as read'};
    }
  }

  /// DELETE /messages/:id - hide a conversation on the caller's side only.
  /// The other participant still sees the chat. The conversation reappears
  /// for the caller if a new message arrives after this call.
  static Future<Map<String, dynamic>> hideConversation(String conversationId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/messages/$conversationId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to remove conversation'};
    }
  }


  /// GET /messages/unread/count
  static Future<int> getUnreadCount() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/messages/unread/count'),
        headers: await _headers(),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        return data['data']?['count'] ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
