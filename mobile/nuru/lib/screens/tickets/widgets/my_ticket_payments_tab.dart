import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../core/widgets/nuru_skeleton.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/received_payments_service.dart';

import '../../../core/utils/money_format.dart';
import '../../payments/payment_receipt_screen.dart';

/// My Ticket Payments - editorial redesign matching the
/// "Total Paid" mockup: search + date filter, summary banner,
/// horizontal event cards with status pill + amount + method,
/// and a secure-payments footer.
class MyTicketPaymentsTab extends StatefulWidget {
  /// Search query owned by the parent screen (single source of truth).
  final String search;
  const MyTicketPaymentsTab({super.key, this.search = ''});

  @override
  State<MyTicketPaymentsTab> createState() => _MyTicketPaymentsTabState();
}

class _MyTicketPaymentsTabState extends State<MyTicketPaymentsTab>
    with AutomaticKeepAliveClientMixin {
  List<dynamic> _payments = [];
  Map<String, dynamic>? _pagination;
  bool _loading = true;
  int _page = 1;
  String _rangeLabel = 'This Year';
  DateTimeRange? _range;
  String get _search => widget.search;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MyTicketPaymentsTab old) {
    super.didUpdateWidget(old);
    if (old.search != widget.search) {
      _page = 1;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ReceivedPaymentsService.myTickets(
      page: _page,
      limit: 20,
      search: _search.isNotEmpty ? _search : null,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        _payments = data is Map ? List.from(data['payments'] ?? []) : [];
        _pagination = data is Map && data['pagination'] is Map
            ? Map<String, dynamic>.from(data['pagination'])
            : null;
      }
    });
  }

  ({Color bg, Color fg, String label}) _statusBadge(String s) {
    switch (s) {
      case 'credited':
      case 'completed':
      case 'paid':
      case 'confirmed':
        return (bg: const Color(0xFFDCFCE7), fg: const Color(0xFF15803D),
            label: 'Completed');
      case 'processing':
        return (bg: const Color(0xFFFEF3C7), fg: const Color(0xFFB45309),
            label: 'Processing');
      case 'pending':
        return (bg: const Color(0xFFFEF3C7), fg: const Color(0xFFB45309),
            label: 'Pending');
      case 'failed':
      case 'rejected':
        return (bg: const Color(0xFFFEE2E2), fg: const Color(0xFFB91C1C),
            label: 'Failed');
      default:
        return (bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1D4ED8),
            label: s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : 'Unknown');
    }
  }

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _wdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  String _eventDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final am = d.hour < 12 ? 'AM' : 'PM';
    return '${_wdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}  •  $h:${d.minute.toString().padLeft(2, '0')} $am';
  }

  String _paidOn(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final am = d.hour < 12 ? 'AM' : 'PM';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}  •  $h:${d.minute.toString().padLeft(2, '0')} $am';
  }

  bool _inRange(DateTime? d) {
    if (_range == null || d == null) return true;
    return !d.isBefore(_range!.start) && !d.isAfter(_range!.end);
  }

  List<dynamic> get _filtered {
    if (_range == null) return _payments;
    return _payments.where((p) {
      final m = p is Map ? p : <String, dynamic>{};
      final iso = (m['completed_at'] ?? m['confirmed_at'] ?? m['initiated_at'])?.toString();
      return _inRange(DateTime.tryParse(iso ?? '')?.toLocal());
    }).toList();
  }

  num get _totalPaid {
    num t = 0;
    for (final p in _filtered) {
      final m = p is Map ? p : {};
      final s = m['status']?.toString();
      if (s == 'credited' || s == 'completed' || s == 'paid' || s == 'confirmed') {
        // Exclude commission/service fee - show what the beneficiary received.
        final v = m['net_amount'] ?? m['gross_amount'];
        if (v is num) t += v;
      }
    }
    return t;
  }

  // Summary uses the active user currency (set globally on login),
  // mirroring the rest of the app - never hard-coded.

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final presets = <({String label, DateTimeRange? range})>[
      (label: 'All time', range: null),
      (label: 'This Week', range: DateTimeRange(start: now.subtract(Duration(days: now.weekday - 1)), end: now)),
      (label: 'This Month', range: DateTimeRange(start: DateTime(now.year, now.month, 1), end: now)),
      (label: 'This Year', range: DateTimeRange(start: DateTime(now.year, 1, 1), end: now)),
      (label: 'Last 30 Days', range: DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now)),
    ];
    final res = await showModalBottomSheet<({String label, DateTimeRange? range})>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(children: [
                SvgPicture.asset('assets/icons/calendar-icon.svg',
                    width: 16, height: 16,
                    colorFilter: const ColorFilter.mode(
                        Color(0xFF111827), BlendMode.srcIn)),
                const SizedBox(width: 8),
                Text('Filter by date',
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ]),
            ),
            const Divider(height: 1),
            for (final p in presets)
              InkWell(
                onTap: () => Navigator.pop(ctx, p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(children: [
                    Expanded(
                      child: Text(p.label,
                          style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ),
                    if (_rangeLabel == p.label)
                      const Icon(Icons.check_rounded,
                          size: 18, color: AppColors.primary),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (res != null) {
      setState(() {
        _rangeLabel = res.label;
        _range = res.range;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return NuruRefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
        children: [
          _summaryBanner(),
          const SizedBox(height: 12),
          if (_loading)
            ...List.generate(3, (_) => _skeleton())
          else if (_filtered.isEmpty)
            _empty()
          else
            ..._filtered.map(_card),
          if (_pagination != null && (_pagination!['total_pages'] ?? 1) > 1)
            _pager(),
        ],
      ),
    );
  }

  // ── Search bar + Filter by Date ─────────────────────────────
  // ── Total Paid summary banner ───────────────────────────────
  Widget _summaryBanner() {
    final count = _filtered.length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCE9B6)),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: SvgPicture.asset('assets/icons/wallet-icon.svg',
                width: 22, height: 22,
                colorFilter: const ColorFilter.mode(
                    Color(0xFF111827), BlendMode.srcIn)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Paid',
                  style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 1),
              Text(formatMoney(_totalPaid),
                  style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.4)),
              Text('$count Payment${count == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        InkWell(
          onTap: _pickRange,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(children: [
              SvgPicture.asset('assets/icons/calendar-icon.svg',
                  width: 12, height: 12,
                  colorFilter: const ColorFilter.mode(
                      Color(0xFF111827), BlendMode.srcIn)),
              const SizedBox(width: 5),
              Text(_rangeLabel,
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w700)),
              const Icon(Icons.expand_more_rounded, size: 14),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Payment card (mockup parity, compact) ──────────────────
  Widget _card(dynamic p) {
    final m = p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
    final status = m['status']?.toString() ?? 'pending';
    final badge = _statusBadge(status);
    // Show the base price the buyer actually paid for the ticket - without
    // the platform service fee/commission added on top.
    final amount = (m['net_amount'] is num)
        ? (m['net_amount'] as num)
        : ((m['gross_amount'] is num) ? (m['gross_amount'] as num) : 0);
    // Always render using the active user currency so KE accounts never see
    // a stale 'TZS' that may have been stored on legacy payment rows.
    final currency = getActiveCurrency();
    final paidIso = m['completed_at'] ?? m['confirmed_at'] ?? m['initiated_at'];
    final eventName = m['event_name']?.toString() ?? '';
    final ticketClass = m['ticket_class_name']?.toString() ?? '';
    final cover = m['event_cover_image']?.toString() ?? '';
    final eventStart = m['event_start_date']?.toString();
    final location = m['event_location']?.toString() ?? '';
    final qty = (m['ticket_quantity'] is int) ? m['ticket_quantity'] as int : 1;
    final txCode = m['transaction_code']?.toString() ?? '';
    final paymentId = txCode.isNotEmpty
        ? 'NRU-${txCode.length > 10 ? txCode.substring(txCode.length - 10) : txCode}'
        : '';
    final title = eventName.isNotEmpty
        ? eventName
        : (m['description']?.toString() ?? 'Ticket payment');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEF2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentReceiptScreen(payment: m),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column: event meta
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _eventThumb(cover),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 5,
                                  runSpacing: 3,
                                  children: [
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 160),
                                      child: Text(title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary,
                                              height: 1.15,
                                              letterSpacing: -0.2)),
                                    ),
                                    if (ticketClass.isNotEmpty)
                                      _classChip(ticketClass),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _svgMetaRow('assets/icons/calendar-icon.svg',
                            _eventDate(eventStart)),
                        if (location.isNotEmpty)
                          _svgMetaRow('assets/icons/location-icon.svg', location),
                        _svgMetaRow('assets/icons/ticket-icon.svg',
                            '$qty Ticket${qty == 1 ? '' : 's'}'),
                        if (paymentId.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text('Payment ID: $paymentId',
                                style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(width: 1, color: const Color(0xFFF1F2F4)),
                  const SizedBox(width: 10),
                  // Right column: status (top-right) + amount + method + paid on
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: _statusPill(badge),
                        ),
                        const SizedBox(height: 8),
                        Text('Amount Paid',
                            style: GoogleFonts.inter(
                                fontSize: 9.5,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w600)),
                        Text(formatMoney(amount, currency: currency),
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3)),
                        const SizedBox(height: 5),
                        Text('Method',
                            style: GoogleFonts.inter(
                                fontSize: 9.5,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 1),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: _methodLine(m)),
                            const SizedBox(width: 4),
                            SvgPicture.asset(
                              'assets/icons/chevron-right-icon.svg',
                              width: 14, height: 14,
                              colorFilter: const ColorFilter.mode(
                                  Color(0xFF9CA3AF), BlendMode.srcIn),
                            ),
                          ],
                        ),
                        if (paidIso != null) ...[
                          const SizedBox(height: 5),
                          Text('Paid on',
                              style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w600)),
                          Text(_paidOn(paidIso.toString()),
                              style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _eventThumb(String url) {
    Widget fallback = Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: SvgPicture.asset('assets/icons/calendar-icon.svg',
            width: 16, height: 16,
            colorFilter: const ColorFilter.mode(
                AppColors.primary, BlendMode.srcIn)),
      ),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 38, height: 38, fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 38, height: 38,
          color: const Color(0xFFF3F4F6),
        ),
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _svgMetaRow(String asset, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(asset,
              width: 11, height: 11,
              colorFilter: const ColorFilter.mode(
                  Color(0xFF9CA3AF), BlendMode.srcIn)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }


  Widget _classChip(String name) {
    final upper = name.toUpperCase();
    final isVip = upper.contains('VIP');
    final bg = isVip ? const Color(0xFFEDE9FE) : const Color(0xFFFFEDD5);
    final fg = isVip ? const Color(0xFF6D28D9) : const Color(0xFFC2410C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(upper,
          style: GoogleFonts.inter(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: fg)),
    );
  }

  Widget _methodLine(Map<String, dynamic> m) {
    final method = (m['method_type']?.toString() ?? '').toLowerCase();
    final pr = (m['provider_name']?.toString() ?? '').trim();
    IconData icon = Icons.account_balance_wallet_outlined;
    Color iconColor = AppColors.textPrimary;
    String label;
    if (m['is_offline'] == true || method.contains('bank')) {
      icon = Icons.account_balance_rounded;
      iconColor = const Color(0xFF6B7280);
      label = pr.isNotEmpty ? pr : 'Bank Transfer';
    } else if (method.contains('mobile') || method.contains('momo')) {
      final p = pr.toLowerCase();
      if (p.contains('airtel')) {
        icon = Icons.circle;
        iconColor = const Color(0xFFEF4444);
      } else if (p.contains('mpesa') || p.contains('m-pesa') || p.contains('vodacom')) {
        icon = Icons.phone_android_rounded;
        iconColor = const Color(0xFF16A34A);
      } else if (p.contains('tigo') || p.contains('mixx') || p.contains('yas')) {
        icon = Icons.phone_android_rounded;
        iconColor = const Color(0xFF1D4ED8);
      } else {
        icon = Icons.phone_android_rounded;
      }
      label = pr.isNotEmpty ? pr : 'Mobile Money';
    } else if (method.contains('card')) {
      icon = Icons.credit_card_rounded;
      label = pr.isNotEmpty ? pr : 'Card';
    } else if (method.contains('wallet')) {
      icon = Icons.account_balance_wallet_rounded;
      iconColor = AppColors.primary;
      label = pr.isNotEmpty ? pr : 'Wallet';
    } else {
      label = pr.isNotEmpty ? pr : (method.isNotEmpty ? method : '-');
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: iconColor),
      const SizedBox(width: 4),
      Flexible(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ),
    ]);
  }

  Widget _statusPill(({Color bg, Color fg, String label}) b) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: b.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(b.label,
          style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: b.fg)),
    );
  }

  // Skeleton that mirrors the real payment card layout: thumb + meta
  // column on the left, vertical divider, amount/method column on the right.
  Widget _skeleton() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: NuruSkeletonGroup(
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEEEEF2)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          NuruSkeleton.box(width: 38, height: 38, radius: 8),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                NuruSkeleton.text(width: 140, height: 11),
                                const SizedBox(height: 6),
                                NuruSkeleton.text(width: 60, height: 9),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        NuruSkeleton.text(width: 170, height: 9),
                        const SizedBox(height: 6),
                        NuruSkeleton.text(width: 130, height: 9),
                        const SizedBox(height: 6),
                        NuruSkeleton.text(width: 90, height: 9),
                        const SizedBox(height: 8),
                        NuruSkeleton.box(width: 110, height: 16, radius: 5),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(width: 1, color: const Color(0xFFF1F2F4)),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: NuruSkeleton.box(width: 70, height: 18, radius: 10),
                        ),
                        const SizedBox(height: 10),
                        NuruSkeleton.text(width: 50, height: 9),
                        const SizedBox(height: 4),
                        NuruSkeleton.text(width: 90, height: 14),
                        const SizedBox(height: 8),
                        NuruSkeleton.text(width: 40, height: 9),
                        const SizedBox(height: 4),
                        NuruSkeleton.text(width: 80, height: 11),
                        const SizedBox(height: 8),
                        NuruSkeleton.text(width: 40, height: 9),
                        const SizedBox(height: 4),
                        NuruSkeleton.text(width: 100, height: 9),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _empty() => Container(
        padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDEDF2), width: 1.2),
        ),
        child: Column(children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_rounded,
                size: 30, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text('No ticket payments yet',
              style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Your purchase receipts will show up here automatically.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12.5, color: AppColors.textTertiary, height: 1.4)),
        ]),
      );

  Widget _pager() {
    final p = _pagination!;
    final hasPrev = p['has_previous'] == true;
    final hasNext = p['has_next'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          onPressed: hasPrev
              ? () { setState(() => _page--); _load(); }
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('Page ${p['page']} of ${p['total_pages']}',
            style: GoogleFonts.inter(
                fontSize: 12, color: AppColors.textSecondary)),
        IconButton(
          onPressed: hasNext
              ? () { setState(() => _page++); _load(); }
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
    );
  }
}
