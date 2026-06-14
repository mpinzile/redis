/// Public ticket verification + view for /ticket/:code - premium Nuru styling.
///
/// Endpoint: GET /api/v1/ticketing/verify/{ticket_code} (public, no auth).
/// States: loading, valid (with QR), used / checked-in, expired, invalid /
/// not-found, network error. Designed to be friendly for ticket holders and
/// professional for gate verifiers.
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import '../../core/services/api_base.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/date_formatters.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/nuru_logo.dart';
import '../events/event_public_view_screen.dart';

class TicketVerificationScreen extends StatefulWidget {
  final String code;
  const TicketVerificationScreen({super.key, required this.code});

  @override
  State<TicketVerificationScreen> createState() => _TicketVerificationScreenState();
}

class _TicketVerificationScreenState extends State<TicketVerificationScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    debugPrint('[TicketVerify] loading code=${widget.code}');
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ApiBase.get('/ticketing/verify/${widget.code}', auth: false);
    debugPrint('[TicketVerify] response success=${res['success']}');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = (res['message'] ?? 'This ticket could not be verified.').toString();
      }
    });
  }

  void _share() {
    final url = 'https://nuru.tz/ticket/${widget.code}';
    Share.share(url, subject: 'My Nuru ticket', sharePositionOrigin: sharePositionOrigin(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const AppIcon('arrow-left', size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Ticket', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const AppIcon('share-upload', size: 20, color: AppColors.textPrimary),
            onPressed: _share,
          ),
        ],
      ),
      body: SafeArea(child: _build()),
    );
  }

  Widget _build() {
    if (_loading) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          NuruLogo(size: 38),
          SizedBox(height: 18),
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary)),
          SizedBox(height: 14),
          Text('Verifying ticket…', style: TextStyle(color: AppColors.textSecondary)),
        ]),
      );
    }
    if (_error != null) {
      return _StatusFull(
        accent: AppColors.error,
        iconName: 'close-circle',
        title: 'Ticket not recognised',
        message: _error!,
        code: widget.code,
        onRetry: _load,
      );
    }

    final d = _data!;
    final status = (d['status'] ?? d['state'] ?? 'valid').toString().toLowerCase();
    final eventName = (d['event_name'] ?? d['event']?['name'] ?? 'Event').toString();
    final ticketType = (d['ticket_type'] ?? d['class_name'] ?? 'Standard').toString();
    final holder = (d['holder_name'] ?? d['attendee_name'] ?? '').toString();
    final eventId = (d['event_id'] ?? d['event']?['id'] ?? '').toString();
    final eventDateRaw = (d['event_date'] ?? d['event']?['event_date'] ?? '').toString();
    final venue = (d['venue'] ?? d['event']?['location'] ?? '').toString();
    final qrPayload = (d['qr_payload'] ?? d['qr_code'] ?? widget.code).toString();

    final used = d['checked_in'] == true || status == 'used' || status == 'checked_in';
    final expired = status == 'expired';
    final valid = !used && !expired;

    final accent = used ? AppColors.warning : (expired ? AppColors.error : AppColors.success);
    final iconName = used
        ? 'double-check'
        : expired
            ? 'clock'
            : 'verified';
    final title = used ? 'Already checked in' : (expired ? 'Ticket expired' : 'Valid ticket');
    final subtitle = used
        ? 'This ticket has already been scanned at the gate.'
        : expired
            ? 'The event has ended for this ticket.'
            : 'Show this screen at the entrance for check-in.';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        _StatusBanner(accent: accent, iconName: iconName, title: title, message: subtitle),
        const SizedBox(height: 20),
        if (valid) _QrCard(payload: qrPayload, code: widget.code),
        if (valid) const SizedBox(height: 18),
        _DetailCard(
          rows: [
            _Row(label: 'Event', value: eventName, iconName: 'event-calendar-check'),
            if (eventDateRaw.isNotEmpty) _Row(label: 'Date', value: formatDateFull(eventDateRaw), iconName: 'calendar'),
            if (venue.isNotEmpty) _Row(label: 'Venue', value: venue, iconName: 'location'),
            _Row(label: 'Ticket type', value: ticketType, iconName: 'card'),
            if (holder.isNotEmpty) _Row(label: 'Holder', value: holder, iconName: 'user'),
            _Row(label: 'Status', value: status.toUpperCase(), iconName: 'info', valueColor: accent),
          ],
        ),
        const SizedBox(height: 16),
        if (eventId.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EventPublicViewScreen(eventId: eventId)),
            ),
            icon: const AppIcon('link', size: 16, color: AppColors.textPrimary),
            label: const Text('Open event page'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppColors.border),
              foregroundColor: AppColors.textPrimary,
            ),
          ),
        const SizedBox(height: 24),
        Center(
          child: Text('Need help? Contact Nuru support',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary.withOpacity(0.9))),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Color accent;
  final String iconName;
  final String title;
  final String message;
  const _StatusBanner({required this.accent, required this.iconName, required this.title, required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(14)),
          child: AppIcon(iconName, size: 22, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: accent)),
            const SizedBox(height: 4),
            Text(message, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

class _QrCard extends StatelessWidget {
  final String payload;
  final String code;
  const _QrCard({required this.payload, required this.code});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: QrImageView(
            data: payload,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.textPrimary),
            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 14),
        SelectableText(
          code,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, letterSpacing: 1.4, fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ]),
    );
  }
}

class _Row {
  final String label;
  final String value;
  final String iconName;
  final Color? valueColor;
  const _Row({required this.label, required this.value, required this.iconName, this.valueColor});
}

class _DetailCard extends StatelessWidget {
  final List<_Row> rows;
  const _DetailCard({required this.rows});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        for (int i = 0; i < rows.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppIcon(rows[i].iconName, size: 16, color: AppColors.primaryDark),
              const SizedBox(width: 12),
              SizedBox(
                width: 88,
                child: Text(rows[i].label, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
              ),
              Expanded(
                child: Text(
                  rows[i].value,
                  style: TextStyle(fontSize: 14, color: rows[i].valueColor ?? AppColors.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          if (i < rows.length - 1) const Divider(height: 1, color: AppColors.borderLight, indent: 16, endIndent: 16),
        ],
      ]),
    );
  }
}

class _StatusFull extends StatelessWidget {
  final Color accent;
  final String iconName;
  final String title;
  final String message;
  final String code;
  final VoidCallback onRetry;
  const _StatusFull({
    required this.accent,
    required this.iconName,
    required this.title,
    required this.message,
    required this.code,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80,
          height: 80,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(26)),
          child: AppIcon(iconName, size: 34, color: accent),
        ),
        const SizedBox(height: 20),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: 8),
        Text('Code: $code', style: const TextStyle(fontSize: 12, color: AppColors.textTertiary, letterSpacing: 1.2)),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: onRetry,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14)),
          child: const Text('Try again'),
        ),
      ]),
    );
  }
}
