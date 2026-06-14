import 'api_base.dart';

/// ReceivedPaymentsService - fetches money landing on a beneficiary's
/// events (contributions / tickets) or services. The wallet is reserved
/// for top-ups only; everything else is surfaced via these endpoints.
class ReceivedPaymentsService {
  static Future<Map<String, dynamic>> eventContributions(
    String eventId, {
    int page = 1,
    int limit = 20,
    String? status,
  }) {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (status != null) params['status'] = status;
    return ApiBase.get(
      '/received-payments/events/$eventId/contributions',
      queryParams: params,
      fallbackError: 'Unable to load contribution payments',
    );
  }

  static Future<Map<String, dynamic>> eventTickets(
    String eventId, {
    int page = 1,
    int limit = 20,
    String? status,
  }) {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (status != null) params['status'] = status;
    return ApiBase.get(
      '/received-payments/events/$eventId/tickets',
      queryParams: params,
      fallbackError: 'Unable to load ticket payments',
    );
  }

  static Future<Map<String, dynamic>> service(
    String serviceId, {
    int page = 1,
    int limit = 20,
    String? status,
  }) {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (status != null) params['status'] = status;
    return ApiBase.get(
      '/received-payments/services/$serviceId',
      queryParams: params,
      fallbackError: 'Unable to load service payments',
    );
  }

  /// Current user's own ticket payment history.
  static Future<Map<String, dynamic>> myTickets({
    int page = 1,
    int limit = 20,
    String? search,
  }) {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (search != null && search.isNotEmpty) params['search'] = search;
    return ApiBase.get(
      '/received-payments/my/tickets',
      queryParams: params,
      fallbackError: 'Unable to load ticket payments',
    );
  }

  /// Current user's own contribution payment history.
  static Future<Map<String, dynamic>> myContributions({
    int page = 1,
    int limit = 20,
    String? search,
  }) {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (search != null && search.isNotEmpty) params['search'] = search;
    return ApiBase.get(
      '/received-payments/my/contributions',
      queryParams: params,
      fallbackError: 'Unable to load contribution payments',
    );
  }
}

