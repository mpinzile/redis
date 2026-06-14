/// DeepLinkService - listens for incoming https://nuru.tz/* and https://nuru.ke/*
/// links (Android App Links + iOS Universal Links) and routes them to the right
/// in-app screen using a global navigatorKey.
///
/// Wire-up: in main.dart, after MaterialApp creation, call
/// `DeepLinkService.instance.init(navigatorKey)`.
///
/// Routes handled (all shareable content):
///   /event/:id          → EventDetailScreen
///   /ticket/:code       → TicketDetailScreen
///   /u/:username        → PublicProfileScreen
///   /services/view/:id  → PublicServiceScreen
///   /post/:id           → PostDetailModal route
///   /moment/:id         → MomentDetailScreen
///   /c/:token           → PublicContributeScreen
///   /rsvp/:code         → RsvpScreen
///   /m/:token           → MeetingRoomScreen (after resolving via backend)
///
/// Unknown paths fall back to the home screen so the app never gets stuck.
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:nuru/core/services/api_service.dart';
import 'package:nuru/screens/meetings/meeting_room_screen.dart';

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _initialHandled = false;

  static const _supportedHosts = {'nuru.tz', 'www.nuru.tz', 'nuru.ke', 'www.nuru.ke'};

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    // Cold-start link
    if (!_initialHandled) {
      _initialHandled = true;
      try {
        final initial = await _appLinks.getInitialLink();
        if (initial != null) _handle(initial);
      } catch (_) {/* ignore */}
    }

    // Warm links while app is alive
    _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  void _handle(Uri uri) {
    debugPrint('[DeepLink] received uri=$uri host=${uri.host} path=${uri.path} segments=${uri.pathSegments}');
    // Accept either https://nuru.tz/* (App Links / Universal Links) or the
    // custom scheme nuru://* used by the web "Open in app" banner. For the
    // custom scheme there is no host, so we skip the host check.
    final isCustomScheme = uri.scheme == 'nuru';
    if (!isCustomScheme && !_supportedHosts.contains(uri.host)) {
      debugPrint('[DeepLink] ignored · unsupported host');
      return;
    }
    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      debugPrint('[DeepLink] navigator not ready');
      return;
    }

    // For custom-scheme URIs like nuru://i/CODE the "i" lives in uri.host,
    // not in pathSegments. Normalize by prepending the host as the first
    // segment so the switch below treats https:// and nuru:// the same.
    final segments = isCustomScheme && uri.host.isNotEmpty
        ? <String>[uri.host, ...uri.pathSegments]
        : uri.pathSegments;
    if (segments.isEmpty) {
      nav.pushNamedAndRemoveUntil('/', (_) => false);
      return;
    }

    // Routing table - uses named routes when available, otherwise pushes
    // a builder via the navigator. Add new mappings here as new routes ship.
    final first = segments.first;
    final rest = segments.length > 1 ? segments[1] : null;
    String? routed;
    switch (first) {
      case 'event':
        if (rest != null) { nav.pushNamed('/event', arguments: {'id': rest}); routed = '/event'; }
        break;
      case 'ticket':
        if (rest != null) { nav.pushNamed('/ticket', arguments: {'code': rest}); routed = '/ticket'; }
        break;
      case 'u':
        if (rest != null) { nav.pushNamed('/profile', arguments: {'username': rest}); routed = '/profile'; }
        break;
      case 'services':
        if (segments.length >= 3 && segments[1] == 'view') {
          nav.pushNamed('/service', arguments: {'id': segments[2]});
          routed = '/service';
        }
        break;
      case 'post':
        if (rest != null) { nav.pushNamed('/post', arguments: {'id': rest}); routed = '/post'; }
        break;
      case 'moment':
        if (rest != null) { nav.pushNamed('/moment', arguments: {'id': rest}); routed = '/moment'; }
        break;
      case 'c':
        if (rest != null) { nav.pushNamed('/contribute', arguments: {'token': rest}); routed = '/contribute'; }
        break;
      case 'rsvp':
        if (rest != null) { nav.pushNamed('/rsvp', arguments: {'code': rest}); routed = '/rsvp'; }
        break;
      case 'i':
        // Invitation landing - distinct from RSVP so the screen can show the
        // right label / actions. Falls back to placeholder until the native
        // invitation screen ships.
        if (rest != null) { nav.pushNamed('/invitation', arguments: {'code': rest}); routed = '/invitation'; }
        break;
      case 'set-password':
        if (rest != null) { nav.pushNamed('/set-password', arguments: {'token': rest}); routed = '/set-password'; }
        break;
      case 'cards':
        if (rest != null) { nav.pushNamed('/cards', arguments: {'id': rest}); routed = '/cards'; }
        break;
      case 'm':
        if (rest != null) { _resolveMeetingToken(nav, rest); routed = '/m'; }
        break;
      default:
        break;
    }
    debugPrint('[DeepLink] routed=${routed ?? "<no-match, stayed in place>"}');
  }

  /// Resolves an opaque meeting redirect token via the backend and pushes the
  /// in-app `MeetingRoomScreen` when possible. If the resolver returns only a
  /// raw URL (e.g. external Zoom/Meet link), the user is sent to a friendly
  /// placeholder screen with a "Open in browser" affordance instead.
  Future<void> _resolveMeetingToken(NavigatorState nav, String token) async {
    try {
      final res = await ApiService.get('/m/$token/resolve', auth: false);
      final data = (res['data'] ?? res) as Map<String, dynamic>?;
      final eventId = data?['event_id']?.toString();
      final meetingId = data?['meeting_id']?.toString();
      final roomId = data?['room_id']?.toString();
      if (eventId != null && eventId.isNotEmpty &&
          meetingId != null && meetingId.isNotEmpty &&
          roomId != null && roomId.isNotEmpty) {
        nav.push(MaterialPageRoute(
          builder: (_) => MeetingRoomScreen(
            eventId: eventId,
            meetingId: meetingId,
            roomId: roomId,
          ),
        ));
        return;
      }
    } catch (e) {
      debugPrint('[DeepLink] /m resolve failed: $e');
    }
    // Fallback: open the friendly placeholder so the user is not dumped on home.
    nav.pushNamed('/deep-link-fallback', arguments: {'path': '/m/$token'});
  }
}
