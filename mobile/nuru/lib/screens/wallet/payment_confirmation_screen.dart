import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/wallet_service.dart';
import 'receipt_screen.dart';

/// Shown immediately after the make-payment screen successfully *initiates*
/// a payment. We use `pushReplacement` so pressing back from here returns
/// the user to whatever screen launched the payment (event detail, ticket
/// checkout, contribution flow, etc.) - never back into the now-stale
/// make-payment form.
///
/// The screen polls the transaction status until it terminates, then shows
/// a clean success/failure state with quick actions.
class PaymentConfirmationScreen extends StatefulWidget {
  final String transactionId;
  final String transactionCode;
  final String title;
  final num amount;
  final String currency;
  final String? initialMessage;
  final void Function(Map<String, dynamic> tx)? onSuccess;

  const PaymentConfirmationScreen({
    super.key,
    required this.transactionId,
    required this.transactionCode,
    required this.title,
    required this.amount,
    required this.currency,
    this.initialMessage,
    this.onSuccess,
  });

  @override
  State<PaymentConfirmationScreen> createState() => _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState extends State<PaymentConfirmationScreen> {
  bool _polling = true;
  Map<String, dynamic>? _tx;
  String? _error;
  Timer? _ticker;
  int _seconds = 0;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage ?? 'Check your phone to approve the payment.';
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    _poll();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final start = DateTime.now();
    while (mounted && DateTime.now().difference(start) < const Duration(minutes: 4)) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final res = await WalletService.getStatus(widget.transactionId);
      if (res['success'] == true && res['data'] != null) {
        final tx = Map<String, dynamic>.from(res['data'] as Map);
        final s = tx['status']?.toString();
        if (['succeeded', 'paid', 'credited'].contains(s)) {
          widget.onSuccess?.call(tx);
          if (!mounted) return;
          setState(() { _polling = false; _tx = tx; });
          return;
        }
        if (['failed', 'cancelled', 'refunded'].contains(s)) {
          if (!mounted) return;
          setState(() {
            _polling = false;
            _tx = tx;
            _error = tx['failure_reason']?.toString() ?? 'Payment $s';
          });
          return;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _polling = false;
      _error = 'Still processing. Check Wallet › Transactions in a moment.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ok = !_polling && _error == null && _tx != null;
    final code = (_tx?['transaction_code'] ?? widget.transactionCode).toString();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('Payment', style: appText(size: 16, weight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: _polling
              ? null // don't let user back out mid-poll
              : () => Navigator.of(context).pop(true),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              _statusCircle(ok: ok, polling: _polling, error: _error != null),
              const SizedBox(height: 24),
              Text(
                _polling
                    ? 'Confirming payment…'
                    : ok ? 'Payment successful' : 'Payment incomplete',
                textAlign: TextAlign.center,
                style: appText(size: 22, weight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                _polling ? '$_message\n${_seconds}s' : (_error ?? 'Your payment for ${widget.title} was received.'),
                textAlign: TextAlign.center,
                style: appText(size: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  _row('Amount', '${widget.currency} ${widget.amount.toStringAsFixed(2)}'),
                  const SizedBox(height: 8),
                  _row('For', widget.title),
                  if (code.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _row('Reference', code),
                  ],
                ]),
              ),
              const Spacer(),
              if (ok)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => ReceiptScreen(transactionCode: code),
                      ));
                    },
                    child: Text('View receipt', style: appText(size: 15, weight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              if (!_polling)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(ok),
                    child: Text(ok ? 'Done' : 'Back', style: appText(size: 14, weight: FontWeight.w600, color: AppColors.textSecondary)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Row(children: [
        Text(k, style: appText(size: 13, color: AppColors.textSecondary)),
        const Spacer(),
        Flexible(child: Text(v, textAlign: TextAlign.right, style: appText(size: 13, weight: FontWeight.w700))),
      ]);

  Widget _statusCircle({required bool ok, required bool polling, required bool error}) {
    final color = polling
        ? AppColors.primary
        : ok ? Colors.green.shade500 : Colors.red.shade400;
    final icon = polling
        ? null
        : ok ? Icons.check_rounded : Icons.error_outline_rounded;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: polling
          ? Padding(
              padding: const EdgeInsets.all(28),
              child: CircularProgressIndicator(strokeWidth: 3, color: color),
            )
          : Icon(icon, color: color, size: 56),
    );
  }
}
