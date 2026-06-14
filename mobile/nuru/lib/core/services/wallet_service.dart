import 'api_base.dart';

/// WalletService - wraps backend `/wallet`, `/payments`, `/payment-profiles`
/// endpoints. All responses use the standard `{success, message, data}` shape.
class WalletService {
  // ── Wallets ──
  static Future<Map<String, dynamic>> listWallets() {
    return ApiBase.get('/wallet', fallbackError: 'Unable to load wallet');
  }

  static Future<Map<String, dynamic>> getLedger(
    String walletId, {
    int page = 1,
    int limit = 25,
  }) {
    return ApiBase.get(
      '/wallet/$walletId/ledger',
      queryParams: {'page': '$page', 'limit': '$limit'},
      fallbackError: 'Unable to load ledger',
    );
  }

  // ── Payments ──

  /// Preview platform service fee for the given country/currency/target/amount.
  /// Backend reads the active CommissionSetting per country.
  static Future<Map<String, dynamic>> feePreview({
    required String countryCode,
    required String currencyCode,
    required String targetType,
    required num grossAmount,
  }) {
    return ApiBase.get(
      '/payments/fee-preview',
      queryParams: {
        'country_code': countryCode,
        'currency_code': currencyCode,
        'target_type': targetType,
        'gross_amount': grossAmount.toString(),
      },
      fallbackError: 'Unable to load fee preview',
    );
  }
  static Future<Map<String, dynamic>> listProviders({
    required String countryCode,
    bool collection = true,
    bool? payout,
  }) {
    String? purpose;
    if (payout == true) {
      purpose = 'payout';
    } else if (collection) {
      purpose = 'collection';
    }

    final params = <String, String>{
      'country_code': countryCode,
      if (purpose != null) 'purpose': purpose,
    };
    return ApiBase.get(
      '/payments/providers',
      queryParams: params,
      fallbackError: 'Unable to load providers',
    );
  }

  static Future<Map<String, dynamic>> initiatePayment({
    required String targetType,
    String? targetId,
    String? beneficiaryUserId,
    required num amount,
    String? countryCode,
    String? currencyCode,
    String? methodType,
    String? paymentChannel,
    String? providerId,
    String? phone,
    String? accountNumber,
    String? description,
    bool useWallet = false,
  }) {
    return ApiBase.post('/payments/initiate', {
      'target_type': targetType,
      if (targetId != null) 'target_id': targetId,
      if (beneficiaryUserId != null) 'beneficiary_user_id': beneficiaryUserId,
      'gross_amount': amount,
      if (countryCode != null) 'country_code': countryCode,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (methodType != null) 'method_type': methodType,
      if (paymentChannel != null) 'payment_channel': paymentChannel,
      if (providerId != null) 'provider_id': providerId,
      if (phone != null) 'phone_number': phone,
      if (accountNumber != null) 'account_number': accountNumber,
      if (description != null) 'payment_description': description,
      'use_wallet': useWallet,
    });
  }

  static Future<Map<String, dynamic>> getStatus(String transactionCode) {
    return ApiBase.get(
      '/payments/${Uri.encodeComponent(transactionCode)}/status',
      fallbackError: 'Unable to fetch status',
    );
  }

  static Future<Map<String, dynamic>> history({int page = 1, int limit = 25}) {
    return ApiBase.get(
      '/payments/my-transactions',
      queryParams: {'page': '$page', 'limit': '$limit'},
      fallbackError: 'Unable to load transactions',
    );
  }

  /// Aggregated Payment History feed for the dedicated screen.
  /// `category` ∈ all | tickets | contributions | vendors | promotions | ads
  static Future<Map<String, dynamic>> paymentHistory({
    String category = 'all',
    int page = 1,
    int limit = 20,
  }) {
    return ApiBase.get(
      '/payments/history',
      queryParams: {
        'category': category,
        'page': '$page',
        'limit': '$limit',
      },
      fallbackError: 'Unable to load payment history',
    );
  }

  // ── Payout profiles ──
  static Future<Map<String, dynamic>> listProfiles() {
    return ApiBase.get('/payment-profiles', fallbackError: 'Unable to load payout profiles');
  }

  static Future<Map<String, dynamic>> createProfile(Map<String, dynamic> data) {
    return ApiBase.post('/payment-profiles', data);
  }

  static Future<Map<String, dynamic>> setDefaultProfile(String id) {
    return ApiBase.post('/payment-profiles/$id/default', {});
  }

  static Future<Map<String, dynamic>> deleteProfile(String id) {
    return ApiBase.delete('/payment-profiles/$id');
  }

  // ── Country / currency ──
  // NOTE: backend route is mounted at POST /users/profile/country
  // (see backend/app/api/routes/profile.py). The previous path
  // `/users/me/country` returned 404, which made the "Where are you?"
  // confirm button silently no-op on mobile.
  static Future<Map<String, dynamic>> confirmCountry({
    required String countryCode,
    String source = 'manual',
  }) {
    return ApiBase.post('/users/profile/country', {
      'country_code': countryCode,
      'source': source,
    });
  }
}
