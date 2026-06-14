import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/calls_service.dart';
import '../../core/services/call_ui_coordinator.dart';

/// WhatsApp-style 1:1 video call screen.
///
/// Mirrors [VoiceCallScreen] but with a remote video tile filling the screen
/// and a draggable local preview in the corner. Mic + camera permissions are
/// requested before joining the LiveKit room.
class VideoCallScreen extends StatefulWidget {
  final String callId;
  final String peerName;
  final String? peerAvatar;
  final bool isOutgoing;
  final String? livekitUrl;
  final String? livekitToken;

  const VideoCallScreen({
    super.key,
    required this.callId,
    required this.peerName,
    this.peerAvatar,
    required this.isOutgoing,
    this.livekitUrl,
    this.livekitToken,
  });

  factory VideoCallScreen.outgoing({
    required String callId,
    required String peerName,
    String? peerAvatar,
    required String livekitUrl,
    required String livekitToken,
  }) =>
      VideoCallScreen(
        callId: callId,
        peerName: peerName,
        peerAvatar: peerAvatar,
        isOutgoing: true,
        livekitUrl: livekitUrl,
        livekitToken: livekitToken,
      );

  factory VideoCallScreen.incoming({
    required String callId,
    required String peerName,
    String? peerAvatar,
  }) =>
      VideoCallScreen(
        callId: callId,
        peerName: peerName,
        peerAvatar: peerAvatar,
        isOutgoing: false,
      );

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  bool _connecting = true;
  bool _connected = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _frontCamera = true;
  bool _speakerOn = true; // video calls default to speaker, like WhatsApp
  String _status = 'Connecting…';
  bool _closed = false;

  Timer? _durationTimer;
  DateTime? _connectedAt;

  // Local preview position - draggable corner tile.
  Offset _previewOffset = const Offset(16, 60);

  VideoTrack? _remoteVideoTrack;
  VideoTrack? _localVideoTrack;

  // WhatsApp-style ringback played to the caller while waiting. The user can
  // silence it via the on-screen "Silence" button.
  final AudioPlayer _ringback = AudioPlayer();
  bool _ringbackStarted = false;
  bool _ringerMuted = false;

  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isOutgoing) {
      _status = 'Ringing…';
      _startRingback();
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
    } else {
      _bootstrap();
    }
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
    final mic = await Permission.microphone.request();
    final cam = await Permission.camera.request();
    if (!mic.isGranted || !cam.isGranted) {
      _fail('Camera & microphone permissions are required');
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
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: true,
          ),
        ),
      );
      _listener = room.createListener();
      _listener!
        ..on<ParticipantConnectedEvent>((_) => _onRemoteJoined())
        ..on<ParticipantDisconnectedEvent>((_) => _onRemoteLeft())
        ..on<TrackSubscribedEvent>((_) => _refreshTracks())
        ..on<TrackUnsubscribedEvent>((_) => _refreshTracks())
        ..on<LocalTrackPublishedEvent>((_) => _refreshTracks())
        ..on<LocalTrackUnpublishedEvent>((_) => _refreshTracks())
        ..on<RoomDisconnectedEvent>((_) => _hangup(notifyServer: false));

      await room.connect(url, token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      await room.localParticipant?.setCameraEnabled(true);

      try {
        await Hardware.instance
            .setSpeakerphoneOn(true, forceSpeakerOutput: true);
      } catch (_) {}

      setState(() {
        _room = room;
        _connecting = false;
      });
      _refreshTracks();

      if (room.remoteParticipants.isNotEmpty) _onRemoteJoined();
    } catch (e) {
      _fail('Failed to connect: $e');
    }
  }

  void _refreshTracks() {
    final room = _room;
    if (room == null) return;

    VideoTrack? local;
    for (final pub in room.localParticipant?.videoTrackPublications ?? const []) {
      if (pub.track is VideoTrack) {
        local = pub.track as VideoTrack;
        break;
      }
    }

    VideoTrack? remote;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        if (pub.subscribed && pub.track is VideoTrack) {
          remote = pub.track as VideoTrack;
          break;
        }
      }
      if (remote != null) break;
    }

    setState(() {
      _localVideoTrack = local;
      _remoteVideoTrack = remote;
    });
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
      final elapsed = DateTime.now().difference(_connectedAt!);
      setState(() => _status = _formatDuration(elapsed));
    });
    _refreshTracks();
  }

  void _onRemoteLeft() => _hangup();

  Future<void> _toggleMute() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    final next = !_muted;
    try {
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

  Future<void> _toggleCamera() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    final next = !_cameraOff;
    await lp.setCameraEnabled(!next);
    setState(() => _cameraOff = next);
    _refreshTracks();
  }

  Future<void> _flipCamera() async {
    final track = _localVideoTrack;
    if (track is! LocalVideoTrack) return;
    final next = _frontCamera ? CameraPosition.back : CameraPosition.front;
    try {
      await track.setCameraPosition(next);
      setState(() => _frontCamera = next == CameraPosition.front);
    } catch (_) {
      // Fallback: toggle the track off and back on, which forces a fresh
      // camera selection on platforms where setCameraPosition isn't supported.
      try {
        final lp = _room?.localParticipant;
        await lp?.setCameraEnabled(false);
        await Future.delayed(const Duration(milliseconds: 150));
        await lp?.setCameraEnabled(true);
        setState(() => _frontCamera = !_frontCamera);
        _refreshTracks();
      } catch (_) {}
    }
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try {
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
      return '${d.inHours.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _durationTimer?.cancel();
    // Defensive: never let the ringback loop survive a screen tear-down.
    try { _ringback.stop(); } catch (_) {}
    _listener?.dispose();
    _room?.dispose();
    _ringback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      body: Stack(
        children: [
          // Remote video fills the screen; falls back to a dark gradient with
          // the peer's avatar while we're still ringing.
          Positioned.fill(child: _remoteLayer()),

          // Top bar: name + status + flip camera.
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.peerName,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _status,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_cameraOff && _localVideoTrack != null)
                      _topIconBtn(
                        icon: Icons.cameraswitch_rounded,
                        onTap: _flipCamera,
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Draggable local preview.
          if (!_cameraOff && _localVideoTrack != null)
            Positioned(
              left: _previewOffset.dx,
              top: _previewOffset.dy,
              child: GestureDetector(
                onPanUpdate: (d) {
                  setState(() {
                    final nx = (_previewOffset.dx + d.delta.dx)
                        .clamp(8.0, size.width - 120.0);
                    final ny = (_previewOffset.dy + d.delta.dy)
                        .clamp(40.0, size.height - 200.0);
                    _previewOffset = Offset(nx, ny);
                  });
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 110, height: 160,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: VideoTrackRenderer(
                      _localVideoTrack!,
                      fit: VideoViewFit.cover,
                      mirrorMode: _frontCamera ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
                    ),
                  ),
                ),
              ),
            ),

          // Bottom controls.
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: _controls(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _remoteLayer() {
    if (_remoteVideoTrack != null) {
      return VideoTrackRenderer(_remoteVideoTrack!, fit: VideoViewFit.cover);
    }
    // Pre-connect / waiting state - gradient + big avatar + ringing label.
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF15181F), Color(0xFF0A0C10)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _avatar(),
            const SizedBox(height: 22),
            Text(
              widget.isOutgoing ? 'Ringing…' : 'Connecting…',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar() {
    const size = 144.0;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 24,
            spreadRadius: 2,
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
          fontSize: 56,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }

  Widget _topIconBtn({required IconData icon, required VoidCallback onTap}) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }

  Widget _controls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleBtn(
          icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: _muted ? 'Unmute' : 'Mute',
          active: _muted,
          onTap: _connecting ? null : _toggleMute,
        ),
        _circleBtn(
          icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
          label: _cameraOff ? 'Camera off' : 'Camera',
          active: _cameraOff,
          onTap: _connecting ? null : _toggleCamera,
        ),
        if (!_connected)
          _circleBtn(
            icon: _ringerMuted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
            label: _ringerMuted ? 'Silenced' : 'Silence',
            active: _ringerMuted,
            onTap: _toggleRinger,
          ),
        _circleBtn(
          icon: _speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
          label: 'Speaker',
          active: _speakerOn,
          onTap: _connecting ? null : _toggleSpeaker,
        ),
        _endBtn(),
      ],
    );
  }

  Widget _endBtn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          radius: 36,
          onTap: () => _hangup(),
          child: Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE53935),
            ),
            child: Transform.rotate(
              angle: 2.356,
              child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'End',
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback? onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          radius: 32,
          onTap: onTap,
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.14),
            ),
            child: Icon(
              icon,
              size: 24,
              color: active ? const Color(0xFF0A0C10) : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}
