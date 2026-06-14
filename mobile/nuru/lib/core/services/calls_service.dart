import 'dart:convert';
import 'package:http/http.dart' as http;
import 'secure_token_storage.dart';
import 'api_config.dart';

/// REST client for the `/calls/*` endpoints exposed by the FastAPI backend.
/// Mirrors the shape of `MessagesService` so the rest of the app stays
/// consistent (success/data envelope, bearer-token headers, etc.).
class CallsService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// POST /calls/start - caller initiates a 1:1 call inside a conversation.
  /// Returns `{ call: {...}, url, token, room }` on success so the client
  /// can immediately join the LiveKit room.
  static Future<Map<String, dynamic>> startCall({
    required String conversationId,
    String kind = 'voice',
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/calls/start'),
        headers: await _headers(),
        body: jsonEncode({'conversation_id': conversationId, 'kind': kind}),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false, 'message': 'Unable to start call'};
    }
  }

  /// POST /calls/{id}/answer - callee accepts and gets their LiveKit token.
  static Future<Map<String, dynamic>> answer(String callId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/calls/$callId/answer'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false, 'message': 'Unable to answer call'};
    }
  }

  /// POST /calls/{id}/decline - callee rejects a ringing call.
  static Future<Map<String, dynamic>> decline(String callId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/calls/$callId/decline'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false, 'message': 'Unable to decline call'};
    }
  }

  /// POST /calls/{id}/end - either party hangs up / cancels.
  static Future<Map<String, dynamic>> end(String callId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/calls/$callId/end'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false, 'message': 'Unable to end call'};
    }
  }

  /// GET /calls/{id}/status - caller polls this so the screen dismisses
  /// the moment the callee declines / ends / the call times out.
  static Future<String?> getStatus(String callId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/calls/$callId/status'),
        headers: await _headers(),
      );
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true && body['data'] is Map) {
        return (body['data']['status'] ?? '').toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// GET /calls/incoming - short-poll endpoint used by the global call poller
  /// to detect ringing calls. Returns `data: null` when there's nothing.
  static Future<Map<String, dynamic>?> getIncoming() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/calls/incoming'),
        headers: await _headers(),
      );
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        return data is Map ? Map<String, dynamic>.from(data) : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// GET /calls/conversation/{id} - call history rendered as in-thread bubbles.
  static Future<List<dynamic>> listForConversation(String conversationId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/calls/conversation/$conversationId'),
        headers: await _headers(),
      );
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true && body['data'] is List) {
        return body['data'] as List;
      }
    } catch (_) {}
    return const [];
  }

  /// POST /calls/devices - register an FCM/APNs/PushKit token for VoIP push.
  static Future<bool> registerDevice({
    required String platform,
    required String token,
    String kind = 'fcm',
    String? appVersion,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/calls/devices'),
        headers: await _headers(),
        body: jsonEncode({
          'platform': platform,
          'token': token,
          'kind': kind,
          if (appVersion != null) 'app_version': appVersion,
        }),
      );
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// DELETE /calls/devices - unregister on logout.
  static Future<bool> unregisterDevice({required String platform, required String token}) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/calls/devices'),
        headers: await _headers(),
        body: jsonEncode({'platform': platform, 'token': token}),
      );
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (_) {
      return false;
    }
  }
}
