import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/services/event_contributors_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart' show formatMoney;
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../payments/payment_receipt_screen.dart';

/// Full contribution payment history for a single event (current user only).
class ContributionHistoryScreen extends StatefulWidget {
  final String eventId;
  final String eventName;
  final String currency;
  const ContributionHistoryScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.currency,
  });

  @override
  State<ContributionHistoryScreen> createState() => _ContributionHistoryScreenState();
}

class _ContributionHistoryScreenState extends State<ContributionHistoryScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _payments = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await EventContributorsService.getMyPaymentsForEvent(widget.eventId);
    if (!mounted) return;
    final list = ((res['data']?['payments'] as List?) ?? [])
        .cast<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    setState(() { _payments = list; _loading = false; });
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try { return DateFormat('d MMM yyyy · h:mm a').format(DateTime.parse(iso).toLocal()); }
    catch (_) { return iso; }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'completed': return const Color(0xFF0F7A4A);
      case 'confirmed': return const Color(0xFF0F7A4A);
      case 'pending':   return const Color(0xFFB07A12);
      case 'failed':    return AppColors.error;
      default:          return AppColors.blue;
    }
  }

  Color _statusBg(String s) {
    switch (s) {
      case 'completed':
      case 'confirmed': return const Color(0xFFD6EFE0);
      case 'pending':   return const Color(0xFFFFE9B0);
      case 'failed':    return AppColors.error.withOpacity(0.12);
      default:          return AppColors.blue.withOpacity(0.12);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _payments.fold<double>(
      0, (s, p) => s + ((p['amount'] as num?)?.toDouble()
          ?? (p['gross_amount'] as num?)?.toDouble() ?? 0));
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const NuruSubPageAppBar(title: 'Contribution History'),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.eventName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('Total Paid',
                      style: GoogleFonts.inter(
                        fontSize: 11.5, color: AppColors.textTertiary)),
                    const SizedBox(height: 2),
                    Text(formatMoney(total, currency: widget.currency),
                      style: GoogleFonts.inter(
                        fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: SvgPicture.asset('assets/icons/donation-icon.svg',
                      width: 20, height: 20,
                      colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                  ),
                  const SizedBox(height: 6),
                  Text('${_payments.length} payments',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            if (_loading)
              NuruSkeletonGroup(
                child: Column(children: List.generate(5, (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Row(children: [
                      NuruSkeleton.box(width: 40, height: 40, radius: 10),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        NuruSkeleton.text(width: 140, height: 12),
                        const SizedBox(height: 8),
                        NuruSkeleton.text(width: 100, height: 10),
                      ])),
                      const SizedBox(width: 12),
                      NuruSkeleton.text(width: 70, height: 12),
                    ]),
                  ),
                ))),
              )
            else if (_payments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(children: [
                  SvgPicture.asset('assets/icons/donation-icon.svg',
                    width: 44, height: 44,
                    colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
                  const SizedBox(height: 10),
                  Text('No payments yet',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ]),
              )
            else
              ..._payments.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _row(p),
              )),
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> p) {
    final status = (p['confirmation_status'] ?? p['status'] ?? 'confirmed').toString();
    final amount = (p['amount'] as num?)?.toDouble()
        ?? (p['gross_amount'] as num?)?.toDouble() ?? 0;
    final method = (p['payment_method'] ?? p['method_type'] ?? p['provider_name'] ?? 'Payment').toString();
    final label = (p['source_label']?.toString().isNotEmpty == true)
        ? p['source_label'].toString() : _humanize(method);
    final ts = (p['contributed_at'] ?? p['confirmed_at'] ?? p['created_at'])?.toString();
    final code = (p['transaction_ref'] ?? p['transaction_code'] ?? '').toString();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => PaymentReceiptScreen(payment: {
            ...p,
            'gross_amount': amount,
            'currency_code': p['currency_code']?.toString() ?? widget.currency,
            'status': (status == 'pending') ? 'pending' : 'paid',
            'transaction_code': code,
            'method_type': method,
            'description': 'Contribution to ${widget.eventName}',
            'event_name': widget.eventName,
            'completed_at': ts,
          }),
        )),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(_methodIcon(method),
                  width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _statusBg(status), borderRadius: BorderRadius.circular(999)),
                      child: Text(status,
                        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: _statusColor(status))),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  if (code.isNotEmpty)
                    Text(code, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textTertiary)),
                  if (ts != null) Text(_fmtDate(ts),
                    style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textHint)),
                ]),
              ),
              const SizedBox(width: 8),
              Text(formatMoney(amount, currency: widget.currency),
                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(width: 6),
              SvgPicture.asset('assets/icons/chevron-right-icon.svg',
                width: 14, height: 14,
                colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
            ]),
          ),
        ),
      ),
    );
  }

  String _humanize(String m) {
    final s = m.replaceAll('_', ' ').trim();
    if (s.isEmpty) return 'Payment';
    return s[0].toUpperCase() + s.substring(1);
  }

  String _methodIcon(String method) {
    final m = method.toLowerCase();
    if (m.contains('bank')) return 'assets/icons/wallet-icon.svg';
    if (m.contains('card')) return 'assets/icons/card-icon.svg';
    if (m.contains('wallet')) return 'assets/icons/wallet-icon.svg';
    if (m.contains('mobile') || m.contains('mpesa') || m.contains('m-pesa') ||
        m.contains('airtel') || m.contains('tigo') || m.contains('halopesa')) {
      return 'assets/icons/phone-icon.svg';
    }
    return 'assets/icons/money-icon.svg';
  }
}
