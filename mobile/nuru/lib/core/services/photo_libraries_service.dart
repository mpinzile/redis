import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'secure_token_storage.dart';
import 'api_config.dart';

/// Photo Libraries API service - mirrors src/lib/api/photoLibraries.ts
class PhotoLibrariesService {
  static String get _baseUrl => ApiConfig.baseUrl;
  static final Map<String, Map<String, dynamic>> _cache = {};
  static Map<String, dynamic>? cached(String key) => _cache[key];
  static void putCache(String key, Map<String, dynamic> value) {
    if (value['success'] == true) _cache[key] = value;
  }

  static Map<String, dynamic> _normalizeBody({
    required String body,
    required int statusCode,
    required String fallbackError,
  }) {
    try {
      final decoded = jsonDecode(body);
      final ok = statusCode >= 200 && statusCode < 300;

      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('success')) return decoded;
        return {
          'success': ok,
          'message': decoded['message']?.toString() ?? (ok ? '' : fallbackError),
          'data': decoded,
        };
      }

      return {
        'success': ok,
        'message': ok ? '' : fallbackError,
        'data': decoded,
      };
    } catch (_) {
      return {
        'success': false,
        'message': fallbackError,
        'data': null,
      };
    }
  }

  static Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, String>> _authOnlyHeaders() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Get all libraries for a service (optional ``search``)
  static Future<Map<String, dynamic>> getServiceLibraries(String serviceId, {String? search}) async {
    final cacheKey = 'service:$serviceId:${(search ?? '').trim().toLowerCase()}';
    try {
      final qp = <String, String>{};
      if (search != null && search.isNotEmpty) qp['search'] = search;
      final uri = Uri.parse('$_baseUrl/photo-libraries/service/$serviceId').replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(uri, headers: await _headers());
      final normalized = _normalizeBody(body: res.body, statusCode: res.statusCode, fallbackError: 'Unable to fetch libraries');
      putCache(cacheKey, normalized);
      return normalized;
    } catch (e) {
      return {'success': false, 'message': 'Unable to fetch libraries'};
    }
  }

  /// Get a single library with photos
  static Future<Map<String, dynamic>> getLibrary(String libraryId) async {
    final cacheKey = 'library:$libraryId';
    try {
      final res = await http.get(Uri.parse('$_baseUrl/photo-libraries/$libraryId'), headers: await _headers());
      final normalized = _normalizeBody(body: res.body, statusCode: res.statusCode, fallbackError: 'Unable to fetch library');
      putCache(cacheKey, normalized);
      return normalized;
    } catch (e) {
      return {'success': false, 'message': 'Unable to fetch library'};
    }
  }

  /// Access library via share token
  static Future<Map<String, dynamic>> getLibraryByToken(String token) async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/photo-libraries/shared/$token'), headers: await _headers());
      return _normalizeBody(body: res.body, statusCode: res.statusCode, fallbackError: 'Unable to fetch shared library');
    } catch (e) {
      return {'success': false, 'message': 'Unable to fetch shared library'};
    }
  }

  /// Create a photo library for a confirmed event
  static Future<Map<String, dynamic>> createLibrary(String serviceId, {required String eventId, String? privacy, String? description}) async {
    try {
      final uri = Uri.parse('$_baseUrl/photo-libraries/service/$serviceId/create');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authOnlyHeaders());
      request.fields['event_id'] = eventId;
      if (privacy != null) request.fields['privacy'] = privacy;
      if (description != null) request.fields['description'] = description;
      final streamedRes = await request.send();
      final body = await streamedRes.stream.bytesToString();
      return _normalizeBody(body: body, statusCode: streamedRes.statusCode, fallbackError: 'Unable to create library');
    } catch (e) {
      return {'success': false, 'message': 'Unable to create library'};
    }
  }

  /// Update library settings (privacy/description)
  static Future<Map<String, dynamic>> updateLibrary(String libraryId, {String? privacy, String? description}) async {
    try {
      final uri = Uri.parse('$_baseUrl/photo-libraries/$libraryId');
      final request = http.MultipartRequest('PUT', uri);
      request.headers.addAll(await _authOnlyHeaders());
      if (privacy != null) request.fields['privacy'] = privacy;
      if (description != null) request.fields['description'] = description;
      final streamedRes = await request.send();
      final body = await streamedRes.stream.bytesToString();
      return _normalizeBody(body: body, statusCode: streamedRes.statusCode, fallbackError: 'Unable to update library');
    } catch (e) {
      return {'success': false, 'message': 'Unable to update library'};
    }
  }

  /// Upload a photo or video to a library
  static Future<Map<String, dynamic>> uploadPhoto(String libraryId, String filePath, {String? caption}) async {
    try {
      final uri = Uri.parse('$_baseUrl/photo-libraries/$libraryId/upload');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authOnlyHeaders());
      request.files.add(await http.MultipartFile.fromPath('file', filePath, contentType: _contentTypeForPath(filePath)));
      if (caption != null) request.fields['caption'] = caption;
      final streamedRes = await request.send();
      final body = await streamedRes.stream.bytesToString();
      return _normalizeBody(body: body, statusCode: streamedRes.statusCode, fallbackError: 'Unable to upload media');
    } catch (e) {
      return {'success': false, 'message': 'Unable to upload media'};
    }
  }

  /// Toggle favorite status on a library
  static Future<Map<String, dynamic>> toggleFavorite(String libraryId) async {
    try {
      final res = await http.post(Uri.parse('$_baseUrl/photo-libraries/$libraryId/favorite'), headers: await _headers());
      return _normalizeBody(body: res.body, statusCode: res.statusCode, fallbackError: 'Unable to update favorite');
    } catch (e) {
      return {'success': false, 'message': 'Unable to update favorite'};
    }
  }

  /// Libraries favorited by the current user
  static Future<Map<String, dynamic>> getMyFavorites() async {
    const cacheKey = 'me:favorites';
    try {
      final res = await http.get(Uri.parse('$_baseUrl/photo-libraries/me/favorites'), headers: await _headers());
      final normalized = _normalizeBody(body: res.body, statusCode: res.statusCode, fallbackError: 'Unable to fetch favorites');
      putCache(cacheKey, normalized);
      return normalized;
    } catch (e) {
      return {'success': false, 'message': 'Unable to fetch favorites'};
    }
  }

  /// Libraries shared with current user (events they organize or favorited public libs)
  static Future<Map<String, dynamic>> getSharedWithMe() async {
    const cacheKey = 'me:shared';
    try {
      final res = await http.get(Uri.parse('$_baseUrl/photo-libraries/me/shared'), headers: await _headers());
      final normalized = _normalizeBody(body: res.body, statusCode: res.statusCode, fallbackError: 'Unable to fetch shared libraries');
      putCache(cacheKey, normalized);
      return normalized;
    } catch (e) {
      return {'success': false, 'message': 'Unable to fetch shared libraries'};
    }
  }

  /// Delete a photo
  static Future<Map<String, dynamic>> deletePhoto(String libraryId, String photoId) async {
    try {
      final res = await http.delete(Uri.parse('$_baseUrl/photo-libraries/$libraryId/photos/$photoId'), headers: await _headers());
      return _normalizeBody(body: res.body, statusCode: res.statusCode, fallbackError: 'Unable to delete photo');
    } catch (e) {
      return {'success': false, 'message': 'Unable to delete photo'};
    }
  }

  /// Delete an entire library
  static Future<Map<String, dynamic>> deleteLibrary(String libraryId) async {
    try {
      final res = await http.delete(Uri.parse('$_baseUrl/photo-libraries/$libraryId'), headers: await _headers());
      return _normalizeBody(body: res.body, statusCode: res.statusCode, fallbackError: 'Unable to delete library');
    } catch (e) {
      return {'success': false, 'message': 'Unable to delete library'};
    }
  }

  /// Get confirmed events for a service (to create libraries from). Optional ``search``.
  static Future<Map<String, dynamic>> getServiceEvents(String serviceId, {String? search}) async {
    try {
      final qp = <String, String>{};
      if (search != null && search.isNotEmpty) qp['search'] = search;
      final uri = Uri.parse('$_baseUrl/photo-libraries/service/$serviceId/events').replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(uri, headers: await _headers());
      return _normalizeBody(body: res.body, statusCode: res.statusCode, fallbackError: 'Unable to fetch events');
    } catch (e) {
      return {'success': false, 'message': 'Unable to fetch events'};
    }
  }

  /// Get photo libraries for an event (event creator view)
  static Future<Map<String, dynamic>> getEventLibraries(String eventId) async {
    final cacheKey = 'event:$eventId';
    try {
      final res = await http.get(Uri.parse('$_baseUrl/photo-libraries/event/$eventId'), headers: await _headers());
      final normalized = _normalizeBody(body: res.body, statusCode: res.statusCode, fallbackError: 'Unable to fetch event libraries');
      putCache(cacheKey, normalized);
      return normalized;
    } catch (e) {
      return {'success': false, 'message': 'Unable to fetch event libraries'};
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
