import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/services/event_contributors_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart' show formatMoney, getActiveCurrency;
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/nuru_skeleton.dart';

/// Premium "Contribution Insights" screen — surfaces a friendly impact line,
/// streak, top stats, a 12-month giving trend, payment-method breakdown,
/// biggest gift and the organisers the user supports most.
class ContributionInsightsScreen extends StatefulWidget {
  const ContributionInsightsScreen({super.key});

  @override
  State<ContributionInsightsScreen> createState() => _ContributionInsightsScreenState();
}

class _ContributionInsightsScreenState extends State<ContributionInsightsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final res = await EventContributorsService.getMyContributionInsights();
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _data = Map<String, dynamic>.from(res['data'] ?? {});
        _loading = false;
      });
    } else {
      setState(() {
        _error = (res['error'] ?? res['message'] ?? 'Could not load insights').toString();
        _loading = false;
      });
    }
  }

  String get _currency =>
      (_data['summary']?['currency']?.toString().isNotEmpty == true)
          ? _data['summary']['currency'].toString()
          : getActiveCurrency();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const NuruSubPageAppBar(title: 'Contribution Insights'),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: _loading
            ? _skeleton()
            : _error != null
                ? _errorState()
                : _content(),
      ),
    );
  }

  Widget _skeleton() => NuruSkeletonGroup(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // Hero gradient card placeholder
        NuruSkeleton.box(height: 196, radius: 22),
        const SizedBox(height: 16),
        // 4 quick stat tiles
        Row(children: List.generate(4, (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 3 ? 0 : 10),
            child: NuruSkeleton.box(height: 84, radius: 16),
          ),
        ))),
        const SizedBox(height: 18),
        NuruSkeleton.box(width: 200, height: 14, radius: 6),
        const SizedBox(height: 10),
        // Trend card
        NuruSkeleton.box(height: 170, radius: 18),
        const SizedBox(height: 18),
        NuruSkeleton.box(width: 130, height: 14, radius: 6),
        const SizedBox(height: 10),
        // Method rows
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(children: List.generate(3, (i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              NuruSkeleton.box(width: 36, height: 36, radius: 11),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                NuruSkeleton.box(width: 120, height: 12, radius: 6),
                const SizedBox(height: 8),
                NuruSkeleton.box(height: 6, radius: 6),
                const SizedBox(height: 8),
                NuruSkeleton.box(width: 80, height: 10, radius: 6),
              ])),
            ]),
          ))),
        ),
        const SizedBox(height: 18),
        NuruSkeleton.box(width: 160, height: 14, radius: 6),
        const SizedBox(height: 10),
        NuruSkeleton.box(height: 80, radius: 18),
        const SizedBox(height: 18),
        NuruSkeleton.box(width: 180, height: 14, radius: 6),
        const SizedBox(height: 10),
        // Top organisers rows
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(children: List.generate(3, (i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              NuruSkeleton.circle(size: 36),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                NuruSkeleton.box(width: 140, height: 12, radius: 6),
                const SizedBox(height: 6),
                NuruSkeleton.box(width: 60, height: 10, radius: 6),
              ])),
              NuruSkeleton.box(width: 60, height: 14, radius: 6),
            ]),
          ))),
        ),
      ],
    ),
  );



  Widget _errorState() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
    children: [
      Center(
        child: SvgPicture.asset('assets/icons/info-icon.svg',
          width: 36, height: 36,
          colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
      ),
      const SizedBox(height: 12),
      Center(child: Text(_error ?? 'Could not load',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary))),
      const SizedBox(height: 16),
      Center(
        child: TextButton(onPressed: _load, child: const Text('Try again')),
      ),
    ],
  );

  Widget _content() {
    final summary = Map<String, dynamic>.from(_data['summary'] ?? {});
    final counts = Map<String, dynamic>.from(_data['counts'] ?? {});
    final streak = (_data['streak_months'] as num?)?.toInt() ?? 0;
    final impact = _data['impact_message']?.toString() ?? '';
    final byMonth = (_data['by_month'] as List?)?.cast<Map>() ?? [];
    final byMethod = (_data['by_method'] as List?)?.cast<Map>() ?? [];
    final topOrgs = (_data['top_organisers'] as List?)?.cast<Map>() ?? [];
    final biggest = _data['biggest_contribution'] is Map
        ? Map<String, dynamic>.from(_data['biggest_contribution'])
        : null;
    final firstAt = _data['first_contribution_at']?.toString();
    final lastAt  = _data['last_contribution_at']?.toString();
    final onTime  = (_data['on_time_rate'] as num?)?.toDouble() ?? 0;
    final avg     = (_data['avg_per_event'] as num?)?.toDouble() ?? 0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _hero(summary, counts, streak, impact),
        const SizedBox(height: 16),
        _quickStats(counts, avg, onTime),
        const SizedBox(height: 18),
        _section('Giving over the last 12 months'),
        const SizedBox(height: 10),
        _trendCard(byMonth),
        const SizedBox(height: 18),
        _section('How you give'),
        const SizedBox(height: 10),
        _methodCard(byMethod),
        if (biggest != null) ...[
          const SizedBox(height: 18),
          _section('Your biggest gift'),
          const SizedBox(height: 10),
          _biggestCard(biggest),
        ],
        if (topOrgs.isNotEmpty) ...[
          const SizedBox(height: 18),
          _section('Organisers you support'),
          const SizedBox(height: 10),
          _topOrgsCard(topOrgs),
        ],
        if (firstAt != null || lastAt != null) ...[
          const SizedBox(height: 18),
          _journeyCard(firstAt, lastAt),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────── Hero
  Widget _hero(Map summary, Map counts, int streak, String impact) {
    final paid = (summary['total_paid'] as num?)?.toDouble() ?? 0;
    final pledged = (summary['total_pledged'] as num?)?.toDouble() ?? 0;
    final balance = (summary['total_balance'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            Color.lerp(AppColors.primary, Colors.black, 0.18) ?? AppColors.primary,
          ],
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.25),
            blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SvgPicture.asset('assets/icons/thunder-icon.svg', width: 12, height: 12,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
              const SizedBox(width: 4),
              Text('$streak mo streak',
                style: GoogleFonts.inter(
                  fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
          ),
          const Spacer(),
          Text('${counts['events_count'] ?? 0} events',
            style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.85))),
        ]),
        const SizedBox(height: 16),
        Text('Total contributed',
          style: GoogleFonts.inter(
            fontSize: 11.5, letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: Colors.white.withOpacity(0.85))),
        const SizedBox(height: 2),
        Text(formatMoney(paid, currency: _currency),
          style: GoogleFonts.inter(
            fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white,
            height: 1.05, letterSpacing: -0.5)),
        const SizedBox(height: 12),
        Row(children: [
          _heroChip('Pledged', formatMoney(pledged, currency: _currency)),
          const SizedBox(width: 8),
          _heroChip('Balance', formatMoney(balance, currency: _currency)),
        ]),
        if (impact.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SvgPicture.asset('assets/icons/sparkle-icon.svg', width: 16, height: 16,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
              const SizedBox(width: 8),
              Expanded(child: Text(impact,
                style: GoogleFonts.inter(
                  fontSize: 12, color: Colors.white, height: 1.4,
                  fontWeight: FontWeight.w500))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _heroChip(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
            style: GoogleFonts.inter(
              fontSize: 9.5, letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.85))),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────── Quick stats
  Widget _quickStats(Map counts, double avg, double onTime) {
    return Row(children: [
      Expanded(child: _statBox(
        iconAsset: 'assets/icons/users-icon.svg',
        label: 'Organisers',
        value: '${counts['organisations_supported'] ?? 0}',
      )),
      const SizedBox(width: 10),
      Expanded(child: _statBox(
        iconAsset: 'assets/icons/double-check-icon.svg',
        label: 'Completed',
        value: '${counts['complete_count'] ?? 0}',
      )),
      const SizedBox(width: 10),
      Expanded(child: _statBox(
        iconAsset: 'assets/icons/wallet-icon.svg',
        label: 'Avg / event',
        value: formatMoney(avg, currency: _currency),
        small: true,
      )),
      const SizedBox(width: 10),
      Expanded(child: _statBox(
        iconAsset: 'assets/icons/thunder-icon.svg',
        label: 'On-time',
        value: '${onTime.toStringAsFixed(0)}%',
      )),
    ]);
  }

  Widget _statBox({required String iconAsset, required String label,
      required String value, bool small = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(iconAsset, width: 14, height: 14,
              colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
        ),
        const SizedBox(height: 8),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: small ? 11 : 14,
            fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label,
          style: GoogleFonts.inter(
            fontSize: 9.5, color: AppColors.textTertiary,
            fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ─────────────────────────────────────────────── Trend
  Widget _trendCard(List<Map> months) {
    if (months.isEmpty) return _emptyCard('No giving history yet.');
    final maxAmount = months
        .map((m) => (m['amount'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final hasAny = maxAmount > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 130,
          child: hasAny
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: months.map((m) {
                    final amt = (m['amount'] as num?)?.toDouble() ?? 0;
                    final h = maxAmount == 0 ? 4.0 : (amt / maxAmount) * 110;
                    final isCurrent = m == months.last;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                              height: h.clamp(4, 110),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    AppColors.primary.withOpacity(isCurrent ? 1 : 0.85),
                                    AppColors.primary.withOpacity(isCurrent ? 0.65 : 0.45),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                )
              : Center(child: Text('No payments in the last 12 months.',
                  style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textTertiary))),
        ),
        const SizedBox(height: 8),
        Row(
          children: months.map((m) {
            final label = _monthLabelShort(m['month']?.toString() ?? '');
            return Expanded(
              child: Center(
                child: Text(label,
                  style: GoogleFonts.inter(
                    fontSize: 8.5, fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary)),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  String _monthLabelShort(String iso) {
    if (iso.length < 7) return '';
    final m = int.tryParse(iso.substring(5, 7)) ?? 0;
    const names = ['', 'J','F','M','A','M','J','J','A','S','O','N','D'];
    return (m >= 1 && m <= 12) ? names[m] : '';
  }

  // ─────────────────────────────────────────────── Method mix
  Widget _methodCard(List<Map> methods) {
    if (methods.isEmpty) return _emptyCard('No payments yet.');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        for (int i = 0; i < methods.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.borderLight),
          _methodRow(methods[i]),
        ],
      ]),
    );
  }

  Widget _methodRow(Map m) {
    final method = m['method']?.toString() ?? 'other';
    final amt = (m['amount'] as num?)?.toDouble() ?? 0;
    final count = (m['count'] as num?)?.toInt() ?? 0;
    final pct = (m['percent'] as num?)?.toDouble() ?? 0;
    final iconAsset = _methodIcon(method);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(iconAsset,
            width: 16, height: 16,
            colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(_humanMethod(method),
                style: GoogleFonts.inter(
                  fontSize: 12.5, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary))),
              Text('${pct.toStringAsFixed(0)}%',
                style: GoogleFonts.inter(
                  fontSize: 11.5, fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0, 1),
                minHeight: 5,
                backgroundColor: AppColors.primary.withOpacity(0.10),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 4),
            Text('$count payment${count == 1 ? '' : 's'} · ${formatMoney(amt, currency: _currency)}',
              style: GoogleFonts.inter(
                fontSize: 10.5, color: AppColors.textTertiary)),
          ]),
        ),
      ]),
    );
  }

  String _humanMethod(String m) {
    switch (m) {
      case 'mobile_money': return 'Mobile money';
      case 'bank': return 'Bank transfer';
      case 'card': return 'Card';
      case 'wallet': return 'Wallet';
      case 'cash': return 'Cash';
      case 'manual': return 'Recorded by organiser';
      default:
        final s = m.replaceAll('_', ' ').trim();
        return s.isEmpty ? 'Other' : s[0].toUpperCase() + s.substring(1);
    }
  }

  String _methodIcon(String method) {
    switch (method) {
      case 'bank': return 'assets/icons/wallet-icon.svg';
      case 'card': return 'assets/icons/card-icon.svg';
      case 'wallet': return 'assets/icons/wallet-icon.svg';
      case 'cash': return 'assets/icons/money-icon.svg';
      case 'mobile_money': return 'assets/icons/phone-icon.svg';
      case 'manual': return 'assets/icons/donation-icon.svg';
      default: return 'assets/icons/money-icon.svg';
    }
  }

  // ─────────────────────────────────────────────── Biggest
  Widget _biggestCard(Map<String, dynamic> b) {
    final amount = (b['amount'] as num?)?.toDouble() ?? 0;
    final cur = b['currency']?.toString() ?? _currency;
    final name = b['event_name']?.toString() ?? 'Event';
    final dStr = _formatDate(b['contributed_at']?.toString());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset('assets/icons/crown-icon.svg', width: 22, height: 22,
              colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatMoney(amount, currency: cur),
              style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
            if (dStr.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(dStr,
                  style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.textTertiary)),
              ),
          ]),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────── Top organisers
  Widget _topOrgsCard(List<Map> orgs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        for (int i = 0; i < orgs.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.borderLight),
          _orgRow(orgs[i], i + 1),
        ],
      ]),
    );
  }

  Widget _orgRow(Map o, int rank) {
    final name = o['name']?.toString().trim().isNotEmpty == true
        ? o['name'].toString() : 'Organiser';
    final amt = (o['amount'] as num?)?.toDouble() ?? 0;
    final events = (o['events'] as num?)?.toInt() ?? 0;
    final initials = name.split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty).take(2)
        .map((s) => s[0].toUpperCase()).join();
    // Try several common keys the API might return for the organiser photo.
    String? avatar;
    for (final k in const ['avatar_url','profile_image','profile_image_url',
        'image_url','photo','photo_url','picture','avatar']) {
      final v = o[k]?.toString();
      if (v != null && v.trim().isNotEmpty) { avatar = v.trim(); break; }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            shape: BoxShape.circle,
            image: (avatar != null && (avatar.startsWith('http://') || avatar.startsWith('https://')))
                ? DecorationImage(image: NetworkImage(avatar), fit: BoxFit.cover)
                : null,
          ),
          alignment: Alignment.center,
          child: (avatar != null && (avatar.startsWith('http://') || avatar.startsWith('https://')))
              ? null
              : Text(initials.isEmpty ? '?' : initials,
                  style: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text('$events event${events == 1 ? '' : 's'}',
              style: GoogleFonts.inter(
                fontSize: 10.5, color: AppColors.textTertiary)),
          ]),
        ),
        Text(formatMoney(amt, currency: _currency),
          style: GoogleFonts.inter(
            fontSize: 13, fontWeight: FontWeight.w800,
            color: AppColors.textPrimary)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('#$rank',
            style: GoogleFonts.inter(
              fontSize: 9.5, fontWeight: FontWeight.w800,
              color: AppColors.primary)),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────── Journey
  Widget _journeyCard(String? firstAt, String? lastAt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(children: [
        Expanded(child: _journeyCol('Started giving', _formatDate(firstAt))),
        Container(width: 1, height: 36, color: AppColors.borderLight),
        Expanded(child: _journeyCol('Last contribution', _formatDate(lastAt))),
      ]),
    );
  }

  Widget _journeyCol(String label, String value) => Column(children: [
    Text(label,
      style: GoogleFonts.inter(
        fontSize: 10, letterSpacing: 0.6,
        fontWeight: FontWeight.w700, color: AppColors.textTertiary)),
    const SizedBox(height: 4),
    Text(value.isEmpty ? '—' : value,
      style: GoogleFonts.inter(
        fontSize: 12.5, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary)),
  ]);

  // ─────────────────────────────────────────────── Helpers
  Widget _section(String title) => Text(title,
    style: GoogleFonts.inter(
      fontSize: 13.5, fontWeight: FontWeight.w700,
      color: AppColors.textPrimary));

  Widget _emptyCard(String label) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Center(child: Text(label,
      style: GoogleFonts.inter(
        fontSize: 12.5, color: AppColors.textTertiary))),
  );

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      return DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso.split('T').first;
    }
  }
}
