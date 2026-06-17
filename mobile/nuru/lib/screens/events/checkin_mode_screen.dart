import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/services/checkin_session.dart';
import '../../core/services/checkin_team_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import 'widgets/event_checkin_tab.dart';

/// Locked scanner shell for an active **Check-In Mode** session.
///
/// Once a team member has redeemed an access code, they land here. The
/// shell:
///   - Wraps [EventCheckinTab] (the existing premium scanner UI: camera,
///     stats, manual entry, recent scans) but in a context where the
///     bearer is the team member and the X-Checkin-Session header is
///     attached automatically.
///   - Locks the back button so a tap doesn't drop the session by
///     accident - ending requires an explicit confirmation.
///   - Sends a heartbeat every 60s so the backend knows the device is
///     still active.
class CheckinModeScreen extends StatefulWidget {
  const CheckinModeScreen({super.key});

  @override
  State<CheckinModeScreen> createState() => _CheckinModeScreenState();
}

class _CheckinModeScreenState extends State<CheckinModeScreen> {
  Timer? _heartbeat;
  String _title = 'Check-In Mode';

  @override
  void initState() {
    super.initState();
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) {
      // Fire-and-forget; we don't surface heartbeat failures to the user.
      CheckinTeamService.heartbeat();
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEC),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFD32F2F), size: 24),
            ),
            const SizedBox(height: 14),
            Text('End Check-In Mode?', style: appText(size: 17, weight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'You will be signed out of the scanner. To start scanning again you will need a new access code from the organizer.',
              style: appText(size: 13, color: AppColors.textSecondary, height: 1.4, weight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('End Session', style: appText(size: 14, weight: FontWeight.w800, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 50,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Keep Scanning',
                    style: appText(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ),
          ]),
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _endSession() async {
    final ok = await _confirmExit();
    if (!ok || !mounted) return;
    // Best-effort end on the backend, then always clear locally.
    await CheckinTeamService.endSession();
    await CheckinSession.clear();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final event = CheckinSession.event ?? const <String, dynamic>{};
    final eventId = CheckinSession.eventId ?? '';
    final eventTitle = (event['name'] ?? event['title'] ?? '').toString();
    final eventDate = (event['start_date'] ?? event['date'] ?? '').toString();
    final eventLocation = (event['location'] ?? event['venue'] ?? '').toString();

    // If the session somehow vanished (cleared in another tab), bail.
    if (eventId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _endSession();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('LIVE',
                    style: appText(size: 10, weight: FontWeight.w800, color: AppColors.primary, letterSpacing: 1)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _title,
                style: appText(size: 16, weight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _endSession();
                },
                icon: SvgPicture.asset(
                  'assets/icons/close-icon.svg',
                  width: 14,
                  height: 14,
                  colorFilter: const ColorFilter.mode(Color(0xFFD32F2F), BlendMode.srcIn),
                ),
                label: Text('End',
                    style: appText(size: 13, weight: FontWeight.w800, color: const Color(0xFFD32F2F))),
              ),
            ),
          ],
        ),
        body: EventCheckinTab(
          eventId: eventId,
          permissions: CheckinSession.permissions,
          eventTitle: eventTitle.isEmpty ? null : eventTitle,
          eventDate: eventDate.isEmpty ? null : eventDate,
          eventLocation: eventLocation.isEmpty ? null : eventLocation,
          onTitleResolved: (t) {
            if (mounted && t != _title) setState(() => _title = t);
          },
        ),
      ),
    );
  }
}
