import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/offline_payments_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/amount_input.dart';

const _methods = [
  {'value': 'cash', 'label': 'Cash', 'icon': Icons.payments_rounded},
  {'value': 'mobile_money', 'label': 'Mobile money', 'icon': Icons.phone_android_rounded},
  {'value': 'bank', 'label': 'Bank transfer', 'icon': Icons.account_balance_rounded},
  {'value': 'other', 'label': 'Other', 'icon': Icons.more_horiz_rounded},
];

class LogOfflinePaymentSheet extends StatefulWidget {
  final String eventId;
  final String eventServiceId;
  final String vendorName;
  final String serviceTitle;
  final num? agreedPrice;
  final VoidCallback? onLogged;

  const LogOfflinePaymentSheet({
    super.key,
    required this.eventId,
    required this.eventServiceId,
    required this.vendorName,
    required this.serviceTitle,
    this.agreedPrice,
    this.onLogged,
  });

  @override
  State<LogOfflinePaymentSheet> createState() => _LogOfflinePaymentSheetState();
}

class _LogOfflinePaymentSheetState extends State<LogOfflinePaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _method = 'cash';
  bool _submitting = false;
  List<dynamic> _history = [];
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _historyLoading = true);
    final res = await OfflinePaymentsService.listForEvent(widget.eventId);
    if (!mounted) return;
    setState(() {
      _historyLoading = false;
      if (res['success'] == true) {
        final items = (res['data']?['items'] ?? []) as List;
        _history = items.where((p) => p['event_service_id'] == widget.eventServiceId).toList();
      }
    });
  }

  Future<void> _submit() async {
    final amt = parseAmount(_amountCtrl.text);
    if (amt == null || amt <= 0) {
      AppSnackbar.error(context, 'Enter a valid amount');
      return;
    }
    setState(() => _submitting = true);
    final res = await OfflinePaymentsService.log(widget.eventId, widget.eventServiceId, {
      'amount': amt,
      'method': _method,
      if (_refCtrl.text.trim().isNotEmpty) 'reference': _refCtrl.text.trim(),
      if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res['success'] == true) {
      AppSnackbar.success(context, 'OTP sent to vendor');
      _amountCtrl.clear(); _refCtrl.clear(); _noteCtrl.clear();
      widget.onLogged?.call();
      _loadHistory();
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Failed to log payment');
    }
  }

  num get _confirmedTotal => _history
      .where((p) => p['status'] == 'confirmed')
      .fold<num>(0, (sum, p) => sum + (num.tryParse(p['amount'].toString()) ?? 0));

  String _money(num v) => '${getActiveCurrency()} ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}';

  @override
  Widget build(BuildContext context) {
    final agreed = widget.agreedPrice;
    final remaining = agreed != null ? (agreed - _confirmedTotal).clamp(0, agreed) : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log offline payment', style: appText(size: 18, weight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Recording a payment to ${widget.vendorName} for ${widget.serviceTitle} made outside Nuru. They will get an SMS code to confirm.',
              style: appText(size: 12, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 14),
            if (agreed != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  _stat('Agreed', _money(agreed)),
                  _stat('Paid', _money(_confirmedTotal), color: const Color(0xFF16A34A)),
                  if (remaining != null) _stat('Remaining', _money(remaining)),
                ]),
              ),
            const SizedBox(height: 14),
            _label('Amount'),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: amountFormatters,
              decoration: _decoration('0'),
            ),
            const SizedBox(height: 12),
            _label('Method'),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _methods.map((m) {
                final active = m['value'] == _method;
                return GestureDetector(
                  onTap: () => setState(() => _method = m['value'] as String),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primarySoft : Colors.white,
                      border: Border.all(color: active ? AppColors.primary : const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(m['icon'] as IconData, size: 14, color: active ? AppColors.primary : AppColors.textTertiary),
                      const SizedBox(width: 6),
                      Text(m['label'] as String, style: appText(size: 12, weight: FontWeight.w600, color: active ? AppColors.primary : AppColors.textSecondary)),
                    ]),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _label('Reference (optional)'),
            TextField(controller: _refCtrl, decoration: _decoration('Txn ID, mobile money ref, etc.')),
            const SizedBox(height: 12),
            _label('Note (optional)'),
            TextField(controller: _noteCtrl, maxLines: 2, decoration: _decoration('Anything the vendor should know')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Send OTP & log payment', style: appText(size: 14, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 18),
            if (_history.isNotEmpty) ...[
              Text('Recent', style: appText(size: 12, weight: FontWeight.w800, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              ..._history.take(5).map((p) => _historyTile(p as Map<String, dynamic>)),
            ] else if (_historyLoading) ...[
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> p) {
    final status = (p['status'] ?? 'pending').toString();
    final styles = {
      'pending':   [const Color(0xFFFEF3C7), const Color(0xFFCA8A04), 'Pending'],
      'confirmed': [const Color(0xFFDCFCE7), const Color(0xFF16A34A), 'Confirmed'],
      'cancelled': [const Color(0xFFF3F4F6), const Color(0xFF6B7280), 'Cancelled'],
      'expired':   [const Color(0xFFF3F4F6), const Color(0xFF6B7280), 'Expired'],
    };
    final s = styles[status] ?? styles['pending']!;
    final amt = num.tryParse(p['amount'].toString()) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_money(amt), style: appText(size: 13, weight: FontWeight.w700)),
          Text('${(p['method'] ?? 'offline').toString().replaceAll('_', ' ')}${p['reference'] != null ? ' · ${p['reference']}' : ''}',
              style: appText(size: 11, color: AppColors.textTertiary)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: s[0] as Color, borderRadius: BorderRadius.circular(8)),
          child: Text(s[2] as String, style: appText(size: 10, weight: FontWeight.w700, color: s[1] as Color)),
        ),
        if (status == 'pending') ...[
          const SizedBox(width: 6),
          IconButton(icon: const Icon(Icons.refresh_rounded, size: 18), onPressed: () async {
            final r = await OfflinePaymentsService.resend(p['id'].toString());
            if (mounted) AppSnackbar.success(context, r['success'] == true ? 'OTP resent' : (r['message']?.toString() ?? 'Failed'));
            _loadHistory();
          }),
          IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.error), onPressed: () async {
            final r = await OfflinePaymentsService.cancel(p['id'].toString());
            if (mounted) AppSnackbar.success(context, r['success'] == true ? 'Cancelled' : (r['message']?.toString() ?? 'Failed'));
            _loadHistory();
          }),
        ],
      ]),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: appText(size: 10, color: AppColors.textTertiary)),
        const SizedBox(height: 2),
        Text(value, style: appText(size: 13, weight: FontWeight.w800, color: color ?? AppColors.textPrimary)),
      ]),
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: appText(size: 11, weight: FontWeight.w700, color: AppColors.textSecondary)));
  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: appText(size: 13, color: AppColors.textHint),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}
