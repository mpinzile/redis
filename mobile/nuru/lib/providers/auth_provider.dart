import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/api_service.dart';
import '../core/services/events_service.dart';
import '../core/services/secure_token_storage.dart';
import '../core/services/push_notification_service.dart';
import '../core/services/saved_accounts_service.dart';
import '../core/services/event_groups_service.dart';
import '../core/utils/event_groups_cache.dart';
import '../core/utils/home_cache.dart';
import '../core/utils/messages_cache.dart';
import '../core/utils/mobile_cache.dart';
import '../core/utils/feed_persistent_cache.dart';
import '../core/utils/money_format.dart' as money_fmt;

class AuthProvider extends ChangeNotifier {
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyHasSeenOnboarding = 'has_seen_onboarding';

  bool _isLoggedIn = false;
  bool _hasSeenOnboarding = false;
  bool _isLoading = true;
  Map<String, dynamic>? _user;

  void _syncCurrencyFromUser() {
    final code = _user?['currency_code'] ?? _user?['currency']?['code'];
    if (code != null) money_fmt.setActiveCurrency(code.toString());
  }

  bool get isLoggedIn => _isLoggedIn;
  bool get hasSeenOnboarding => _hasSeenOnboarding;
  bool get isLoading => _isLoading;
  Map<String, dynamic>? get user => _user;
  String? get userName => _user?['first_name'];
  String? get userEmail => _user?['email'];
  String? get userAvatar => _user?['avatar'] as String?;

  AuthProvider() {
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      // Migrate tokens from plain SharedPreferences to secure storage (one-time)
      await SecureTokenStorage.migrateFromSharedPreferences();

      final prefs = await SharedPreferences.getInstance();
      _hasSeenOnboarding = prefs.getBool(_keyHasSeenOnboarding) ?? false;

      final token = await SecureTokenStorage.getToken();
      debugPrint('[AuthProvider] _loadSession: token=${token != null ? 'present' : 'null'}');
      if (token != null) {
        // Optimistic restore: a valid token in secure storage means we trust
        // the previous session. Bring the user straight into the app and
        // hydrate /auth/me + profile in the background. This shaves the cold-
        // start latency that previously waited on two sequential network
        // round-trips before the splash could dismiss.
        _isLoggedIn = true;
        // Use the lightweight cached snapshot while the network call is in
        // flight so screens that read userName/avatar don't flash empty.
        final cachedUser = prefs.getString('cached_user');
        if (cachedUser != null && cachedUser.isNotEmpty) {
          try {
            final decoded = jsonDecode(cachedUser);
            if (decoded is Map<String, dynamic>) _user = decoded;
          } catch (_) {}
        }
        _syncCurrencyFromUser();

        // Background hydration - never blocks UI.
        // Roll the 30-day refresh window forward FIRST so a long-dormant
        // user who just opened the app gets a brand-new pair of tokens
        // before anything else hits the network.
        // ignore: discarded_futures
        _rollRefreshAndHydrate();
      }
    } catch (e) {
      // A failure reading secure storage (e.g. Android master-key rotation)
      // must NEVER freeze the splash or imply the user is logged out. We
      // simply fall through to the login screen on this cold start; the
      // next launch will retry the secure read.
      debugPrint('[AuthProvider] _loadSession error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _rollRefreshAndHydrate() async {
    // Best-effort proactive refresh. If it fails (offline, server down,
    // refresh token finally expired after 30 days of total inactivity), we
    // simply fall through to /auth/me - ApiBase will retry the refresh on
    // any 401 it sees and we still won't sign the user out automatically.
    try {
      final rt = await SecureTokenStorage.getRefreshToken();
      if (rt != null && rt.isNotEmpty) {
        final res = await AuthApi.refresh(rt);
        if (res['success'] == true && res['data'] is Map) {
          final data = res['data'] as Map;
          final newAccess = data['access_token']?.toString();
          final newRefresh = data['refresh_token']?.toString();
          if (newAccess != null && newAccess.isNotEmpty) {
            await SecureTokenStorage.setToken(newAccess);
          }
          if (newRefresh != null && newRefresh.isNotEmpty) {
            await SecureTokenStorage.setRefreshToken(newRefresh);
          }
        }
      }
    } catch (_) {}
    await _hydrateUserInBackground();
  }

  Future<void> _hydrateUserInBackground() async {
    try {
      final results = await Future.wait([
        AuthApi.me(),
        EventsService.getProfile(),
      ]);
      final meRes = results[0];
      final profileRes = results[1];

      // Only treat the session as dead if the backend explicitly says the
      // bearer is invalid AND our refresh attempt (handled inside ApiBase)
      // already failed. Transient network/server errors must NOT log the
      // user out - that's what was wiping sessions even though tokens are
      // valid for 24h with a 30-day refresh window.
      final meSucceeded = meRes['success'] == true && meRes['data'] != null;
      final msg = meRes['message']?.toString().toLowerCase() ?? '';
      final isAuthDead = meRes['success'] == false &&
          (msg.contains('unauthor') ||
              msg.contains('expired') ||
              msg.contains('invalid token') ||
              msg.contains('not authenticated'));

      if (meSucceeded) {
        Map<String, dynamic>? userData =
            meRes['data'] is Map<String, dynamic> ? meRes['data'] : null;
        if (userData != null) {
          _user = userData;
          if (profileRes['success'] == true &&
              profileRes['data'] is Map<String, dynamic>) {
            _user = {..._user!, ...profileRes['data'] as Map<String, dynamic>};
          }
          _syncCurrencyFromUser();
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('cached_user', jsonEncode(_user));
          } catch (_) {}
          notifyListeners();
        }
        try {
          await PushNotificationService.instance.registerWithBackend();
        } catch (_) {}
      }
      // Session is permanent until the user explicitly signs out: even if
      // /auth/me returns an auth-dead response, we keep the local session
      // intact. ApiBase will keep trying to refresh on the next request,
      // and the refresh-token window (30 days) is rolled forward on every
      // cold start by `_rollRefreshTokenForward()`.
    } catch (_) {
      // Network exceptions never log the user out.
    }
  }

  /// Refresh the cached user from the server (used after profile changes
  /// like confirming country/currency, avatar updates, etc.).
  Future<void> refreshUser() async {
    try {
      final res = await AuthApi.me();
      Map<String, dynamic>? userData;
      if (res['success'] == true && res['data'] is Map<String, dynamic>) {
        userData = res['data'] as Map<String, dynamic>;
      } else if (res['data'] is Map<String, dynamic> && res['data']['id'] != null) {
        userData = res['data'] as Map<String, dynamic>;
      }
      if (userData != null) {
        _user = userData;
        try {
          final profileRes = await EventsService.getProfile();
          if (profileRes['success'] == true && profileRes['data'] is Map<String, dynamic>) {
            _user = {..._user!, ...profileRes['data'] as Map<String, dynamic>};
          }
        } catch (_) {}
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasSeenOnboarding, true);
    _hasSeenOnboarding = true;
    notifyListeners();
  }

  /// Sign in with credential (email/phone/username) + password
  Future<Map<String, dynamic>> signIn({
    required String credential,
    required String password,
  }) async {
    final res = await AuthApi.signin(credential: credential, password: password);

    if (res['success'] == true && res['data'] != null) {
      final data = res['data'] as Map<String, dynamic>;
      final token = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final user = data['user'] as Map<String, dynamic>?;

      if (token != null) {
        await SecureTokenStorage.setToken(token);
        if (refreshToken != null) await SecureTokenStorage.setRefreshToken(refreshToken);
        final prefs = await SharedPreferences.getInstance();

        // Privacy: if we're switching from a different account, wipe every
        // cache BEFORE flipping _isLoggedIn so no UI ever renders the
        // previous user's data on top of the new session.
        final prevCached = prefs.getString('cached_user');
        String? prevId;
        if (prevCached != null && prevCached.isNotEmpty) {
          try {
            final decoded = jsonDecode(prevCached);
            if (decoded is Map) prevId = decoded['id']?.toString();
          } catch (_) {}
        }
        final newId = user?['id']?.toString();
        if (prevId != null && newId != null && prevId != newId) {
          await _wipeAllCaches();
        }

        await prefs.setBool(_keyIsLoggedIn, true);
        _isLoggedIn = true;
        _user = user;

        try {
          final profileRes = await EventsService.getProfile();
          if (profileRes['success'] == true && profileRes['data'] != null) {
            final profileData = profileRes['data'] as Map<String, dynamic>;
            _user = {...(_user ?? {}), ...profileData};
          }
        } catch (_) {}

        _syncCurrencyFromUser();
        try {
          await prefs.setString('cached_user', jsonEncode(_user));
        } catch (_) {}

        // Register the device's FCM token with the backend so push
        // notifications (messages, payments, invitations, etc.) reach this
        // device. Best-effort - never block sign-in.
        try {
          await PushNotificationService.instance.registerWithBackend();
        } catch (_) {}

        // Save this account to the quick-switcher so the user can return
        // with one tap. Refresh token stays in secure storage keyed by
        // user id so we can resume without asking for the password again.
        if (_user != null && refreshToken != null && refreshToken.isNotEmpty) {
          try {
            await SavedAccountsService.upsert(user: _user!, refreshToken: refreshToken);
          } catch (_) {}
        }

        // Silent contributor-claim refresh: reset the My Groups cache and
        // prefetch so any event groups the backend just attached on login
        // appear immediately on the My Groups tab.
        try {
          EventGroupsCache.reset();
          final groupsRes = await EventGroupsService.listMyGroups();
          if (groupsRes['success'] == true && groupsRes['data'] != null) {
            final data = groupsRes['data'] as Map<String, dynamic>;
            EventGroupsCache.groups = (data['groups'] as List?) ?? const [];
          }
        } catch (_) {}

        notifyListeners();
      }
    }

    return res;
  }

  /// Sign up - creates account, returns response with user ID
  Future<Map<String, dynamic>> signUp({
    required String firstName,
    required String lastName,
    required String username,
    required String phone,
    required String password,
    String? email,
  }) async {
    return AuthApi.signup(
      firstName: firstName,
      lastName: lastName,
      username: username,
      phone: phone,
      password: password,
      email: email,
    );
  }

  /// Verify OTP
  Future<Map<String, dynamic>> verifyOtp({
    required String userId,
    required String verificationType,
    required String otpCode,
  }) {
    return AuthApi.verifyOtp(
      userId: userId,
      verificationType: verificationType,
      otpCode: otpCode,
    );
  }

  /// Request OTP
  Future<Map<String, dynamic>> requestOtp({
    required String userId,
    required String verificationType,
  }) {
    return AuthApi.requestOtp(userId: userId, verificationType: verificationType);
  }

  /// Check username availability
  Future<Map<String, dynamic>> checkUsername(String username, {String? firstName, String? lastName}) {
    return AuthApi.checkUsername(username, firstName: firstName, lastName: lastName);
  }

  /// Proactive username suggestions from first + last name
  Future<Map<String, dynamic>> getUsernameSuggestions({String? firstName, String? lastName}) {
    return AuthApi.getUsernameSuggestions(firstName: firstName, lastName: lastName);
  }

  /// Validate name
  Future<Map<String, dynamic>> validateName(String name) {
    return AuthApi.validateName(name);
  }

  /// Auto sign-in after OTP verification (same as web)
  Future<bool> autoSignInAfterVerification({
    required String phone,
    required String password,
  }) async {
    final res = await signIn(credential: phone, password: password);
    return res['success'] == true;
  }

  /// Forgot password (email)
  Future<Map<String, dynamic>> forgotPassword(String email) {
    return AuthApi.forgotPassword(email);
  }

  /// Forgot password (phone)
  Future<Map<String, dynamic>> forgotPasswordPhone(String phone) {
    return AuthApi.forgotPasswordPhone(phone);
  }

  /// Verify reset OTP
  Future<Map<String, dynamic>> verifyResetOtp(String phone, String otpCode) {
    return AuthApi.verifyResetOtp(phone, otpCode);
  }

  /// Reset password
  Future<Map<String, dynamic>> resetPassword(String token, String password, String confirmation) {
    return AuthApi.resetPassword(token, password, confirmation);
  }

  Future<void> signOut() async {
    // Resolve the current FCM token first so we can hand it to BOTH the
    // device-unregister call and the /auth/logout safety net. Doing this
    // before _clearTokens() guarantees the bearer token is still valid.
    String? fcmToken;
    try {
      fcmToken = await PushNotificationService.instance.currentToken();
    } catch (_) {}

    // Primary path: unbind the device row by (platform, token).
    try { await PushNotificationService.instance.unregister(); } catch (_) {}

    // Belt-and-suspenders: tell /auth/logout the token so the backend can
    // delete any leftover row owned by this user. Awaited (not fire-and-
    // forget) so we know the unbind happened before we drop the bearer.
    try {
      await AuthApi.logout(body: {
        if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
      });
    } catch (_) {}

    await _clearTokens();
    // Wipe every in-memory + on-disk cache (including avatars and other
    // network images) so a different account that signs in on this
    // device - or even a snapshot of the recents/multitasking switcher -
    // can never reveal the previous user's data.
    await _wipeAllCaches();
    _isLoggedIn = false;
    _user = null;
    notifyListeners();
  }

  /// Resume a previously-signed-in account using its stored refresh token.
  /// Returns true on success.
  Future<bool> quickSignIn(String accountId) async {
    try {
      final refresh = await SavedAccountsService.getRefreshToken(accountId);
      if (refresh == null || refresh.isEmpty) return false;
      final res = await AuthApi.refresh(refresh);
      if (res['success'] != true || res['data'] is! Map) return false;
      final data = res['data'] as Map;
      final access = data['access_token']?.toString();
      final newRefresh = data['refresh_token']?.toString();
      if (access == null || access.isEmpty) return false;

      final prefs = await SharedPreferences.getInstance();
      // Switching: if a different account was signed in last, wipe caches first.
      final prevCached = prefs.getString('cached_user');
      String? prevId;
      if (prevCached != null && prevCached.isNotEmpty) {
        try {
          final decoded = jsonDecode(prevCached);
          if (decoded is Map) prevId = decoded['id']?.toString();
        } catch (_) {}
      }
      if (prevId != null && prevId != accountId) {
        await _wipeAllCaches();
      }

      await SecureTokenStorage.setToken(access);
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await SecureTokenStorage.setRefreshToken(newRefresh);
      }
      await prefs.setBool(_keyIsLoggedIn, true);
      _isLoggedIn = true;

      final meRes = await AuthApi.me();
      if (meRes['success'] == true && meRes['data'] is Map<String, dynamic>) {
        _user = meRes['data'] as Map<String, dynamic>;
        try {
          final profileRes = await EventsService.getProfile();
          if (profileRes['success'] == true && profileRes['data'] is Map<String, dynamic>) {
            _user = {..._user!, ...profileRes['data'] as Map<String, dynamic>};
          }
        } catch (_) {}
        _syncCurrencyFromUser();
        try { await prefs.setString('cached_user', jsonEncode(_user)); } catch (_) {}
        try {
          await SavedAccountsService.upsert(
            user: _user!,
            refreshToken: newRefresh ?? refresh,
          );
        } catch (_) {}
      }

      try { await PushNotificationService.instance.registerWithBackend(); } catch (_) {}
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Remove an account from the quick-switcher list and forget its refresh token.
  Future<void> forgetSavedAccount(String accountId) async {
    await SavedAccountsService.remove(accountId);
  }

  /// Centralised cache wipe used by both signOut and account-switch flows.
  Future<void> _wipeAllCaches() async {
    try { EventGroupsCache.reset(); EventGroupsCache.groups = null; } catch (_) {}
    try { HomeCache.reset(); } catch (_) {}
    try { MessagesCache.reset(); } catch (_) {}
    // Wipe the persisted feed + glimpses cache so the next account never
    // briefly sees the previous user's glimpses on the home tab.
    try { await FeedPersistentCache.clear(); } catch (_) {}
    try { await MobileCache.clearAll(); } catch (_) {}
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
    try { await CachedNetworkImage.evictFromCache(''); } catch (_) {}
    try { await DefaultCacheManager().emptyCache(); } catch (_) {}
  }

  Future<void> _clearTokens() async {
    await SecureTokenStorage.clearTokens();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, false);
    await prefs.remove('cached_user');
    _isLoggedIn = false;
    _user = null;
  }
}
