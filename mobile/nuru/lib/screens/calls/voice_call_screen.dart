import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/calls_service.dart';
import '../../core/services/call_ui_coordinator.dart';

/// WhatsApp-style 1:1 voice call screen.
///
/// Handles BOTH:
///   • Outgoing - caller initiates via [VoiceCallScreen.outgoing]. We already
///     have a LiveKit token from `/calls/start`, so we connect immediately and
///     show "Calling…" until a remote participant joins.
///   • Incoming - callee accepts from CallKit / in-app and gets routed here
///     via [VoiceCallScreen.incoming]. We call `/calls/{id}/answer` to fetch
///     the LiveKit token, then connect.
///
/// Both modes share the same UI: large avatar, name, status line, and the
/// three-button control row (Mute · Speaker · End).
class VoiceCallScreen extends StatefulWidget {
  final String callId;
  final String peerName;
  final String? peerAvatar;
  final bool isOutgoing;

  /// Pre-fetched LiveKit credentials for outgoing calls.
  /// For incoming calls these stay null and we fetch them via /answer.
  final String? livekitUrl;
  final String? livekitToken;

  const VoiceCallScreen({
    super.key,
    required this.callId,
    required this.peerName,
    this.peerAvatar,
    required this.isOutgoing,
    this.livekitUrl,
    this.livekitToken,
  });

  factory VoiceCallScreen.outgoing({
    required String callId,
    required String peerName,
    String? peerAvatar,
    required String livekitUrl,
    required String livekitToken,
  }) =>
      VoiceCallScreen(
        callId: callId,
        peerName: peerName,
        peerAvatar: peerAvatar,
        isOutgoing: true,
        livekitUrl: livekitUrl,
        livekitToken: livekitToken,
      );

  factory VoiceCallScreen.incoming({
    required String callId,
    required String peerName,
    String? peerAvatar,
  }) =>
      VoiceCallScreen(
        callId: callId,
        peerName: peerName,
        peerAvatar: peerAvatar,
        isOutgoing: false,
      );

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  bool _connecting = true;
  bool _connected = false; // remote participant has joined
  bool _muted = false;
  bool _speakerOn = false;
  String _status = 'Connecting…';
  bool _closed = false;

  Timer? _durationTimer;
  DateTime? _connectedAt;
  Duration _elapsed = Duration.zero;

  // WhatsApp-style ringback tone played to the caller while the other side
  // is ringing. Stops as soon as the remote participant joins. The user can
  // mute the ringer independently via the on-screen "Silence" button.
  final AudioPlayer _ringback = AudioPlayer();
  bool _ringbackStarted = false;
  bool _ringerMuted = false;

  // Polls the backend so the caller's screen dismisses the moment the
  // callee declines / ends / the call times out (mirrors WhatsApp UX).
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isOutgoing) {
      _status = 'Ringing…';
      _startRingback();
      _startStatusPoller();
    } else {
      _bootstrap();
    }
  }

  void _startStatusPoller() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_closed || _connected) return;
      final status = await CallsService.getStatus(widget.callId);
      if (status == null) return;
      if (status == 'ongoing') {
        _statusTimer?.cancel();
        await _bootstrap();
        return;
      }
      if (status == 'declined' || status == 'missed' || status == 'ended') {
        if (mounted) setState(() => _status = status == 'declined' ? 'Declined' : 'Call ended');
        _hangup(notifyServer: false);
      }
    });
  }

  Future<void> _startRingback() async {
    if (_ringbackStarted) return;
    _ringbackStarted = true;
    try {
      await _ringback.setReleaseMode(ReleaseMode.loop);
      await _ringback.setVolume(_ringerMuted ? 0.0 : 0.6);
      await _ringback.play(AssetSource('audio/ringback.wav'));
    } catch (_) {}
  }

  Future<void> _stopRingback() async {
    if (!_ringbackStarted) return;
    _ringbackStarted = false;
    try { await _ringback.stop(); } catch (_) {}
  }

  Future<void> _toggleRinger() async {
    final next = !_ringerMuted;
    try { await _ringback.setVolume(next ? 0.0 : 0.6); } catch (_) {}
    if (mounted) setState(() => _ringerMuted = next);
  }

  Future<void> _bootstrap() async {
    // Mic permission is mandatory for voice calls.
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _fail('Microphone permission is required');
      return;
    }

    String? url = widget.livekitUrl;
    String? token = widget.livekitToken;

    if (!widget.isOutgoing) {
      setState(() => _status = 'Connecting…');
      final res = await CallsService.answer(widget.callId);
      if (res['success'] == true && res['data'] is Map) {
        final data = res['data'] as Map;
        url = data['url']?.toString();
        token = data['token']?.toString();
      }
    }

    if (widget.isOutgoing) {
      setState(() => _status = 'Ringing…');
    }

    if (url == null || token == null || url.isEmpty || token.isEmpty) {
      _fail('Could not get call credentials');
      return;
    }

    setState(() => _status = widget.isOutgoing ? 'Ringing…' : 'Connecting…');
    await _connectLiveKit(url, token);
  }

  Future<void> _connectLiveKit(String url, String token) async {
    try {
      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
        ),
      );
      _listener = room.createListener();
      _listener!
        ..on<ParticipantConnectedEvent>((_) => _onRemoteJoined())
        ..on<ParticipantDisconnectedEvent>((_) => _onRemoteLeft())
        ..on<RoomDisconnectedEvent>((_) => _hangup(notifyServer: false));

      await room.connect(url, token);
      await room.localParticipant?.setMicrophoneEnabled(true);

      // If the other party is already in the room (we were the callee), mark
      // connected immediately.
      final hasRemote = room.remoteParticipants.isNotEmpty;
      setState(() {
        _room = room;
        _connecting = false;
      });
      if (hasRemote) _onRemoteJoined();
    } catch (e) {
      _fail('Failed to connect: $e');
    }
  }

  void _onRemoteJoined() {
    if (_connected || !mounted) return;
    _stopRingback();
    setState(() {
      _connected = true;
      _status = '00:00';
      _connectedAt = DateTime.now();
    });
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) return;
      setState(() {
        _elapsed = DateTime.now().difference(_connectedAt!);
        _status = _formatDuration(_elapsed);
      });
    });
  }

  void _onRemoteLeft() {
    // Other side dropped - end the call from our side too.
    _hangup();
  }

  Future<void> _toggleMute() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    final next = !_muted;
    try {
      // Prefer track.mute()/unmute() so the audio publication stays alive
      // (setMicrophoneEnabled(false) unpublishes the track entirely, which
      // some servers/clients don't pick up correctly mid-call).
      final pub = lp.audioTrackPublications.isNotEmpty
          ? lp.audioTrackPublications.first
          : null;
      if (pub?.track != null) {
        if (next) {
          await pub!.mute();
        } else {
          await pub!.unmute();
        }
      } else {
        await lp.setMicrophoneEnabled(!next);
      }
    } catch (_) {
      try {
        await lp.setMicrophoneEnabled(!next);
      } catch (_) {}
    }
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try {
      // forceSpeakerOutput is required on iOS to actually route audio to the
      // loudspeaker even when headphones/Bluetooth would otherwise win.
      // On Android, this argument is ignored and the standard speakerphone
      // toggle is applied via the underlying AudioManager.
      await Hardware.instance
          .setSpeakerphoneOn(next, forceSpeakerOutput: next);
    } catch (_) {}
    if (mounted) setState(() => _speakerOn = next);
  }

  Future<void> _hangup({bool notifyServer = true}) async {
    if (_closed) return;
    _closed = true;
    _statusTimer?.cancel();
    _stopRingback();
    _durationTimer?.cancel();
    try {
      await _room?.disconnect();
    } catch (_) {}
    try {
      await FlutterCallkitIncoming.endCall(widget.callId);
    } catch (_) {}
    CallUiCoordinator.closeActive(widget.callId);
    CallUiCoordinator.closeRinging(widget.callId);
    if (notifyServer) {
      // Fire-and-forget; UI shouldn't block on it.
      // ignore: unawaited_futures
      CallsService.end(widget.callId);
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _connecting = false;
    });
    Future.delayed(const Duration(seconds: 2), () => _hangup());
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hh = d.inHours.toString().padLeft(2, '0');
      return '$hh:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _durationTimer?.cancel();
    // Defensive: always silence the ringer if the screen leaves the tree
    // for any reason (route push, hot reload, app backgrounding into a
    // different flow). Without this the loop has been known to keep
    // playing after the call screen is gone.
    try { _ringback.stop(); } catch (_) {}
    _listener?.dispose();
    _room?.dispose();
    _ringback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              widget.isOutgoing ? 'Voice call' : 'Incoming voice call',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.peerName,
              style: GoogleFonts.inter(
                fontSize: 26,
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _status,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            _avatar(),
            const Spacer(),
            _controls(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _avatar() {
    final size = 168.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: _connected ? 0.35 : 0.18),
            blurRadius: _connected ? 32 : 18,
            spreadRadius: _connected ? 4 : 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: (widget.peerAvatar != null && widget.peerAvatar!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: widget.peerAvatar!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _avatarFallback(),
              placeholder: (_, __) => _avatarFallback(),
            )
          : _avatarFallback(),
    );
  }

  Widget _avatarFallback() {
    return Center(
      child: Text(
        widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          fontSize: 64,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }

  Widget _controls() {
    final showRinger = !_connected; // ringer button only relevant while ringing
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleBtn(
          icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: _muted ? 'Unmute' : 'Mute',
          active: _muted,
          onTap: _connecting ? null : _toggleMute,
        ),
        if (showRinger)
          _circleBtn(
            icon: _ringerMuted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
            label: _ringerMuted ? 'Silenced' : 'Silence',
            active: _ringerMuted,
            onTap: _toggleRinger,
          ),
        _endBtn(),
        _circleBtn(
          icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
          label: 'Speaker',
          active: _speakerOn,
          onTap: _connecting ? null : _toggleSpeaker,
        ),
      ],
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required String label,
    required bool active,
    VoidCallback? onTap,
  }) {
    final bg = active ? Colors.white : Colors.white.withValues(alpha: 0.14);
    final fg = active ? const Color(0xFF0E1116) : Colors.white;
    return Column(
      children: [
        InkResponse(
          onTap: onTap,
          radius: 38,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            child: Icon(icon, color: fg, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _endBtn() {
    return Column(
      children: [
        InkResponse(
          onTap: _hangup,
          radius: 44,
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE53935),
            ),
            child: Transform.rotate(
              angle: 2.356, // 135° to mimic the WhatsApp end-call icon
              child: SvgPicture.asset(
                'assets/icons/call-icon.svg',
                width: 30,
                height: 30,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'End',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
