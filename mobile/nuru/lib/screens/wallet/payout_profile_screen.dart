import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/app_action_sheet.dart';
import 'package:provider/provider.dart';
import '../../core/services/wallet_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../providers/wallet_provider.dart';

/// PayoutProfileScreen - manage saved mobile money / bank accounts that Nuru
/// uses to send the user money. Mirrors the web `SettingsPayments` page.
class PayoutProfileScreen extends StatefulWidget {
  const PayoutProfileScreen({super.key});

  @override
  State<PayoutProfileScreen> createState() => _PayoutProfileScreenState();
}

class _PayoutProfileScreenState extends State<PayoutProfileScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _profiles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await WalletService.listProfiles();
    if (!mounted) return;
    setState(() {
      final data = res['data'];
      List rawList = const [];
      if (data is Map) {
        final p = data['profiles'];
        if (p is List) rawList = p;
      } else if (data is List) {
        rawList = data;
      }
      _profiles = rawList
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _loading = false;
    });
  }

  Future<void> _setDefault(String id) async {
    final res = await WalletService.setDefaultProfile(id);
    if (res['success'] == true) {
      _load();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Failed to set default')),
      );
    }
  }

  Future<void> _delete(String id) async {
    final res = await WalletService.deleteProfile(id);
    if (res['success'] == true) _load();
  }

  void _openAdd() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddProfileSheet(onSaved: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultCount = _profiles.where((p) => p['is_default'] == true).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: NuruSubPageAppBar(
        title: 'Payout methods',
        actions: [
          IconButton(
            onPressed: _openAdd,
            tooltip: 'Add method',
            icon: const AppIcon('plus', size: 20, color: AppColors.textPrimary),
          ),
        ],
      ),
      body: _loading
          ? const _PayoutSkeletonList()
          : _profiles.isEmpty
              ? _EmptyState(onAdd: _openAdd)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    // Summary chip row
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 12),
                      child: Row(
                        children: [
                          Text(
                            '${_profiles.length} method${_profiles.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                          ),
                          const SizedBox(width: 8),
                          Container(width: 3, height: 3,
                            decoration: const BoxDecoration(
                                color: AppColors.textTertiary,
                                shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(
                            defaultCount == 0
                                ? 'No default set'
                                : '$defaultCount default',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    ..._profiles.map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PayoutMethodCard(
                            profile: p,
                            onSetDefault: () => _setDefault(p['id'] as String),
                            onDelete: () => _delete(p['id'] as String),
                          ),
                        )),
                  ],
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium payout method card - provider-branded, credit-card inspired tile.
// ---------------------------------------------------------------------------
class _PayoutMethodCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  const _PayoutMethodCard({
    required this.profile,
    required this.onSetDefault,
    required this.onDelete,
  });

  bool get _isMobile => (profile['method_type'] ?? '') == 'mobile_money';
  bool get _isDefault => profile['is_default'] == true;

  String get _providerName {
    final prov = profile['provider'];
    final fromMap = prov is Map
        ? (prov['name'] ?? prov['display_name'] ?? '').toString()
        : '';
    if (fromMap.isNotEmpty) return fromMap;
    return (profile['network_name'] ??
            profile['bank_name'] ??
            profile['provider_id'] ??
            '')
        .toString();
  }

  String get _holder =>
      (profile['account_holder_name'] ?? profile['account_name'] ?? '')
          .toString();

  String get _number =>
      ((_isMobile ? profile['phone_number'] : profile['account_number']) ?? '')
          .toString();

  String get _currency => (profile['currency_code'] ?? '').toString();

  /// Mask all but last 4 digits of the account/phone for the big display.
  String get _maskedNumber {
    final digits = _number.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 4) return digits.isEmpty ? '••••' : digits;
    final last = digits.substring(digits.length - 4);
    final groups = (digits.length - 4) ~/ 4;
    final remainder = (digits.length - 4) % 4;
    final maskGroups = List.filled(groups, '••••');
    final maskRemainder = remainder > 0 ? '•' * remainder : '';
    final parts = <String>[
      if (maskRemainder.isNotEmpty) maskRemainder,
      ...maskGroups,
      last,
    ];
    return parts.join(' ');
  }

  // Brand palette guess by provider name. Falls back to neutral.
  ({Color start, Color end, Color accent}) get _brand {
    final n = _providerName.toLowerCase();
    if (n.contains('m-pesa') || n.contains('mpesa') || n.contains('vodacom')) {
      return (start: const Color(0xFF0F3D2E), end: const Color(0xFF1B7A4F), accent: const Color(0xFF54E2A0));
    }
    if (n.contains('tigo') || n.contains('mixx') || n.contains('yas')) {
      return (start: const Color(0xFF0D1A66), end: const Color(0xFF1E3DB8), accent: const Color(0xFF6FA8FF));
    }
    if (n.contains('airtel')) {
      return (start: const Color(0xFF6E0E1A), end: const Color(0xFFC2293A), accent: const Color(0xFFFFB1B9));
    }
    if (n.contains('halotel') || n.contains('halopesa')) {
      return (start: const Color(0xFF7A2E07), end: const Color(0xFFE0701A), accent: const Color(0xFFFFD4A8));
    }
    if (n.contains('ttcl') || n.contains('t-pesa')) {
      return (start: const Color(0xFF0A2E5C), end: const Color(0xFF1F6BC2), accent: const Color(0xFF9CCBFF));
    }
    if (n.contains('crdb')) {
      return (start: const Color(0xFF4A1010), end: const Color(0xFF8E1B1B), accent: const Color(0xFFFFC0C0));
    }
    if (n.contains('nmb')) {
      return (start: const Color(0xFF1A3D14), end: const Color(0xFF3A8A2E), accent: const Color(0xFFB6F2A6));
    }
    if (n.contains('nbc')) {
      return (start: const Color(0xFF0C1F3D), end: const Color(0xFF1F4B91), accent: const Color(0xFFB8D3FF));
    }
    if (n.contains('equity')) {
      return (start: const Color(0xFF5A0A0A), end: const Color(0xFFB2151F), accent: const Color(0xFFFFC8CC));
    }
    if (n.contains('kcb')) {
      return (start: const Color(0xFF0E3B1C), end: const Color(0xFF1F8A3E), accent: const Color(0xFFB7F4C7));
    }
    // Neutral premium fallback
    return (start: AppColors.surfaceDark, end: AppColors.primaryDark, accent: const Color(0xFFFFD66B));
  }

  @override
  Widget build(BuildContext context) {
    final brand = _brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openActions(context),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [brand.start, brand.end],
            ),
            boxShadow: [
              BoxShadow(
                color: brand.end.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative orb
              Positioned(
                right: -30, top: -30,
                child: Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
              Positioned(
                right: 30, bottom: -40,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.04),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(
                                _isMobile ? 'mobile' : 'card',
                                size: 13,
                                color: Colors.white.withOpacity(0.95),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isMobile ? 'Mobile money' : 'Bank account',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: Colors.white.withOpacity(0.95),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (_isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: brand.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIcon('check',
                                    size: 12, color: brand.start),
                                const SizedBox(width: 4),
                                Text(
                                  'Default',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                    color: brand.start,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: () => _openActions(context),
                          icon: AppIcon('more-vertical',
                              color: Colors.white.withOpacity(0.85)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    // Masked number
                    Text(
                      _maskedNumber,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.4,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Footer: holder + provider
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ACCOUNT HOLDER',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                  color: Colors.white.withOpacity(0.55),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _holder.isEmpty ? '-' : _holder,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
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
                              _currency.isEmpty ? '-' : _currency,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: Colors.white.withOpacity(0.55),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _providerName.isEmpty ? 'Provider' : _providerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openActions(BuildContext context) async {
    final v = await AppActionSheet.show<String>(
      context: context,
      title: _providerName.isEmpty ? 'Payout method' : _providerName,
      subtitle: _holder.isEmpty ? null : _holder,
      actions: [
        if (!_isDefault)
          const MenuAction(
              value: 'default', label: 'Set as default', icon: 'money'),
        const MenuAction(
            value: 'delete', label: 'Delete', icon: 'delete', destructive: true),
      ],
    );
    if (v == 'default') onSetDefault();
    if (v == 'delete') onDelete();
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const AppIcon('wallet',
                  color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 18),
            const Text(
              'No payout methods yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add a mobile money or bank account so Nuru can send you money.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                  height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const AppIcon('plus', size: 18, color: AppColors.textOnPrimary),
              label: const Text('Add method',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Branded color palette per provider - mirrors make_payment_screen.
({Color bg, Color bg2, Color fg}) _brandFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('mpesa') || n.contains('m-pesa') || n.contains('vodacom')) {
    return (bg: const Color(0xFFDCFCE7), bg2: const Color(0xFFBBF7D0), fg: const Color(0xFF15803D));
  }
  if (n.contains('airtel')) {
    return (bg: const Color(0xFFFEE2E2), bg2: const Color(0xFFFECACA), fg: const Color(0xFFB91C1C));
  }
  if (n.contains('tigo') || n.contains('mixx') || n.contains('yas')) {
    return (bg: const Color(0xFFDBEAFE), bg2: const Color(0xFFBFDBFE), fg: const Color(0xFF1D4ED8));
  }
  if (n.contains('halopesa') || n.contains('halotel')) {
    return (bg: const Color(0xFFFFEDD5), bg2: const Color(0xFFFED7AA), fg: const Color(0xFFB45309));
  }
  if (n.contains('crdb')) {
    return (bg: const Color(0xFFFEE2E2), bg2: const Color(0xFFFCA5A5), fg: const Color(0xFF991B1B));
  }
  if (n.contains('nmb')) {
    return (bg: const Color(0xFFDCFCE7), bg2: const Color(0xFFBBF7D0), fg: const Color(0xFF166534));
  }
  if (n.contains('nbc')) {
    return (bg: const Color(0xFFDBEAFE), bg2: const Color(0xFFBFDBFE), fg: const Color(0xFF1E40AF));
  }
  return (bg: AppColors.primarySoft, bg2: Colors.white, fg: AppColors.primary);
}

class _AddProfileSheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _AddProfileSheet({required this.onSaved});

  @override
  State<_AddProfileSheet> createState() => _AddProfileSheetState();
}

class _AddProfileSheetState extends State<_AddProfileSheet> {
  String _method = 'mobile_money';
  String? _providerId;
  bool _busy = false;
  bool _loadingProviders = false;
  bool _setDefault = true;
  List<Map<String, dynamic>> _providers = [];

  final _name = TextEditingController();
  final _number = TextEditingController();
  final _phone = TextEditingController();
  final _branch = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _phone.dispose();
    _branch.dispose();
    super.dispose();
  }

  Future<void> _loadProviders() async {
    setState(() => _loadingProviders = true);
    final country = context.read<WalletProvider>().currency == 'KES' ? 'KE' : 'TZ';
    final res = await WalletService.listProviders(countryCode: country, payout: true);
    if (!mounted) return;
    final data = res['data'];
    List rawList = const [];
    if (data is List) {
      rawList = data;
    } else if (data is Map) {
      final p = data['providers'];
      if (p is List) rawList = p;
    }
    final wantType = _method == 'mobile_money' ? 'mobile_money' : 'bank';
    final list = rawList
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((p) => (p['provider_type'] ?? '') == wantType)
        .where(_isProviderEnabled)
        .toList();
    setState(() {
      _providers = list;
      _loadingProviders = false;
      if (list.isNotEmpty && !list.any((p) => p['id'] == _providerId)) {
        _providerId = list.first['id'] as String;
      }
    });
  }

  bool _isProviderEnabled(Map<String, dynamic> p) {
    if (p['is_active'] == false) return false;
    final payout = p['supports_payout'] ?? p['is_payout_enabled'];
    return payout != false;
  }

  String _providerLabel(Map<String, dynamic> p) =>
      (p['name'] ?? p['display_name'] ?? p['code'] ?? '').toString();
  String _providerCode(Map<String, dynamic> p) => (p['code'] ?? '').toString();

  String get _currency => context.read<WalletProvider>().currency;

  Future<void> _save() async {
    if (_providerId == null) return _toast('Select a provider');
    if (_name.text.trim().isEmpty || _number.text.trim().isEmpty) {
      return _toast('Account name and number are required');
    }
    setState(() => _busy = true);
    final country = context.read<WalletProvider>().currency == 'KES' ? 'KE' : 'TZ';
    final provider = _providers.firstWhere(
      (p) => p['id'] == _providerId,
      orElse: () => <String, dynamic>{},
    );
    final label = _providerLabel(provider).isNotEmpty
        ? _providerLabel(provider)
        : _providerCode(provider);
    final res = await WalletService.createProfile({
      'method_type': _method == 'bank_account' ? 'bank' : 'mobile_money',
      'provider_id': _providerId,
      'country_code': country,
      'currency_code': _currency,
      'account_holder_name': _name.text.trim(),
      'account_number': _number.text.trim(),
      if (_method == 'mobile_money' && _phone.text.trim().isNotEmpty)
        'phone_number': _phone.text.trim(),
      if (_method == 'mobile_money') 'network_name': label,
      if (_method == 'bank_account') 'bank_name': label,
      if (_method == 'bank_account' && _branch.text.trim().isNotEmpty)
        'bank_branch': _branch.text.trim(),
      'is_default': _setDefault,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      widget.onSaved();
      Navigator.pop(context);
    } else {
      _toast(res['message']?.toString() ?? 'Failed to save');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _method == 'mobile_money';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add payout method',
                            style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text('Where should we send your money?',
                            style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const AppIcon('close', size: 18, color: AppColors.textSecondary),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF6F6F8),
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Method switcher - pill segmented
                    _MethodSwitcher(
                      value: _method,
                      onChanged: (v) {
                        setState(() {
                          _method = v;
                          _providerId = null;
                        });
                        _loadProviders();
                      },
                    ),
                    const SizedBox(height: 18),

                    // Provider section
                    _SectionLabel(isMobile ? 'Mobile money provider' : 'Bank'),
                    const SizedBox(height: 8),
                    if (_loadingProviders)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    else if (_providers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppColors.borderLight),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          isMobile
                              ? 'No mobile money providers available for your country.'
                              : 'No banks available for your country.',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500),
                        ),
                      )
                    else
                      Column(
                        children: [
                          for (int i = 0; i < _providers.length; i++) ...[
                            _ProviderTile(
                              label: _providerLabel(_providers[i]),
                              method: _method,
                              selected: _providerId == _providers[i]['id'],
                              onTap: () => setState(
                                  () => _providerId = _providers[i]['id'] as String),
                            ),
                            if (i != _providers.length - 1)
                              const SizedBox(height: 8),
                          ],
                        ],
                      ),

                    const SizedBox(height: 20),
                    _SectionLabel('Account details'),
                    const SizedBox(height: 8),
                    _LabeledField(
                      label: 'Account holder name',
                      controller: _name,
                      hint: 'e.g. John Mwakyusa',
                    ),
                    const SizedBox(height: 10),
                    _LabeledField(
                      label: isMobile ? 'Mobile money number' : 'Account number',
                      controller: _number,
                      hint: isMobile ? '07XX XXX XXX' : '0123456789012',
                      keyboardType: TextInputType.phone,
                    ),
                    if (isMobile) ...[
                      const SizedBox(height: 10),
                      _LabeledField(
                        label: 'Phone (international, optional)',
                        controller: _phone,
                        hint: '+255 7XX XXX XXX',
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                    if (!isMobile) ...[
                      const SizedBox(height: 10),
                      _LabeledField(
                        label: 'Branch (optional)',
                        controller: _branch,
                        hint: 'e.g. Mlimani City',
                      ),
                    ],

                    const SizedBox(height: 16),
                    // Default toggle row
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _setDefault = !_setDefault),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                              color: _setDefault
                                  ? AppColors.primary.withOpacity(0.5)
                                  : AppColors.borderLight),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: const AppIcon('money',
                                  size: 18, color: AppColors.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Set as default',
                                      style: GoogleFonts.inter(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text('We use this method first for payouts',
                                      style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          color: AppColors.textTertiary,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            _CheckSquare(checked: _setDefault),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Sticky save bar
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 14 + MediaQuery.of(context).padding.bottom),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEFEFF3))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Save payout method',
                          style: GoogleFonts.inter(
                              fontSize: 14.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textTertiary,
        ),
      );
}

class _MethodSwitcher extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _MethodSwitcher({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _seg('mobile_money', 'Mobile money', 'mobile'),
          _seg('bank_account', 'Bank', 'card'),
        ],
      ),
    );
  }

  Widget _seg(String v, String label, String icon) {
    final selected = value == v;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(icon,
                  size: 15,
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  final String label;
  final String method;
  final bool selected;
  final VoidCallback onTap;
  const _ProviderTile({
    required this.label,
    required this.method,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = _brandFor(label);
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFE5E7EB),
              width: selected ? 1.4 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [brand.bg, brand.bg2],
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(initial,
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w800, color: brand.fg)),
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
                  method == 'mobile_money' ? 'Mobile money' : 'Bank transfer',
                  style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? AppColors.primary : const Color(0xFFD1D5DB),
                  width: 2),
              color: selected ? AppColors.primary : Colors.white,
            ),
            alignment: Alignment.center,
            child: selected
                ? const AppIcon('check', size: 11, color: Colors.white)
                : null,
          ),
        ]),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  const _LabeledField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
                fontSize: 13.5,
                color: AppColors.textHint,
                fontWeight: FontWeight.w400),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckSquare extends StatelessWidget {
  final bool checked;
  const _CheckSquare({required this.checked});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked ? AppColors.primary : Colors.white,
        border: Border.all(
            color: checked ? AppColors.primary : const Color(0xFFD1D5DB),
            width: 2),
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child:
          checked ? const AppIcon('check', size: 13, color: Colors.white) : null,
    );
  }
}

// ─── Skeleton list mirroring the payout method card layout ───────────────────
class _PayoutSkeletonList extends StatelessWidget {
  const _PayoutSkeletonList();

  @override
  Widget build(BuildContext context) {
    return NuruSkeletonGroup(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Row(
              children: [
                NuruSkeleton.text(width: 90, height: 12),
                const SizedBox(width: 10),
                NuruSkeleton.text(width: 70, height: 10),
              ],
            ),
          ),
          for (int i = 0; i < 3; i++) ...[
            const _PayoutCardSkeleton(),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _PayoutCardSkeleton extends StatelessWidget {
  const _PayoutCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NuruSkeleton(width: 110, height: 22,
                borderRadius: BorderRadius.circular(999)),
              const Spacer(),
              NuruSkeleton(width: 72, height: 22,
                borderRadius: BorderRadius.circular(999)),
              const SizedBox(width: 6),
              NuruSkeleton.circle(size: 28),
            ],
          ),
          const SizedBox(height: 28),
          NuruSkeleton.text(width: 220, height: 22),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    NuruSkeleton(width: 90, height: 9),
                    SizedBox(height: 6),
                    NuruSkeleton(width: 130, height: 14),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  NuruSkeleton(width: 40, height: 9),
                  SizedBox(height: 6),
                  NuruSkeleton(width: 80, height: 14),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
