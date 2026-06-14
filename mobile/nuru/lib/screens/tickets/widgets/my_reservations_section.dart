// MyReservationsSection - airline-style ticket holds shown at the top of the
// My Tickets screen. Mirrors the web `MyReservations` component:
//   - Live countdown to `reserved_until`
//   - "Pay now" converts reservation → pending order → opens MakePaymentScreen
//   - "Cancel" deletes the reservation
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/ticketing_service.dart';
import '../../../core/utils/money_format.dart' show getActiveCurrency;
import '../../../core/widgets/app_snackbar.dart';
import '../../wallet/make_payment_screen.dart';

class MyReservationsSection extends StatefulWidget {
  final VoidCallback? onChanged;
  const MyReservationsSection({super.key, this.onChanged});

  @override
  State<MyReservationsSection> createState() => _MyReservationsSectionState();
}

class _MyReservationsSectionState extends State<MyReservationsSection> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  Timer? _tick;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Auto-prune expired rows.
      final now = DateTime.now();
      final next = _items.where((r) {
        final until = DateTime.tryParse(r['reserved_until']?.toString() ?? '');
        return until == null || until.isAfter(now);
      }).toList();
      if (next.length != _items.length) {
        setState(() => _items = next);
      } else {
        setState(() {}); // refresh countdown labels
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await TicketingService.getMyReservations();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        final list = data is Map ? (data['reservations'] ?? []) : (data is List ? data : []);
        _items = (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    });
  }

  String _fmtRemaining(int seconds) {
    if (seconds <= 0) return 'Expired';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, "0")}s';
    return '${s}s';
  }

  String _formatAmount(dynamic v) {
    if (v == null) return '0';
    final n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return n.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  Future<void> _payNow(Map<String, dynamic> r) async {
    setState(() => _busyId = r['id']?.toString());
    final res = await TicketingService.convertReservation(r['id']?.toString() ?? '');
    if (!mounted) return;
    setState(() => _busyId = null);
    if (res['success'] != true) {
      final raw = res['message']?.toString() ?? '';
      final isClosed = raw.toLowerCase().contains('no longer') ||
          raw.toLowerCase().contains('reservation') ||
          raw.toLowerCase().contains('deadline') ||
          raw.toLowerCase().contains('closed');
      if (isClosed) {
        AppSnackbar.show(
          context,
          type: AppSnackbarType.warning,
          title: 'Reservations closed',
          message:
              'This event is no longer accepting ticket reservations. Please pay directly to continue.',
          actionLabel: 'Pay now',
          onAction: () => _payDirectly(r),
        );
      } else {
        AppSnackbar.error(context, raw.isEmpty ? 'Could not start payment' : raw);
      }
      _load();
      return;
    }
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data']) : <String, dynamic>{};
    final pendingTicketId = (data['ticket_id'] ?? r['id'])?.toString() ?? '';
    final event = r['event'] is Map ? Map<String, dynamic>.from(r['event']) : <String, dynamic>{};
    final amount = (r['total_amount'] is num)
        ? r['total_amount'] as num
        : (num.tryParse(r['total_amount']?.toString() ?? '0') ?? 0);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MakePaymentScreen(
          targetType: 'event_ticket',
          targetId: pendingTicketId,
          amount: amount.toDouble(),
          allowBank: false,
          title: 'Pay for ${r['ticket_class'] ?? 'ticket'} × ${r['quantity'] ?? 1}',
          description: 'Reservation ${r['ticket_code'] ?? ''}',
          summaryImageUrl: event['cover_image']?.toString(),
          summarySubtitle: '${r['quantity'] ?? 1} ticket(s)',
          summaryMeta: [event['start_date'], event['start_time']]
              .where((s) => s != null && s.toString().trim().isNotEmpty)
              .join(' • '),
          showFee: true,
          onSuccess: (_) {
            if (!mounted) return;
            setState(() => _items.removeWhere((x) => x['id'] == r['id']));
            widget.onChanged?.call();
            AppSnackbar.show(
              context,
              type: AppSnackbarType.success,
              title: 'Payment confirmed',
              message: 'Your ticket has been issued.',
            );
          },
        ),
      ),
    );
  }

  /// Open the event so the user can buy tickets directly when reservation
  /// holds are no longer accepted.
  void _payDirectly(Map<String, dynamic> r) {
    final event = r['event'] is Map ? Map<String, dynamic>.from(r['event']) : <String, dynamic>{};
    final eventId = event['id']?.toString();
    if (eventId == null || eventId.isEmpty) return;
    Navigator.pushNamed(context, '/event/$eventId');
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    setState(() => _busyId = r['id']?.toString());
    final res = await TicketingService.cancelReservation(r['id']?.toString() ?? '');
    if (!mounted) return;
    setState(() => _busyId = null);
    if (res['success'] == true) {
      setState(() => _items.removeWhere((x) => x['id'] == r['id']));
      widget.onChanged?.call();
      AppSnackbar.success(context, 'Reservation cancelled');
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not cancel');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RESERVATIONS AWAITING PAYMENT',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          ..._items.map(_card),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final event = r['event'] is Map ? r['event'] as Map : const {};
    final eventName = (event['name'] ?? event['title'] ?? 'Event').toString();
    final location = event['location']?.toString() ?? '';
    final ticketClass = r['ticket_class']?.toString() ?? '';
    final qty = r['quantity'] ?? 1;
    final code = r['ticket_code']?.toString() ?? '';
    final currency = (r['currency']?.toString().isNotEmpty == true)
        ? r['currency'].toString()
        : getActiveCurrency();
    final total = _formatAmount(r['total_amount']);
    final until = DateTime.tryParse(r['reserved_until']?.toString() ?? '');
    final seconds = until == null
        ? 0
        : until.difference(DateTime.now()).inSeconds;
    final urgent = seconds > 0 && seconds < 30 * 60;
    final busy = _busyId == r['id']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: urgent ? const Color(0xFFFCD34D) : const Color(0xFFEDEDF2),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/ticket-icon.svg',
                    width: 18, height: 18,
                    colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eventName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 10, runSpacing: 2,
                      children: [
                        if (ticketClass.isNotEmpty)
                          Text('$ticketClass × $qty',
                              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
                        Text('$currency $total',
                            style: GoogleFonts.inter(
                                fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        if (location.isNotEmpty)
                          Text(location,
                              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _badge(
                icon: Icons.schedule_rounded,
                label: 'Pay within ${_fmtRemaining(seconds)}',
                color: urgent ? const Color(0xFFB45309) : AppColors.textTertiary,
                bg: urgent ? const Color(0xFFFEF3C7) : const Color(0xFFF3F4F6),
              ),
              const SizedBox(width: 6),
              if (code.isNotEmpty)
                _badge(
                  label: code,
                  color: AppColors.textSecondary,
                  bg: const Color(0xFFF3F4F6),
                  mono: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: (busy || seconds <= 0) ? null : () => _payNow(r),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: (seconds <= 0)
                        ? const Color(0xFFE5E7EB)
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: busy
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Pay now',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: busy ? null : () => _cancel(r),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Center(
                  child: Text('Cancel',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _badge({
    IconData? icon,
    required String label,
    required Color color,
    required Color bg,
    bool mono = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: mono ? 0.4 : 0)),
      ]),
    );
  }
}
