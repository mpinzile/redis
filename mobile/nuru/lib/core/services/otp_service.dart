import 'api_service.dart';

/// Service for OTP delivery via the Nuru backend API.
/// All OTP calls are now proxied through api.nuru.tz - no direct Supabase access.
class OtpService {
  /// Request OTP - routed through backend which calls edge functions server-side
  static Future<Map<String, dynamic>> requestOtp({
    required String phone,
    String? userId,
    String purpose = 'phone_verification',
  }) async {
    try {
      // Use the existing backend endpoint which handles OTP delivery
      if (userId != null) {
        final res = await ApiService.post('/users/request-otp', {
          'user_id': userId,
          'verification_type': 'phone',
        }, auth: false);
        return {
          'success': res['success'] ?? false,
          'message': res['message'] ?? '',
          'channels': <String>[],
          'whatsapp_sent': false,
        };
      }
      // For password reset OTPs without user_id, use forgot-password-phone
      final res = await ApiService.post('/auth/forgot-password-phone', {
        'phone': phone,
      }, auth: false);
      return {
        'success': res['success'] ?? false,
        'message': res['message'] ?? '',
        'channels': <String>[],
        'whatsapp_sent': false,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to send verification code',
        'channels': <String>[],
        'whatsapp_sent': false,
      };
    }
  }

  /// Verify OTP code via backend
  static Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String code,
    String purpose = 'phone_verification',
  }) async {
    try {
      final res = await ApiService.post('/auth/verify-reset-otp', {
        'phone': phone,
        'otp_code': code,
      }, auth: false);
      return {
        'success': res['success'] ?? false,
        'message': res['message'] ?? '',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Verification failed. Please try again.',
      };
    }
  }
}