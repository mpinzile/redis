import 'dart:async';
import '../../../widgets/app_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/nuru_search_bar.dart';
import 'package:nuru/core/utils/money_format.dart' show getActiveCurrency, formatMoney;
import '../../../core/services/event_contributors_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../contributors/contribution_details_screen.dart';
import '../../contributors/contribution_insights_screen.dart';

/// "My Contributions" tab - events where the current user is a contributor.
/// Layout follows the supplied mockup: 3-tile summary (Total Pledged /
/// Total Paid / Active Pledges), search bar, filter chips
/// (All / Active / Complete / Pending) + sort, then per-event cards.
class MyContributionsTab extends StatefulWidget {
  const MyContributionsTab({super.key});
  @override
  State<MyContributionsTab> createState() => MyContributionsTabState();
}

enum _Filter { all, complete, pending }
enum _Sort { latest, oldest, amountDesc, amountAsc }

// Status palette (matches mockup tones).
const _kCompleteBg = Color(0xFFD6EFE0);
const _kCompleteFg = Color(0xFF0F7A4A);
const _kPendingBg  = Color(0xFFFFE2C7);
const _kPendingFg  = Color(0xFFB05A12);
const _kActiveBg   = Color(0xFFE3F1EA);
const _kActiveFg   = Color(0xFF0F7A4A);

class MyContributionsTabState extends State<MyContributionsTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic> _summary = {};
  String _searchTerm = '';
  Timer? _debounce;
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.latest;
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;

  /// Public - called from the global app-bar search button via GlobalKey.
  void toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        if (_searchTerm.isNotEmpty) {
          _searchTerm = '';
          _load();
        }
      }
    });
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _debounce?.cancel(); _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final res = await EventContributorsService.getMyContributions(
      search: _searchTerm.isEmpty ? null : _searchTerm,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      final data = res['data'] as Map? ?? {};
      final list = (data['events'] as List?) ?? [];
      setState(() {
        _events = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _summary = Map<String, dynamic>.from((data['summary'] as Map?) ?? {});
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message']?.toString() ?? 'Failed to load';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _searchTerm = v.trim());
      _load();
    });
  }

  String _statusOf(Map<String, dynamic> e) {
    final s = e['status']?.toString();
    if (s != null && s.isNotEmpty) return s;
    // Fallback for older API responses.
    final pledge = (e['pledge_amount'] as num?)?.toDouble() ?? 0;
    final paid = (e['total_paid'] as num?)?.toDouble() ?? 0;
    final balance = (e['balance'] as num?)?.toDouble() ?? 0;
    final pending = (e['pending_amount'] as num?)?.toDouble() ?? 0;
    if (pledge > 0 && balance == 0 && pending == 0) return 'complete';
    if (paid == 0 && pending == 0) return 'pending';
    return 'active';
  }

  List<Map<String, dynamic>> get _visible {
    var list = _events.where((e) {
      final s = _statusOf(e);
      switch (_filter) {
        case _Filter.all: return true;
        case _Filter.complete: return s == 'complete';
        case _Filter.pending: return s == 'pending' || s == 'active';
      }
    }).toList();
    int cmpDate(Map<String, dynamic> a, Map<String, dynamic> b) {
      final aT = (a['last_payment_at'] ?? a['event_start_date'] ?? '').toString();
      final bT = (b['last_payment_at'] ?? b['event_start_date'] ?? '').toString();
      return aT.compareTo(bT);
    }
    int cmpAmt(Map<String, dynamic> a, Map<String, dynamic> b) {
      final aA = (a['pledge_amount'] as num?)?.toDouble() ?? 0;
      final bA = (b['pledge_amount'] as num?)?.toDouble() ?? 0;
      return aA.compareTo(bA);
    }
    switch (_sort) {
      case _Sort.latest: list.sort((a, b) => cmpDate(b, a)); break;
      case _Sort.oldest: list.sort(cmpDate); break;
      case _Sort.amountDesc: list.sort((a, b) => cmpAmt(b, a)); break;
      case _Sort.amountAsc: list.sort(cmpAmt); break;
    }
    return list;
  }

  String _activeCurrency() {
    final c = _summary['currency']?.toString();
    if (c != null && c.isNotEmpty) return c;
    if (_events.isNotEmpty) {
      final fc = _events.first['currency']?.toString();
      if (fc != null && fc.isNotEmpty) return fc;
    }
    return getActiveCurrency();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      color: Colors.white,
      child: RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
        children: [
          _summaryCard(),
          const SizedBox(height: 16),
          if (_searchOpen) ...[
            _searchBar(),
            const SizedBox(height: 14),
          ],
          _filterRow(),
          const SizedBox(height: 14),
          if (_loading && _events.isEmpty)
            ...List.generate(3, (_) => const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _MyContributionCardSkeleton(),
            ))
          else if (_error != null)
            _errorState()
          else if (_visible.isEmpty)
            _emptyState()
          else ...[
            ..._visible.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _eventCard(e),
            )),
            const SizedBox(height: 8),
            _insightsCta(),
          ],
        ],
      ),
      ),
    );
  }

  // ── Summary card (3 tiles: Pledged / Paid / Active Pledges) ─────
  Widget _summaryCard() {
    final currency = _activeCurrency();
    final totalPledged = (_summary['total_pledged'] as num?)?.toDouble() ?? 0;
    final totalPaid = (_summary['total_paid'] as num?)?.toDouble() ?? 0;
    // "Pending" = pledges still owing (active + pending statuses).
    final pendingCount = ((_summary['pending_count'] as num?)?.toInt() ?? 0)
        + ((_summary['active_pledges'] as num?)?.toInt() ?? 0);

    final tiles = [
      _StatTileData(
        asset: 'assets/icons/wallet-icon.svg',
        label: 'Total Pledged',
        value: formatMoney(totalPledged, currency: currency),
      ),
      _StatTileData(
        asset: 'assets/icons/card-icon.svg',
        label: 'Total Paid',
        value: formatMoney(totalPaid, currency: currency),
      ),
      _StatTileData(
        asset: 'assets/icons/donation-icon.svg',
        label: 'Pending',
        value: '$pendingCount',
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      // Adaptive layout: stack vertically on narrow devices so currency
      // amounts (e.g. "TZS 1,250,000") are never truncated. On wider
      // screens keep the original 3-up row.
      child: LayoutBuilder(
        builder: (ctx, c) {
          final stacked = c.maxWidth < 360;
          if (stacked) {
            return Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  _statTile(asset: tiles[i].asset, label: tiles[i].label, value: tiles[i].value, stacked: true),
                  if (i != tiles.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Container(height: 1, color: AppColors.borderLight),
                    ),
                ],
              ],
            );
          }
          return Row(children: [
            Expanded(child: _statTile(asset: tiles[0].asset, label: tiles[0].label, value: tiles[0].value)),
            Container(width: 1, height: 44, color: AppColors.borderLight),
            Expanded(child: _statTile(asset: tiles[1].asset, label: tiles[1].label, value: tiles[1].value)),
            Container(width: 1, height: 44, color: AppColors.borderLight),
            Expanded(child: _statTile(asset: tiles[2].asset, label: tiles[2].label, value: tiles[2].value)),
          ]);
        },
      ),
    );
  }

  Widget _statTile({required String asset, required String label, required String value, bool stacked = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            asset, width: 16, height: 16,
            colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            // FittedBox + scaleDown keeps long amounts readable on every
            // screen size without truncating with an ellipsis.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: GoogleFonts.inter(
                  fontSize: stacked ? 14 : 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  height: 1.1,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }



  // ── Search ──────────────────────────────────────────────────────
  Widget _searchBar() {
    return NuruSearchBar(
      controller: _searchCtrl,
      hintText: 'Search my contributions',
      debounce: const Duration(milliseconds: 300),
      onChanged: _onSearchChanged,
    );
  }

  // ── Filter chips + sort ─────────────────────────────────────────
  Widget _filterRow() {
    return Row(children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _chip('All', _filter == _Filter.all, () => setState(() => _filter = _Filter.all)),
            const SizedBox(width: 8),
            _chip('Complete', _filter == _Filter.complete, () => setState(() => _filter = _Filter.complete)),
            const SizedBox(width: 8),
            _chip('Pending', _filter == _Filter.pending, () => setState(() => _filter = _Filter.pending)),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      _sortButton(),
    ]);
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.primary : AppColors.primary.withOpacity(0.5)),
        ),
        child: Text(label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppColors.primary,
          )),
      ),
    );
  }

  // Inline SVG for a sort glyph - keeps us off Material icons.
  static const String _sortSvg =
    '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M7 4v14M7 18l-3-3M7 18l3-3" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
    '<path d="M14 7h7M14 12h5M14 17h3" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'
    '</svg>';

  Widget _sortButton() {
    String label;
    switch (_sort) {
      case _Sort.latest: label = 'Latest'; break;
      case _Sort.oldest: label = 'Oldest'; break;
      case _Sort.amountDesc: label = 'Amount ↓'; break;
      case _Sort.amountAsc: label = 'Amount ↑'; break;
    }
    return GestureDetector(
      onTap: () async {
        final v = await AppActionSheet.show<_Sort>(
          context: context,
          title: 'Sort by',
          actions: [
            MenuAction(value: _Sort.latest, label: 'Latest', icon: 'time-fast', selected: _sort == _Sort.latest),
            MenuAction(value: _Sort.oldest, label: 'Oldest', icon: 'time-fast', selected: _sort == _Sort.oldest),
            MenuAction(value: _Sort.amountDesc, label: 'Amount: high to low', icon: 'money', selected: _sort == _Sort.amountDesc),
            MenuAction(value: _Sort.amountAsc, label: 'Amount: low to high', icon: 'money', selected: _sort == _Sort.amountAsc),
          ],
        );
        if (v != null) setState(() => _sort = v);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SvgPicture.string(_sortSvg, width: 14, height: 14,
            colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn)),
          const SizedBox(width: 6),
          Text(label,
            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(width: 2),
          Transform.rotate(
            angle: 1.5708, // 90deg → down chevron
            child: SvgPicture.asset(
              'assets/icons/chevron-right-icon.svg', width: 12, height: 12,
              colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn),
            ),
          ),
        ]),
      ),
    );
  }

  // ── States ──────────────────────────────────────────────────────
  Widget _errorState() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      Icon(Icons.error_outline, color: AppColors.error, size: 40),
      const SizedBox(height: 12),
      Text(_error ?? 'Failed to load', textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: _load, child: const Text('Retry')),
    ]),
  );

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    child: Column(children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: SvgPicture.asset(
          'assets/icons/donation-icon.svg', width: 30, height: 30,
          colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        _searchTerm.isEmpty && _filter == _Filter.all
          ? 'No contributions yet'
          : 'No matches',
        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      ),
      const SizedBox(height: 6),
      Text(
        _searchTerm.isEmpty && _filter == _Filter.all
          ? 'When an organiser adds you to their event, your contribution will appear here.'
          : 'Try a different filter or search term.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textTertiary, height: 1.4),
      ),
    ]),
  );

  // ── Event card (mockup style) ───────────────────────────────────
  Widget _eventCard(Map<String, dynamic> ev) {
    final name = ev['event_name']?.toString() ?? 'Event';
    final currency = ev['currency']?.toString() ?? getActiveCurrency();
    final pledge = (ev['pledge_amount'] as num?)?.toDouble() ?? 0;
    final paid = (ev['total_paid'] as num?)?.toDouble() ?? 0;
    final balance = (ev['balance'] as num?)?.toDouble() ?? 0;
    final cover = ev['event_cover_image_url']?.toString();
    final loc = ev['event_location']?.toString();
    final dateStr = _fmtDate(ev['event_start_date']?.toString());
    final status = _statusOf(ev);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ContributionDetailsScreen(initialEvent: ev)),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 78, height: 78,
                  color: AppColors.primary.withOpacity(0.10),
                  child: cover != null && cover.isNotEmpty
                      ? Image.network(cover, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _coverFallback())
                      : _coverFallback(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary,
                      ))),
                    const SizedBox(width: 6),
                    _statusBadge(status),
                    const SizedBox(width: 4),
                    SvgPicture.asset('assets/icons/chevron-right-icon.svg',
                      width: 14, height: 14,
                      colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
                  ]),
                  const SizedBox(height: 8),
                  if (dateStr.isNotEmpty)
                    _metaRow('assets/icons/calendar-icon.svg', dateStr),
                  if (loc != null && loc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _metaRow('assets/icons/location-icon.svg', loc),
                  ],
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _amountStat('Pledged', formatMoney(pledge, currency: currency))),
              Expanded(child: _amountStat('Paid', formatMoney(paid, currency: currency))),
              Expanded(child: _amountStat('Balance', formatMoney(balance, currency: currency))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _coverFallback() => Center(
    child: SvgPicture.asset('assets/icons/calendar-icon.svg',
      width: 26, height: 26,
      colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
  );

  Widget _metaRow(String iconAsset, String label) {
    return Row(children: [
      SvgPicture.asset(iconAsset, width: 13, height: 13,
        colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
      const SizedBox(width: 6),
      Flexible(child: Text(label,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary))),
    ]);
  }

  Widget _amountStat(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
        style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
      const SizedBox(height: 3),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
    ]);
  }

  Widget _statusBadge(String status) {
    String label;
    Color bg, fg;
    switch (status) {
      case 'complete':
        label = 'Complete'; bg = _kCompleteBg; fg = _kCompleteFg; break;
      case 'pending':
        label = 'Pending'; bg = _kPendingBg; fg = _kPendingFg; break;
      case 'active':
      default:
        label = 'Active'; bg = _kActiveBg; fg = _kActiveFg; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  // ── Bottom CTA: Insights ────────────────────────────────────────
  // Inline SVG (trending-up) - kept inline because no matching asset exists.
  static const String _trendUpSvg =
    '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M3 17l6-6 4 4 8-8" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
    '<path d="M14 7h7v7" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
    '</svg>';

  Widget _insightsCta() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: SvgPicture.string(_trendUpSvg, width: 20, height: 20,
            colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('See how your giving makes an impact',
              style: GoogleFonts.inter(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text('Explore insights and trends across your contributions.',
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary, height: 1.35)),
          ]),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => const ContributionInsightsScreen(),
            ));
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SvgPicture.string(_trendUpSvg, width: 14, height: 14,
              colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
            const SizedBox(width: 6),
            Text('Insights',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try { return DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal()); }
    catch (_) { return iso.split('T').first; }
  }
}

class _StatTileData {
  final String asset;
  final String label;
  final String value;
  const _StatTileData({required this.asset, required this.label, required this.value});
}

/// Shimmer skeleton that mirrors the real `_eventCard` layout:
/// cover thumbnail + title + status chip + 2 meta rows + 3 amount stats.
class _MyContributionCardSkeleton extends StatefulWidget {
  const _MyContributionCardSkeleton();
  @override
  State<_MyContributionCardSkeleton> createState() =>
      _MyContributionCardSkeletonState();
}

class _MyContributionCardSkeletonState
    extends State<_MyContributionCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _bar({double? width, double height = 12, double radius = 6}) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = 0.55 + _c.value * 0.30;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.borderLight.withOpacity(t),
            borderRadius: BorderRadius.circular(radius),
          ),
        );
      },
    );
  }

  Widget _block({required double w, required double h, double radius = 12}) =>
      _bar(width: w, height: h, radius: radius);

  Widget _amountStat() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bar(width: 44, height: 9),
          const SizedBox(height: 6),
          _bar(width: 70, height: 13),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _block(w: 78, h: 78, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: _bar(width: double.infinity, height: 14)),
                      const SizedBox(width: 6),
                      _bar(width: 56, height: 16, radius: 999),
                    ]),
                    const SizedBox(height: 12),
                    _bar(width: 140, height: 11),
                    const SizedBox(height: 8),
                    _bar(width: 100, height: 11),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.borderLight),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _amountStat()),
            Expanded(child: _amountStat()),
            Expanded(child: _amountStat()),
          ]),
        ],
      ),
    );
  }
}
