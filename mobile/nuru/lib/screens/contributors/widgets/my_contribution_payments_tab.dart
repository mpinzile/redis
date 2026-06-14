import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/received_payments_service.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../core/widgets/nuru_pagination.dart';
import '../../../core/widgets/nuru_skeleton.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/nuru_search_bar.dart';
import '../../payments/payment_receipt_screen.dart';
import '../contribution_details_screen.dart';

String _prettyTag(String raw) {
  if (raw.isEmpty) return raw;
  return raw
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// Redesigned My Contributions list — premium ticket-stub aesthetic with
/// summary header, filter chips and dashed-perforation cards.
class MyContributionPaymentsTab extends StatefulWidget {
  const MyContributionPaymentsTab({super.key});

  @override
  State<MyContributionPaymentsTab> createState() =>
      _MyContributionPaymentsTabState();
}

class _MyContributionPaymentsTabState extends State<MyContributionPaymentsTab>
    with AutomaticKeepAliveClientMixin {
  List<dynamic> _payments = [];
  Map<String, dynamic>? _pagination;
  bool _loading = true;
  int _page = 1;
  String _search = '';
  String _filter = 'all'; // all | credited | failed
  final _searchCtrl = TextEditingController();
  final Map<String, GlobalKey> _chipKeys = {
    'all': GlobalKey(), 'credited': GlobalKey(),
    'failed': GlobalKey(), 'pending': GlobalKey(),
  };

  void _selectFilter(String id) {
    setState(() => _filter = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: 0.5);
      }
    });
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ReceivedPaymentsService.myContributions(
      page: _page,
      limit: 15,
      search: _search.isNotEmpty ? _search : null,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        _payments = data is Map ? List.from(data['payments'] ?? []) : [];
        _pagination = data is Map && data['pagination'] is Map
            ? Map<String, dynamic>.from(data['pagination'])
            : null;
      }
    });
  }

  // Color tokens
  static const _navy = Color(0xFF0F172A);
  static const _coral = Color(0xFFEF6F61);
  static const _coralSoft = Color(0xFFFFF2EF);
  static const _green = Color(0xFF059669);
  static const _greenSoft = Color(0xFFE7F6EE);
  static const _amber = Color(0xFFD97706);
  static const _amberSoft = Color(0xFFFFF6E5);
  static const _gold = Color(0xFFE0B23A);
  static const _goldSoft = Color(0xFFFBF1D7);
  static const _ink = Color(0xFF1F2937);
  static const _muted = Color(0xFF6B7280);
  static const _hair = Color(0xFFEDEDEF);

  bool _isCredited(String s) =>
      s == 'completed' || s == 'confirmed' || s == 'credited';
  bool _isFailed(String s) => s == 'failed' || s == 'cancelled';

  List<Map<String, dynamic>> get _visible {
    final list = _payments.cast<Map<String, dynamic>>();
    if (_filter == 'credited') {
      return list
          .where((p) => _isCredited((p['status'] ?? '').toString()))
          .toList();
    }
    if (_filter == 'failed') {
      return list
          .where((p) => _isFailed((p['status'] ?? '').toString()))
          .toList();
    }
    if (_filter == 'pending') {
      return list.where((p) {
        final s = (p['status'] ?? '').toString();
        return !_isCredited(s) && !_isFailed(s);
      }).toList();
    }
    return list;
  }

  ({double total, int count, int credited, int failed, int pending, String currency})
      _summary() {
    double total = 0;
    int credited = 0, failed = 0, pending = 0;
    String currency = getActiveCurrency();
    for (final p in _payments) {
      final s = (p['status'] ?? '').toString();
      final amt = (p['gross_amount'] is num)
          ? (p['gross_amount'] as num).toDouble()
          : 0.0;
      if (_isCredited(s)) {
        credited++;
        total += amt;
      } else if (_isFailed(s)) {
        failed++;
      } else {
        pending++;
      }
      final c = (p['currency_code'] ?? '').toString();
      if (c.isNotEmpty) currency = c;
    }
    return (
      total: total,
      count: _payments.length,
      credited: credited,
      failed: failed,
      pending: pending,
      currency: currency,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = _summary();
    return NuruRefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _summaryCard(s),
          const SizedBox(height: 14),
          _searchField(),
          const SizedBox(height: 14),
          _filterChips(s),
          const SizedBox(height: 14),
          if (_loading)
            ..._skeletons()
          else if (_visible.isEmpty)
            _emptyState()
          else
            for (final p in _visible) _ticketCard(p),
          if (_pagination != null && (_pagination!['total_pages'] ?? 1) > 1)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: NuruPagination.fromMap(
                _pagination,
                onChanged: (p) {
                  setState(() => _page = p);
                  _load();
                },
              ),
            ),
        ],
      ),
    );
  }

  // ─── Summary header ─────────────────────────────────────────────────
  Widget _summaryCard(({double total, int count, int credited, int failed, int pending, String currency}) s) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _goldSoft.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Total Contributions',
              style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(s.total, currency: s.currency),
              style: GoogleFonts.sora(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                  letterSpacing: -0.4),
            ),
          ),
          const SizedBox(height: 2),
          Text('${s.count} transactions',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _muted)),
          const SizedBox(height: 10),
          Divider(height: 1, color: _gold.withOpacity(0.25)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _miniStat(s.credited.toString(), 'Credited', _green)),
            Expanded(child: _miniStat(s.failed.toString(), 'Failed', _coral)),
            Expanded(child: _miniStat(s.pending.toString(), 'Pending', _amber)),
          ]),
        ],
      ),
    );
  }

  Widget _miniStat(String count, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(count,
            style: GoogleFonts.sora(
                fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 1),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  // ─── Search ─────────────────────────────────────────────────────────
  Widget _searchField() {
    return Row(children: [
      Expanded(
        child: NuruSearchBar(
          controller: _searchCtrl,
          hintText: 'Search transactions',
          debounce: const Duration(milliseconds: 300),
          onChanged: (v) {
            _page = 1;
            _search = v.trim();
            _load();
          },
        ),
      ),
      const SizedBox(width: 10),
      GestureDetector(
        onTap: _openFilterSheet,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _filter == 'all' ? Colors.white : _navy,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _filter == 'all' ? _hair : _navy),
          ),
          child: Center(
            // Direct SvgPicture (rather than AppIcon) — on iOS, AppIcon's
            // colorFilter rendering on stroke-only SVGs occasionally
            // produced an invisible glyph. Using SvgPicture.asset with an
            // explicit srcIn ColorFilter is reliable on both platforms.
            child: SvgPicture.asset(
              'assets/icons/filter-icon.svg',
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(
                _filter == 'all' ? _navy : Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        Widget tile(String id, String label, Color? dot) {
          final active = _filter == id;
          return ListTile(
            onTap: () {
              _selectFilter(id);
              Navigator.pop(context);
            },
            leading: dot == null
                ? const AppIcon('circle', size: 16, color: _navy)
                : Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
            title: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _navy)),
            trailing: active
                ? const AppIcon('double-check', size: 18, color: _navy)
                : null,
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _hair,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Filter by status',
                      style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _navy)),
                ),
              ),
              tile('all', 'All', null),
              tile('credited', 'Credited', _green),
              tile('failed', 'Failed', _coral),
              tile('pending', 'Pending', _amber),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ─── Filter chips ───────────────────────────────────────────────────
  Widget _filterChips(({double total, int count, int credited, int failed, int pending, String currency}) s) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _chip('all', 'All', null),
        const SizedBox(width: 8),
        _chip('credited', 'Credited', _green),
        const SizedBox(width: 8),
        _chip('failed', 'Failed', _coral),
        const SizedBox(width: 8),
        _chip('pending', 'Pending', _amber),
      ]),
    );
  }

  Widget _chip(String id, String label, Color? dot) {
    final active = _filter == id;
    final bg = active ? _navy : Colors.white;
    final fg = active ? Colors.white : _ink;
    return GestureDetector(
      key: _chipKeys[id],
      onTap: () => _selectFilter(id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? _navy : _hair),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[
            Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }

  // ─── Skeletons (Nuru shimmer matching ticket-stub layout) ───────────
  List<Widget> _skeletons() => List.generate(
        4,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: NuruSkeletonGroup(
            child: ClipPath(
              clipper: _TicketCardClipper(),
              child: Container(
                height: 172,
                color: Colors.white,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Center(
                        child: NuruSkeleton.box(
                            width: 46, height: 46, radius: 12),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                            top: 14, right: 8, bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            NuruSkeleton.box(
                                width: 80, height: 18, radius: 6),
                            NuruSkeleton.text(width: 170, height: 13),
                            NuruSkeleton.text(width: 130, height: 11),
                            NuruSkeleton.box(
                                width: double.infinity,
                                height: 18,
                                radius: 6),
                            Row(children: [
                              NuruSkeleton.box(
                                  width: 60, height: 16, radius: 6),
                              const SizedBox(width: 5),
                              NuruSkeleton.box(
                                  width: 50, height: 16, radius: 6),
                            ]),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 14),
                        child: NuruSkeleton.box(
                            width: double.infinity,
                            height: 72,
                            radius: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
              color: _goldSoft, shape: BoxShape.circle),
          child: const AppIcon('donation', size: 32, color: _gold),
        ),
        const SizedBox(height: 14),
        Text('No contributions yet',
            style: GoogleFonts.sora(
                fontSize: 16, fontWeight: FontWeight.w700, color: _navy)),
        const SizedBox(height: 4),
        Text('Your contribution receipts will appear here.',
            style: GoogleFonts.inter(
                fontSize: 12.5, color: _muted, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  // ─── Ticket-stub card ───────────────────────────────────────────────
  // ─── Ticket-stub card (single clipped ticket with cutouts) ──────────
  Widget _ticketCard(Map<String, dynamic> p) {
    final status = (p['status'] ?? 'pending').toString();
    final amount = (p['gross_amount'] is num)
        ? (p['gross_amount'] as num).toDouble()
        : 0.0;
    final code = (p['transaction_code'] ?? '').toString();
    final eventName = (p['event_name'] ?? '').toString();
    // Always show a clean fixed label — event name is rendered separately
    // as the subtitle, and the raw backend description
    // (`Nuru · Event Contribution · For {event} · by {payer} · ref …`)
    // would otherwise duplicate it.
    const desc = 'Event Contribution';
    final method = (p['method_type'] ?? '').toString();
    final provider = (p['provider_name'] ?? '').toString();
    final ts = (p['completed_at'] ?? p['confirmed_at'] ?? p['initiated_at'])
        ?.toString();
    final currency = (p['currency_code'] ?? getActiveCurrency()).toString();
    final canRetry = p['can_retry'] == true || _isFailed(status);

    final credited = _isCredited(status);
    final failed = _isFailed(status);
    final tone = credited ? _green : (failed ? _coral : _amber);
    final toneSoft = credited
        ? _greenSoft
        : (failed ? _coralSoft : _amberSoft);
    final borderTone = tone.withOpacity(0.45);
    final subtitle = eventName.isNotEmpty ? 'For $eventName' : '';


    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentReceiptScreen(payment: p),
            ),
          ),
          child: SizedBox(
            height: 172,
            child: CustomPaint(
              foregroundPainter: _TicketCardPainter(
                borderColor: borderTone,
                dividerColor: borderTone.withOpacity(0.85),
              ),
              child: ClipPath(
                clipper: _TicketCardClipper(),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          // ── Left icon section
                          SizedBox(
                            width: 76,
                            child: Center(
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: toneSoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: borderTone),
                                ),
                                child: Center(
                                  child: AppIcon(
                                    failed
                                        ? 'warning'
                                        : (credited ? 'donation' : 'clock'),
                                    color: tone,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // ── Middle content section
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  top: 42, right: 6, bottom: 58),

                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    desc.isNotEmpty
                                        ? desc
                                        : 'Event Contribution',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.sora(
                                      color: _navy,
                                      fontSize: 15,
                                      height: 1.1,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  if (subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF536176),
                                        fontSize: 11,
                                        height: 1.15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                  if (ts != null) ...[
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      const AppIcon('calendar',
                                          size: 11,
                                          color: Color(0xFF66758C)),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          _prettyDate(ts),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            color: const Color(0xFF66758C),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ]),
                                  ],

                                ],
                              ),
                            ),

                          ),
                          // ── Right amount section
                          SizedBox(
                            width: 92,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  top: 14, right: 8, bottom: 12, left: 6),
                              child: Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: credited ? 72 : 56,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: borderTone),
                                      boxShadow: [
                                        BoxShadow(
                                          color: tone.withOpacity(0.12),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          currency,
                                          style: GoogleFonts.sora(
                                            color: tone,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            height: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            _amountOnly(amount, currency),
                                            style: GoogleFonts.sora(
                                              color: tone,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w900,
                                              height: 1,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!credited && canRetry) ...[
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 26,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          final eid = p['event_id']?.toString() ?? '';
                                          if (eid.isEmpty) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Cannot retry: event not found.')),
                                            );
                                            return;
                                          }
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ContributionDetailsScreen(
                                                initialEvent: {
                                                  'event_id': eid,
                                                  'event_name': p['event_name'] ?? '',
                                                  'event_cover_image': p['event_cover_image'] ?? '',
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const AppIcon('echo',
                                            size: 12, color: Colors.white),
                                        label: Text(
                                          'Retry',
                                          style: GoogleFonts.inter(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          elevation: 0,
                                          backgroundColor: tone,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      // ── Bottom chip row (code + method + provider)
                      Positioned(
                        left: 12,
                        right: 100,
                        bottom: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (code.isNotEmpty)
                              _InfoChip(prefix: '#', text: code),
                            if ((method.isNotEmpty || provider.isNotEmpty)) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                if (method.isNotEmpty)
                                  Flexible(
                                    child: _InfoChip(text: _prettyTag(method)),
                                  ),
                                if (method.isNotEmpty && provider.isNotEmpty)
                                  const SizedBox(width: 5),
                                if (provider.isNotEmpty)
                                  Flexible(
                                    child: _InfoChip(text: _prettyTag(provider)),
                                  ),
                              ]),
                            ],
                          ],
                        ),
                      ),
                      // ── Status ribbon
                      Positioned(
                        top: 8,
                        left: 92,
                        child: _StatusRibbon(
                          isCredited: credited,
                          label: credited
                              ? 'CREDITED'
                              : (failed
                                  ? 'FAILED'
                                  : _prettyTag(status).toUpperCase()),
                          color: tone,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _amountOnly(double amount, String currency) {
    final full = formatMoney(amount, currency: currency);
    final stripped = full.replaceFirst(RegExp('^$currency\\s*'), '');
    return stripped.isEmpty ? full : stripped;
  }

  String _prettyDate(String iso) {
    final raw = iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return iso.replaceAll('T', ' ').split('.').first;
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · ${h.toString().padLeft(2, '0')}:$mm $ampm';
  }
}

// ─── Ticket helpers ───────────────────────────────────────────────────

class _StatusRibbon extends StatelessWidget {
  final bool isCredited;
  final String label;
  final Color color;
  const _StatusRibbon({
    required this.isCredited,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: AppIcon(
            isCredited ? 'double-check' : 'close',
            size: 14,
            color: Colors.white,
          ),
        ),
      ),
      ClipPath(
        clipper: _RibbonClipper(),
        child: Container(
          height: 24,
          padding: const EdgeInsets.only(left: 10, right: 18),
          alignment: Alignment.centerLeft,
          color: color.withOpacity(0.10),
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    ]);
  }
}

class _InfoChip extends StatelessWidget {
  final String? iconName;
  final String? prefix;
  final String text;
  const _InfoChip({this.iconName, this.prefix, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix != null) ...[
            Text(
              prefix!,
              style: GoogleFonts.inter(
                color: const Color(0xFF4F6077),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
          ] else if (iconName != null) ...[
            AppIcon(iconName!, size: 10, color: const Color(0xFF4F6077)),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: const Color(0xFF26364D),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketCardClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const double radius = 16;
    const double cutoutRadius = 6;
    const double dividerX = 76;
    final double rightDividerX = size.width - 92;
    final path = Path();

    path.moveTo(radius, 0);
    path.lineTo(dividerX - cutoutRadius, 0);
    path.arcToPoint(
      const Offset(dividerX + cutoutRadius, 0),
      radius: const Radius.circular(cutoutRadius),
      clockwise: false,
    );
    path.lineTo(rightDividerX - cutoutRadius, 0);
    path.arcToPoint(
      Offset(rightDividerX + cutoutRadius, 0),
      radius: const Radius.circular(cutoutRadius),
      clockwise: false,
    );
    path.lineTo(size.width - radius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, radius);
    path.lineTo(size.width, size.height - radius);
    path.quadraticBezierTo(
        size.width, size.height, size.width - radius, size.height);
    path.lineTo(rightDividerX + cutoutRadius, size.height);
    path.arcToPoint(
      Offset(rightDividerX - cutoutRadius, size.height),
      radius: const Radius.circular(cutoutRadius),
      clockwise: false,
    );
    path.lineTo(dividerX + cutoutRadius, size.height);
    path.arcToPoint(
      Offset(dividerX - cutoutRadius, size.height),
      radius: const Radius.circular(cutoutRadius),
      clockwise: false,
    );
    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);
    path.lineTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_TicketCardClipper oldClipper) => false;
}

class _TicketCardPainter extends CustomPainter {
  final Color borderColor;
  final Color dividerColor;
  _TicketCardPainter({required this.borderColor, required this.dividerColor});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = _TicketCardClipper().getClip(size);
    canvas.drawPath(path, borderPaint);
  }


  @override
  bool shouldRepaint(_TicketCardPainter old) =>
      old.borderColor != borderColor || old.dividerColor != dividerColor;
}

class _RibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width - 12, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(size.width - 12, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_RibbonClipper oldClipper) => false;
}

