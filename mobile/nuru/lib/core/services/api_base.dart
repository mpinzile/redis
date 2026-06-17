import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'secure_token_storage.dart';
import 'api_config.dart';
import 'rate_limit_notifier.dart';
import 'checkin_session.dart';

void _checkRateLimit(http.Response res, String endpoint) {
  if (res.statusCode != 429) return;
  final retryAfter = int.tryParse(res.headers['retry-after'] ?? '') ?? 60;
  final isAuth = endpoint.startsWith('/auth/') ||
      endpoint.startsWith('/users/signup') ||
      endpoint.startsWith('/users/verify-otp') ||
      endpoint.startsWith('/users/request-otp');
  RateLimitNotifier.instance.trigger(retryAfter: retryAfter, isAuth: isAuth);
}

/// Single-flight refresh: if multiple requests hit 401 simultaneously, only
/// the first one calls /auth/refresh; the rest await the same Future. This
/// prevents thundering-herd refresh storms and racey token overwrites that
/// would otherwise log the user out.
Completer<bool>? _refreshInFlight;
Future<bool> _attemptRefresh() async {
  if (_refreshInFlight != null) return _refreshInFlight!.future;
  final c = Completer<bool>();
  _refreshInFlight = c;
  try {
    final rt = await SecureTokenStorage.getRefreshToken();
    if (rt == null || rt.isEmpty) {
      c.complete(false);
      return false;
    }
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/refresh'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'refresh_token': rt}),
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      c.complete(false);
      return false;
    }
    final body = jsonDecode(res.body);
    final data = (body is Map && body['data'] is Map) ? body['data'] as Map : body;
    final newAccess = (data is Map ? data['access_token'] : null)?.toString();
    final newRefresh = (data is Map ? data['refresh_token'] : null)?.toString();
    if (newAccess == null || newAccess.isEmpty) {
      c.complete(false);
      return false;
    }
    await SecureTokenStorage.setToken(newAccess);
    if (newRefresh != null && newRefresh.isNotEmpty) {
      await SecureTokenStorage.setRefreshToken(newRefresh);
    }
    c.complete(true);
    return true;
  } catch (_) {
    if (!c.isCompleted) c.complete(false);
    return false;
  } finally {
    _refreshInFlight = null;
  }
}

/// Returns true if the response indicates an expired/invalid bearer token
/// that the refresh-token flow should attempt to recover from.
bool _isAuthExpired(http.Response res) =>
    res.statusCode == 401 || res.statusCode == 419;

void _debugAutomationHttp(String method, String endpoint, http.Response res) {
  if (!endpoint.contains('/automations')) return;
  print('[Automations API] $method $endpoint -> HTTP ${res.statusCode}');
  print('[Automations API] response body: ${res.body}');
}

void _debugAutomationError(String method, String endpoint, Object error) {
  if (!endpoint.contains('/automations')) return;
  print('[Automations API] $method $endpoint threw: $error');
}

class ApiBase {
  static String get baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> headers({bool auth = true}) async {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final token = await SecureTokenStorage.getToken();
      if (token != null) h['Authorization'] = 'Bearer $token';
    }
    // Scanner team members operate inside a scoped Check-In Mode session.
    // Forward the session token so the backend can audit scans to the team
    // member and enforce per-session permissions (guests / tickets / both).
    final cs = CheckinSession.token;
    if (cs != null && cs.isNotEmpty) {
      h['X-Checkin-Session'] = cs;
    }
    return h;
  }

  static Future<Map<String, String>> authOnlyHeaders() async {
    final h = <String, String>{'Accept': 'application/json'};
    final token = await SecureTokenStorage.getToken();
    if (token != null) h['Authorization'] = 'Bearer $token';
    final cs = CheckinSession.token;
    if (cs != null && cs.isNotEmpty) {
      h['X-Checkin-Session'] = cs;
    }
    return h;
  }

  static Map<String, dynamic> normalizeResponse(
    http.Response res, {
    String fallbackError = 'Request failed',
  }) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic> && decoded.containsKey('success')) {
        return decoded;
      }
      return {
        'success': res.statusCode >= 200 && res.statusCode < 300,
        'message': decoded is Map ? (decoded['message']?.toString() ?? '') : '',
        'data': decoded,
      };
    } catch (_) {
      return {'success': false, 'message': fallbackError, 'data': null};
    }
  }

  static Future<Map<String, dynamic>> get(
    String endpoint, {
    bool auth = true,
    Map<String, String>? queryParams,
    String fallbackError = 'Request failed',
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      var res = await http
          .get(uri, headers: await headers(auth: auth))
          .timeout(ApiConfig.timeout);
      if (auth && _isAuthExpired(res) && await _attemptRefresh()) {
        res = await http
            .get(uri, headers: await headers(auth: auth))
            .timeout(ApiConfig.timeout);
      }
      _checkRateLimit(res, endpoint);
      return normalizeResponse(res, fallbackError: fallbackError);
    } catch (_) {
      return {'success': false, 'message': fallbackError, 'data': null};
    }
  }

  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body, {
    bool auth = true,
    String fallbackError = 'Request failed',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final encoded = jsonEncode(body);
      var res = await http
          .post(uri, headers: await headers(auth: auth), body: encoded)
          .timeout(ApiConfig.timeout);
      if (auth && _isAuthExpired(res) && await _attemptRefresh()) {
        res = await http
            .post(uri, headers: await headers(auth: auth), body: encoded)
            .timeout(ApiConfig.timeout);
      }
      _debugAutomationHttp('POST', endpoint, res);
      _checkRateLimit(res, endpoint);
      return normalizeResponse(res, fallbackError: fallbackError);
    } catch (e) {
      _debugAutomationError('POST', endpoint, e);
      return {'success': false, 'message': fallbackError, 'data': null};
    }
  }

  static Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> body, {
    bool auth = true,
    String fallbackError = 'Request failed',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final encoded = jsonEncode(body);
      var res = await http
          .put(uri, headers: await headers(auth: auth), body: encoded)
          .timeout(ApiConfig.timeout);
      if (auth && _isAuthExpired(res) && await _attemptRefresh()) {
        res = await http
            .put(uri, headers: await headers(auth: auth), body: encoded)
            .timeout(ApiConfig.timeout);
      }
      _checkRateLimit(res, endpoint);
      return normalizeResponse(res, fallbackError: fallbackError);
    } catch (_) {
      return {'success': false, 'message': fallbackError, 'data': null};
    }
  }

  static Future<Map<String, dynamic>> patch(
    String endpoint,
    Map<String, dynamic> body, {
    bool auth = true,
    String fallbackError = 'Request failed',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final encoded = jsonEncode(body);
      var res = await http
          .patch(uri, headers: await headers(auth: auth), body: encoded)
          .timeout(ApiConfig.timeout);
      if (auth && _isAuthExpired(res) && await _attemptRefresh()) {
        res = await http
            .patch(uri, headers: await headers(auth: auth), body: encoded)
            .timeout(ApiConfig.timeout);
      }
      _debugAutomationHttp('PATCH', endpoint, res);
      _checkRateLimit(res, endpoint);
      return normalizeResponse(res, fallbackError: fallbackError);
    } catch (e) {
      _debugAutomationError('PATCH', endpoint, e);
      return {'success': false, 'message': fallbackError, 'data': null};
    }
  }

  static Future<Map<String, dynamic>> delete(
    String endpoint, {
    bool auth = true,
    String fallbackError = 'Request failed',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      var res = await http
          .delete(uri, headers: await headers(auth: auth))
          .timeout(ApiConfig.timeout);
      if (auth && _isAuthExpired(res) && await _attemptRefresh()) {
        res = await http
            .delete(uri, headers: await headers(auth: auth))
            .timeout(ApiConfig.timeout);
      }
      _checkRateLimit(res, endpoint);
      return normalizeResponse(res, fallbackError: fallbackError);
    } catch (_) {
      return {'success': false, 'message': fallbackError, 'data': null};
    }
  }

  static Future<Map<String, dynamic>> getRaw(String endpoint) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: await headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false, 'message': 'Request failed', 'data': null};
    }
  }

  static Future<Map<String, dynamic>> postRaw(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: await headers(),
        body: jsonEncode(body),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false, 'message': 'Request failed', 'data': null};
    }
  }

  static Future<Map<String, dynamic>> putRaw(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: await headers(),
        body: jsonEncode(body),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false, 'message': 'Request failed', 'data': null};
    }
  }

  static Future<Map<String, dynamic>> deleteRaw(String endpoint) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl$endpoint'),
        headers: await headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false, 'message': 'Request failed', 'data': null};
    }
  }

  /// Submit a multipart/form-data POST. `fields` are stringified, `files`
  /// are tuples of (fieldName, absolutePath). Used for media uploads
  /// (moments, posts, receipts). Uses a generous timeout because video
  /// uploads can take a while on mobile networks.
  static Future<Map<String, dynamic>> postMultipart(
    String endpoint, {
    Map<String, String> fields = const {},
    List<MapEntry<String, String>> files = const [],
    Duration timeout = const Duration(minutes: 4),
    void Function(double progress)? onProgress,
  }) async {
    try {
      print('[Multipart] preparing POST $endpoint -> $baseUrl$endpoint');
      print('[Multipart] fields=${fields.keys.toList()} files=${files.length} timeout=${timeout.inSeconds}s');
      Future<http.Response> sendOnce({bool trackProgress = true}) async {
        final uri = Uri.parse('$baseUrl$endpoint');
        final req = http.MultipartRequest('POST', uri);
        final authHeaders = await authOnlyHeaders();
        req.headers.addAll(authHeaders);
        req.fields.addAll(fields);
        print("[Multipart] request created uri=$uri auth=${authHeaders.containsKey('Authorization')} trackProgress=$trackProgress");

        int totalBytes = 0;
        final fileEntries = <_PendingFile>[];
        for (final f in files) {
          final file = File(f.value);
          final exists = await file.exists();
          print('[Multipart] file field=${f.key} path=${f.value} exists=$exists');
          if (!exists) {
            throw FileSystemException('Upload file does not exist', f.value);
          }
          final length = await file.length();
          totalBytes += length;
          print('[Multipart] file name=${file.path.split(Platform.pathSeparator).last} size=$length contentType=${_contentTypeForPath(file.path)}');
          fileEntries.add(_PendingFile(field: f.key, file: file, length: length));
        }
        print('[Multipart] total payload file bytes=$totalBytes');

        int sent = 0;
        void bump(int n) {
          if (!trackProgress || onProgress == null || totalBytes <= 0) return;
          sent += n;
          final pct = (sent / totalBytes).clamp(0.0, 1.0);
          onProgress(pct);
        }

        for (final pf in fileEntries) {
          final stream = pf.file.openRead().transform<List<int>>(
            StreamTransformer.fromHandlers(
              handleData: (data, sink) {
                bump(data.length);
                sink.add(data);
              },
            ),
          );
          req.files.add(http.MultipartFile(
            pf.field,
            stream,
            pf.length,
            filename: pf.file.path.split(Platform.pathSeparator).last,
            contentType: _contentTypeForPath(pf.file.path),
          ));
        }

        if (trackProgress) onProgress?.call(0.0);
        print('[Multipart] sending POST $endpoint');
        final streamed = await req.send().timeout(timeout);
        print('[Multipart] server responded status=${streamed.statusCode} for $endpoint');
        final response = await http.Response.fromStream(streamed);
        print('[Multipart] response body for $endpoint: ${response.body}');
        return response;
      }

      var res = await sendOnce();
      if (_isAuthExpired(res) && await _attemptRefresh()) {
        print('[Multipart] auth expired for $endpoint, token refreshed; retrying once');
        res = await sendOnce(trackProgress: false);
      }
      onProgress?.call(1.0);
      _checkRateLimit(res, endpoint);
      return normalizeResponse(res);
    } catch (e) {
      print('[Multipart] failed before/while calling $endpoint: ${e.runtimeType}: $e');
      return {
        'success': false,
        'message': 'Upload failed: ${e.toString()}',
        'data': null,
      };
    }
  }

  /// Generic request that lets the caller pass arbitrary headers
  /// (used by services that mix auth + guest tokens, e.g. event groups).
  static Future<Map<String, dynamic>> requestWithHeaders({
    required String method,
    required String endpoint,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    String fallbackError = 'Request failed',
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      http.Response res;
      switch (method.toUpperCase()) {
        case 'GET':
          res = await http.get(uri, headers: headers);
          break;
        case 'POST':
          res = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
          break;
        case 'PUT':
          res = await http.put(uri, headers: headers, body: jsonEncode(body ?? {}));
          break;
        case 'PATCH':
          res = await http.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: headers);
          break;
        default:
          throw UnsupportedError('Method $method not supported');
      }
      _checkRateLimit(res, endpoint);
      return normalizeResponse(res, fallbackError: fallbackError);
    } catch (_) {
      return {'success': false, 'message': fallbackError, 'data': null};
    }
  }
}

MediaType _contentTypeForPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return MediaType('image', 'jpeg');
  if (lower.endsWith('.png')) return MediaType('image', 'png');
  if (lower.endsWith('.webp')) return MediaType('image', 'webp');
  if (lower.endsWith('.gif')) return MediaType('image', 'gif');
  if (lower.endsWith('.avif')) return MediaType('image', 'avif');
  if (lower.endsWith('.heic')) return MediaType('image', 'heic');
  if (lower.endsWith('.heif')) return MediaType('image', 'heif');
  if (lower.endsWith('.mp4')) return MediaType('video', 'mp4');
  if (lower.endsWith('.mov')) return MediaType('video', 'quicktime');
  if (lower.endsWith('.m4v')) return MediaType('video', 'x-m4v');
  if (lower.endsWith('.3gp')) return MediaType('video', '3gpp');
  if (lower.endsWith('.avi')) return MediaType('video', 'x-msvideo');
  if (lower.endsWith('.mkv')) return MediaType('video', 'x-matroska');
  if (lower.endsWith('.webm')) return MediaType('video', 'webm');
  return MediaType('application', 'octet-stream');
}

class _PendingFile {
  final String field;
  final File file;
  final int length;
  _PendingFile({required this.field, required this.file, required this.length});
}
