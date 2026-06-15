import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/widgets/amount_input.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../core/services/wallet_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../providers/wallet_provider.dart';
import 'receipt_screen.dart';

/// CheckoutSheet - bottom sheet that mirrors the web `<CheckoutModal>`.
///
/// Lets the user pay via Wallet, Mobile Money (STK push), or Bank transfer.
/// Polls `/payments/{id}/status` until the gateway returns a terminal state.
class CheckoutSheet extends StatefulWidget {
  final String targetType;
  final String? targetId;
  final String? beneficiaryUserId;
  final num? amount;
  final bool amountEditable;
  final bool allowWallet;
  final bool allowBank;
  final String title;
  final String? description;
  final void Function(Map<String, dynamic> tx)? onSuccess;

  const CheckoutSheet({
    super.key,
    required this.targetType,
    this.targetId,
    this.beneficiaryUserId,
    this.amount,
    this.amountEditable = false,
    this.allowWallet = true,
    this.allowBank = true,
    required this.title,
    this.description,
    this.onSuccess,
  });

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  String _method = 'wallet';
  String? _providerId;
  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  bool _busy = false;
  bool _loadingProviders = false;
  String? _pendingMessage;
  List<Map<String, dynamic>> _providers = [];

  static const _inputBorder = OutlineInputBorder(
    borderSide: BorderSide(color: AppColors.border, width: 1),
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  @override
  void initState() {
    super.initState();
    _method = widget.allowWallet ? 'wallet' : 'mobile_money';
    if (widget.amount != null) {
      _amountCtrl.text = widget.amount!.toString();
    }
    _loadProviders();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _phoneCtrl.dispose();
    _accountCtrl.dispose();
    super.dispose();
  }

  String get _currency => context.read<WalletProvider>().currency;
  String get _country => _currency == 'KES' ? 'KE' : 'TZ';

  Future<void> _loadProviders() async {
    if (_method == 'wallet') return;
    setState(() => _loadingProviders = true);
    final res = await WalletService.listProviders(
      countryCode: _country,
      collection: true,
    );
    if (!mounted) return;
    final data = res['data'];
    List rawList = const [];
    if (data is List) {
      rawList = data;
    } else if (data is Map) {
      final p = data['providers'];
      if (p is List) rawList = p;
    }
    final filtered = rawList
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((p) =>
            (p['provider_type'] ?? '') ==
            (_method == 'mobile_money' ? 'mobile_money' : 'bank'))
        .where((p) => _isProviderEnabled(p))
        .toList();
    setState(() {
      _providers = filtered;
      _loadingProviders = false;
      if (filtered.isNotEmpty &&
          !filtered.any((p) => p['id'] == _providerId)) {
        _providerId = filtered.first['id'] as String;
      }
    });
  }

  bool _isProviderEnabled(Map<String, dynamic> provider) {
    final active = provider['is_active'];
    if (active == false) return false;

    if (_method == 'mobile_money') {
      final collectionEnabled = provider['supports_collection'] ??
          provider['is_collection_enabled'];
      return collectionEnabled != false;
    }

    final payoutEnabled = provider['supports_payout'] ??
        provider['is_payout_enabled'];
    return payoutEnabled != false;
  }

  String _providerLabel(Map<String, dynamic> provider) {
    return (provider['name'] ??
            provider['display_name'] ??
            provider['code'] ??
            '')
        .toString();
  }

  String _digitsOnly(String raw) => raw.replaceAll(RegExp(r'[^0-9.]'), '');

  void _onAmountChanged(String value) {
    final cleaned = _digitsOnly(value);
    if (cleaned == value) {
      setState(() {});
      return;
    }

    _amountCtrl.value = TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
    setState(() {});
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    String? labelText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: _inputBorder,
      enabledBorder: _inputBorder,
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.primary, width: 1.4),
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    );
  }

  Future<Map<String, dynamic>?> _pollUntilTerminal(String transactionId) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < const Duration(minutes: 4)) {
      await Future.delayed(const Duration(seconds: 3));
      final res = await WalletService.getStatus(transactionId);
      if (res['success'] == true && res['data'] != null) {
        final tx = Map<String, dynamic>.from(res['data'] as Map);
        final status = tx['status']?.toString();
        if (['succeeded', 'failed', 'cancelled', 'refunded', 'paid', 'credited'].contains(status)) {
          return tx;
        }
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final amount = num.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? widget.amount ?? 0;
    if (amount <= 0) {
      _toast('Enter a valid amount');
      return;
    }
    if (_method == 'mobile_money') {
      if (_phoneCtrl.text.trim().isEmpty) {
        _toast('Enter your mobile number');
        return;
      }
      // Make sure providers have loaded and one is selected before we
      // hit /payments/initiate. Without provider_id the gateway has no
      // way to push an STK prompt and the request silently fails.
      if (_loadingProviders) {
        _toast('Loading payment providers… please try again in a moment');
        return;
      }
      if (_providers.isEmpty) {
        await _loadProviders();
        if (_providers.isEmpty) {
          _toast('No mobile money providers available for your country');
          return;
        }
      }
      if (_providerId == null || !_providers.any((p) => p['id'] == _providerId)) {
        _providerId = _providers.first['id'] as String?;
      }
      if (_providerId == null) {
        _toast('Pick a mobile money provider');
        return;
      }
    }
    if (_method == 'bank') {
      if (_accountCtrl.text.trim().isEmpty) {
        _toast('Enter your account number');
        return;
      }
      if (_providerId == null) {
        _toast('Pick a bank');
        return;
      }
    }

    setState(() {
      _busy = true;
      _pendingMessage = null;
    });
    try {
      final baseDesc = (widget.description ?? widget.title).trim();
      final paymentDescription = baseDesc.length >= 8
          ? baseDesc
          : '${widget.title} for ${widget.targetType.replaceAll('_', ' ')}'.trim();

      final res = await WalletService.initiatePayment(
        targetType: widget.targetType,
        targetId: widget.targetId,
        beneficiaryUserId: widget.beneficiaryUserId,
        amount: amount,
        countryCode: _country,
        currencyCode: _currency,
        methodType: _method,
        paymentChannel: _method == 'mobile_money' ? 'stk_push' : _method,
        providerId: _method != 'wallet' ? _providerId : null,
        phone: _method == 'mobile_money' ? _phoneCtrl.text.trim() : null,
        accountNumber: _method == 'bank' ? _accountCtrl.text.trim() : null,
        description: paymentDescription,
      );
      if (res['success'] != true || res['data'] == null) {
        // Surface the real backend message so the user knows WHY the push
        // never arrived (e.g. "Provider unavailable", "Invalid phone").
        final msg = res['message']?.toString().trim();
        _toast((msg != null && msg.isNotEmpty) ? msg : 'Failed to start payment');
        return;
      }
      final data = Map<String, dynamic>.from(res['data'] as Map);
      final tx = Map<String, dynamic>.from(data['transaction'] as Map);
      final txStatus = tx['status']?.toString();
      final txId = tx['id']?.toString() ?? '';
      final txCode = tx['transaction_code']?.toString() ?? '';

      if (_method == 'wallet' || txStatus == 'succeeded') {
        if (!mounted) return;
        widget.onSuccess?.call(tx);
        Navigator.of(context).pop();
        if (txCode.isNotEmpty) _openReceipt(txCode);
        return;
      }

      if (mounted) {
        setState(() {
          _pendingMessage = res['message']?.toString() ??
              data['user_message']?.toString() ??
              'Check your phone to approve the payment.';
        });
      }

      final final_ = txId.isNotEmpty ? await _pollUntilTerminal(txId) : null;
      if (!mounted) return;
      final finalStatus = final_?['status']?.toString();
      if (final_ != null && ['succeeded', 'paid', 'credited'].contains(finalStatus)) {
        widget.onSuccess?.call(final_);
        _toast('Payment confirmed');
        final finalCode = final_['transaction_code']?.toString() ?? txCode;
        Navigator.of(context).pop();
        if (finalCode.isNotEmpty) _openReceipt(finalCode);
      } else if (final_ != null) {
        _toast(final_['failure_reason']?.toString() ?? 'Payment $finalStatus');
        setState(() => _pendingMessage = null);
      } else {
        _toast('Still processing · check Wallet › Transactions in a moment');
        setState(() => _pendingMessage = null);
      }
      return;
    } catch (e) {
      // Surface the actual exception so we don't silently swallow auth /
      // network / validation failures (which is what made this look like
      // "the button does nothing").
      _toast('Payment error: $e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openReceipt(String code) {
    final nav = NuruApp.navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(
      builder: (_) => ReceiptScreen(transactionCode: code),
    ));
  }

  void _toast(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context) ??
        ScaffoldMessenger.maybeOf(NuruApp.navigatorKey.currentContext!);
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final amount = num.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? widget.amount ?? 0;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 14),
              Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              if (widget.description != null) ...[
                const SizedBox(height: 4),
                Text(widget.description!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
              const SizedBox(height: 16),

              // Amount
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AMOUNT',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: AppColors.textTertiary, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    if (widget.amountEditable)
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primary, width: 1.2),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: TextField(
                          controller: _amountCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: amountFormatters,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            prefixText: '$_currency ',
                            prefixStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.textHint),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                            hintText: '0',
                            hintStyle: const TextStyle(color: AppColors.textHint, fontWeight: FontWeight.w500),
                          ),
                          onChanged: _onAmountChanged,
                        ),
                      )
                    else
                      Text(formatMoney(amount, currency: _currency),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Method picker
              if (widget.allowWallet)
                _MethodTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Nuru Wallet',
                  subtitle: 'Instant · No fee',
                  selected: _method == 'wallet',
                  onTap: () => setState(() => _method = 'wallet'),
                ),
              _MethodTile(
                icon: Icons.smartphone,
                title: 'Mobile Money',
                subtitle: 'M-Pesa, Mixx by Yas, Airtel Money',
                selected: _method == 'mobile_money',
                onTap: () { setState(() => _method = 'mobile_money'); _loadProviders(); },
              ),
              _MethodTile(
                icon: Icons.account_balance_outlined,
                title: 'Bank Transfer',
                subtitle: widget.allowBank ? 'CRDB, NMB, Equity, KCB' : 'Coming soon',
                selected: _method == 'bank' && widget.allowBank,
                disabled: !widget.allowBank,
                badge: widget.allowBank ? null : 'Coming soon',
                onTap: () {
                  if (!widget.allowBank) return;
                  setState(() => _method = 'bank');
                  _loadProviders();
                },
              ),

              if (_method != 'wallet') ...[
                const SizedBox(height: 14),
                if (_loadingProviders)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_providers.isEmpty)
                  const Text('No providers available for your country.', style: TextStyle(color: AppColors.textTertiary, fontSize: 12))
                else
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _providers.map((p) {
                      final selected = _providerId == p['id'];
                      return GestureDetector(
                        onTap: () => setState(() => _providerId = p['id'] as String),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primarySoft : AppColors.surfaceVariant,
                            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(_providerLabel(p),
                            style: TextStyle(fontWeight: FontWeight.w600, color: selected ? AppColors.primary : AppColors.textPrimary, fontSize: 12)),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 12),
                if (_method == 'mobile_money')
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: _fieldDecoration(
                      labelText: 'Mobile number',
                      hintText: '07XXXXXXXX',
                    ),
                  ),
                if (_method == 'bank')
                  TextField(
                    controller: _accountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _fieldDecoration(
                      labelText: 'Account number',
                      hintText: 'Enter account number',
                    ),
                  ),
              ],

              const SizedBox(height: 16),
              if (_pendingMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.infoSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.blue.withOpacity(0.18)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Payment request sent. Check your phone and wait here for confirmation.',
                          style: TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: const [
                  Icon(Icons.shield_outlined, size: 14, color: AppColors.textTertiary),
                  SizedBox(width: 6),
                  Expanded(child: Text(
                    'Secured by Nuru. Funds held in escrow until delivery.',
                    style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                  )),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Pay ${formatMoney(amount, currency: _currency)}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool disabled;
  final String? badge;
  final VoidCallback onTap;
  const _MethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.disabled = false,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: disabled
                ? AppColors.surfaceVariant
                : selected
                    ? AppColors.primarySoft
                    : AppColors.surface,
            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: disabled
                      ? AppColors.surfaceMuted
                      : selected
                          ? AppColors.primary
                          : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: disabled ? AppColors.textTertiary : selected ? AppColors.textOnPrimary : AppColors.textPrimary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(subtitle, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                  ],
                ),
              ),
              if (badge != null) ...[
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                ),
              ],
              Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 2),
                  color: selected ? AppColors.primary : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
