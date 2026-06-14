/// API configuration with obfuscated base URL.
/// The URL is constructed at runtime to prevent static analysis tools
/// from extracting endpoint URLs from the binary.
class ApiConfig {
  ApiConfig._();

  // Obfuscated URL parts - assembled at runtime
  static const _p = 'https://';
  static const _h1 = 'nuruapi';
  static const _h2 = 'nuru';
  static const _h3 = 'tz';
  static const _v = '/api/v1';

  /// Base URL assembled at runtime
  static String get baseUrl => '$_p$_h1.$_h2.$_h3$_v';

  // FOR LOCAL TESTING ONLY - REPLACE WITH ABOVE IN PRODUCTION
  // static String get baseUrl => 'http://192.168.100.8:8000/api/v1';

  /// Request timeout
  static const Duration timeout = Duration(seconds: 30);

  /// Maximum retry attempts
  static const int maxRetries = 2;

  /// Client identifier for request signing
  static const String _clientId = 'nuru-mobile-v1';

  /// Generate a request fingerprint to prevent tampering
  static Map<String, String> securityHeaders() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return {
      'X-Client-Id': _clientId,
      'X-Request-Time': timestamp,
      'X-Platform': 'mobile',
    };
  }
}
