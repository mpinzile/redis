import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';

/// Premium full-screen "Check In Failed" page. Renders the unified error
/// payload returned by the scanner endpoint when a QR cannot be checked in
/// (not found, already used, wrong event timing, ticket not paid, etc).
class CheckinFailedScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final String message;
  final VoidCallback onScanAgain;
  final VoidCallback onManualCheckIn;

  const CheckinFailedScreen({
    super.key,
    required this.data,
    required this.message,
    required this.onScanAgain,
    required this.onManualCheckIn,
  });

  String _fmtDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    // Server timestamps may arrive without a tz suffix; treat naive ISO
    // strings as UTC so toLocal() can shift them to the viewer's timezone.
    final hasTz = iso.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso);
    var normalized = iso;
    if (!hasTz) {
      if (iso.contains('T')) {
        normalized = '${iso}Z';
      } else if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}').hasMatch(iso)) {
        normalized = '${iso.replaceFirst(' ', 'T')}Z';
      }
    }
    final dt = DateTime.tryParse(normalized)?.toLocal();
    if (dt == null) return iso;
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m $ampm';
  }

  String get _reasonLabel {
    final r = (data['reason'] ?? '').toString();
    switch (r) {
      case 'already_used': return 'Already checked in';
      case 'not_found': return 'Guest not found';
      case 'wrong_event': return 'Wrong event';
      case 'ticket_pending': return 'Awaiting payment';
      case 'ticket_rejected': return 'Ticket rejected';
      case 'ticket_cancelled': return 'Ticket cancelled';
      case 'event_ended': return 'Event ended';
      case 'event_not_started': return 'Check-in not ready';
      case 'rsvp_declined': return 'Guest declined';
      case 'empty_code': return 'Invalid QR code';
      case 'forbidden': return 'Scanner not allowed';
      default:
        // Fall back to the message text rather than echoing the title.
        final m = message.trim();
        if (m.isNotEmpty) return m;
        return 'Failed to check in';
    }
  }

  String get _whatThisMeans {
    final r = (data['reason'] ?? '').toString();
    final at = _fmtDateTime(data['checked_in_at']?.toString());
    final guest = (data['name'] ?? '').toString();
    final ev = (data['event'] as Map?) ?? const {};
    final evName = (ev['name'] ?? '').toString();
    final who = guest.isNotEmpty && guest.toLowerCase() != 'unknown'
        ? guest
        : 'This guest';
    switch (r) {
      case 'already_used':
        return at == '-'
            ? '$who has already been checked in for this event.'
            : '$who was already checked in on $at.';
      case 'not_found':
        return "We couldn't match this QR code to any guest or ticket for ${evName.isNotEmpty ? evName : 'this event'}. They may not be invited, or the code is from another event.";
      case 'wrong_event':
        return "This QR code belongs to a different event. Switch to the correct event in the scanner and try again.";
      case 'ticket_pending':
        return "$who hasn't paid for this ticket yet, so it can't be used to enter.";
      case 'ticket_rejected':
        return "$who's ticket was rejected and cannot be used for entry.";
      case 'ticket_cancelled':
        return "$who's ticket was cancelled and is no longer valid.";
      case 'event_ended':
        return "${evName.isNotEmpty ? evName : 'This event'} has already ended, so check-in is closed.";
      case 'event_not_started':
        return "${evName.isNotEmpty ? evName : 'This event'} hasn't started yet. Check-in opens on the event day.";
      case 'rsvp_declined':
        return "$who declined this invitation and isn't expected to attend.";
      case 'empty_code':
        return 'No readable QR code was received. Please scan again or enter the code manually.';
      default:
        return message.isEmpty
            ? 'This QR code cannot be used to check in right now.'
            : message;
    }
  }


  String _shortId(String s) {
    if (s.isEmpty) return '-';
    final compact = s.replaceAll('-', '');
    if (compact.length <= 8) return compact.toUpperCase();
    return compact.substring(0, 8).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final ev = (data['event'] as Map?) ?? {};
    final scanTime = _fmtDateTime(data['scan_time']?.toString());
    final rawName = (data['name'] ?? '').toString().trim();
    final hasName = data['has_name'] == true ||
        (rawName.isNotEmpty &&
            rawName.toLowerCase() != 'guest' &&
            rawName.toLowerCase() != 'unknown' &&
            rawName.toLowerCase() != 'guest checked in');
    final guestName = hasName ? rawName : 'Guest';
    final isTicket = data['kind'] == 'ticket';
    final isTicketed = data['is_ticketed_event'] == true || isTicket;
    final whoLabel = isTicketed ? 'Ticket Holder' : 'Guest Name';
    final eventName = (ev['name'] ?? '-').toString();
    final eventType = (data['event_type'] ?? '').toString();
    final plusOnes = (data['plus_ones'] is num) ? (data['plus_ones'] as num).toInt() : 0;
    final rawCode = (data['ticket_id'] ?? data['code'] ?? data['scanned_code'] ?? '').toString();
    final code = _shortId(rawCode);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset('assets/icons/arrow-left-icon.svg',
              width: 22, height: 22,
              colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Cannot Check In', style: appText(size: 18, weight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _heroBlock(),
                  const SizedBox(height: 16),
                  _detailsCard([
                    _row('assets/icons/clock-icon.svg', 'Scan Time', scanTime),
                    _row('assets/icons/user-icon.svg', whoLabel, guestName),
                    if (!isTicketed && eventType.isNotEmpty)
                      _row('assets/icons/calendar-icon.svg', 'Event Type', eventType),
                    _row('assets/icons/calendar-icon.svg', 'Event', eventName),
                    _row('assets/icons/ticket-icon.svg', isTicketed ? 'Ticket ID' : 'Guest ID', code, mono: true),
                    if (plusOnes > 0)
                      _row('assets/icons/users-icon.svg', 'Plus Ones', '+$plusOnes'),
                    _reasonRow(),
                  ]),
                  const SizedBox(height: 12),
                  _whatThisMeansBox(),
                  const SizedBox(height: 14),
                  _whatYouCanDo(context),
                ]),
              ),
            ),
            _bottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _heroBlock() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(color: AppColors.error.withOpacity(0.08), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 70, height: 70,
            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.14), shape: BoxShape.circle),
            child: Center(
              child: SvgPicture.asset('assets/icons/close-circle-icon.svg', width: 38, height: 38,
                  colorFilter: const ColorFilter.mode(AppColors.error, BlendMode.srcIn)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text("We couldn't check in this guest",
            style: appText(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary),
            textAlign: TextAlign.center),
        const SizedBox(height: 10),
        // Reason — large, red, easy to read at the gate.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(_reasonLabel,
              style: appText(size: 22, weight: FontWeight.w800, color: AppColors.error),
              textAlign: TextAlign.center),
        ),
      ]),
    );
  }

  Widget _detailsCard(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Scan Details', style: appText(size: 14, weight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...rows,
      ]),
    );
  }

  Widget _row(String iconAsset, String label, String value, {bool mono = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight.withOpacity(0.7))),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.10), shape: BoxShape.circle),
          child: Center(
            child: SvgPicture.asset(iconAsset, width: 17, height: 17,
                colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(label, style: appText(size: 13, color: AppColors.textSecondary, weight: FontWeight.w500)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(value,
                textAlign: TextAlign.right,
                style: appText(
                  size: mono ? 12 : 13,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.35,
                )),
          ),
        ),
      ]),
    );
  }

  Widget _reasonRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: AppColors.error.withOpacity(0.10), shape: BoxShape.circle),
          child: Center(
            child: SvgPicture.asset('assets/icons/info-icon.svg', width: 17, height: 17,
                colorFilter: const ColorFilter.mode(AppColors.error, BlendMode.srcIn)),
          ),
        ),
        const SizedBox(width: 12),
        Text('Reason', style: appText(size: 13, color: AppColors.textSecondary, weight: FontWeight.w500)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(_reasonLabel,
              textAlign: TextAlign.right,
              style: appText(size: 16, weight: FontWeight.w800, color: AppColors.error)),
        ),
      ]),
    );
  }

  Widget _whatThisMeansBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withOpacity(0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('What this means',
            style: appText(size: 13, weight: FontWeight.w800, color: AppColors.error)),
        const SizedBox(height: 4),
        Text(_whatThisMeans,
            style: appText(size: 12.5, color: AppColors.textSecondary, weight: FontWeight.w500)),
      ]),
    );
  }

  Widget _whatYouCanDo(BuildContext context) {
    Widget action(String iconAsset, String t, String s, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.10), shape: BoxShape.circle),
                child: Center(
                  child: SvgPicture.asset(iconAsset, width: 18, height: 18,
                      colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: appText(size: 13.5, weight: FontWeight.w800)),
                Text(s, style: appText(size: 12, color: AppColors.textTertiary)),
              ])),
              SvgPicture.asset('assets/icons/arrow-right-icon.svg', width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
            ]),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        Text('What you can do', style: appText(size: 14, weight: FontWeight.w800)),
        action('assets/icons/camera-icon.svg', 'Scan Again',
            'Ensure the QR code is clear and try scanning again.', () { Navigator.of(context).maybePop(); onScanAgain(); }),
        action('assets/icons/keyboard-icon.svg', 'Manual Check In',
            'Search for the guest and check them in manually.', () { Navigator.of(context).maybePop(); onManualCheckIn(); }),
      ]),
    );
  }

  Widget _bottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Column(children: [
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: () { Navigator.of(context).pop(); onScanAgain(); },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SvgPicture.asset('assets/icons/camera-icon.svg', width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
              const SizedBox(width: 8),
              Text('Scan Again', style: appText(size: 14, weight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity, height: 48,
          child: OutlinedButton(
            onPressed: () { Navigator.of(context).pop(); onManualCheckIn(); },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary, width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SvgPicture.asset('assets/icons/keyboard-icon.svg', width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
              const SizedBox(width: 8),
              Text('Manual Check In',
                  style: appText(size: 14, weight: FontWeight.w700, color: AppColors.primary)),
            ]),
          ),
        ),
      ]),
    );
  }
}
