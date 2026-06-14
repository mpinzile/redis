import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'secure_token_storage.dart';
import 'rate_limit_notifier.dart';

void _checkRateLimit(http.Response response, String endpoint) {
  if (response.statusCode != 429) return;
  final retryHeader = response.headers['retry-after'];
  final retryAfter = int.tryParse(retryHeader ?? '') ?? 60;
  final isAuth = endpoint.startsWith('/auth/') ||
      endpoint.startsWith('/users/signup') ||
      endpoint.startsWith('/users/verify-otp') ||
      endpoint.startsWith('/users/request-otp');
  RateLimitNotifier.instance.trigger(retryAfter: retryAfter, isAuth: isAuth);
}

/// Standardized API response matching backend { success, message, data }
class ApiResponse<T> {
  final bool success;
  final String message;
  final T? data;

  ApiResponse({required this.success, required this.message, this.data});

  factory ApiResponse.fromJson(Map<String, dynamic> json, T Function(dynamic)? fromData) {
    return ApiResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      data: json['data'] != null && fromData != null ? fromData(json['data']) : json['data'] as T?,
    );
  }
}

class ApiService {
  static String get baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...ApiConfig.securityHeaders(),
    };
    if (auth) {
      final token = await SecureTokenStorage.getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  static Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    final body = jsonDecode(response.body);
    if (body is Map<String, dynamic> && body.containsKey('success')) {
      return body;
    }
    return {
      'success': response.statusCode >= 200 && response.statusCode < 300,
      'message': body['message'] ?? '',
      'data': body,
    };
  }

  /// POST request
  static Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body, {bool auth = true}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: await _headers(auth: auth),
        body: jsonEncode(body),
      ).timeout(ApiConfig.timeout);
      _checkRateLimit(response, endpoint);
      return _handleResponse(response);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to connect. Please check your internet connection.',
        'data': null,
      };
    }
  }

  /// GET request
  static Future<Map<String, dynamic>> get(String endpoint, {bool auth = true, Map<String, String>? queryParams}) async {
    try {
      var uri = Uri.parse('$baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await http.get(uri, headers: await _headers(auth: auth)).timeout(ApiConfig.timeout);
      _checkRateLimit(response, endpoint);
      return _handleResponse(response);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to connect. Please check your internet connection.',
        'data': null,
      };
    }
  }

  /// PUT request
  static Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> body, {bool auth = true}) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: await _headers(auth: auth),
        body: jsonEncode(body),
      ).timeout(ApiConfig.timeout);
      _checkRateLimit(response, endpoint);
      return _handleResponse(response);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to connect. Please check your internet connection.',
        'data': null,
      };
    }
  }

  /// DELETE request
  static Future<Map<String, dynamic>> delete(String endpoint, {bool auth = true}) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl$endpoint'),
        headers: await _headers(auth: auth),
      ).timeout(ApiConfig.timeout);
      _checkRateLimit(response, endpoint);
      return _handleResponse(response);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to connect. Please check your internet connection.',
        'data': null,
      };
    }
  }
}

/// Auth-specific API calls matching web frontend exactly
class AuthApi {
  /// POST /users/signup
  static Future<Map<String, dynamic>> signup({
    required String firstName,
    required String lastName,
    required String username,
    required String phone,
    required String password,
    String? email,
    String? registeredBy,
  }) {
    return ApiService.post('/users/signup', {
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'phone': phone,
      'password': password,
      'email': email ?? '',
      if (registeredBy != null && registeredBy.isNotEmpty) 'registered_by': registeredBy,
    }, auth: false);
  }

  /// POST /auth/signin
  static Future<Map<String, dynamic>> signin({
    required String credential,
    required String password,
  }) {
    return ApiService.post('/auth/signin', {
      'credential': credential,
      'password': password,
    }, auth: false);
  }

  /// POST /users/verify-otp
  static Future<Map<String, dynamic>> verifyOtp({
    required String userId,
    required String verificationType,
    required String otpCode,
  }) {
    return ApiService.post('/users/verify-otp', {
      'user_id': userId,
      'verification_type': verificationType,
      'otp_code': otpCode,
    }, auth: false);
  }

  /// POST /users/request-otp
  static Future<Map<String, dynamic>> requestOtp({
    required String userId,
    required String verificationType,
  }) {
    return ApiService.post('/users/request-otp', {
      'user_id': userId,
      'verification_type': verificationType,
    }, auth: false);
  }

  /// GET /users/check-username
  static Future<Map<String, dynamic>> checkUsername(String username, {String? firstName, String? lastName}) {
    final params = <String, String>{'username': username};
    if (firstName != null) params['first_name'] = firstName;
    if (lastName != null) params['last_name'] = lastName;
    return ApiService.get('/users/check-username', auth: false, queryParams: params);
  }

  /// GET /users/username-suggestions - proactive Gmail-style suggestions
  /// from the user's name (indexed lookup, never scans the users table).
  static Future<Map<String, dynamic>> getUsernameSuggestions({String? firstName, String? lastName}) {
    final params = <String, String>{};
    if (firstName != null && firstName.isNotEmpty) params['first_name'] = firstName;
    if (lastName != null && lastName.isNotEmpty) params['last_name'] = lastName;
    return ApiService.get('/users/username-suggestions', auth: false, queryParams: params);
  }

  /// GET /users/validate-name
  static Future<Map<String, dynamic>> validateName(String name) {
    return ApiService.get('/users/validate-name', auth: false, queryParams: {'name': name});
  }

  /// GET /auth/me
  static Future<Map<String, dynamic>> me() {
    return ApiService.get('/auth/me');
  }

  /// POST /auth/refresh - exchange a refresh token for a fresh access token.
  /// Sent unauthenticated so a stale access token doesn't trigger another
  /// 401 inside the refresh flow itself.
  static Future<Map<String, dynamic>> refresh(String refreshToken) {
    return ApiService.post(
      '/auth/refresh',
      {'refresh_token': refreshToken},
      auth: false,
    );
  }

  /// POST /auth/forgot-password
  static Future<Map<String, dynamic>> forgotPassword(String email) {
    return ApiService.post('/auth/forgot-password', {'email': email}, auth: false);
  }

  /// POST /auth/forgot-password-phone
  static Future<Map<String, dynamic>> forgotPasswordPhone(String phone) {
    return ApiService.post('/auth/forgot-password-phone', {'phone': phone}, auth: false);
  }

  /// POST /auth/verify-reset-otp
  static Future<Map<String, dynamic>> verifyResetOtp(String phone, String otpCode) {
    return ApiService.post('/auth/verify-reset-otp', {
      'phone': phone,
      'otp_code': otpCode,
    }, auth: false);
  }

  /// POST /auth/reset-password
  static Future<Map<String, dynamic>> resetPassword(String token, String password, String passwordConfirmation) {
    return ApiService.post('/auth/reset-password', {
      'token': token,
      'password': password,
      'password_confirmation': passwordConfirmation,
    }, auth: false);
  }

  /// POST /auth/logout
  static Future<Map<String, dynamic>> logout({Map<String, dynamic>? body}) {
    return ApiService.post('/auth/logout', body ?? {});
  }
}
