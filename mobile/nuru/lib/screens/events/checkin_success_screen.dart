import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';

/// Premium full-screen "Check In Successful" page shown after a guest or
/// ticket scan succeeds. Renders the unified scanner payload returned by
/// `POST /user-events/{event_id}/guests/checkin-qr`.
class CheckinSuccessScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onScanNext;

  const CheckinSuccessScreen({
    super.key,
    required this.data,
    required this.onScanNext,
  });

  DateTime? _parse(String? iso) {
    if (iso == null || iso.isEmpty) return null;
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
    return DateTime.tryParse(normalized)?.toLocal();
  }

  String _fmtDateTime(String? iso) {
    final dt = _parse(iso);
    if (dt == null) return (iso == null || iso.isEmpty) ? '-' : iso;
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m $ampm';
  }

  String _fmtClock(String? iso) {
    final dt = _parse(iso);
    if (dt == null) return '';
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final ev = (data['event'] as Map?) ?? {};
    final isTicket = data['kind'] == 'ticket';
    final rawName = (data['name'] ?? '').toString().trim();
    final hasName = data['has_name'] == true ||
        (rawName.isNotEmpty && rawName.toLowerCase() != 'guest checked in');
    final name = rawName.isEmpty ? 'Guest checked in' : rawName;
    final ticketClass = (data['ticket_class'] ?? (isTicket ? 'Ticket' : 'Guest Pass')).toString();
    final ticketId = (data['ticket_id'] ?? data['code'] ?? '').toString();
    final qty = (data['quantity'] is num) ? (data['quantity'] as num).toInt() : 1;
    final eventName = (ev['name'] ?? '').toString();
    final whenIso = (data['checked_in_at']?.toString().isNotEmpty == true)
        ? data['checked_in_at']?.toString()
        : data['scan_time']?.toString();
    final checkedInAt = _fmtDateTime(whenIso);
    final clockOnly = _fmtClock(whenIso);

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
        title: Text('Check In Successful', style: appText(size: 18, weight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _heroCard(name, hasName, clockOnly),
                  const SizedBox(height: 16),
                  _detailsCard([
                    _row('assets/icons/user-icon.svg', 'Guest Name', name),
                    _row(isTicket ? 'assets/icons/ticket-icon.svg' : 'assets/icons/users-icon.svg', 'Ticket Type', ticketClass),
                    _row('assets/icons/ticket-icon.svg', 'Ticket ID', ticketId.isEmpty ? '-' : ticketId),
                    if (qty > 1) _row('assets/icons/users-icon.svg', 'Number of Guests', '$qty'),
                    _row('assets/icons/calendar-icon.svg', 'Event', eventName.isEmpty ? '-' : eventName),
                    _row('assets/icons/clock-icon.svg', 'Checked In At', checkedInAt, last: true),
                  ]),
                  const SizedBox(height: 12),
                  _statusBanner(),
                ]),
              ),
            ),
            _bottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _heroCard(String name, bool hasName, String clockOnly) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.success.withOpacity(0.18), AppColors.success.withOpacity(0.04)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(children: [
        Container(
          width: 86, height: 86,
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: SvgPicture.asset('assets/icons/verified-icon.svg', width: 44, height: 44,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
          ),
        ),
        const SizedBox(height: 16),
        Text('Check in successful!',
            style: appText(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(hasName ? name : 'Guest checked in',
            textAlign: TextAlign.center,
            style: appText(size: 16, weight: FontWeight.w700, color: AppColors.success)),
        if (clockOnly.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Checked in at $clockOnly',
              style: appText(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary)),
        ],
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Guest Details', style: appText(size: 14, weight: FontWeight.w800)),
        const SizedBox(height: 10),
        ...rows,
      ]),
    );
  }

  Widget _row(String iconAsset, String label, String value, {bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: AppColors.borderLight.withOpacity(0.7))),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: AppColors.success.withOpacity(0.12), shape: BoxShape.circle),
          child: Center(
            child: SvgPicture.asset(iconAsset, width: 17, height: 17,
                colorFilter: const ColorFilter.mode(AppColors.success, BlendMode.srcIn)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: appText(size: 13, color: AppColors.textSecondary, weight: FontWeight.w500))),
        const SizedBox(width: 10),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              style: appText(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
      ]),
    );
  }

  Widget _statusBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withOpacity(0.22)),
      ),
      child: Row(children: [
        SvgPicture.asset('assets/icons/secure-shield-icon.svg', width: 22, height: 22,
            colorFilter: const ColorFilter.mode(AppColors.success, BlendMode.srcIn)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('All good to go', style: appText(size: 13, weight: FontWeight.w800)),
            Text('Enjoy the event!', style: appText(size: 12, color: AppColors.textTertiary)),
          ]),
        ),
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
            onPressed: () { Navigator.of(context).pop(); onScanNext(); },
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
              Text('Scan Next Guest', style: appText(size: 14, weight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity, height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary, width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SvgPicture.asset('assets/icons/user-icon.svg', width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
              const SizedBox(width: 8),
              Text('View Guest Details',
                  style: appText(size: 14, weight: FontWeight.w700, color: AppColors.primary)),
            ]),
          ),
        ),
      ]),
    );
  }
}
