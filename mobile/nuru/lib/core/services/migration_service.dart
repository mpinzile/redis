import 'api_base.dart';

/// MigrationService - wraps `/users/me/migration-status`.
///
/// Backend returns:
///   {
///     needs_setup: bool,
///     has_monetized_content: bool,
///     has_pending_balance: bool,
///     monetized_summary: {events,services,ticketed_events,contributions,bookings},
///     country_guess: { code: 'TZ'|'KE'|null, source: 'phone'|'ip'|'locale'|null },
///     pending_balance: { amount, currency } | null,
///     legacy_since: ISO date | null,
///   }
class MigrationService {
  static Future<Map<String, dynamic>> getStatus() {
    return ApiBase.get(
      '/users/me/migration-status',
      fallbackError: 'Unable to load migration status',
    );
  }
}
