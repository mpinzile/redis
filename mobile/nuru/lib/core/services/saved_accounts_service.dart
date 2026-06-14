import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Facebook-style "Continue as …" account switcher.
///
/// Stores a small, non-sensitive snapshot per account in SharedPreferences
/// (id, display name, avatar, email/phone) and keeps each account's
/// refresh token in FlutterSecureStorage so the user can resume their
/// session with a single tap - no password retype.
///
/// Saved accounts survive sign-out on purpose: the whole point of this
/// feature is to make coming back fast. Users can remove individual
/// accounts from the login screen.
class SavedAccount {
  final String id;
  final String name;
  final String? avatar;
  final String? email;
  final String? phone;
  final int savedAt;

  const SavedAccount({
    required this.id,
    required this.name,
    this.avatar,
    this.email,
    this.phone,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (avatar != null) 'avatar': avatar,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        'saved_at': savedAt,
      };

  static SavedAccount? tryFrom(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString();
    final name = raw['name']?.toString();
    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;
    return SavedAccount(
      id: id,
      name: name,
      avatar: raw['avatar']?.toString(),
      email: raw['email']?.toString(),
      phone: raw['phone']?.toString(),
      savedAt: (raw['saved_at'] is int) ? raw['saved_at'] as int : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class SavedAccountsService {
  static const _prefsKey = 'saved_accounts_v1';
  static const _refreshTokenPrefix = 'refresh_token_for_';
  static const int _maxAccounts = 6;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<List<SavedAccount>> list() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <SavedAccount>[];
      for (final r in decoded) {
        final a = SavedAccount.tryFrom(r);
        if (a != null) out.add(a);
      }
      out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('[SavedAccounts] list failed: $e');
      return const [];
    }
  }

  /// Persist or update a saved account snapshot + its refresh token.
  static Future<void> upsert({
    required Map<String, dynamic> user,
    required String refreshToken,
  }) async {
    final id = user['id']?.toString();
    if (id == null || id.isEmpty) return;
    final first = (user['first_name'] ?? '').toString().trim();
    final last = (user['last_name'] ?? '').toString().trim();
    final fallback = (user['username'] ?? user['email'] ?? user['phone'] ?? 'Account').toString();
    final name = [first, last].where((s) => s.isNotEmpty).join(' ').trim();
    final entry = SavedAccount(
      id: id,
      name: name.isEmpty ? fallback : name,
      avatar: user['avatar']?.toString(),
      email: user['email']?.toString(),
      phone: user['phone']?.toString(),
      savedAt: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      final current = await list();
      final next = [entry, ...current.where((a) => a.id != id)];
      while (next.length > _maxAccounts) next.removeLast();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(next.map((a) => a.toJson()).toList()));
      if (refreshToken.isNotEmpty) {
        await _storage.write(key: '$_refreshTokenPrefix$id', value: refreshToken);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SavedAccounts] upsert failed: $e');
    }
  }

  static Future<String?> getRefreshToken(String accountId) async {
    try {
      return await _storage.read(key: '$_refreshTokenPrefix$accountId');
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String accountId) async {
    try {
      final current = await list();
      final next = current.where((a) => a.id != accountId).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(next.map((a) => a.toJson()).toList()));
      await _storage.delete(key: '$_refreshTokenPrefix$accountId');
    } catch (e) {
      if (kDebugMode) debugPrint('[SavedAccounts] remove failed: $e');
    }
  }
}