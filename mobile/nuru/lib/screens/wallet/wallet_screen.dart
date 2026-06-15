import '../../core/widgets/nuru_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../core/widgets/nuru_scrollable_tabs.dart';

import '../../providers/wallet_provider.dart';
import '../bookings/bookings_screen.dart';
import 'make_payment_screen.dart';
import 'receipt_screen.dart';
import 'payout_profile_screen.dart';
import 'payment_history_screen.dart';
import '../migration/migration_banner.dart';

/// WalletScreen - premium dashboard mirroring the web `/wallet` page.
/// Shows balance hero, quick actions, ledger + transactions tabs.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openTopUp() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MakePaymentScreen(
          targetType: 'wallet_topup',
          title: 'Top up wallet',
          amountEditable: true,
          allowWallet: false,
          showFee: false,
          onSuccess: (_) => context.read<WalletProvider>().refresh(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: NuruSubPageAppBar(
        title: 'Wallet',
        actions: [
          IconButton(
            icon: const AppIcon('list', size: 22, color: AppColors.textPrimary),
            tooltip: 'Payment history',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const AppIcon('wallet', size: 22, color: AppColors.textPrimary),
            tooltip: 'Payout settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PayoutProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<WalletProvider>(
        builder: (context, p, _) {
          return NuruRefreshIndicator(
            onRefresh: p.refresh,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Static (non-scrolling) header - like event detail page.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const MigrationBanner(
                        surface: MigrationSurface.wallet,
                        margin: EdgeInsets.only(bottom: 12),
                      ),
                      _BalanceHero(
                        provider: p,
                        onTopUp: _openTopUp,
                        onPay: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BookingsScreen()),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ActivityTabs(controller: _tabs),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                // Each tab scrolls itself, matching event detail behaviour.
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _LedgerList(
                        entries: p.ledger,
                        currency: p.currency,
                        loading: p.loading,
                      ),
                      _TransactionList(
                        transactions: p.transactions,
                        loading: p.loading,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Balance hero ─────────────────────────────────────────────────────────────

class _BalanceHero extends StatefulWidget {
  final WalletProvider provider;
  final VoidCallback onTopUp;
  final VoidCallback onPay;
  const _BalanceHero({
    required this.provider,
    required this.onTopUp,
    required this.onPay,
  });

  @override
  State<_BalanceHero> createState() => _BalanceHeroState();
}

class _BalanceHeroState extends State<_BalanceHero> {
  bool _hidden = false;

  static const _gradStart = Color(0xFF1A1530);
  static const _gradEnd = Color(0xFF3B2A6B);
  static const _accent = Color(0xFFFFD66B);

  String _mask(num value) {
    if (_hidden) return '••••••';
    return formatMoney(value, currency: widget.provider.currency);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gradStart, _gradEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: _gradEnd.withOpacity(0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative orbs
          Positioned(
            right: -40, top: -50,
            child: Container(
              width: 170, height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          Positioned(
            right: 60, bottom: -60,
            child: Container(
              width: 130, height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withOpacity(0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: label + currency pill + eye toggle
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon('wallet',
                              size: 13,
                              color: Colors.white.withOpacity(0.95)),
                          const SizedBox(width: 6),
                          Text(
                            'AVAILABLE BALANCE',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 10,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        p.currency,
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: _hidden ? 'Show balance' : 'Hide balance',
                      onPressed: () => setState(() => _hidden = !_hidden),
                      icon: AppIcon(
                        _hidden ? 'eye-off' : 'eye-on',
                        size: 18,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  _mask(p.availableBalance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'PENDING',
                        value: _mask(p.pendingBalance),
                        dotColor: const Color(0xFFFFC857),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        label: 'RESERVED',
                        value: _mask(p.reservedBalance),
                        dotColor: const Color(0xFF7DD3FC),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _HeroAction(
                        label: 'Top up',
                        icon: 'plus',
                        filled: true,
                        onTap: widget.onTopUp,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroAction(
                        label: 'Pay',
                        icon: 'send',
                        onTap: widget.onPay,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroAction(
                        label: 'Withdraw',
                        icon: 'arrow-right',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PayoutProfileScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;
  final bool filled;
  const _HeroAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF1A1530) : Colors.white;
    return Material(
      color: filled ? Colors.white : Colors.white.withOpacity(0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color dotColor;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 9.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Activity tabs ────────────────────────────────────────────────────────────

class _ActivityTabs extends StatelessWidget {
  final TabController controller;
  const _ActivityTabs({required this.controller});

  static const _labels = ['Ledger', 'Transactions'];

  @override
  Widget build(BuildContext context) {
    return NuruPillTabBar(
      controller: controller,
      labels: _labels,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    );
  }
}


// ─── Purpose icon resolver ────────────────────────────────────────────────────
/// Picks an SVG icon name that matches the *purpose* of a wallet entry,
/// not just its credit/debit direction.
///
/// Inputs are lowercased and matched against a richer keyword list so that
/// a transaction whose `target_type` is `event_contribution` and whose
/// description is "Contribution to Bella's wedding" both resolve to a
/// donation-style icon.
class _PurposeIcon {
  final String name;
  final Color tint;
  final Color soft;
  const _PurposeIcon(this.name, this.tint, this.soft);
}

_PurposeIcon _resolvePurpose({
  required String type,
  required String description,
  required bool isCredit,
}) {
  final t = '$type $description'.toLowerCase();

  bool has(List<String> needles) => needles.any((n) => t.contains(n));

  Color creditTint = AppColors.success;
  Color creditSoft = AppColors.successSoft;
  Color debitTint  = AppColors.primary;
  Color debitSoft  = AppColors.primary.withOpacity(0.10);

  if (has(['contribution', 'pledge', 'donation', 'harambee'])) {
    return _PurposeIcon('donation', AppColors.accent, AppColors.accentSoft);
  }
  if (has(['ticket'])) {
    return _PurposeIcon('ticket', AppColors.primary, AppColors.primarySoft);
  }
  if (has(['booking', 'vendor', 'service'])) {
    return _PurposeIcon('bag', AppColors.blue, AppColors.blueSoft);
  }
  if (has(['topup', 'top_up', 'top up', 'deposit', 'fund'])) {
    return _PurposeIcon('plus', AppColors.success, AppColors.successSoft);
  }
  if (has(['payout', 'withdraw'])) {
    return _PurposeIcon('arrow-right', AppColors.warning, AppColors.warningSoft);
  }
  if (has(['refund', 'reversal', 'return'])) {
    return _PurposeIcon('download', AppColors.info, AppColors.infoSoft);
  }
  if (has(['meeting', 'committee'])) {
    return _PurposeIcon('users', AppColors.blue, AppColors.blueSoft);
  }
  if (has(['expense', 'spend'])) {
    return _PurposeIcon('money', AppColors.warning, AppColors.warningSoft);
  }
  if (has(['rsvp', 'invitation'])) {
    return _PurposeIcon('email', AppColors.blue, AppColors.blueSoft);
  }
  if (has(['fee', 'commission', 'charge'])) {
    return _PurposeIcon('card', AppColors.textSecondary, AppColors.surfaceMuted);
  }
  if (has(['release', 'settlement', 'escrow'])) {
    return _PurposeIcon('shield', AppColors.success, AppColors.successSoft);
  }
  if (has(['gift', 'reward', 'bonus'])) {
    return _PurposeIcon('star', AppColors.primary, AppColors.primarySoft);
  }
  return _PurposeIcon(
    isCredit ? 'download' : 'send',
    isCredit ? creditTint : debitTint,
    isCredit ? creditSoft : debitSoft,
  );
}

String _humanTitle(String raw) {
  if (raw.isEmpty) return 'Transaction';
  return raw
      .replaceAll('_', ' ')
      .split(' ')
      .where((s) => s.isNotEmpty)
      .map((s) => s[0].toUpperCase() + s.substring(1))
      .join(' ');
}

// ─── Ledger list ──────────────────────────────────────────────────────────────

class _LedgerList extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final String currency;
  final bool loading;
  const _LedgerList({
    required this.entries,
    required this.currency,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && entries.isEmpty)
      return const NuruSkeletonList(itemCount: 6, showTrailing: true);
    if (entries.isEmpty)
      return const _EmptyState(text: 'No wallet activity yet.');
    return ListView.separated(
      itemCount: entries.length,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _LedgerCard(entry: entries[i], currency: currency),
    );
  }
}

/// Redesigned ledger row - a card mirroring the transaction card style so
/// the two tabs look consistent, with a purpose-aware icon, clear
/// signed amount, running balance pill and reference tag.
class _LedgerCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String currency;
  const _LedgerCard({required this.entry, required this.currency});

  @override
  Widget build(BuildContext context) {
    final type = (entry['entry_type'] ?? '').toString();
    final desc = (entry['description'] ?? '').toString();
    final isCredit = const ['credit', 'release', 'settlement', 'refund', 'topup']
        .contains(type.toLowerCase());
    final amount = (entry['amount'] ?? 0) as num;
    final balanceAfter = (entry['balance_after'] ?? 0) as num;
    final refCode = (entry['reference_code'] ?? '').toString();

    final purpose = _resolvePurpose(
      type: type,
      description: desc,
      isCredit: isCredit,
    );

    final title = desc.isNotEmpty ? desc : _humanTitle(type);
    final accent = isCredit ? AppColors.success : AppColors.textPrimary;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: purpose.soft,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: AppIcon(purpose.name, size: 18, color: purpose.tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _fmtDate(entry['created_at']),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isCredit ? '+' : '−'} ${formatMoney(amount, currency: currency)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'BAL ${formatMoney(balanceAfter, currency: currency)}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (refCode.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: AppColors.borderLight),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('REF',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textTertiary,
                      letterSpacing: 0.8,
                    )),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    refCode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isCredit ? AppColors.successSoft : AppColors.warningSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _humanTitle(type).toUpperCase(),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: isCredit ? AppColors.success : AppColors.warning,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Transaction list ─────────────────────────────────────────────────────────

class _TransactionList extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final bool loading;
  const _TransactionList({required this.transactions, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading && transactions.isEmpty) {
      return const NuruSkeletonList(itemCount: 6, showTrailing: true);
    }
    if (transactions.isEmpty) {
      return const _EmptyState(text: 'No transactions yet.');
    }
    return ListView.separated(
      itemCount: transactions.length,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _TransactionCard(tx: transactions[i]),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final Map<String, dynamic> tx;
  const _TransactionCard({required this.tx});

  bool get _isCredit {
    final t = (tx['target_type'] ?? '').toString().toLowerCase();
    final dir = (tx['direction'] ?? '').toString().toLowerCase();
    if (dir == 'credit' || dir == 'in') return true;
    if (dir == 'debit' || dir == 'out') return false;
    return t.contains('topup') || t.contains('refund') || t.contains('payout_in');
  }

  @override
  Widget build(BuildContext context) {
    final status = (tx['status'] ?? '').toString();
    final code = (tx['transaction_code'] ?? '').toString();
    final amount = (tx['gross_amount'] ?? 0) as num;
    final currency = (tx['currency_code'] ?? '').toString();
    final title = (tx['description'] ??
            (tx['target_type'] ?? 'Transaction').toString().replaceAll('_', ' '))
        .toString();
    final method = (tx['payment_method'] ?? tx['provider'] ?? '').toString();
    final credit = _isCredit;
    final accent = credit ? AppColors.success : AppColors.textPrimary;
    final purpose = _resolvePurpose(
      type: (tx['target_type'] ?? '').toString(),
      description: title,
      isCredit: credit,
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReceiptScreen(transactionCode: code),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: purpose.soft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: AppIcon(
                      purpose.name,
                      size: 18,
                      color: purpose.tint,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _fmtDate(tx['initiated_at']),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${credit ? '+' : '−'} ${formatMoney(amount, currency: currency)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: accent,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _StatusChip(status: status),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: AppColors.borderLight),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('REF',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textTertiary,
                        letterSpacing: 0.8,
                      )),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      code.isEmpty ? '-' : code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (method.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        method.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (status) {
      case 'succeeded':
        bg = AppColors.successSoft;
        fg = AppColors.success;
        break;
      case 'pending':
      case 'processing':
        bg = AppColors.warningSoft;
        fg = AppColors.warning;
        break;
      case 'failed':
      case 'cancelled':
        bg = AppColors.errorSoft;
        fg = AppColors.error;
        break;
      default:
        bg = AppColors.surfaceMuted;
        fg = AppColors.textSecondary;
    }
    final label = status.isEmpty ? '-' : status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, style: const TextStyle(color: AppColors.textTertiary)),
    ),
  );
}

String _fmtDate(dynamic v) {
  if (v == null) return '';
  try {
    final d = DateTime.parse(v.toString()).toLocal();
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return v.toString();
  }
}
