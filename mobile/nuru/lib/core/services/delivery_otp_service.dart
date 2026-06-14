import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'secure_token_storage.dart';

/// Service-Delivery OTP - Phase 1.3
/// Mandatory in-person check-in code that gates escrow release.
class DeliveryOtpService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> getState(String bookingId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/delivery-otp/booking/$bookingId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to load check-in'};
    }
  }

  /// Vendor: "I've arrived" → backend issues a fresh 6-digit code.
  static Future<Map<String, dynamic>> arrive(String bookingId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/delivery-otp/booking/$bookingId/arrive'),
        headers: await _headers(),
        body: jsonEncode({}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Could not issue code'};
    }
  }

  /// Vendor: enters the 6-digit code shared by the organiser.
  static Future<Map<String, dynamic>> verify(
      String bookingId, String code) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/delivery-otp/booking/$bookingId/verify'),
        headers: await _headers(),
        body: jsonEncode({'code': code}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Verification failed'};
    }
  }

  static Future<Map<String, dynamic>> cancel(String bookingId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/delivery-otp/booking/$bookingId/cancel'),
        headers: await _headers(),
        body: jsonEncode({}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Cancel failed'};
    }
  }
}
