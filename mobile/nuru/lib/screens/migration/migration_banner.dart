import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/migration_provider.dart';
import '../wallet/payout_profile_screen.dart';

/// Surface keys mirror the web `MigrationSurface` so copy stays consistent.
enum MigrationSurface { events, services, wallet, tickets, bookings, generic }

const Map<MigrationSurface, _BannerCopy> _copy = {
  MigrationSurface.events: _BannerCopy(
    'Your events can receive payouts after payment setup.',
    'Complete setup so contributions and ticket sales reach you instantly.',
  ),
  MigrationSurface.services: _BannerCopy(
    'Complete payment setup to continue receiving bookings and earnings.',
    'New bookings will pause until your payout details are saved.',
  ),
  MigrationSurface.wallet: _BannerCopy(
    'Activate your wallet by completing payment setup.',
    'Your balance, withdrawals, and history live here once setup is done.',
  ),
  MigrationSurface.tickets: _BannerCopy(
    'Payment setup required to continue ticket sales settlements.',
    "We'll release ticket revenue to your wallet as soon as you're set up.",
  ),
  MigrationSurface.bookings: _BannerCopy(
    'Set up payments to confirm new paid bookings.',
    "Customers can still browse · but checkouts pause until you're ready.",
  ),
  MigrationSurface.generic: _BannerCopy(
    'Complete your payment setup to keep earning.',
    'Takes about a minute. Mobile money or bank · your choice.',
  ),
};

class _BannerCopy {
  final String headline;
  final String sub;
  const _BannerCopy(this.headline, this.sub);
}

/// MigrationBanner - mobile companion to the web banner. Drop it at the top
/// of any monetized page (events, services, wallet, tickets, bookings).
/// Hides automatically when the user has no migration debt.
class MigrationBanner extends StatefulWidget {
  final MigrationSurface surface;
  final EdgeInsets margin;

  const MigrationBanner({
    super.key,
    required this.surface,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 4),
  });

  @override
  State<MigrationBanner> createState() => _MigrationBannerState();
}

class _MigrationBannerState extends State<MigrationBanner>
    with WidgetsBindingObserver {
  bool _hidden = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Kick a refresh immediately + start a soft poll while the banner
    // is visible. Auto-clears the banner once the user finishes payout setup.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshIfNeeded());
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refreshIfNeeded());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshIfNeeded();
  }

  Future<void> _refreshIfNeeded() async {
    if (!mounted) return;
    final mig = context.read<MigrationProvider>();
    if (!mig.needsSetup) return;
    final uid = context.read<AuthProvider>().user?['id']?.toString();
    if (uid == null || uid.isEmpty) return;
    await mig.load(uid);
  }

  @override
  Widget build(BuildContext context) {
    final mig = context.watch<MigrationProvider>();
    if (!mig.needsSetup || _hidden) return const SizedBox.shrink();

    final phase = mig.phase;
    final isRestrict = phase == MigrationPhase.restrict;
    final isNudge = phase == MigrationPhase.nudge;
    final copy = _copy[widget.surface]!;

    final accent = isRestrict
        ? AppColors.error
        : isNudge
            ? const Color(0xFFD97706) // amber-600
            : AppColors.primary;
    final bg = accent.withOpacity(0.08);
    final border = accent.withOpacity(0.30);

    return Padding(
      padding: widget.margin,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isRestrict ? Icons.lock_outline : Icons.account_balance_wallet_outlined,
                size: 20,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(copy.headline,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.3)),
                  const SizedBox(height: 4),
                  Text(copy.sub,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4)),
                  const SizedBox(height: 10),
                  Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PayoutProfileScreen(),
                      )),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('Setup now',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward, size: 13, color: Colors.white),
                        ]),
                      ),
                    ),
                    if (!isRestrict) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _hidden = true),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                          child: Text('Not now',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textTertiary)),
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
            if (!isRestrict)
              GestureDetector(
                onTap: () => setState(() => _hidden = true),
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.close, size: 18, color: AppColors.textHint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
