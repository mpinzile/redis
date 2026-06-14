import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../../core/services/event_contributors_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart' show formatMoney, getActiveCurrency;
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../wallet/make_payment_screen.dart';
import 'contribution_history_screen.dart';
import '../payments/payment_receipt_screen.dart';

/// Per-event Contribution Details - opened when the user taps a card on the
/// My Contributions tab. Layout follows the supplied mockup: event header,
/// pledge summary card, circular pledge progress, recent contributions
/// list and Pay Balance + Download Receipt actions.
class ContributionDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> initialEvent;
  const ContributionDetailsScreen({super.key, required this.initialEvent});

  @override
  State<ContributionDetailsScreen> createState() => _ContributionDetailsScreenState();
}

// Status palette
const _kCompleteBg = Color(0xFFD6EFE0);
const _kCompleteFg = Color(0xFF0F7A4A);
const _kPendingBg  = Color(0xFFFFE2C7);
const _kPendingFg  = Color(0xFFB05A12);

class _ContributionDetailsScreenState extends State<ContributionDetailsScreen> {
  late Map<String, dynamic> _ev;
  bool _loadingPayments = true;
  List<Map<String, dynamic>> _payments = [];

  @override
  void initState() {
    super.initState();
    _ev = Map<String, dynamic>.from(widget.initialEvent);
    _refresh();
  }

  Future<void> _refresh() async {
    await Future.wait([_refreshSummary(), _loadPayments()]);
  }

  Future<void> _refreshSummary() async {
    final res = await EventContributorsService.getMyContributions();
    if (!mounted) return;
    if (res['success'] == true) {
      final list = (res['data']?['events'] as List?) ?? [];
      final match = list.cast<Map>().firstWhere(
        (e) => e['event_id']?.toString() == _ev['event_id']?.toString(),
        orElse: () => {},
      );
      if (match.isNotEmpty) setState(() => _ev = Map<String, dynamic>.from(match));
    }
  }

  Future<void> _loadPayments() async {
    setState(() => _loadingPayments = true);
    final eid = _ev['event_id']?.toString();
    if (eid == null || eid.isEmpty) {
      setState(() { _payments = []; _loadingPayments = false; });
      return;
    }
    // Unified endpoint - returns ALL payment rows (online gateway,
    // offline-claim and organiser-recorded) from event_contributions for
    // every event_contributor row that maps to me (by user id OR phone).
    final res = await EventContributorsService.getMyPaymentsForEvent(eid);
    if (!mounted) return;
    final list = (res['data']?['payments'] as List?) ?? [];
    setState(() {
      _payments = list.cast<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
      _loadingPayments = false;
    });
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try { return DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal()); }
    catch (_) { return iso.split('T').first; }
  }

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try { return DateFormat('h:mm a').format(DateTime.parse(iso).toLocal()); }
    catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final currency = _ev['currency']?.toString() ?? getActiveCurrency();
    final pledge = (_ev['pledge_amount'] as num?)?.toDouble() ?? 0;
    final paid = (_ev['total_paid'] as num?)?.toDouble() ?? 0;
    final pending = (_ev['pending_amount'] as num?)?.toDouble() ?? 0;
    final balance = (_ev['balance'] as num?)?.toDouble() ?? math.max(0, pledge - paid - pending);
    final pct = pledge > 0 ? (paid / pledge).clamp(0.0, 1.0) : 0.0;
    final isComplete = pledge > 0 && balance == 0 && pending == 0;
    final showPay = balance > 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const NuruSubPageAppBar(title: 'Contribution Details'),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _eventHeader(),
            const SizedBox(height: 18),
            Text('Pledge Summary',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            _summaryCard(currency, pledge, paid, balance, isComplete, pending),
            const SizedBox(height: 18),
            _progressCard(currency, paid, pledge, pct),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: Text('Recent Contributions',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
              ),
              if (_payments.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ContributionHistoryScreen(
                      eventId: _ev['event_id']?.toString() ?? '',
                      eventName: _ev['event_name']?.toString() ?? 'Event',
                      currency: currency,
                    ),
                  )),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('View Full History',
                        style: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary,
                        )),
                      const SizedBox(width: 4),
                      SvgPicture.asset('assets/icons/chevron-right-icon.svg',
                        width: 14, height: 14,
                        colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            _recentList(currency),
            const SizedBox(height: 22),
            if (showPay)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _openPay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SvgPicture.asset('assets/icons/card-icon.svg',
                      width: 18, height: 18,
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                    const SizedBox(width: 8),
                    Text('Pay Balance',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            if (_payments.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    String? verifyUrl;
                    try {
                      final eid = (_ev['event_id'] ?? '').toString();
                      if (eid.isNotEmpty) {
                        final res = await EventContributorsService.getAggregateVerifyToken(eid);
                        if (res['success'] == true && res['data'] is Map) {
                          verifyUrl = (res['data'] as Map)['verify_url']?.toString();
                        }
                      }
                    } catch (_) {}
                    if (!mounted) return;
                    final receipt = _buildAggregateReceipt(currency, pledge, paid, balance, pending);
                    if (verifyUrl != null && verifyUrl.isNotEmpty) {
                      receipt['verification_url'] = verifyUrl;
                    }
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PaymentReceiptScreen(payment: receipt),
                    ));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SvgPicture.asset('assets/icons/download-icon.svg',
                      width: 18, height: 18,
                      colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                    const SizedBox(width: 8),
                    Text('Download Receipt',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _eventHeader() {
    final cover = _ev['event_cover_image_url']?.toString();
    final name = _ev['event_name']?.toString() ?? 'Event';
    final dateStr = _fmtDate(_ev['event_start_date']?.toString());
    final timeStr = _ev['event_start_time']?.toString().isNotEmpty == true
        ? _ev['event_start_time'].toString()
        : _fmtTime(_ev['event_start_date']?.toString());
    final loc = _ev['event_location']?.toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 86, height: 100,
            color: AppColors.primary.withOpacity(0.10),
            child: cover != null && cover.isNotEmpty
                ? Image.network(cover, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _coverFallback())
                : _coverFallback(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.2,
              )),
            const SizedBox(height: 8),
            if (dateStr.isNotEmpty)
              _metaRow('assets/icons/calendar-icon.svg', dateStr),
            if (timeStr.isNotEmpty) ...[
              const SizedBox(height: 4),
              _metaRow('assets/icons/clock-icon.svg', timeStr),
            ],
            if (loc != null && loc.isNotEmpty) ...[
              const SizedBox(height: 4),
              _metaRow('assets/icons/location-icon.svg', loc),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _coverFallback() => Center(
    child: SvgPicture.asset('assets/icons/calendar-icon.svg',
      width: 30, height: 30,
      colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
  );

  Widget _metaRow(String iconAsset, String label) {
    return Row(children: [
      SvgPicture.asset(iconAsset, width: 14, height: 14,
        colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
      const SizedBox(width: 6),
      Flexible(child: Text(label,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary))),
    ]);
  }

  Widget _summaryCard(String currency, double pledge, double paid, double balance,
      bool isComplete, double pending) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        _summaryRow('assets/icons/wallet-icon.svg', 'Amount Pledged',
          formatMoney(pledge, currency: currency), AppColors.textPrimary),
        _divider(),
        _summaryRow('assets/icons/card-icon.svg', 'Amount Paid',
          formatMoney(paid, currency: currency), AppColors.primary),
        _divider(),
        _summaryRow('assets/icons/donation-icon.svg', 'Balance',
          formatMoney(balance, currency: currency), AppColors.textPrimary),
        _divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            _iconBox('assets/icons/info-icon.svg'),
            const SizedBox(width: 12),
            Expanded(child: Text('Status',
              style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textPrimary))),
            _statusPill(isComplete: isComplete, pending: pending > 0),
          ]),
        ),
      ]),
    );
  }

  Widget _iconBox(String asset) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(
      color: AppColors.primary.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: SvgPicture.asset(asset, width: 18, height: 18,
      colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
  );

  Widget _summaryRow(String asset, String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(children: [
        _iconBox(asset),
        const SizedBox(width: 12),
        Expanded(child: Text(label,
          style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textPrimary))),
        Text(value,
          style: GoogleFonts.inter(
            fontSize: 14, fontWeight: FontWeight.w800, color: valueColor,
          )),
      ]),
    );
  }

  Widget _divider() => Container(height: 1, color: AppColors.borderLight, margin: const EdgeInsets.symmetric(horizontal: 14));

  Widget _statusPill({required bool isComplete, required bool pending}) {
    final label = isComplete ? 'Complete' : (pending ? 'Pending' : 'Incomplete');
    final bg = isComplete ? _kCompleteBg : _kPendingBg;
    final fg = isComplete ? _kCompleteFg : _kPendingFg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _progressCard(String currency, double paid, double pledge, double pct) {
    final percent = (pct * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
          width: 88, height: 88,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 88, height: 88,
              child: CircularProgressIndicator(
                value: pct,
                strokeWidth: 8,
                backgroundColor: AppColors.primary.withOpacity(0.12),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            Text('$percent%',
              style: GoogleFonts.inter(
                fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary,
              )),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pledge Progress',
              style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary,
              )),
            const SizedBox(height: 6),
            Text(
              pledge > 0
                ? 'You have paid ${formatMoney(paid, currency: currency)} of your ${formatMoney(pledge, currency: currency)} pledge.'
                : 'No pledge has been recorded yet.',
              style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct, minHeight: 6,
                    backgroundColor: AppColors.primary.withOpacity(0.12),
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$percent%',
                style: GoogleFonts.inter(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.primary,
                )),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _recentList(String currency) {
    if (_loadingPayments) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
      );
    }
    if (_payments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Center(child: Text('No contributions paid yet.',
          style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textTertiary))),
      );
    }
    final recent = _payments.take(2).toList();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        for (int i = 0; i < recent.length; i++) ...[
          if (i > 0) _divider(),
          _paymentRow(recent[i], currency),
        ],
      ]),
    );
  }

  Widget _paymentRow(Map<String, dynamic> p, String currency) {
    // Backend returns { amount, payment_method, source_label,
    // confirmation_status, contributed_at, recorded_by_organiser, ... }
    final amount = (p['amount'] as num?)?.toDouble()
        ?? (p['gross_amount'] as num?)?.toDouble() ?? 0;
    final method = (p['payment_method'] ?? '').toString().toLowerCase();
    final label = (p['source_label']?.toString().isNotEmpty == true)
        ? p['source_label'].toString()
        : (method.isEmpty ? 'Payment' : _humanizeMethod(method));
    final ts = (p['contributed_at'] ?? p['confirmed_at'] ?? p['created_at'])?.toString();
    final dateStr = _fmtDate(ts);
    final status = (p['confirmation_status'] ?? 'confirmed').toString();
    final isPending = status == 'pending';
    final recordedByOrganiser = p['recorded_by_organiser'] == true;

    String iconAsset;
    if (method.contains('bank')) {
      iconAsset = 'assets/icons/wallet-icon.svg';
    } else if (method.contains('card')) {
      iconAsset = 'assets/icons/card-icon.svg';
    } else if (method.contains('wallet')) {
      iconAsset = 'assets/icons/wallet-icon.svg';
    } else if (method.contains('cash') || recordedByOrganiser) {
      iconAsset = 'assets/icons/wallet-icon.svg';
    } else {
      iconAsset = 'assets/icons/phone-icon.svg';
    }
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => PaymentReceiptScreen(payment: _enrichForReceipt(p, currency)),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          _iconBox(iconAsset),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                if (isPending) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kPendingBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Pending',
                      style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: _kPendingFg)),
                  ),
                ],
              ]),
              if (dateStr.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(dateStr,
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textTertiary)),
              ],
            ]),
          ),
          Text(formatMoney(amount, currency: currency),
            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(width: 6),
          SvgPicture.asset('assets/icons/chevron-right-icon.svg',
            width: 14, height: 14,
            colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
        ]),
      ),
    );
  }

  /// Map a single payment row from `/my-contributions/{id}/payments` into the
  /// shape PaymentReceiptScreen expects.
  Map<String, dynamic> _enrichForReceipt(Map<String, dynamic> p, String currency) {
    final amount = (p['amount'] as num?)?.toDouble()
        ?? (p['gross_amount'] as num?)?.toDouble() ?? 0;
    final status = (p['confirmation_status'] ?? p['status'] ?? 'paid').toString();
    return {
      ...p,
      'gross_amount': amount,
      'commission_amount': (p['commission_amount'] as num?)?.toDouble() ?? 0,
      'currency_code': p['currency_code']?.toString() ?? currency,
      'status': status == 'pending' ? 'pending' : 'paid',
      'transaction_code': (p['transaction_ref'] ?? p['transaction_code'] ?? p['id'] ?? '').toString(),
      'method_type': p['payment_method']?.toString() ?? '',
      'provider_name': p['provider_name']?.toString() ?? '',
      'description': 'Contribution to ${_ev['event_name'] ?? 'event'}',
      'event_id': _ev['event_id'],
      'event_name': _ev['event_name'],
      'event_cover_image': _ev['event_cover_image_url'],
      'completed_at': p['contributed_at'] ?? p['confirmed_at'] ?? p['created_at'],
    };
  }

  /// Build a synthetic aggregate "contribution receipt" map covering ALL
  /// payments the user has made towards this event. Shown when the user
  /// taps Download Receipt.
  Map<String, dynamic> _buildAggregateReceipt(String currency, double pledge,
      double paid, double balance, double pending) {
    final eid = (_ev['event_id'] ?? '').toString();
    final shortId = eid.length >= 6 ? eid.substring(0, 6).toUpperCase() : eid.toUpperCase();
    final ts = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    final desc = StringBuffer('Total contribution to ${_ev['event_name'] ?? 'event'}');
    if (pledge > 0) desc.write(' · Pledged ${formatMoney(pledge, currency: currency)}');
    if (balance > 0) desc.write(' · Balance ${formatMoney(balance, currency: currency)}');
    if (pending > 0) desc.write(' · Pending ${formatMoney(pending, currency: currency)}');
    return {
      'gross_amount': paid,
      'commission_amount': 0,
      'currency_code': currency,
      'status': balance > 0 ? 'pending' : 'paid',
      'transaction_code': 'CONT-$shortId-$ts',
      'method_type': _payments.length > 1 ? 'multiple sources' : (_payments.first['payment_method']?.toString() ?? ''),
      'provider_name': '',
      'description': desc.toString(),
      'event_id': _ev['event_id'],
      'event_name': _ev['event_name'],
      'event_cover_image': _ev['event_cover_image_url'],
      'completed_at': DateTime.now().toIso8601String(),
    };
  }

  String _humanizeMethod(String m) {
    final s = m.replaceAll('_', ' ').trim();
    if (s.isEmpty) return 'Payment';
    return s[0].toUpperCase() + s.substring(1);
  }

  void _openPay() {
    final balance = (_ev['balance'] as num?)?.toDouble() ?? 0;
    final eventId = _ev['event_id']?.toString();
    final eventName = _ev['event_name']?.toString() ?? 'Event contribution';
    final eventCover = _ev['event_cover_image_url']?.toString();
    if (eventId == null || eventId.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MakePaymentScreen(
        targetType: 'event_contribution',
        targetId: eventId,
        amount: balance > 0 ? balance : null,
        amountEditable: true,
        allowBank: false,
        title: 'Pay contribution',
        description: 'For $eventName',
        summaryImageUrl: eventCover,
        summaryMeta: eventName,
        showFee: true,
        onSuccess: (_) => _refresh(),
      ),
    ));
  }
}
