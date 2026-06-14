import 'package:nuru/core/utils/money_format.dart' show getActiveCurrency;
import 'package:flutter/material.dart';
import '../core/services/received_payments_service.dart';
import '../core/services/offline_payments_service.dart';
import '../core/widgets/nuru_skeleton.dart';

/// ReceivedPaymentsPanel - drop-in widget that shows a paginated list of
/// payments received for an event (contributions/tickets) or a service.
/// Mirrors the web `ReceivedPaymentsPanel`. Wallet balance is **not**
/// affected by these payments - they live here only.
enum ReceivedPaymentsSource { eventContributions, eventTickets, service }

class ReceivedPaymentsPanel extends StatefulWidget {
  final ReceivedPaymentsSource source;
  final String targetId;
  final String? title;

  const ReceivedPaymentsPanel({
    super.key,
    required this.source,
    required this.targetId,
    this.title,
  });

  @override
  State<ReceivedPaymentsPanel> createState() => _ReceivedPaymentsPanelState();
}

class _ReceivedPaymentsPanelState extends State<ReceivedPaymentsPanel> {
  int _page = 1;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _offlineItems = [];
  Map<String, dynamic>? _pagination;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _fetch() {
    switch (widget.source) {
      case ReceivedPaymentsSource.eventContributions:
        return ReceivedPaymentsService.eventContributions(
          widget.targetId, page: _page,
        );
      case ReceivedPaymentsSource.eventTickets:
        return ReceivedPaymentsService.eventTickets(
          widget.targetId, page: _page,
        );
      case ReceivedPaymentsSource.service:
        return ReceivedPaymentsService.service(
          widget.targetId, page: _page,
        );
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _fetch();
      if (!mounted) return;
      if (res['success'] == true) {
        final data = res['data'] as Map<String, dynamic>? ?? {};
        setState(() {
          _items = ((data['payments'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
          _pagination = data['pagination'] as Map<String, dynamic>?;
          _loading = false;
        });
        if (widget.source == ReceivedPaymentsSource.service) {
          final offline = await OfflinePaymentsService.listMine();
          if (!mounted) return;
          if (offline['success'] == true) {
            final rows = ((offline['data']?['items'] as List?) ?? const [])
                .cast<Map<String, dynamic>>()
                .where((p) => p['provider_user_service_id']?.toString() == widget.targetId)
                .toList();
            setState(() => _offlineItems = rows);
          }
        } else if (mounted) {
          setState(() => _offlineItems = []);
        }
      } else {
        setState(() { _loading = false; _error = res['message']?.toString() ?? 'Failed'; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  String _defaultTitle() {
    switch (widget.source) {
      case ReceivedPaymentsSource.eventContributions:
        return 'Contribution payments';
      case ReceivedPaymentsSource.eventTickets:
        return 'Ticket payments';
      case ReceivedPaymentsSource.service:
        return 'Service payments';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.title ?? _defaultTitle();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'All payments received via Nuru.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
                if (_pagination != null)
                  Text('${_pagination!['total_items'] ?? 0} total',
                      style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: NuruSkeletonList(itemCount: 4, showTrailing: true, padding: EdgeInsets.zero),
              )
            else if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              )
            else if (_items.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('No payments yet.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor)),
              )
            else
              Column(
                children: [
                  for (final p in _items) _PaymentTile(payment: p),
                ],
              ),

            if (_pagination != null && (_pagination!['total_pages'] ?? 1) > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _page <= 1
                        ? null
                        : () { setState(() => _page--); _load(); },
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous'),
                  ),
                  Text('Page $_page of ${_pagination!['total_pages']}'),
                  TextButton.icon(
                    onPressed: _page >= (_pagination!['total_pages'] ?? 1)
                        ? null
                        : () { setState(() => _page++); _load(); },
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next'),
                  ),
                ],
              ),
            ],
            if (widget.source == ReceivedPaymentsSource.service && _offlineItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text('Offline payments', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Paid outside platform · not added to wallet.', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
              const SizedBox(height: 8),
              for (final p in _offlineItems) _OfflinePaymentTile(payment: p),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _PaymentTile({required this.payment});

  String _money(num n, String currency) {
    final s = n.toStringAsFixed(0);
    final buf = StringBuffer();
    final chars = s.split('').reversed.toList();
    for (var i = 0; i < chars.length; i++) {
      if (i != 0 && i % 3 == 0) buf.write(',');
      buf.write(chars[i]);
    }
    return '$currency ${buf.toString().split('').reversed.join()}';
  }

  Color _statusColor(String? status, BuildContext ctx) {
    final s = (status ?? '').toLowerCase();
    if (s == 'paid' || s == 'credited') return Colors.green;
    if (s == 'failed' || s == 'cancelled') return Theme.of(ctx).colorScheme.error;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = (payment['currency_code'] ?? getActiveCurrency()).toString();
    final gross = (payment['gross_amount'] as num?) ?? 0;
    final fee = (payment['commission_amount'] as num?) ?? 0;
    final net = (payment['net_amount'] as num?) ?? 0;
    final status = payment['status']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment['payer_name']?.toString() ?? '-',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (payment['payer_phone'] != null)
                      Text(payment['payer_phone'].toString(),
                          style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (status != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor(status, context).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: _statusColor(status, context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Metric(label: 'Gross', value: _money(gross, currency)),
              const SizedBox(width: 12),
              _Metric(label: 'Fee', value: _money(fee, currency)),
              const SizedBox(width: 12),
              _Metric(label: 'Net', value: _money(net, currency), strong: true),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(payment['transaction_code']?.toString() ?? '',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace')),
              if (payment['provider_name'] != null ||
                  payment['method_type'] != null)
                Text(
                  'via ${payment['provider_name'] ?? payment['method_type']}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfflinePaymentTile extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _OfflinePaymentTile({required this.payment});

  String _money(num n, String currency) {
    final s = n.toStringAsFixed(0);
    final buf = StringBuffer();
    final chars = s.split('').reversed.toList();
    for (var i = 0; i < chars.length; i++) {
      if (i != 0 && i % 3 == 0) buf.write(',');
      buf.write(chars[i]);
    }
    return '$currency ${buf.toString().split('').reversed.join()}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = (payment['status'] ?? 'pending').toString();
    final confirmed = status == 'confirmed';
    final amount = num.tryParse(payment['amount']?.toString() ?? '') ?? 0;
    final currency = (payment['currency'] ?? getActiveCurrency()).toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_money(amount, currency), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text('Paid offline · not in wallet', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (confirmed ? Colors.green : Colors.orange).withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(status, style: TextStyle(color: confirmed ? Colors.green : Colors.orange, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  const _Metric({required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}
