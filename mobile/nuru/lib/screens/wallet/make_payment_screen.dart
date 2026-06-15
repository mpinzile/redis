import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../core/services/wallet_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../core/widgets/amount_input.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/data/countries.dart';
import '../../providers/wallet_provider.dart';
import 'receipt_screen.dart';
import 'payment_confirmation_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// MakePaymentScreen - full-screen replacement for the legacy `CheckoutSheet`
/// that mirrors the canonical "Make Payment" mockup.
///
/// Behaviourally identical to `CheckoutSheet` (same /payments/initiate call,
/// same status-poll loop, same wallet/MoMo/bank routing) - only the
/// presentation layer is new. All callers can swap
/// `showModalBottomSheet(builder: CheckoutSheet(...))` for
/// `Navigator.push(MakePaymentScreen(...))` with no other changes.
class MakePaymentScreen extends StatefulWidget {
  final String targetType;
  final String? targetId;
  final String? beneficiaryUserId;
  final num? amount;
  final bool amountEditable;
  final bool allowWallet;
  final bool allowBank;
  final String title;
  final String? description;

  /// Optional payment-summary metadata so the cream summary card can render
  /// a rich preview (event thumb, ticket-class line, schedule line). Pass
  /// what you have - anything missing is hidden gracefully.
  final String? summaryImageUrl;
  final String? summarySubtitle;
  final String? summaryMeta;

  /// When true, fetch /payments/fee-preview and render a "Service Fee" line
  /// + a "Total" line under the amount-to-pay. Defaults to true so all
  /// callers automatically reflect the active CommissionSetting.
  final bool showFee;

  /// Optional "Reserve · pay later" action. When provided, MakePaymentScreen
  /// renders an outlined secondary button beneath the primary Pay CTA so the
  /// user can hold their order and complete payment from My Tickets later.
  /// The caller owns the actual reservation logic (mirrors web behaviour).
  final Future<void> Function()? onReserve;

  /// Label for the reserve button (defaults to "Reserve · pay later").
  final String reserveLabel;

  final void Function(Map<String, dynamic> tx)? onSuccess;

  const MakePaymentScreen({
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
    this.summaryImageUrl,
    this.summarySubtitle,
    this.summaryMeta,
    this.showFee = true,
    this.onReserve,
    this.reserveLabel = 'Reserve · pay later',
    this.onSuccess,
  });


  @override
  State<MakePaymentScreen> createState() => _MakePaymentScreenState();
}

class _MakePaymentScreenState extends State<MakePaymentScreen> {
  // Methods: 'wallet' | 'mobile_money' | 'bank'
  String _method = 'mobile_money';
  String? _providerId;

  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();

  bool _busy = false;
  bool _loadingProviders = false;
  String? _pendingMessage;
  List<Map<String, dynamic>> _providers = [];

  // Service-fee preview (per-country CommissionSetting from backend).
  double _serviceFee = 0;
  bool _feeLoading = false;

  // IP-detected country. Locks the phone field to TZ or KE; if neither,
  // disables the phone input (mobile money is not supported there yet).
  String? _detectedCC;
  bool _phoneSupported = true;

  @override
  void initState() {
    super.initState();
    _method = widget.allowWallet ? 'wallet' : 'mobile_money';
    if (widget.amount != null) {
      // Seed editable input pre-formatted with thousand separators.
      final raw = widget.amount!.toStringAsFixed(0);
      _amountCtrl.value = AmountInputFormatter()
          .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: raw));
    }
    _loadProviders();
    _detectCountry();
    if (widget.showFee) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFee());
    }
  }

  Future<void> _detectCountry() async {
    try {
      final res = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final cc = (data['country_code'] as String?)?.toUpperCase();
        if (!mounted) return;
        setState(() {
          _detectedCC = cc;
          _phoneSupported = cc == 'TZ' || cc == 'KE';
        });
      }
    } catch (_) {/* fallback to wallet currency */}
  }

  Future<void> _loadFee() async {
    if (!widget.showFee || _feeLoading) return;
    setState(() => _feeLoading = true);
    final amt = num.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ??
        widget.amount ?? 1;
    final res = await WalletService.feePreview(
      countryCode: _country,
      currencyCode: _currency,
      targetType: widget.targetType,
      grossAmount: amt <= 0 ? 1 : amt,
    );
    if (!mounted) return;
    setState(() {
      _feeLoading = false;
      if (res['success'] == true && res['data'] is Map) {
        _serviceFee = ((res['data'] as Map)['commission_amount'] as num?)
                ?.toDouble() ??
            0;
      }
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _phoneCtrl.dispose();
    _accountCtrl.dispose();
    super.dispose();
  }

  String get _currency => context.read<WalletProvider>().currency;
  String get _country {
    final cc = _detectedCC;
    if (cc == 'KE' || cc == 'TZ') return cc!;
    return _currency == 'KES' ? 'KE' : 'TZ';
  }
  // ignore: unused_element
  String get _phonePrefix => _country == 'KE' ? '+254' : '+255';
  CountryData get _countryData => allCountries.firstWhere(
        (c) => c.code == _country,
        orElse: () => allCountries.firstWhere((c) => c.code == 'TZ'),
      );

  // ─── Backend wiring (unchanged from CheckoutSheet) ──────────────────────

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

  bool _isProviderEnabled(Map<String, dynamic> p) {
    if (p['is_active'] == false) return false;
    if (_method == 'mobile_money') {
      final c = p['supports_collection'] ?? p['is_collection_enabled'];
      return c != false;
    }
    final po = p['supports_payout'] ?? p['is_payout_enabled'];
    return po != false;
  }

  String _providerLabel(Map<String, dynamic> p) =>
      (p['name'] ?? p['display_name'] ?? p['code'] ?? '').toString();

  Future<Map<String, dynamic>?> _pollUntilTerminal(String txId) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < const Duration(minutes: 4)) {
      await Future.delayed(const Duration(seconds: 3));
      final res = await WalletService.getStatus(txId);
      if (res['success'] == true && res['data'] != null) {
        final tx = Map<String, dynamic>.from(res['data'] as Map);
        final s = tx['status']?.toString();
        if (['succeeded', 'failed', 'cancelled', 'refunded', 'paid', 'credited']
            .contains(s)) return tx;
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final amount = num.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ??
        widget.amount ??
        0;
    if (amount <= 0) return _toast('Enter a valid amount');

    if (_method == 'mobile_money') {
      if (!_phoneSupported) {
        return _toast('Mobile money is only available in TZ and KE.');
      }
      if (_phoneCtrl.text.trim().isEmpty) return _toast('Enter your mobile number');
      if (_loadingProviders) {
        return _toast('Loading payment providers… please try again in a moment');
      }
      if (_providers.isEmpty) {
        await _loadProviders();
        if (_providers.isEmpty) {
          return _toast('No mobile money providers available for your country');
        }
      }
      _providerId ??= _providers.first['id'] as String?;
      if (_providerId == null) return _toast('Pick a mobile money provider');
    }
    if (_method == 'bank') {
      if (_accountCtrl.text.trim().isEmpty) return _toast('Enter your account number');
      if (_providerId == null) return _toast('Pick a bank');
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
        final msg = res['message']?.toString().trim();
        return _toast((msg != null && msg.isNotEmpty) ? msg : 'Failed to start payment');
      }
      final data = Map<String, dynamic>.from(res['data'] as Map);
      final tx = Map<String, dynamic>.from(data['transaction'] as Map);
      final status = tx['status']?.toString();
      final txId = tx['id']?.toString() ?? '';
      final txCode = tx['transaction_code']?.toString() ?? '';

      // Wallet payments succeed synchronously - for everything else we hand
      // off to the dedicated PaymentConfirmationScreen which polls the
      // status. We use `pushReplacement` so back from confirmation goes to
      // whatever opened the make-payment flow, not back into this form.
      if (_method == 'wallet' || status == 'succeeded') {
        if (!mounted) return;
        widget.onSuccess?.call(tx);
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PaymentConfirmationScreen(
          transactionId: txId,
          transactionCode: txCode,
          title: widget.title,
          amount: amount,
          currency: _currency,
          initialMessage: res['message']?.toString() ??
              data['user_message']?.toString() ??
              'Check your phone to approve the payment.',
          onSuccess: widget.onSuccess,
        ),
      ));
      return;
    } catch (e) {
      _toast('Payment error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openReceipt(String code) {
    final nav = NuruApp.navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => ReceiptScreen(transactionCode: code)));
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.maybeOf(context) ??
        ScaffoldMessenger.maybeOf(NuruApp.navigatorKey.currentContext!);
    m?.showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final amount = num.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ??
        widget.amount ??
        0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset(
            'assets/icons/arrow-left-icon.svg',
            width: 22, height: 22,
            colorFilter: const ColorFilter.mode(Color(0xFF111827), BlendMode.srcIn),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Text(
          'Make Payment',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _summaryCard(amount),
                  const SizedBox(height: 22),
                  _section('Choose Payment Method'),
                  const SizedBox(height: 10),
                  if (widget.allowWallet)
                    _methodCard(
                      key: 'wallet',
                      iconPath: 'assets/icons/wallet-icon.svg',
                      title: 'Nuru Wallet',
                      subtitle: 'Instant · No fee',
                    ),
                  _methodCard(
                    key: 'mobile_money',
                    iconPath: 'assets/icons/call-icon.svg',
                    title: 'Mobile Money',
                    subtitle: 'Pay using your mobile money account',
                  ),
                  if (widget.allowBank)
                    _methodCard(
                      key: 'bank',
                      iconPath: 'assets/icons/card-icon.svg',
                      title: 'Bank Transfer',
                      subtitle: 'Pay directly from your bank account',
                    ),
                  if (_method == 'mobile_money') ...[
                    const SizedBox(height: 18),
                    _section('Mobile Money Provider'),
                    const SizedBox(height: 10),
                    _providerGrid(),
                    const SizedBox(height: 18),
                    _section('Enter Phone Number'),
                    const SizedBox(height: 10),
                    _phoneField(),
                  ],
                  if (_method == 'bank') ...[
                    const SizedBox(height: 18),
                    _section('Choose Bank'),
                    const SizedBox(height: 10),
                    _providerGrid(),
                    const SizedBox(height: 18),
                    _section('Account Number'),
                    const SizedBox(height: 10),
                    _accountField(),
                  ],
                  const SizedBox(height: 18),
                  _amountToPay(amount),
                  if (_pendingMessage != null) ...[
                    const SizedBox(height: 12),
                    _pendingBanner(),
                  ],
                ],
              ),
            ),
            _payBar(amount),
          ],
        ),
      ),
    );
  }

  // ── Summary card ─────────────────────────────────────────────
  Widget _summaryCard(num amount) {
    final hasImage = (widget.summaryImageUrl ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCE9B6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Summary',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: hasImage
                    ? CachedNetworkImage(
                        imageUrl: widget.summaryImageUrl!,
                        width: 56, height: 56, fit: BoxFit.cover,
                        placeholder: (_, __) => _thumbFallback(),
                        errorWidget: (_, __, ___) => _thumbFallback(),
                      )
                    : _thumbFallback(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.2)),
                    if ((widget.summarySubtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(widget.summarySubtitle!,
                          style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500)),
                    ],
                    if ((widget.summaryMeta ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(widget.summaryMeta!,
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w500)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(formatMoney(amount, currency: _currency),
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumbFallback() => Container(
        width: 56, height: 56,
        color: AppColors.primary.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: SvgPicture.asset(
          'assets/icons/calendar-icon.svg',
          width: 22, height: 22,
          colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
        ),
      );

  // ── Section header ───────────────────────────────────────────
  Widget _section(String label) => Text(label,
      style: GoogleFonts.inter(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: -0.1));

  // ── Method radio card ────────────────────────────────────────
  Widget _methodCard({
    required String key,
    required String iconPath,
    required String title,
    required String subtitle,
    bool disabled = false,
  }) {
    final selected = _method == key && !disabled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: disabled
            ? null
            : () {
                setState(() {
                  _method = key;
                  _providerId = null;
                });
                if (key != 'wallet') _loadProviders();
              },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF7E6) : Colors.white,
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : const Color(0xFFE5E7EB),
              width: selected ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.10)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEAECEF)),
              ),
              alignment: Alignment.center,
              child: SvgPicture.asset(
                iconPath,
                width: 20, height: 20,
                colorFilter: ColorFilter.mode(
                  disabled
                      ? AppColors.textTertiary
                      : (selected ? AppColors.primary : AppColors.textPrimary),
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: disabled
                              ? AppColors.textTertiary
                              : AppColors.textPrimary)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            _radio(selected),
          ]),
        ),
      ),
    );
  }

  Widget _radio(bool selected) => Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFD1D5DB),
              width: 2),
        ),
        alignment: Alignment.center,
        child: selected
            ? Container(
                width: 10, height: 10,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.primary),
              )
            : null,
      );

  // ── Provider chips ───────────────────────────────────────────
  Widget _providerGrid() {
    if (_loadingProviders) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SkeletonGroup(
          child: Column(children: [
            SkeletonBox(height: 56, radius: 12),
            SizedBox(height: 10),
            SkeletonBox(height: 56, radius: 12),
            SizedBox(height: 10),
            SkeletonBox(height: 56, radius: 12),
          ]),
        ),
      );
    }
    if (_providers.isEmpty) {
      return Text(
        _method == 'mobile_money'
            ? 'No mobile money providers available for your country.'
            : 'No banks available for your country.',
        style: GoogleFonts.inter(
            fontSize: 12, color: AppColors.textTertiary),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < _providers.length; i++) ...[
          _providerTile(_providers[i]),
          if (i != _providers.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _providerTile(Map<String, dynamic> p) {
    final selected = _providerId == p['id'];
    final label = _providerLabel(p);
    final brand = _brandFor(label);
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _providerId = p['id'] as String),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7E6) : Colors.white,
          border: Border.all(
              color: selected
                  ? AppColors.primary
                  : const Color(0xFFE5E7EB),
              width: selected ? 1.4 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [brand.bg, brand.bg2],
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: brand.fg),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  _method == 'mobile_money' ? 'Mobile money' : 'Bank transfer',
                  style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          _radio(selected),
        ]),
      ),
    );
  }

  ({Color bg, Color bg2, Color fg}) _brandFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('mpesa') || n.contains('m-pesa') || n.contains('vodacom')) {
      return (
        bg: const Color(0xFFDCFCE7),
        bg2: const Color(0xFFBBF7D0),
        fg: const Color(0xFF15803D),
      );
    }
    if (n.contains('airtel')) {
      return (
        bg: const Color(0xFFFEE2E2),
        bg2: const Color(0xFFFECACA),
        fg: const Color(0xFFB91C1C),
      );
    }
    if (n.contains('tigo') || n.contains('mixx') || n.contains('yas')) {
      return (
        bg: const Color(0xFFDBEAFE),
        bg2: const Color(0xFFBFDBFE),
        fg: const Color(0xFF1D4ED8),
      );
    }
    if (n.contains('halopesa') || n.contains('halotel')) {
      return (
        bg: const Color(0xFFFFEDD5),
        bg2: const Color(0xFFFED7AA),
        fg: const Color(0xFFB45309),
      );
    }
    return (
      bg: Colors.white,
      bg2: AppColors.primarySoft,
      fg: AppColors.textSecondary,
    );
  }

  // ── Phone field ──────────────────────────────────────────────
  Widget _phoneField() {
    final cd = _countryData;
    final supported = _phoneSupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEAECEF)),
          ),
          child: Row(children: [
            // Locked country selector (IP-detected, not tappable)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 22, height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: Text(cd.flag, style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 8),
                Text(cd.dialCode,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(width: 4),
                const AppIcon('chevron-down',
                    size: 18, color: AppColors.textTertiary),
              ]),
            ),
            Container(width: 1, height: 26, color: const Color(0xFFEAECEF)),
            Expanded(
              child: TextField(
                controller: _phoneCtrl,
                enabled: supported,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '7XX XXX XXX',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 14.5, color: const Color(0xFFC4C7CD)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                ),
              ),
            ),
          ]),
        ),
        if (!supported) ...[
          const SizedBox(height: 8),
          Text(
            'Mobile money is currently available only in Tanzania and Kenya.',
            style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFB45309)),
          ),
        ],
      ],
    );
  }

  // ── Account field ────────────────────────────────────────────
  Widget _accountField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TextField(
        controller: _accountCtrl,
        keyboardType: TextInputType.number,
        style: GoogleFonts.inter(
            fontSize: 13.5, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Enter account number',
          hintStyle: GoogleFonts.inter(
              fontSize: 13, color: const Color(0xFFC4C7CD)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }

  // ── Amount to pay ────────────────────────────────────────────
  Widget _amountToPay(num amount) {
    if (widget.amountEditable) {
      final showFee = widget.showFee && _serviceFee > 0;
      final total = amount + (showFee ? _serviceFee : 0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Amount to Pay'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(_currency,
                    style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.6)),
              ),
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: amountFormatters,
                  style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.6),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    hintText: '0',
                    hintStyle: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFD1D5DB)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (_) {
                    setState(() {});
                    if (widget.showFee) _loadFee();
                  },
                ),
              ),
            ],
          ),
          if (widget.showFee) ...[
            const SizedBox(height: 18),
            _feeRow('Subtotal', amount),
            const SizedBox(height: 12),
            _feeRow('Service Fee',
                showFee ? _serviceFee : 0,
                loading: _feeLoading && _serviceFee == 0,
                muted: true),
            const SizedBox(height: 14),
            Container(height: 1, color: const Color(0xFFEEEEF2)),
            const SizedBox(height: 14),
            _feeRow('Total', total, bold: true),
          ],
        ],
      );
    }
    final showFee = widget.showFee && _serviceFee > 0;
    final total = amount + (showFee ? _serviceFee : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Amount to Pay'),
        const SizedBox(height: 8),
        Text(formatMoney(amount, currency: _currency),
            style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.6)),
        if (widget.showFee) ...[
          const SizedBox(height: 18),
          _feeRow('Subtotal', amount),
          const SizedBox(height: 12),
          _feeRow('Service Fee',
              showFee ? _serviceFee : 0,
              loading: _feeLoading && _serviceFee == 0,
              muted: true),
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFEEEEF2)),
          const SizedBox(height: 14),
          _feeRow('Total', total, bold: true),
        ],
      ],
    );
  }

  Widget _feeRow(String label, num value,
      {bool bold = false, bool muted = false, bool loading = false}) {
    final valueText =
        loading ? '…' : formatMoney(value, currency: _currency);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: muted ? AppColors.textTertiary : AppColors.textSecondary)),
        Text(valueText,
            style: GoogleFonts.inter(
                fontSize: bold ? 14 : 12.5,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }


  Widget _pendingBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _pendingMessage ?? '',
              style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E3A8A)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky pay bar ───────────────────────────────────────────
  Widget _payBar(num amount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEF2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                elevation: 0,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ).copyWith(
                elevation: WidgetStateProperty.all(0),
                shadowColor: WidgetStateProperty.all(Colors.transparent),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset('assets/icons/card-icon.svg',
                            width: 18, height: 18,
                            colorFilter: const ColorFilter.mode(
                                Colors.black, BlendMode.srcIn)),
                        const SizedBox(width: 8),
                        Text('Pay ${formatMoney(amount + (widget.showFee ? _serviceFee : 0), currency: _currency)}',
                            style: GoogleFonts.inter(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.black)),
                      ],
                    ),
            ),
          ),
          if (widget.onReserve != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await widget.onReserve!();
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset('assets/icons/clock-icon.svg',
                        width: 16, height: 16,
                        colorFilter: const ColorFilter.mode(
                            AppColors.textPrimary, BlendMode.srcIn)),
                    const SizedBox(width: 8),
                    Text(widget.reserveLabel,
                        style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

