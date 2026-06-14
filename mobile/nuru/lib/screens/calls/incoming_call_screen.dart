import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/calls_service.dart';
import '../../core/services/call_ui_coordinator.dart';
import 'voice_call_screen.dart';
import 'video_call_screen.dart';

/// Full-screen in-app ringer shown when a call comes in while the app is in
/// the foreground. (When the app is backgrounded / locked, CallKit /
/// ConnectionService - wired in IncomingCallService - handles the ring.)
///
/// Tapping Accept pushes the appropriate call screen ([VoiceCallScreen] or
/// [VideoCallScreen] depending on [kind]) which calls `/calls/{id}/answer`
/// and joins the LiveKit room. Decline calls `/calls/{id}/decline`.
class IncomingCallScreen extends StatelessWidget {
  final String callId;
  final String peerName;
  final String? peerAvatar;
  final String kind; // 'voice' | 'video'

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.peerName,
    this.peerAvatar,
    this.kind = 'voice',
  });

  bool get _isVideo => kind == 'video';

  Future<void> _accept(BuildContext context) async {
    CallUiCoordinator.openActive(callId);
    try { await FlutterCallkitIncoming.endCall(callId); } catch (_) {}
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: RouteSettings(name: 'active_call_$callId'),
        builder: (_) => _isVideo
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

  Future<void> _decline(BuildContext context) async {
    // Fire-and-forget; we close the UI immediately so the user feels it's
    // instant. The server will mark the call as declined.
    // ignore: unawaited_futures
    CallsService.decline(callId);
    CallUiCoordinator.closeRinging(callId);
    try { await FlutterCallkitIncoming.endCall(callId); } catch (_) {}
    if (context.mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            Text(
              _isVideo ? 'Incoming video call' : 'Incoming voice call',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              peerName,
              style: GoogleFonts.inter(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ringing…',
              style: GoogleFonts.inter(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            _avatar(),
            const Spacer(),
            _actions(context),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _avatar() {
    const size = 168.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: (peerAvatar != null && peerAvatar!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: peerAvatar!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _fallback(),
              placeholder: (_, __) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() {
    return Center(
      child: Text(
        peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          fontSize: 64,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _actionBtn(
          color: const Color(0xFFE53935),
          icon: SvgPicture.asset(
            'assets/icons/call-icon.svg',
            width: 30,
            height: 30,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          rotate: 2.356,
          label: 'Decline',
          onTap: () => _decline(context),
        ),
        _actionBtn(
          color: const Color(0xFF22C55E),
          icon: _isVideo
              ? const Icon(Icons.videocam_rounded, color: Colors.white, size: 30)
              : SvgPicture.asset(
                  'assets/icons/call-icon.svg',
                  width: 30,
                  height: 30,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
          label: 'Accept',
          onTap: () => _accept(context),
        ),
      ],
    );
  }

  Widget _actionBtn({
    required Color color,
    required Widget icon,
    required String label,
    required VoidCallback onTap,
    double rotate = 0,
  }) {
    return Column(
      children: [
        InkResponse(
          onTap: onTap,
          radius: 44,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Center(
              child: rotate == 0 ? icon : Transform.rotate(angle: rotate, child: icon),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
