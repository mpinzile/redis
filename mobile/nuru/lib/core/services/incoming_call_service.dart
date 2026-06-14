import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'calls_service.dart';
import '../../screens/calls/incoming_call_screen.dart';
import '../../screens/calls/voice_call_screen.dart';
import '../../screens/calls/video_call_screen.dart';
import 'call_ui_coordinator.dart';

/// App-level service that:
///   1. Short-polls `GET /calls/incoming` every 3 seconds while signed in.
///   2. When a ringing call is found, shows a native CallKit (iOS) /
///      ConnectionService (Android) incoming-call UI via flutter_callkit_incoming
///      so the phone rings even when the app is backgrounded or locked.
///   3. Mirrors the ring with an in-app full-screen [IncomingCallScreen] when
///      the app is foregrounded - same UX as WhatsApp.
///   4. Bridges CallKit Accept/Decline events back to the FastAPI backend
///      (`/calls/{id}/answer` / `/calls/{id}/decline`) and pushes the
///      [VoiceCallScreen] when accepted.
///
/// This is intentionally a singleton, started once from `main.dart` after the
/// user signs in, and stopped on logout.
class IncomingCallService {
  IncomingCallService._();
  static final IncomingCallService instance = IncomingCallService._();

  GlobalKey<NavigatorState>? _navKey;
  Timer? _pollTimer;
  String? _activeRingingId; // de-dupe: avoid re-showing the same call
  StreamSubscription? _ckSub;
  bool _started = false;

  /// Pending answered call - populated when CallKit Accept fires before the
  /// app's navigator is mounted (e.g., user tapped Accept on the lock screen
  /// while the app was killed). The first navigator frame consumes it.
  Map<String, dynamic>? _pendingAccept;

  void start(GlobalKey<NavigatorState> navKey) {
    if (_started) return;
    _started = true;
    _navKey = navKey;

    // Listen for native CallKit events (Accept / Decline / End / Timeout).
    _ckSub = FlutterCallkitIncoming.onEvent.listen(_onCallKitEvent);

    // Kick off the poll loop. 3s matches the meeting-room poll cadence.
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    // Run once immediately so the first incoming call doesn't wait 3s.
    _poll();
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _ckSub?.cancel();
    _ckSub = null;
    _started = false;
    _activeRingingId = null;
    CallUiCoordinator.reset();
  }

  Future<void> _poll() async {
    final data = await CallsService.getIncoming();
    if (data == null) {
      // Backend says no ringing calls - clear our local "active" marker so a
      // future call from the same peer can ring again.
      final staleCallId = _activeRingingId;
      if (staleCallId != null && staleCallId.isNotEmpty) {
        await _endNativeCall(staleCallId);
        _navKey?.currentState?.popUntil(
          (route) => route.settings.name != 'incoming_call_$staleCallId',
        );
        CallUiCoordinator.closeRinging(staleCallId);
      }
      _activeRingingId = null;
      return;
    }

    final status = data['status']?.toString();
    if (status != null && status != 'ringing') {
      await _endNativeCall(data['id']?.toString() ?? '');
      _activeRingingId = null;
      return;
    }

    final callId = data['id']?.toString() ?? '';
    if (callId.isEmpty || callId == _activeRingingId) return;
    _activeRingingId = callId;

    final caller = data['caller'] is Map ? data['caller'] as Map : const {};
    final peerName = caller['name']?.toString() ?? caller['display_name']?.toString() ?? 'Incoming call';
    final peerAvatar = caller['avatar']?.toString();
    final kind = (data['kind']?.toString() ?? 'voice').toLowerCase() == 'video' ? 'video' : 'voice';

    final foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    await _ringNative(callId: callId, peerName: peerName, peerAvatar: peerAvatar, kind: kind);
    if (foreground) {
      _ringInApp(callId: callId, peerName: peerName, peerAvatar: peerAvatar, kind: kind);
    }
  }

  Future<void> _ringNative({
    required String callId,
    required String peerName,
    String? peerAvatar,
    String kind = 'voice',
  }) async {
    final isVideo = kind == 'video';
    try {
      final params = CallKitParams(
        id: callId,
        nameCaller: peerName,
        appName: 'Nuru',
        avatar: peerAvatar,
        handle: peerName,
        type: isVideo ? 1 : 0, // 0 = audio call, 1 = video
        textAccept: 'Accept',
        textDecline: 'Decline',
        duration: 30000, // 30s ring timeout
        extra: {'kind': kind},
        missedCallNotification: NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: isVideo ? 'Missed video call' : 'Missed voice call',
          callbackText: 'Call back',
        ),
        android: AndroidParams(
          isCustomNotification: false,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0E1116',
          actionColor: '#FECA08',
          incomingCallNotificationChannelName:
              isVideo ? 'Incoming video calls' : 'Incoming voice calls',
          missedCallNotificationChannelName: 'Missed calls',
        ),
        ios: IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: isVideo,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          supportsDTMF: false,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
        ),
      );
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      debugPrint('[IncomingCallService] CallKit show failed: $e');
    }
  }

  void _ringInApp({
    required String callId,
    required String peerName,
    String? peerAvatar,
    String kind = 'voice',
  }) {
    final nav = _navKey?.currentState;
    if (nav == null) return;
    if (!CallUiCoordinator.showRinging(callId)) return;
    final route = MaterialPageRoute(
      settings: RouteSettings(name: 'incoming_call_$callId'),
      builder: (_) => IncomingCallScreen(
        callId: callId,
        peerName: peerName,
        peerAvatar: peerAvatar,
        kind: kind,
      ),
      fullscreenDialog: true,
    );
    nav.push(route).whenComplete(() => CallUiCoordinator.closeRinging(callId));
  }

  Future<void> _onCallKitEvent(CallEvent? event) async {
    if (event == null) return;
    final body = event.body;
    final callId = body is Map ? (body['id']?.toString() ?? '') : '';

    switch (event.event) {
      case Event.actionCallAccept:
        await _handleAccept(callId, body);
        break;
      case Event.actionCallDecline:
      case Event.actionCallTimeout:
        if (callId.isNotEmpty) {
          // ignore: unawaited_futures
          CallsService.decline(callId);
        }
        if (callId.isNotEmpty) await _endNativeCall(callId);
        if (callId.isNotEmpty) CallUiCoordinator.closeRinging(callId);
        _activeRingingId = null;
        break;
      case Event.actionCallEnded:
        if (callId.isNotEmpty) {
          // ignore: unawaited_futures
          CallsService.end(callId);
        }
        if (callId.isNotEmpty) await _endNativeCall(callId);
        if (callId.isNotEmpty) CallUiCoordinator.closeRinging(callId);
        _activeRingingId = null;
        break;
      default:
        break;
    }
  }

  Future<void> _handleAccept(String callId, dynamic body) async {
    if (callId.isEmpty) return;
    final peerName = (body is Map ? body['nameCaller']?.toString() : null) ?? 'Call';
    final peerAvatar = (body is Map ? body['avatar']?.toString() : null);
    // CallKit echoes back the `extra` map we set in _ringNative; use it to
    // tell voice vs video apart on Accept.
    String kind = 'voice';
    if (body is Map) {
      final extra = body['extra'];
      if (extra is Map) {
        final k = extra['kind']?.toString().toLowerCase();
        if (k == 'video') kind = 'video';
      }
      // Some platforms surface the type as int (0 = audio, 1 = video).
      final t = body['type'];
      if (t == 1 || t == '1') kind = 'video';
    }

    final nav = _navKey?.currentState;
    if (nav == null) {
      // Navigator not mounted yet - stash and let the splash/auth flow consume
      // it after first frame.
      _pendingAccept = {
        'id': callId,
        'name': peerName,
        'avatar': peerAvatar,
        'kind': kind,
      };
      return;
    }

    if (!CallUiCoordinator.openActive(callId)) return;
    await _endNativeCall(callId);
    nav.popUntil((route) => route.settings.name != 'incoming_call_$callId');

    nav.push(
      MaterialPageRoute(
        settings: RouteSettings(name: 'active_call_$callId'),
        builder: (_) => kind == 'video'
            ? VideoCallScreen.incoming(
                callId: callId,
                peerName: peerName,
                peerAvatar: peerAvatar,
              )
            : VoiceCallScreen.incoming(
                callId: callId,
                peerName: peerName,
                peerAvatar: peerAvatar,
              ),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _endNativeCall(String callId) async {
    if (callId.isEmpty) return;
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (_) {}
  }

  /// Drain a pending CallKit Accept that arrived before the navigator was
  /// ready. Call this from your post-login root screen.
  void consumePendingAccept() {
    final pending = _pendingAccept;
    if (pending == null) return;
    _pendingAccept = null;
    _handleAccept(pending['id'] as String, {
      'id': pending['id'],
      'nameCaller': pending['name'],
      'avatar': pending['avatar'],
      'extra': {'kind': pending['kind'] ?? 'voice'},
    });
  }
}
