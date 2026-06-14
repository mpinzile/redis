import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'secure_token_storage.dart';

/// Escrow Service - Phase 1.1
/// Logical-only ledger for booking funds held by Nuru.
class EscrowService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> getForBooking(String bookingId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/escrow/booking/$bookingId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to load escrow'};
    }
  }

  static Future<Map<String, dynamic>> release(String bookingId,
      {String? reason}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/escrow/booking/$bookingId/release'),
        headers: await _headers(),
        body: jsonEncode({'reason': reason ?? 'organiser_confirmed_delivery'}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Release failed'};
    }
  }

  static Future<Map<String, dynamic>> refund(
      String bookingId, double amount,
      {String? reason}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/escrow/booking/$bookingId/refund'),
        headers: await _headers(),
        body: jsonEncode({
          'amount': amount,
          'reason': reason ?? 'vendor_initiated_refund',
        }),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Refund failed'};
    }
  }

  static Future<Map<String, dynamic>> markSettled(
      String holdId, {String? externalRef}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/escrow/holds/$holdId/mark-settled'),
        headers: await _headers(),
        body: jsonEncode({'external_ref': externalRef}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Mark-settled failed'};
    }
  }
}
