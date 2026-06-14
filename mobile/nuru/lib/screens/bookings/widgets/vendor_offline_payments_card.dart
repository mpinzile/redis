import 'package:flutter/material.dart';
import '../../../core/services/offline_payments_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/app_snackbar.dart';

class VendorOfflinePaymentsCard extends StatefulWidget {
  final String? eventId;
  const VendorOfflinePaymentsCard({super.key, this.eventId});

  @override
  State<VendorOfflinePaymentsCard> createState() => _VendorOfflinePaymentsCardState();
}

class _VendorOfflinePaymentsCardState extends State<VendorOfflinePaymentsCard> {
  bool _loading = true;
  List<dynamic> _items = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await OfflinePaymentsService.listMine();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        var list = (res['data']?['items'] ?? []) as List;
        if (widget.eventId != null) {
          list = list.where((p) => p['event_id'] == widget.eventId).toList();
        }
        _items = list;
      }
    });
  }

  String _money(num v) => '${getActiveCurrency()} ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}';

  Future<void> _confirm(Map<String, dynamic> p) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Confirm receipt', style: appText(size: 16, weight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Enter the SMS code to confirm you received ${_money(num.tryParse(p['amount'].toString()) ?? 0)} for ${p['service_title']}.',
              style: appText(size: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: appText(size: 18, weight: FontWeight.w800, letterSpacing: 6),
            decoration: InputDecoration(
              hintText: '000000',
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () async {
              final r = await OfflinePaymentsService.confirm(p['id'].toString(), ctrl.text.trim());
              if (!mounted) return;
              Navigator.pop(ctx);
              if (r['success'] == true) {
                AppSnackbar.success(context, 'Payment confirmed');
                _load();
              } else {
                AppSnackbar.error(context, r['message']?.toString() ?? 'Could not confirm');
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();
    final pending = _items.where((p) => p['status'] == 'pending').toList();
    final confirmed = _items.where((p) => p['status'] == 'confirmed').toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Offline payments', style: appText(size: 14, weight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Payments organisers logged outside Nuru. These do not appear in your wallet.',
            style: appText(size: 11, color: AppColors.textTertiary)),
        const SizedBox(height: 10),
        ...pending.map((p) => _row(p as Map<String, dynamic>, true)),
        ...confirmed.map((p) => _row(p as Map<String, dynamic>, false)),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> p, bool isPending) {
    final amt = num.tryParse(p['amount'].toString()) ?? 0;
    final bg = isPending ? const Color(0xFFFFFBEB) : Colors.white;
    final pillBg = isPending ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7);
    final pillFg = isPending ? const Color(0xFFCA8A04) : const Color(0xFF16A34A);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isPending ? const Color(0xFFFDE68A) : const Color(0xFFE5E7EB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_money(amt), style: appText(size: 14, weight: FontWeight.w800)),
            Text('${p['service_title']} · ${p['recorded_by_name'] ?? 'Organiser'}',
                style: appText(size: 11, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (!isPending) Text('Paid offline · not in wallet', style: appText(size: 10, color: AppColors.textTertiary)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(8)),
            child: Text(isPending ? 'Pending' : 'Confirmed', style: appText(size: 10, weight: FontWeight.w800, color: pillFg)),
          ),
        ]),
        if (isPending) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity, height: 38,
            child: ElevatedButton(
              onPressed: () => _confirm(p),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text('Enter OTP & confirm', style: appText(size: 12, weight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ]),
    );
  }
}
