import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/wallet_service.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/migration_provider.dart';
import '../../providers/wallet_provider.dart';

/// Returns "TZ" if phone starts with +255/255, "KE" for +254/254, else null.
String? _regionFromPhone(String? phone) {
  if (phone == null) return null;
  final cleaned = phone.replaceAll(RegExp(r'[\s\-()]'), '');
  if (cleaned.startsWith('+255') || cleaned.startsWith('255')) return 'TZ';
  if (cleaned.startsWith('+254') || cleaned.startsWith('254')) return 'KE';
  return null;
}

/// Returns "TZ" / "KE" if the device locale ends in `_TZ` / `_KE`.
/// Falls back to null when the locale is unknown or unsupported.
String? _regionFromDeviceLocale() {
  try {
    // Platform.localeName is e.g. "en_TZ" / "sw_TZ" / "en_US".
    final loc = Platform.localeName.toUpperCase();
    if (loc.endsWith('_TZ') || loc.endsWith('-TZ')) return 'TZ';
    if (loc.endsWith('_KE') || loc.endsWith('-KE')) return 'KE';
  } catch (_) {}
  return null;
}

/// CountryConfirmSheet - first-login prompt asking the user to confirm
/// their country (Tanzania or Kenya). Detection priority:
///   1. Backend migration_status.country_guess (phone+ip+history-aware)
///   2. Phone prefix on the user record
///   3. Device locale (Platform.localeName)
///   4. Manual / default TZ
///
/// Persists via `/users/me/country`, then refreshes wallet so the UI flips
/// to the right currency.
class CountryConfirmSheet extends StatefulWidget {
  const CountryConfirmSheet({super.key});

  @override
  State<CountryConfirmSheet> createState() => _CountryConfirmSheetState();
}

class _CountryConfirmSheetState extends State<CountryConfirmSheet> {
  String? _selected;
  String _source = 'manual';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mig = context.read<MigrationProvider>();
      final auth = context.read<AuthProvider>();
      // 1) Backend guess
      final guess = mig.countryGuess;
      if (guess != null && guess['code'] != null) {
        setState(() {
          _selected = guess['code'].toString();
          _source = (guess['source'] ?? 'manual').toString();
        });
        return;
      }
      // 2) Phone prefix
      final phone = auth.user?['phone']?.toString();
      final fromPhone = _regionFromPhone(phone);
      if (fromPhone != null) {
        setState(() { _selected = fromPhone; _source = 'phone'; });
        return;
      }
      // 3) Device locale
      final fromLocale = _regionFromDeviceLocale();
      if (fromLocale != null) {
        setState(() { _selected = fromLocale; _source = 'locale'; });
        return;
      }
      // 4) Default TZ - user may override.
      setState(() { _selected = 'TZ'; _source = 'manual'; });
    });
  }

  Future<void> _save() async {
    if (_selected == null) return;
    setState(() => _busy = true);
    final res = await WalletService.confirmCountry(countryCode: _selected!, source: _source);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      // Refresh wallet so the new currency picks up immediately.
      context.read<WalletProvider>().refresh();
      // Refresh the auth user so country/currency fields update everywhere.
      context.read<AuthProvider>().refreshUser();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Could not save country')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 16),
            const Text('Where are you?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text(
              'We use this to show prices in your local currency and let you pay with the right mobile money providers.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),
            _CountryTile(
              flag: '🇹🇿', name: 'Tanzania', currency: 'TZS',
              selected: _selected == 'TZ',
              onTap: () => setState(() { _selected = 'TZ'; _source = 'manual'; }),
            ),
            const SizedBox(height: 8),
            _CountryTile(
              flag: '🇰🇪', name: 'Kenya', currency: 'KES',
              selected: _selected == 'KE',
              onTap: () => setState(() { _selected = 'KE'; _source = 'manual'; }),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy || _selected == null ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  final String flag, name, currency;
  final bool selected;
  final VoidCallback onTap;
  const _CountryTile({
    required this.flag, required this.name, required this.currency,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text('Pays in $currency',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                ],
              ),
            ),
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
    );
  }
}

/// Helper to launch the sheet from anywhere (post-login splash, settings).
Future<void> showCountryConfirmSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const CountryConfirmSheet(),
  );
}
