import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'api_base.dart';
import 'api_config.dart';
import 'secure_token_storage.dart';

class EventExtrasService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> getSettings() {
    return ApiBase.getRaw('/settings');
  }

  static Future<Map<String, dynamic>> updateNotificationSettings(Map<String, dynamic> data) {
    return ApiBase.putRaw('/settings/notifications', data);
  }

  static Future<Map<String, dynamic>> updatePrivacySettings(Map<String, dynamic> data) {
    return ApiBase.putRaw('/settings/privacy', data);
  }

  static Future<Map<String, dynamic>> getVerificationStatus() {
    return ApiBase.getRaw('/users/verify-identity/status');
  }

  static MediaType _ctFor(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'png': return MediaType('image', 'png');
      case 'webp': return MediaType('image', 'webp');
      case 'pdf': return MediaType('application', 'pdf');
      case 'jpg':
      case 'jpeg':
      default: return MediaType('image', 'jpeg');
    }
  }

  static Future<Map<String, dynamic>> submitVerification({
    String? documentNumber,
    required String idFrontPath,
    String? idBackPath,
    String? selfiePath,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/users/verify-identity');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await ApiBase.authOnlyHeaders());
      if (documentNumber != null && documentNumber.trim().isNotEmpty) {
        request.fields['document_number'] = documentNumber.trim();
      }
      request.files.add(await http.MultipartFile.fromPath('id_front', idFrontPath, contentType: _ctFor(idFrontPath)));
      if (idBackPath != null) {
        request.files.add(await http.MultipartFile.fromPath('id_back', idBackPath, contentType: _ctFor(idBackPath)));
      }
      if (selfiePath != null) {
        request.files.add(await http.MultipartFile.fromPath('selfie', selfiePath, contentType: _ctFor(selfiePath)));
      }
      final streamedRes = await request.send();
      final body = await streamedRes.stream.bytesToString();
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'success': false, 'message': 'Unexpected response'};
    } catch (_) {
      return {'success': false, 'message': 'Unable to submit verification'};
    }
  }

  static Future<Map<String, dynamic>> searchUsers(String query, {int limit = 20}) {
    return ApiBase.get('/users/search', queryParams: {'q': query, 'limit': '$limit'}, fallbackError: 'Search failed');
  }

  static Future<Map<String, dynamic>> getInvitationCard(String eventId, {String? guestId}) {
    final params = <String, String>{};
    if (guestId != null) {
      params['guest_id'] = guestId;
      params['attendee_id'] = guestId;
    }
    return ApiBase.get(
      '/user-events/$eventId/invitation-card',
      queryParams: params.isNotEmpty ? params : null,
      fallbackError: 'Unable to fetch invitation',
    );
  }

  static Future<Map<String, dynamic>> getEventServices(String eventId) {
    return ApiBase.getRaw('/user-events/$eventId/services');
  }

  static Future<Map<String, dynamic>> addEventService(String eventId, Map<String, dynamic> data) {
    return ApiBase.postRaw('/user-events/$eventId/services', data);
  }

  /// Add an off-platform (manual) vendor to the event.
  static Future<Map<String, dynamic>> addManualVendor(String eventId, Map<String, dynamic> data) {
    final payload = {...data, 'is_manual': true};
    return ApiBase.postRaw('/user-events/$eventId/services', payload);
  }

  /// Download the confirmed-vendors report (pdf/xlsx) and open it.
  static Future<Map<String, dynamic>> downloadVendorsReport(String eventId, {String format = 'pdf'}) async {
    try {
      final uri = Uri.parse('$_baseUrl/user-events/$eventId/vendors/report').replace(
        queryParameters: {'format': format},
      );
      final headers = await _headers();
      headers.remove('Content-Type');
      final res = await http.get(uri, headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final dir = await getApplicationDocumentsDirectory();
        final ext = format == 'xlsx' ? 'xlsx' : 'pdf';
        final fileName = 'vendors_${eventId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(res.bodyBytes);
        final r = await OpenFilex.open(file.path);
        if (r.type == ResultType.done) return {'success': true, 'message': 'Report opened'};
        return {'success': true, 'message': 'Report saved to ${file.path}'};
      }
      try {
        final json = jsonDecode(res.body);
        return {'success': false, 'message': json['message'] ?? 'Failed (${res.statusCode})'};
      } catch (_) {
        return {'success': false, 'message': 'Failed (${res.statusCode})'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Unable to download report'};
    }
  }


  static Future<Map<String, dynamic>> removeEventService(String eventId, String serviceId) {
    return ApiBase.deleteRaw('/user-events/$eventId/services/$serviceId');
  }

  static Future<Map<String, dynamic>> searchServicesPublic(String query, {String? eventTypeId, int limit = 10}) {
    final params = <String, String>{'search': query, 'limit': '$limit', 'sort_by': 'rating'};
    if (eventTypeId != null) params['event_type_id'] = eventTypeId;
    return ApiBase.get('/services', queryParams: params, fallbackError: 'Search failed');
  }

  static Future<Map<String, dynamic>> getServices({int limit = 20, String? category, String? search}) {
    final params = <String, String>{'limit': '$limit'};
    if (category != null) params['category'] = category;
    if (search != null) params['search'] = search;
    return ApiBase.get('/services', queryParams: params, fallbackError: 'Unable to fetch services');
  }

  static Future<Map<String, dynamic>> getServiceCategories() {
    return ApiBase.getRaw('/references/service-categories');
  }

  static Future<Map<String, dynamic>> getEventTypes() {
    return ApiBase.getRaw('/references/event-types');
  }

  static Future<Map<String, dynamic>> downloadReport(String eventId, {String format = 'pdf', String section = 'full'}) async {
    try {
      final uri = Uri.parse('$_baseUrl/user-events/$eventId/report').replace(
        queryParameters: {'format': format, 'section': section},
      );
      final headers = await _headers();
      headers.remove('Content-Type');
      final res = await http.get(uri, headers: headers);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final contentType = res.headers['content-type'] ?? '';
        if (contentType.contains('application/json')) {
          try {
            final json = jsonDecode(res.body);
            if (json['success'] == false) {
              return {'success': false, 'message': json['message'] ?? 'Unable to generate report'};
            }
            final downloadUrl = json['data']?['url'] ?? json['data']?['download_url'] ?? json['url'];
            if (downloadUrl != null) {
              return await _downloadFromUrl(downloadUrl.toString(), eventId, format);
            }
            return {'success': false, 'message': 'Report generation not available for this event'};
          } catch (_) {
            return {'success': false, 'message': 'Unexpected response format'};
          }
        }

        final dir = await getApplicationDocumentsDirectory();
        final ext = format == 'xlsx' ? 'xlsx' : 'pdf';
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'event_report_${eventId}_$timestamp.$ext';
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(res.bodyBytes);

        final result = await OpenFilex.open(file.path);
        if (result.type == ResultType.done) return {'success': true, 'message': 'Report opened'};
        if (result.type == ResultType.noAppToOpen) return {'success': true, 'message': 'Report saved to ${file.path}'};
        return {'success': true, 'message': 'Report saved'};
      }

      try {
        final json = jsonDecode(res.body);
        return {'success': false, 'message': json['message'] ?? 'Failed to generate report (${res.statusCode})'};
      } catch (_) {
        return {'success': false, 'message': 'Failed to generate report (${res.statusCode})'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Unable to download report: ${e.toString().length > 80 ? e.toString().substring(0, 80) : e}'};
    }
  }

  static Future<Map<String, dynamic>> _downloadFromUrl(String url, String eventId, String format) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final dir = await getApplicationDocumentsDirectory();
        final ext = format == 'xlsx' ? 'xlsx' : 'pdf';
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'event_report_${eventId}_$timestamp.$ext';
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(res.bodyBytes);
        await OpenFilex.open(file.path);
        return {'success': true, 'message': 'Report opened'};
      }
      return {'success': false, 'message': 'Failed to download report file'};
    } catch (_) {
      return {'success': false, 'message': 'Unable to download report file'};
    }
  }
}
