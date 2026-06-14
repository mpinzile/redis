import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'secure_token_storage.dart';

/// Cancellations API (Phase 1.2) - preview + commit refund.
class CancellationsService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Returns the refund breakdown without cancelling.
  static Future<Map<String, dynamic>> previewRefund(
    String bookingId, {
    String cancellingParty = 'organiser',
  }) async {
    try {
      final res = await http.get(
        Uri.parse(
            '$_baseUrl/bookings/$bookingId/refund-preview?cancelling_party=$cancellingParty'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to load refund preview'};
    }
  }

  /// Cancel; backend re-runs the calculator and applies the refund.
  static Future<Map<String, dynamic>> cancel(
      String bookingId, String reason) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/bookings/$bookingId/cancel'),
        headers: await _headers(),
        body: jsonEncode({'reason': reason}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Cancel failed'};
    }
  }
}
