import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:nuru/core/services/meetings_service.dart';
import 'package:nuru/screens/meetings/meeting_details_screen.dart';

class MeetingRoomScreen extends StatefulWidget {
  final String eventId;
  final String meetingId;
  final String roomId;
  final String? eventName;

  const MeetingRoomScreen({
    super.key,
    required this.eventId,
    required this.meetingId,
    required this.roomId,
    this.eventName,
  });

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final MeetingsService _service = MeetingsService();

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _loading = true;
  String? _error;
  String? _participantName;
  bool _isHost = false;

  // Join status
  String _joinStatus = '';
  String _meetingTitle = '';
  String _meetingSubtitle = '';
  Timer? _waitingPollTimer;

  // Live timer (computed from server-side started_at when available)
  DateTime? _meetingStartedAt;
  final Stopwatch _liveStopwatch = Stopwatch();
  Timer? _tickerTimer;

  // Local controls
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _showParticipants = false;
  bool _showChat = false;
  bool _screenShareEnabled = false;
  bool _handRaised = false;

  // Pre-join state - true until user confirms mic/cam
  bool _preJoin = true;

  // Raised hands from other participants
  final Set<String> _raisedHands = {};

  // Floating reactions with animation
  final List<_AnimatedReaction> _animatedReactions = [];

  // Join requests (host only)
  List<Map<String, dynamic>> _joinRequests = [];
  Timer? _joinRequestsPollTimer;

  // Chat
  final TextEditingController _chatController = TextEditingController();
  final List<_ChatMessage> _chatMessages = [];
  final ScrollController _chatScrollController = ScrollController();
  int _unreadChat = 0;

  // Reactions row above control bar (matches mockup)
  static const _quickReactions = ['👋', '👍', '❤️', '😂', '👏', '🎉'];

  // Set to true once the user explicitly hits "End / Leave". Until then, we
  // keep the LiveKit Room connected even if the screen is briefly recreated
  // (e.g. when Android shows the screen-share permission dialog or the user
  // background the app while sharing). This prevents the "rejoin every time
  // you screen-share" bug.
  bool _userLeft = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _meetingSubtitle = widget.eventName ?? '';
    _loading = false; // Pre-join screen first
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Intentionally a no-op: we want the LiveKit room to stay connected when
    // the app is paused/resumed (screen-share permission, notification panel,
    // etc.). The OS keeps audio/screen tracks alive via the foreground
    // service declared in AndroidManifest.xml.
    super.didChangeAppLifecycleState(state);
  }

  Future<void> _confirmJoin() async {
    setState(() {
      _preJoin = false;
      _loading = true;
    });
    await _connect();
  }

  Future<void> _connect() async {
    try {
      final joinRes = await _service.joinMeeting(widget.eventId, widget.meetingId);
      final joinData = joinRes['data'];
      final status = joinData?['status'] as String? ?? '';

      if (status == 'joined' || status == 'already_joined') {
        _meetingTitle = joinData?['title'] as String? ?? '';
        final startedAtStr = joinData?['started_at'] as String?;
        if (startedAtStr != null) {
          _meetingStartedAt = DateTime.tryParse(startedAtStr)?.toLocal();
        }
        await _fetchTokenAndConnect();
      } else if (status == 'waiting') {
        setState(() {
          _joinStatus = 'waiting';
          _loading = false;
        });
        _startWaitingPoll();
      } else if (status == 'rejected') {
        setState(() {
          _error = 'Your request to join was declined by the host.';
          _loading = false;
        });
      } else {
        setState(() {
          _error = joinRes['message'] as String? ?? 'Unable to join meeting.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to connect: $e';
        _loading = false;
      });
    }
  }

  void _startWaitingPoll() {
    _waitingPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final res = await _service.checkJoinStatus(widget.eventId, widget.meetingId);
        final status = res['data']?['status'] as String? ?? '';
        if (status == 'approved') {
          _waitingPollTimer?.cancel();
          setState(() {
            _joinStatus = 'approved';
            _loading = true;
          });
          await _fetchTokenAndConnect();
        } else if (status == 'rejected') {
          _waitingPollTimer?.cancel();
          setState(() {
            _joinStatus = 'rejected';
            _error = 'Your request to join was declined by the host.';
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _fetchTokenAndConnect() async {
    try {
      final res = await _service.getMeetingToken(widget.eventId, widget.meetingId);
      if (res['success'] != true || res['data'] == null) {
        setState(() {
          _error = 'Failed to get meeting token.';
          _loading = false;
        });
        return;
      }

      final token = res['data']['token'] as String;
      final url = res['data']['url'] as String;
      _participantName = res['data']['participant_name'] as String?;
      _isHost = res['data']['is_host'] as bool? ?? false;

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
          defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
        ),
      );

      _listener = room.createListener();
      _setupListeners();

      await room.connect(url, token);
      await room.localParticipant?.setCameraEnabled(_cameraEnabled);
      await room.localParticipant?.setMicrophoneEnabled(_micEnabled);

      setState(() {
        _room = room;
        _loading = false;
        _joinStatus = 'joined';
      });
      _startLiveTimer();

      if (_isHost) {
        _startJoinRequestsPoll();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to connect: $e';
        _loading = false;
      });
    }
  }

  void _startJoinRequestsPoll() {
    _pollJoinRequests();
    _joinRequestsPollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollJoinRequests());
  }

  Future<void> _pollJoinRequests() async {
    try {
      final res = await _service.listJoinRequests(widget.eventId, widget.meetingId);
      if (res['success'] == true && res['data'] != null) {
        setState(() {
          _joinRequests = List<Map<String, dynamic>>.from(res['data']);
        });
      }
    } catch (_) {}
  }

  Future<void> _approveJoinRequest(String requestId) async {
    try {
      await _service.reviewJoinRequest(widget.eventId, widget.meetingId, requestId, 'approve');
      setState(() {
        _joinRequests.removeWhere((r) => r['id'] == requestId);
      });
    } catch (_) {}
  }

  Future<void> _rejectJoinRequest(String requestId) async {
    try {
      await _service.reviewJoinRequest(widget.eventId, widget.meetingId, requestId, 'reject');
      setState(() {
        _joinRequests.removeWhere((r) => r['id'] == requestId);
      });
    } catch (_) {}
  }

  void _setupListeners() {
    _listener
      ?..on<ParticipantConnectedEvent>((event) => setState(() {}))
      ..on<ParticipantDisconnectedEvent>((event) => setState(() {}))
      ..on<TrackPublishedEvent>((event) => setState(() {}))
      ..on<TrackUnpublishedEvent>((event) => setState(() {}))
      ..on<TrackSubscribedEvent>((event) => setState(() {}))
      ..on<TrackUnsubscribedEvent>((event) => setState(() {}))
      ..on<TrackMutedEvent>((event) => setState(() {}))
      ..on<TrackUnmutedEvent>((event) => setState(() {}))
      ..on<ActiveSpeakersChangedEvent>((event) => setState(() {}))
      ..on<DataReceivedEvent>((event) {
        try {
          final text = utf8.decode(event.data, allowMalformed: true);
          final senderIdentity = event.participant?.identity ?? '';
          final senderName = (event.participant?.name?.isNotEmpty == true)
              ? event.participant!.name
              : (event.participant?.identity ?? 'Unknown');
          try {
            final msg = jsonDecode(text) as Map<String, dynamic>;
            final type = msg['type'] as String?;
            if (type == 'reaction') {
              final emoji = msg['payload'] as String? ?? '👍';
              _showAnimatedReaction(emoji, senderName);
              return;
            } else if (type == 'hand_raise') {
              setState(() => _raisedHands.add(senderIdentity));
              return;
            } else if (type == 'hand_lower') {
              setState(() => _raisedHands.remove(senderIdentity));
              return;
            } else if (type == 'mute_request') {
              final target = msg['target'] as String?;
              final localId = _room?.localParticipant?.identity;
              if (target != null && target == localId && _micEnabled) {
                _toggleMic();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('You were muted by $senderName'),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              }
              return;
            } else if (type == 'chat') {
              final body = (msg['payload'] as String?) ?? '';
              if (body.isEmpty) return;
              setState(() {
                _chatMessages.add(_ChatMessage(
                    sender: senderName, text: body, time: DateTime.now()));
                if (!_showChat) _unreadChat++;
              });
              _scrollChatToBottom();
              return;
            }
          } catch (_) {}
          // Plain text fallback (legacy clients)
          setState(() {
            _chatMessages.add(
              _ChatMessage(sender: senderName, text: text, time: DateTime.now()),
            );
            if (!_showChat) _unreadChat++;
          });
          _scrollChatToBottom();
        } catch (_) {}
      })
      ..on<RoomDisconnectedEvent>((event) {
        if (mounted) Navigator.pop(context);
      });
  }

  void _showAnimatedReaction(String emoji, String sender) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    final xPos = 20.0 + Random().nextDouble() * 60.0;
    final reaction = _AnimatedReaction(
      emoji: emoji,
      sender: sender,
      controller: controller,
      xPercent: xPos,
    );
    setState(() {
      _animatedReactions.add(reaction);
      if (_animatedReactions.length > 10) {
        _animatedReactions.first.controller.dispose();
        _animatedReactions.removeAt(0);
      }
    });
    controller.forward().then((_) {
      if (mounted) {
        setState(() => _animatedReactions.remove(reaction));
        controller.dispose();
      }
    });
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleMic() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    await lp.setMicrophoneEnabled(!_micEnabled);
    setState(() => _micEnabled = !_micEnabled);
  }

  Future<void> _toggleCamera() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    await lp.setCameraEnabled(!_cameraEnabled);
    setState(() => _cameraEnabled = !_cameraEnabled);
  }

  Future<void> _toggleScreenShare() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    try {
      await lp.setScreenShareEnabled(!_screenShareEnabled);
      setState(() => _screenShareEnabled = !_screenShareEnabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Screen share failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    // Find the camera track publication
    final cameraPub = lp.trackPublications.values
        .where((pub) => pub.source == TrackSource.camera && pub.track != null)
        .firstOrNull;
    if (cameraPub?.track is LocalVideoTrack) {
      final videoTrack = cameraPub!.track as LocalVideoTrack;
      try {
        await videoTrack.setCameraPosition(CameraPosition.back);
      } catch (_) {
        // Toggle approach
        await lp.setCameraEnabled(false);
        await Future.delayed(const Duration(milliseconds: 200));
        await lp.setCameraEnabled(true);
      }
    }
  }

  void _toggleHandRaise() {
    setState(() => _handRaised = !_handRaised);
    final identity = _room?.localParticipant?.identity ?? '';
    if (_handRaised) {
      _raisedHands.add(identity);
    } else {
      _raisedHands.remove(identity);
    }
    _sendDataMessage({
      'type': _handRaised ? 'hand_raise' : 'hand_lower',
    });
  }

  void _sendReaction(String emoji) {
    _sendDataMessage({'type': 'reaction', 'payload': emoji});
    _showAnimatedReaction(emoji, 'You');
  }

  void _sendDataMessage(Map<String, dynamic> msg) {
    final data = Uint8List.fromList(utf8.encode(jsonEncode(msg)));
    _room?.localParticipant?.publishData(data, reliable: true);
  }

  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _room == null) return;

    _sendDataMessage({'type': 'chat', 'payload': text});

    setState(() {
      _chatMessages.add(
        _ChatMessage(sender: _participantName ?? 'You', text: text, time: DateTime.now(), isMe: true),
      );
    });
    _chatController.clear();
    _scrollChatToBottom();
  }

  void _muteParticipant(String identity, String name) {
    _sendDataMessage({'type': 'mute_request', 'target': identity});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Asked $name to mute'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _leaveRoom() async {
    _userLeft = true;
    // Fire-and-forget server call so the UI exits immediately
    // and the next rejoin doesn't block on a stale leave roundtrip.
    unawaited(_service.leaveMeeting(widget.eventId, widget.meetingId)
        .catchError((_) => <String, dynamic>{}));
    unawaited(_room?.disconnect() ?? Future.value());
    if (mounted) Navigator.pop(context);
  }

  void _startLiveTimer() {
    _meetingStartedAt ??= DateTime.now();
    _liveStopwatch
      ..reset()
      ..start();
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  String _formatLiveDuration() {
    final base = _meetingStartedAt;
    final d = base != null
        ? DateTime.now().difference(base)
        : _liveStopwatch.elapsed;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waitingPollTimer?.cancel();
    _joinRequestsPollTimer?.cancel();
    _tickerTimer?.cancel();
    _liveStopwatch.stop();
    for (final r in _animatedReactions) {
      r.controller.dispose();
    }
    // Only tear down the LiveKit room when the user explicitly left. This
    // way Flutter widget rebuilds (e.g. when Android shows the screen-share
    // permission dialog) don't kick the user out of the meeting.
    if (_userLeft) {
      _listener?.dispose();
      _room?.disconnect();
      _room?.dispose();
    }
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: _preJoin
            ? _buildPreJoin()
            : _loading
                ? _buildLoading()
                : _joinStatus == 'waiting'
                    ? _buildWaitingRoom()
                    : _error != null
                        ? _buildError()
                        : _buildMeetingRoom(),
      ),
    );
  }

  Widget _buildPreJoin() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Top bar
          Row(children: [
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: SvgPicture.asset(
                'assets/icons/arrow-left-icon.svg',
                width: 22, height: 22,
                colorFilter:
                    const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
            ),
            const Spacer(),
          ]),
          const Spacer(),
          // Camera preview placeholder
          Container(
            width: double.infinity,
            height: 260,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF1F1F28), Color(0xFF111118)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    'assets/icons/people-in-meeting.svg',
                    width: 40, height: 40,
                    colorFilter: const ColorFilter.mode(
                        Colors.white70, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(height: 12),
                Text(_cameraEnabled ? 'Camera ready' : 'Camera off',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            _meetingTitle.isNotEmpty ? _meetingTitle : 'Ready to join?',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20, fontWeight: FontWeight.w800,
                letterSpacing: -0.4),
          ),
          if (_meetingSubtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_meetingSubtitle,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ],
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _preJoinToggle(
              svg: _micEnabled
                  ? 'assets/icons/mic-on.svg'
                  : 'assets/icons/mic-off.svg',
              label: _micEnabled ? 'Mic on' : 'Mic off',
              active: _micEnabled,
              onTap: () => setState(() => _micEnabled = !_micEnabled),
            ),
            const SizedBox(width: 16),
            _preJoinToggle(
              svg: 'assets/icons/camera-icon.svg',
              label: _cameraEnabled ? 'Camera on' : 'Camera off',
              active: _cameraEnabled,
              onTap: () => setState(() => _cameraEnabled = !_cameraEnabled),
            ),
          ]),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _confirmJoin,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF7B500),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50)),
              ),
              child: const Text('Join Meeting',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _preJoinToggle({
    required String svg,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Column(children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? Colors.white.withOpacity(0.14)
                : const Color(0xFFEF4444).withOpacity(0.85),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(svg,
              width: 24, height: 24,
              colorFilter:
                  const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
        ),
      ),
      const SizedBox(height: 8),
      Text(label,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('Connecting to meeting...', style: TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildWaitingRoom() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  strokeWidth: 3,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Waiting to be admitted', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('The host will let you in shortly.', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 8),
                Text('Waiting for host approval...', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: SvgPicture.asset('assets/icons/video_chat_icon.svg', width: 32, height: 32, colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn)),
            ),
            const SizedBox(height: 16),
            const Text('Unable to join meeting', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: SvgPicture.asset('assets/icons/arrow-left-icon.svg',
                  width: 16, height: 16, colorFilter: const ColorFilter.mode(Colors.white70, BlendMode.srcIn)),
              label: const Text('Go Back'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingRoom() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E0E14), Color(0xFF050507)],
        ),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _showParticipants
                    ? _buildParticipantsSheet()
                    : _showChat
                        ? _buildChatSheet()
                        : _buildVideoGrid(),
              ),
              if (!_showChat) _buildControlBar(),
            ],
          ),
          // Floating reactions
          ..._animatedReactions.map((r) => AnimatedBuilder(
                animation: r.controller,
                builder: (context, child) {
                  final progress = r.controller.value;
                  final screenHeight = MediaQuery.of(context).size.height;
                  final yOffset = progress * screenHeight * 0.45;
                  final opacity = progress < 0.7 ? 1.0 : (1.0 - (progress - 0.7) / 0.3);
                  final scale = progress < 0.2 ? (progress / 0.2) * 1.4 : 1.4 - (progress - 0.2) * 0.5;
                  return Positioned(
                    left: MediaQuery.of(context).size.width * r.xPercent / 100,
                    bottom: 120 + yOffset,
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: scale.clamp(0.5, 1.6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(r.emoji, style: const TextStyle(fontSize: 40)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(r.sender,
                                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              )),
          // Reactions are now always visible above the control bar (mockup).

          // Host: join requests
          if (_isHost && _joinRequests.isNotEmpty)
            Positioned(
              top: 70,
              right: 12,
              left: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A22),
                  border: Border.all(color: Colors.white10),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.person_add_rounded, size: 16, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text('${_joinRequests.length} waiting to join',
                            style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    ..._joinRequests.take(5).map((req) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(children: [
                            _buildAvatar(req['name'] as String? ?? '?', req['avatar_url'] as String?, 14),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(req['name'] as String? ?? 'Unknown',
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            GestureDetector(
                              onTap: () => _approveJoinRequest(req['id'] as String),
                              child: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(color: Colors.green.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.check_rounded, size: 18, color: Colors.green),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _rejectJoinRequest(req['id'] as String),
                              child: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(color: Colors.red.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                              ),
                            ),
                          ]),
                        )),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String name, String? avatarUrl, double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
      backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
      child: (avatarUrl == null || avatarUrl.isEmpty)
          ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: radius * 0.8, fontWeight: FontWeight.w600))
          : null,
    );
  }

  Widget _buildTopBar() {
    final participantCount = (_room?.remoteParticipants.length ?? 0) + 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.55), Colors.transparent],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapse / leave (chevron-down)
          _circleIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            size: 38,
            onTap: () => Navigator.maybePop(context),
          ),
          // Centered title + subtitle + live timer
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _meetingTitle.isNotEmpty ? _meetingTitle : 'Meeting',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                if (_meetingSubtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _meetingSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 11.5, fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    const Text('Live',
                        style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 11.5, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    Text(_formatLiveDuration(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5, fontWeight: FontWeight.w700,
                            letterSpacing: 0.3)),
                  ],
                ),
              ],
            ),
          ),
          // Participant count pill (tap to open participants panel)
          GestureDetector(
            onTap: () => setState(() {
              _showParticipants = true;
              _showChat = false;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SvgPicture.asset('assets/icons/people-in-meeting.svg',
                    width: 16, height: 16,
                    colorFilter: const ColorFilter.mode(
                        Colors.white, BlendMode.srcIn)),
                const SizedBox(width: 6),
                Text('$participantCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? bg,
    Color? fg,
    double size = 34,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            color: bg ?? Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: size * 0.5, color: fg ?? Colors.white),
        ),
      ),
    );
  }

  Widget _buildVideoGrid() {
    final room = _room;
    if (room == null) return const SizedBox();

    final localP = room.localParticipant! as Participant<TrackPublication>;
    final remotes = room.remoteParticipants.values
        .cast<Participant<TrackPublication>>()
        .toList();

    // Promote any active screen-share to "main"
    Participant<TrackPublication>? screenSharer;
    for (final p in [localP, ...remotes]) {
      final share = p.trackPublications.values.where(
        (pub) => pub.source == TrackSource.screenShareVideo && pub.track != null,
      ).firstOrNull;
      if (share != null) { screenSharer = p; break; }
    }

    final all = <Participant<TrackPublication>>[localP, ...remotes];

    // Solo
    if (all.length == 1) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: _buildParticipantTile(localP, fullSize: true),
      );
    }

    // Screen-share takes the full canvas, others as bottom strip
    if (screenSharer != null) {
      final others = all.where((p) => p.identity != screenSharer!.identity).toList();
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Expanded(child: _buildParticipantTile(screenSharer, fullSize: true)),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => AspectRatio(
                aspectRatio: 3 / 4,
                child: _buildParticipantTile(others[i]),
              ),
            ),
          ),
        ]),
      );
    }

    // 1-on-1: main = remote, self as floating PiP
    if (all.length == 2) {
      final remote = remotes.first;
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(children: [
          Positioned.fill(child: _buildParticipantTile(remote, fullSize: true)),
          Positioned(
            top: 12, right: 12,
            child: SizedBox(
              width: 110, height: 150,
              child: _buildParticipantTile(localP),
            ),
          ),
        ]),
      );
    }

    // 3 → top full-width, bottom row of 2
    if (all.length == 3) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Expanded(child: _buildParticipantTile(all[0])),
          const SizedBox(height: 8),
          Expanded(
            child: Row(children: [
              Expanded(child: _buildParticipantTile(all[1])),
              const SizedBox(width: 8),
              Expanded(child: _buildParticipantTile(all[2])),
            ]),
          ),
        ]),
      );
    }

    // 4 → 2x2, 5-6 → 2x3, 7+ → 3 col scroll
    final cross = all.length <= 4 ? 2 : (all.length <= 9 ? 2 : 3);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cross,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: cross == 2 ? 3 / 4 : 4 / 5,
        ),
        itemCount: all.length,
        itemBuilder: (_, i) => _buildParticipantTile(all[i]),
      ),
    );
  }

  Widget _buildParticipantTile(Participant<TrackPublication> participant, {bool fullSize = false}) {
    final videoTrack = participant.trackPublications.values
        .where((pub) => pub.source == TrackSource.camera && pub.track != null && !pub.muted)
        .firstOrNull?.track as VideoTrack?;

    final screenTrack = participant.trackPublications.values
        .where((pub) => pub.source == TrackSource.screenShareVideo && pub.track != null)
        .firstOrNull?.track as VideoTrack?;

    final isMuted = participant.trackPublications.values
        .where((pub) => pub.source == TrackSource.microphone)
        .firstOrNull?.muted ?? true;

    final isLocal = participant is LocalParticipant;
    final displayName = participant.name.isNotEmpty
        ? (isLocal ? 'You' : participant.name)
        : (isLocal ? 'You' : 'Participant');

    final isSpeaking = participant.isSpeaking;
    final isHandUp = _raisedHands.contains(participant.identity);
    final trackToShow = screenTrack ?? videoTrack;

    String? avatarUrl;
    try {
      if (participant.metadata != null && participant.metadata!.isNotEmpty) {
        final meta = jsonDecode(participant.metadata!) as Map<String, dynamic>;
        avatarUrl = meta['avatar_url'] as String?;
      }
    } catch (_) {}

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: const Color(0xFF15151B),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (isSpeaking) ...[
            const BoxShadow(
              color: Color(0xFFF7B500),
              blurRadius: 0,
              spreadRadius: 2.5,
            ),
            BoxShadow(
              color: const Color(0xFFF7B500).withOpacity(0.35),
              blurRadius: 18,
              spreadRadius: 4,
            ),
          ],
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (trackToShow != null)
            VideoTrackRenderer(
              trackToShow,
              fit: VideoViewFit.cover,
              mirrorMode: isLocal && screenTrack == null
                  ? VideoViewMirrorMode.mirror
                  : VideoViewMirrorMode.off,
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF1F1F28), Color(0xFF111118)],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAvatar(displayName, avatarUrl, fullSize ? 40 : 26),
                    const SizedBox(height: 10),
                    Text(displayName,
                        style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: fullSize ? 14 : 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          // Bottom gradient for legibility
          Positioned(
            left: 0, right: 0, bottom: 0, height: 70,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                  ),
                ),
              ),
            ),
          ),
          // Hand raise badge
          if (isHandUp)
            Positioned(
              top: 10, left: 10,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.5)),
                ),
                child: const Center(child: Text('✋', style: TextStyle(fontSize: 16))),
              ),
            ),
          // Speaking pulse
          if (isSpeaking)
            Positioned(
              top: 10, right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7B500).withOpacity(0.85),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.graphic_eq_rounded, size: 14, color: Colors.white),
              ),
            ),
          // Bottom name + mic
          Positioned(
            left: 10, right: 10, bottom: 10,
            child: Row(
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: isMuted ? const Color(0xFFEF4444) : Colors.white.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    isMuted ? 'assets/icons/mic-off.svg' : 'assets/icons/mic-on.svg',
                    width: 14, height: 14,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: -0.1),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          // Switch camera (local only with video)
          if (isLocal && videoTrack != null)
            Positioned(
              right: 10, top: 10,
              child: GestureDetector(
                onTap: _switchCamera,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                  child: const Icon(Icons.flip_camera_ios_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Full-screen participants panel (replaces side panel on mobile) ──
  Widget _buildParticipantsSheet() {
    final room = _room;
    if (room == null) return const SizedBox();

    final List<Participant<TrackPublication>> all = <Participant<TrackPublication>>[
      room.localParticipant! as Participant<TrackPublication>,
      ...room.remoteParticipants.values.cast<Participant<TrackPublication>>(),
    ];

    return Container(
      color: const Color(0xFF0F0F0F),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Icon(Icons.people_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text('Participants (${all.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showParticipants = false),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.close_rounded, size: 18, color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
          // List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10, indent: 64),
              itemCount: all.length,
              itemBuilder: (_, i) {
                final p = all[i];
                final isLocal = p is LocalParticipant;
                final isMuted = p.trackPublications.values
                    .where((pub) => pub.source == TrackSource.microphone)
                    .firstOrNull?.muted ?? true;
                final pName = p.name.isNotEmpty ? p.name : 'Participant';
                final isHandUp = _raisedHands.contains(p.identity);

                String? avatarUrl;
                try {
                  if (p.metadata != null && p.metadata!.isNotEmpty) {
                    final meta = jsonDecode(p.metadata!) as Map<String, dynamic>;
                    avatarUrl = meta['avatar_url'] as String?;
                  }
                } catch (_) {}

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _buildAvatar(pName, avatarUrl, 20),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$pName${isLocal ? " (You)" : ""}',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                            if (isLocal && _isHost)
                              Text('Host', style: TextStyle(color: Colors.amber.shade300, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      if (isHandUp)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                            child: const Center(child: Text('✋', style: TextStyle(fontSize: 14))),
                          ),
                        ),
                      if (p.isSpeaking)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.volume_up_rounded, size: 16, color: Colors.green),
                        ),
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: isMuted ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: SvgPicture.asset(
                          isMuted ? 'assets/icons/mic-off.svg' : 'assets/icons/mic-on.svg',
                          width: 16, height: 16,
                          colorFilter: ColorFilter.mode(
                              isMuted ? Colors.redAccent : Colors.green, BlendMode.srcIn),
                        ),
                      ),
                      if (_isHost && !isLocal && !isMuted) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _muteParticipant(p.identity, pName),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Mute',
                                style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Full-screen chat panel ──
  Widget _buildChatSheet() {
    return Container(
      color: const Color(0xFF0F0F0F),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                const Text('Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showChat = false),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.close_rounded, size: 18, color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: _chatMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 40, color: Colors.white.withOpacity(0.12)),
                        const SizedBox(height: 12),
                        Text('No messages yet', style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('Start the conversation', style: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 11)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _chatScrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _chatMessages.length,
                    itemBuilder: (_, i) {
                      final msg = _chatMessages[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(msg.isMe ? 'You' : msg.sender,
                                  style: TextStyle(
                                    color: msg.isMe ? Theme.of(context).colorScheme.primary : Colors.white70,
                                    fontSize: 12, fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: msg.isMe
                                    ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                                    : Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          // Input - matches messages_screen.dart pill style (no attachment / no voice)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.fromLTRB(18, 0, 6, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        maxLines: 4,
                        minLines: 1,
                        style: const TextStyle(fontSize: 15, color: Color(0xFF111111), height: 1.35),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(fontSize: 15, color: Color(0xFF9AA0A6), height: 1.35),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        onSubmitted: (_) => _sendChatMessage(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _sendChatMessage,
                      child: Container(
                        width: 40, height: 40,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/icons/send-icon.svg',
                            width: 16, height: 16,
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.55),
              Colors.black.withOpacity(0.85),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reactions row (always visible - matches mockup)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _quickReactions
                  .map((e) => GestureDetector(
                        onTap: () => _sendReaction(e),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          child: Text(e,
                              style: const TextStyle(fontSize: 26)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            // 6-button control row including Raise Hand
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _controlButton(
                  svgAsset: _micEnabled
                      ? 'assets/icons/mic-on.svg'
                      : 'assets/icons/mic-off.svg',
                  label: _micEnabled ? 'Mute' : 'Unmute',
                  onTap: _toggleMic,
                ),
                _controlButton(
                  icon: _cameraEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  label: _cameraEnabled ? 'Stop Video' : 'Start Video',
                  onTap: _toggleCamera,
                ),
                _controlButton(
                  svgAsset: 'assets/icons/raise-hand-icon.svg',
                  label: _handRaised ? 'Lower' : 'Raise',
                  active: _handRaised,
                  onTap: _toggleHandRaise,
                ),
                _controlButton(
                  svgAsset: 'assets/icons/share-screen.svg',
                  label: 'Share',
                  active: _screenShareEnabled,
                  onTap: _toggleScreenShare,
                ),
                _controlButton(
                  svgAsset: 'assets/icons/chat-icon.svg',
                  label: 'Chat',
                  active: _showChat,
                  onTap: () => setState(() {
                    _showChat = !_showChat;
                    if (_showChat) {
                      _showParticipants = false;
                      _unreadChat = 0;
                    }
                  }),
                  trailingBadge: _unreadChat > 0 ? _unreadChat : null,
                ),
                _controlButton(
                  svgAsset: 'assets/icons/call-end.svg',
                  label: 'End',
                  isLeave: true,
                  onTap: _leaveRoom,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton({
    IconData? icon,
    String? svgAsset,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool isLeave = false,
    int? trailingBadge,
  }) {
    final size = 46.0;
    final bg = isLeave
        ? const Color(0xFFEF4444)
        : active
            ? const Color(0xFFF7B500)
            : const Color(0xFF1F1F26);
    const fg = Colors.white;
    final iconSize = 20.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(clipBehavior: Clip.none, children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  boxShadow: isLeave
                      ? [
                          BoxShadow(
                            color: const Color(0xFFEF4444).withOpacity(0.45),
                            blurRadius: 16, offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: svgAsset != null
                      ? SvgPicture.asset(svgAsset,
                          width: iconSize, height: iconSize,
                          colorFilter:
                              const ColorFilter.mode(fg, BlendMode.srcIn))
                      : Icon(icon, color: fg, size: iconSize),
                ),
              ),
            ),
          ),
          if (trailingBadge != null && trailingBadge > 0)
            Positioned(
              top: -2, right: -2,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7B500),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$trailingBadge',
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _openMoreSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF15151B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 8,
                childAspectRatio: 0.95,
                children: [
                  _moreTile(ctx, Icons.people_alt_rounded, 'People',
                      svgAsset: 'assets/icons/people-in-meeting.svg',
                      onTap: () { Navigator.pop(ctx); setState(() { _showParticipants = true; _showChat = false; }); }),
                  _moreTile(ctx, Icons.chat_bubble_rounded, 'Chat',
                      onTap: () { Navigator.pop(ctx); setState(() { _showChat = true; _showParticipants = false; }); }),
                  _moreTile(ctx, Icons.screen_share_rounded, _screenShareEnabled ? 'Stop share' : 'Share screen',
                      svgAsset: 'assets/icons/share-screen.svg',
                      active: _screenShareEnabled,
                      onTap: () { Navigator.pop(ctx); _toggleScreenShare(); }),
                  _moreTile(ctx, _handRaised ? Icons.back_hand : Icons.back_hand_outlined,
                      _handRaised ? 'Lower hand' : 'Raise hand',
                      active: _handRaised,
                      onTap: () { Navigator.pop(ctx); _toggleHandRaise(); }),
                  _moreTile(ctx, Icons.flip_camera_ios_rounded, 'Flip camera',
                      onTap: () { Navigator.pop(ctx); _switchCamera(); }),
                  _moreTile(ctx, Icons.info_outline_rounded, 'Details',
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => MeetingDetailsScreen(
                            eventId: widget.eventId,
                            meetingId: widget.meetingId,
                            isCreator: _isHost,
                          ),
                        ));
                      }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreTile(BuildContext ctx, IconData icon, String label,
      {VoidCallback? onTap, bool active = false, String? svgAsset}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: active ? const Color(0xFFF7B500) : Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: svgAsset != null
                    ? SvgPicture.asset(svgAsset, width: 22, height: 22,
                        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))
                    : Icon(icon, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String sender;
  final String text;
  final DateTime time;
  final bool isMe;

  _ChatMessage({required this.sender, required this.text, required this.time, this.isMe = false});
}

class _AnimatedReaction {
  final String emoji;
  final String sender;
  final AnimationController controller;
  final double xPercent;

  _AnimatedReaction({required this.emoji, required this.sender, required this.controller, required this.xPercent});
}
