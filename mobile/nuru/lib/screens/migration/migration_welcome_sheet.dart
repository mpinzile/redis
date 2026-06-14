import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/migration_provider.dart';
import '../wallet/payout_profile_screen.dart';

/// MigrationWelcomeSheet - mobile companion to MigrationWelcomeModal (web).
///
/// Premium bottom-sheet shown to legacy users who don't yet have a payment
/// profile. Wording and dismissability harden with phase:
///   • soft   → "Secure Payments Upgrade", "Setup now" + "Remind me later"
///   • nudge  → same shape, returns weekly
///   • restrict → "Action required", non-dismissable
///
/// Show via the helper at the bottom: `showMigrationWelcomeSheet(context)`.
class MigrationWelcomeSheet extends StatelessWidget {
  const MigrationWelcomeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final mig = context.watch<MigrationProvider>();
    final isRestrict = mig.phase == MigrationPhase.restrict;
    final summary = mig.monetizedSummary;
    final pending = mig.pendingBalance;

    final chips = <_Chip>[];
    final addChip = (String label, dynamic v) {
      final n = (v is num) ? v.toInt() : 0;
      if (n > 0) chips.add(_Chip('$n $label${n > 1 ? 's' : ''}'));
    };
    final contribCount = (summary['contributions'] is num)
        ? (summary['contributions'] as num).toInt()
        : 0;
    addChip('event', summary['events']);
    addChip('ticketed', summary['ticketed_events']);
    addChip('service', summary['services']);
    if (contribCount > 0) {
      chips.add(_Chip(
          '$contribCount contribution${contribCount > 1 ? 's' : ''} received'));
    }
    addChip('booking', summary['bookings']);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                isRestrict
                    ? 'Action required: complete payment setup'
                    : 'Secure Payments Upgrade',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.25),
              ),
              const SizedBox(height: 6),
              Text(
                isRestrict
                    ? 'To keep accepting payments and access your wallet, please complete payment setup now.'
                    : 'To help you receive earnings faster, manage withdrawals, and access your Nuru wallet, please complete your payment setup.',
                style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.45),
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('On your account',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: AppColors.textHint)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: chips),
                      if (pending != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Pending balance: ${pending['currency'] ?? ''} ${pending['amount'] ?? 0} · payable once setup is complete.',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const _Benefit(icon: Icons.account_balance_wallet_outlined,
                  text: 'Activate your wallet · all your earnings flow here'),
              const SizedBox(height: 10),
              const _Benefit(icon: Icons.arrow_forward,
                  text: 'Withdraw to mobile money or bank in minutes'),
              const SizedBox(height: 10),
              const _Benefit(icon: Icons.shield_outlined,
                  text: 'Bank-grade security & full transaction history'),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await mig.dismissWelcome();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const PayoutProfileScreen()));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Setup now',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              if (!isRestrict) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () async {
                      await mig.dismissWelcome();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('Remind me later',
                        style: TextStyle(
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Center(
                    child: Text(
                      'This is required to continue using monetized features.',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textHint),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.borderLight),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      );
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Benefit({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.4)),
            ),
          ),
        ],
      );
}

/// Show the welcome sheet. Locked-down (non-dismissable barrier) for
/// users in the "restrict" phase; otherwise a normal swipeable sheet.
Future<void> showMigrationWelcomeSheet(BuildContext context) {
  final mig = context.read<MigrationProvider>();
  final isRestrict = mig.phase == MigrationPhase.restrict;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: !isRestrict,
    enableDrag: !isRestrict,
    backgroundColor: Colors.transparent,
    builder: (_) => const MigrationWelcomeSheet(),
  );
}
