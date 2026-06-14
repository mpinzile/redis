import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show Platform;

import 'api_base.dart';
import 'secure_token_storage.dart';
import '../../screens/meetings/meeting_details_screen.dart';

/// Top-level background handler - required by FCM. Must be a top-level fn.
@pragma('vm:entry-point')
Future<void> _firebaseBgHandler(RemoteMessage message) async {
  // Ensure Firebase is up in the background isolate.
  await Firebase.initializeApp();
  // The system tray will show the notification automatically when the
  // payload contains `notification:` (we always set that backend-side).
  // No extra UI work needed here.
}

/// Centralised push-notification plumbing for the Nuru mobile app.
///
/// Responsibilities:
///   1. Initialise Firebase + request permissions.
///   2. Register the device's FCM token with the Nuru backend so any
///      notification (chat message, payment, invitation, RSVP, etc.) the
///      backend creates will fan-out to this device.
///   3. Show a local notification when a push arrives while the app is in
///      the foreground (so the user sees something, like WhatsApp does).
///   4. Surface the navigation key so taps on a push can route the user.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialised = false;
  String? _lastToken;
  GlobalKey<NavigatorState>? _navKey;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'nuru_default',
    'Nuru notifications',
    description: 'Messages, payments, invitations and other Nuru updates.',
    importance: Importance.high,
  );

  /// Call once, *before* `runApp`, from `main.dart`.
  Future<void> initialise({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (_initialised) return;
    _navKey = navigatorKey;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[push] Firebase.initializeApp failed: $e');
      return;
    }

    // Background isolate handler.
    FirebaseMessaging.onBackgroundMessage(_firebaseBgHandler);

    // Local notifications (used to render foreground pushes).
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        _handleTapPayload(resp.payload);
      },
    );

    // Create the Android channel up-front so high-priority pushes show.
    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    // Permissions.
    await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true,
    );
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    // Foreground messages → render via local notifications.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Tap on a push that opened the app from background.
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      _handleNavigation(m.data);
    });
    // Or that cold-started the app.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Defer a tick so the navigator exists.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNavigation(initial.data);
      });
    }

    // Token refresh.
    FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      _lastToken = t;
      debugPrint('[push] FCM token refreshed => ${_redact(t)}');
      _registerToken(t);
    });

    _initialised = true;
  }

  /// Register the current FCM token with the Nuru backend. Call after the
  /// user signs in, and again whenever the token rotates.
  Future<void> registerWithBackend() async {
    if (!_initialised) return;
    try {
      final token = _lastToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _lastToken = token;
      // Log a redacted preview only - never the full FCM token.
      debugPrint('[push] FCM token => ${_redact(token)}');
      await _registerToken(token);
    } catch (e) {
      debugPrint('[push] registerWithBackend failed: $e');
    }
  }

  /// Return the current FCM token (cached or freshly fetched). Used at
  /// logout time so callers can pass it to /auth/logout for cleanup.
  Future<String?> currentToken() async {
    if (_lastToken != null && _lastToken!.isNotEmpty) return _lastToken;
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null && t.isNotEmpty) _lastToken = t;
      return t;
    } catch (_) {
      return null;
    }
  }

  /// Unregister the current device on logout.
  Future<void> unregister() async {
    // Resolve the token even if registerWithBackend was never called this
    // session (e.g. user opened the app already-logged-in and now signs out).
    String? token = _lastToken;
    try {
      token ??= await FirebaseMessaging.instance.getToken();
    } catch (_) {}
    if (token == null || token.isEmpty) return;

    try {
      await http.delete(
        Uri.parse('${ApiBase.baseUrl}/calls/devices'),
        headers: await ApiBase.headers(),
        body: jsonEncode({
          'platform': Platform.isIOS ? 'ios' : 'android',
          'token': token,
        }),
      );
    } catch (_) {}

    // Force FCM to mint a fresh token on next login so the *new* user
    // never inherits the previous user's token mapping on this device.
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _lastToken = null;
  }

  Future<void> _registerToken(String token) async {
    final auth = await SecureTokenStorage.getToken();
    if (auth == null) {
      debugPrint('[push] skip register · no auth token (user not signed in yet)');
      return;
    }
    try {
      final res = await http.post(
        Uri.parse('${ApiBase.baseUrl}/calls/devices'),
        headers: await ApiBase.headers(),
        body: jsonEncode({
          'platform': Platform.isIOS ? 'ios' : 'android',
          'token': token,
          'kind': 'fcm',
        }),
      );
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      final preview = res.body.length > 160
          ? '${res.body.substring(0, 160)}…'
          : res.body;
      debugPrint('[push] device register status=${res.statusCode} ok=$ok '
          'token=${_redact(token)} body=$preview');
    } catch (e) {
      debugPrint('[push] device register failed: $e (token=${_redact(token)})');
    }
  }

  static String _redact(String t) {
    if (t.length <= 12) return '***';
    return '${t.substring(0, 6)}…${t.substring(t.length - 4)} (len=${t.length})';
  }

  Future<void> _onForegroundMessage(RemoteMessage m) async {
    final n = m.notification;
    final title = n?.title ?? m.data['title'] ?? 'Nuru';
    final body = n?.body ?? m.data['body'] ?? '';
    final payload = jsonEncode(m.data);

    // WhatsApp-style: render the sender's avatar as the notification's
    // largeIcon when the backend supplies one (chat messages, social
    // notifications, etc.). Falls back to the app icon if missing or the
    // fetch fails - push must never block on the network.
    final avatarUrl = (m.data['sender_avatar'] ?? n?.android?.imageUrl ?? '').toString();
    AndroidBitmap<Object>? largeIcon;
    if (avatarUrl.isNotEmpty) {
      try {
        final resp = await http
            .get(Uri.parse(avatarUrl))
            .timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          largeIcon = ByteArrayAndroidBitmap(resp.bodyBytes);
        }
      } catch (_) {}
    }

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          largeIcon: largeIcon,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  void _handleTapPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      _handleNavigation(data);
    } catch (_) {}
  }

  void _handleNavigation(Map<String, dynamic> data) {
    final nav = _navKey?.currentState;
    if (nav == null) return;
    final type = (data['type'] ?? '').toString();
    switch (type) {
      case 'message':
        final convId = (data['conversation_id'] ?? '').toString();
        if (convId.isNotEmpty) {
          nav.pushNamed('/chat', arguments: {'conversation_id': convId});
        } else {
          nav.pushNamed('/messages');
        }
        break;
      case 'payment':
      case 'payment_received':
      case 'payment_failed':
      case 'withdrawal':
        nav.pushNamed('/wallet');
        break;
      case 'event_invite':
      case 'committee_invite':
      case 'rsvp_update':
        final ref = (data['reference_id'] ?? '').toString();
        if (ref.isNotEmpty) {
          nav.pushNamed('/event', arguments: {'id': ref, 'event_id': ref});
        } else {
          nav.pushNamed('/notifications');
        }
        break;
      case 'meeting':
      case 'meeting_invite':
      case 'meeting_starting':
      case 'meeting_reminder':
        final eventId = (data['event_id'] ?? '').toString();
        final meetingId = (data['meeting_id'] ?? data['reference_id'] ?? '').toString();
        if (eventId.isNotEmpty && meetingId.isNotEmpty) {
          nav.push(MaterialPageRoute(builder: (_) => MeetingDetailsScreen(
            eventId: eventId, meetingId: meetingId,
          )));
        } else {
          nav.pushNamed('/notifications');
        }
        break;
      default:
        nav.pushNamed('/notifications');
    }
  }
}
