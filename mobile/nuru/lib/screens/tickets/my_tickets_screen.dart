import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_refresh_indicator.dart';
import '../../core/services/ticketing_service.dart';
import '../../core/utils/money_format.dart' show getActiveCurrency;
import '../../core/l10n/l10n_helper.dart';
import '../migration/migration_banner.dart';
import 'widgets/my_ticket_payments_tab.dart';
import 'widgets/my_reservations_section.dart';
import 'ticket_details_screen.dart';
import 'browse_tickets_screen.dart';
import '../../core/widgets/nuru_search_bar.dart';
import '../../core/widgets/nuru_skeleton.dart';

/// My Tickets - premium redesign matching the mobile mockup.
/// App bar mirrors the home page (logo + bell). Tabs: Upcoming / Past / Cancelled / Payments.
class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});
  @override
  State<MyTicketsScreen> createState() => MyTicketsScreenState();
}

class MyTicketsScreenState extends State<MyTicketsScreen> {
  static const _tabs = ['All', 'Upcoming', 'Past', 'Cancelled', 'Payments'];
  int _activeTab = 0;
  bool _searchOpen = false;

  void toggleSearch() => setState(() => _searchOpen = !_searchOpen);

  List<dynamic> _tickets = [];
  List<dynamic> _upcomingTickets = [];
  bool _loading = true;
  int _page = 1;
  Map<String, dynamic>? _pagination;
  String _search = '';
  final TextEditingController _searchCtl = TextEditingController();
  /// 'all' | 'active' | 'used'
  String _statusFilter = 'all';

  static const _cacheKey = 'cache_my_tickets_v1';
  static const _cacheUpcomingKey = 'cache_my_tickets_upcoming_v1';

  final ScrollController _tabsScrollCtrl = ScrollController();
  final List<GlobalKey> _tabKeys = List.generate(_tabs.length, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    _hydrateFromCache().then((_) => _load());
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _tabsScrollCtrl.dispose();
    super.dispose();
  }

  void _selectTab(int i) {
    setState(() => _activeTab = i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveTabIntoView());
  }

  void _scrollActiveTabIntoView() {
    if (!mounted) return;
    final ctx = _tabKeys[_activeTab].currentContext;
    if (ctx == null || !_tabsScrollCtrl.hasClients) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final viewportWidth = _tabsScrollCtrl.position.viewportDimension;
    final tabOffset = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject()).dx;
    final tabWidth = box.size.width;
    final currentScroll = _tabsScrollCtrl.offset;
    final tabCenterAbs = currentScroll + tabOffset + tabWidth / 2;
    final target = (tabCenterAbs - viewportWidth / 2).clamp(
      _tabsScrollCtrl.position.minScrollExtent,
      _tabsScrollCtrl.position.maxScrollExtent,
    );
    _tabsScrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Future<void> _hydrateFromCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_cacheKey);
      final upRaw = sp.getString(_cacheUpcomingKey);
      if (!mounted) return;
      setState(() {
        if (raw != null) {
          final d = jsonDecode(raw);
          if (d is List) _tickets = d;
        }
        if (upRaw != null) {
          final d = jsonDecode(upRaw);
          if (d is List) _upcomingTickets = d;
        }
        if (_tickets.isNotEmpty || _upcomingTickets.isNotEmpty) _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _persistCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_cacheKey, jsonEncode(_tickets));
      await sp.setString(_cacheUpcomingKey, jsonEncode(_upcomingTickets));
    } catch (_) {}
  }

  Future<void> _load() async {
    if (_tickets.isEmpty && _upcomingTickets.isEmpty) {
      setState(() => _loading = true);
    }
    final results = await Future.wait([
      TicketingService.getMyTickets(page: _page, search: _search.isNotEmpty ? _search : null),
      TicketingService.getMyUpcomingTickets(),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      final res = results[0];
      if (res['success'] == true) {
        final data = res['data'];
        _tickets = data is Map ? (data['tickets'] ?? []) : (data is List ? data : []);
        if (data is Map && data['pagination'] != null) {
          _pagination = data['pagination'] is Map<String, dynamic> ? data['pagination'] : null;
        }
      }
      final upRes = results[1];
      if (upRes['success'] == true) {
        final upData = upRes['data'];
        _upcomingTickets = upData is Map ? (upData['tickets'] ?? []) : (upData is List ? upData : []);
      }
    });
    _persistCache();
  }

  // ─── Filtering by tab ──────────────────────────────────────────────────────
  bool _isCancelled(dynamic t) {
    final s = (t is Map ? t['status']?.toString() : '') ?? '';
    return s == 'cancelled' || s == 'rejected';
  }
  bool _isPast(dynamic t) {
    if (_isCancelled(t)) return false;
    if (t is! Map) return false;
    final ev = t['event'] is Map ? t['event'] as Map : const {};
    final s = ev['start_date']?.toString() ?? '';
    if (s.isEmpty) return false;
    try {
      final d = DateTime.parse(s);
      return DateTime(d.year, d.month, d.day).isBefore(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));
    } catch (_) { return false; }
  }

  bool _matchesSearch(dynamic t) {
    if (_search.trim().isEmpty) return true;
    if (t is! Map) return false;
    final q = _search.trim().toLowerCase();
    final ev = t['event'] is Map ? t['event'] as Map : const {};
    final hay = [
      ev['name'], ev['title'], ev['location'],
      t['event_name'], t['ticket_class_name'], t['code'], t['reference'],
    ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
    return hay.contains(q);
  }

  List<dynamic> get _filteredTickets {
    final base = switch (_activeTab) {
      0 => _tickets,
      1 => _tickets.where((t) => !_isPast(t) && !_isCancelled(t)),
      2 => _tickets.where(_isPast),
      3 => _tickets.where(_isCancelled),
      _ => _tickets,
    };
    Iterable<dynamic> filtered = base.where(_matchesSearch);
    if (_statusFilter == 'active') {
      filtered = filtered.where((t) => !(t is Map && t['checked_in'] == true));
    } else if (_statusFilter == 'used') {
      filtered = filtered.where((t) => t is Map && t['checked_in'] == true);
    }
    return filtered.toList();
  }

  Future<void> _openFilterSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget tile(String value, String label, IconData icon) {
          final active = _statusFilter == value;
          return ListTile(
            leading: Icon(icon, color: active ? AppColors.primary : AppColors.textSecondary),
            title: Text(label, style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AppColors.primary : AppColors.textPrimary,
            )),
            trailing: active ? Icon(Icons.check_rounded, color: AppColors.primary) : null,
            onTap: () => Navigator.pop(ctx, value),
          );
        }
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(alignment: Alignment.centerLeft, child: Text('Filter tickets',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700))),
            ),
            const SizedBox(height: 4),
            tile('all', 'All tickets', Icons.confirmation_num_outlined),
            tile('active', 'Active (not used)', Icons.qr_code_2_rounded),
            tile('used', 'Used at the gate', Icons.do_not_disturb_on_outlined),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
    if (selected != null && mounted) setState(() => _statusFilter = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: _activeTab == 4
                ? Column(children: [
                    const SizedBox(height: 8),
                    _buildTabPills(),
                    const SizedBox(height: 6),
                    if (_searchOpen)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: _buildSearchBar(),
                      ),
                    SizedBox(height: _searchOpen ? 8 : 14),
                    Expanded(child: MyTicketPaymentsTab(search: _search)),
                  ])
                : NuruRefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                      children: [
                        _buildTabPills(),
                        const SizedBox(height: 6),
                        if (_searchOpen)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: _buildSearchBar(),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: MigrationBanner(
                            surface: MigrationSurface.tickets,
                            margin: EdgeInsets.only(top: _searchOpen ? 8 : 14, bottom: 8),
                          ),
                        ),
                        // Pending reservations (airline-style holds)
                        MyReservationsSection(onChanged: _load),
                        if (_loading)
                          ..._buildSkeletons()
                        else if (_filteredTickets.isEmpty)
                          _buildEmpty()
                        else
                          ..._filteredTickets.map((t) => Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: _ticketCard(t),
                          )),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPills() {
    return SingleChildScrollView(
      controller: _tabsScrollCtrl,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final active = _activeTab == i;
          return GestureDetector(
            key: _tabKeys[i],
            onTap: () => _selectTab(i),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
              margin: const EdgeInsets.only(right: 22),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? AppColors.secondary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
              child: Text(
                _tabs[i],
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColors.textPrimary : AppColors.textSecondary,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }


  Widget _buildSearchBar() {
    return Row(children: [
      Expanded(
        child: NuruSearchBar(
          controller: _searchCtl,
          hintText: 'Search tickets…',
          debounce: const Duration(milliseconds: 200),
          onChanged: (v) => setState(() => _search = v),
        ),
      ),
      const SizedBox(width: 10),
      GestureDetector(
        onTap: _openFilterSheet,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _statusFilter == 'all' ? Colors.white : AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _statusFilter == 'all' ? const Color(0xFFEDEDF2) : AppColors.primary.withOpacity(0.5)),
          ),
          child: Center(child: _FilterIcon(active: _statusFilter != 'all')),
        ),
      ),
    ]);
  }

  // ─── Ticket card (mockup style) ────────────────────────────────────────────
  Widget _ticketCard(dynamic ticket) {
    final t = ticket is Map<String, dynamic> ? ticket : <String, dynamic>{};
    final event = t['event'] is Map<String, dynamic> ? t['event'] as Map<String, dynamic> : <String, dynamic>{};
    final eventName = event['name']?.toString() ?? t['event_name']?.toString() ?? t['ticket_class_name']?.toString() ?? 'Event';
    final cover = event['cover_image']?.toString() ?? '';
    final location = event['location']?.toString() ?? '';
    final ticketClass = (t['ticket_class_name'] ?? t['ticket_class'])?.toString() ?? '';
    final status = t['status']?.toString() ?? 'pending';
    final checkedIn = t['checked_in'] == true;
    final quantity = t['quantity'] ?? 1;
    final totalAmount = t['total_amount'];
    // Active currency wins so KE accounts never see a stale TZS on legacy rows.
    final currency = getActiveCurrency();
    DateTime? d;
    try { d = DateTime.parse(event['start_date']?.toString() ?? ''); } catch (_) {}
    final time = (event['start_time']?.toString() ?? '');
    final timeShort = time.length >= 5 ? time.substring(0, 5) : '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TicketDetailsScreen(ticket: t)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEDEDF2)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.025), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 88, height: 88,
                      child: cover.isNotEmpty
                          ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover, errorWidget: (_, __, ___) => _coverFallback())
                          : _coverFallback(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badges row
                        Row(
                          children: [
                            if (ticketClass.isNotEmpty) _classBadge(ticketClass),
                            const Spacer(),
                            if (checkedIn) _usedBadge() else _statusBadge(status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(eventName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 6),
                        if (d != null)
                          _metaRow('assets/icons/calendar-icon.svg',
                            '${_shortDate(d)}${timeShort.isNotEmpty ? "  •  $timeShort" : ""}'),
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _metaRow('assets/icons/location-icon.svg', location),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: const Color(0xFFF1F1F4)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('${quantity is int && quantity > 1 ? "$quantity Tickets" : "1 Ticket"}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text(totalAmount != null ? '$currency ${_formatAmount(totalAmount)}' : '-',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverFallback() => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [AppColors.primarySoft, Color(0xFFFFFFFF)],
      ),
    ),
    child: Center(
      child: SvgPicture.asset('assets/icons/ticket-icon.svg', width: 22, height: 22,
        colorFilter: ColorFilter.mode(AppColors.textHint.withOpacity(0.5), BlendMode.srcIn)),
    ),
  );

  Widget _metaRow(String svg, String text) => Row(
    children: [
      SvgPicture.asset(svg, width: 12, height: 12,
        colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
      ),
    ],
  );

  Widget _classBadge(String c) {
    final lower = c.toLowerCase();
    Color bg; Color fg;
    if (lower.contains('vip')) { bg = const Color(0xFFEDE9FE); fg = const Color(0xFF6D28D9); }
    else if (lower.contains('premium') || lower.contains('platinum')) { bg = const Color(0xFFFEF3C7); fg = const Color(0xFFB45309); }
    else { bg = AppColors.primarySoft; fg = AppColors.primary; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(c.toUpperCase(), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: fg, letterSpacing: 0.5)),
    );
  }

  Widget _statusBadge(String s) {
    Color bg; Color fg; String label = s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '';
    switch (s) {
      case 'confirmed': bg = AppColors.successSoft; fg = AppColors.success; break;
      case 'approved':  bg = const Color(0x142471E7); fg = AppColors.blue; break;
      case 'pending':   bg = const Color(0x1AFECA08); fg = const Color(0xFFB45309); break;
      case 'cancelled':
      case 'rejected':  bg = const Color(0x14DC2626); fg = AppColors.error; break;
      default:          bg = const Color(0x142471E7); fg = AppColors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _usedBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded,
              size: 11, color: AppColors.success),
          const SizedBox(width: 4),
          Text('USED',
              style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                  letterSpacing: 0.6)),
        ]),
      );

  // ─── Empty + skeletons ─────────────────────────────────────────────────────
  Widget _buildEmpty() {
    // 'All' = 0, 'Upcoming' = 1 → Browse Tickets CTA makes sense.
    // 'Past' = 2 / 'Cancelled' = 3 → CTA would be misleading.
    final showBrowseCta = _activeTab == 0 || _activeTab == 1;
    final title = switch (_activeTab) {
      2 => 'No past tickets',
      3 => 'No cancelled tickets',
      _ => 'No tickets yet',
    };
    final hint = switch (_activeTab) {
      2 => 'Tickets you’ve already used will show up here.',
      3 => 'Cancellations and refunds will appear here.',
      _ => 'Browse events and purchase tickets to see them here.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
      child: Column(
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFEDEDF2))),
            child: Center(
              child: SvgPicture.asset('assets/icons/ticket-icon.svg', width: 28, height: 28,
                colorFilter: ColorFilter.mode(AppColors.textHint.withOpacity(0.6), BlendMode.srcIn)),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(hint, textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textTertiary)),
          if (showBrowseCta) ...[
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BrowseTicketsScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                child: Text('Browse Tickets',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildSkeletons() {
    return List.generate(4, (_) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: NuruSkeletonGroup(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEDEDF2)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NuruSkeleton.box(width: 88, height: 88, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    NuruSkeleton.box(width: 44, height: 16, radius: 6),
                    const Spacer(),
                    NuruSkeleton.box(width: 60, height: 16, radius: 6),
                  ]),
                  const SizedBox(height: 12),
                  NuruSkeleton.text(width: 180, height: 12),
                  const SizedBox(height: 10),
                  NuruSkeleton.text(width: 140, height: 10),
                  const SizedBox(height: 6),
                  NuruSkeleton.text(width: 110, height: 10),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Container(height: 1, color: const Color(0xFFF1F1F4)),
            const SizedBox(height: 12),
            Row(children: [
              NuruSkeleton.text(width: 70, height: 10),
              const Spacer(),
              NuruSkeleton.text(width: 80, height: 12),
            ]),
          ]),
        ),
      ),
    ));
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────
  String _shortDate(DateTime d) {
    const wk = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${wk[d.weekday-1]}, ${d.day} ${mo[d.month-1]} ${d.year}';
  }

  String _formatAmount(dynamic v) {
    if (v == null) return '0';
    final n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
}

/// Tiny custom filter icon (3 horizontal lines, varied widths).
/// Used since no asset filter SVG exists in the bundle.
class _FilterIcon extends StatelessWidget {
  const _FilterIcon({this.active = false});
  final bool active;
  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textPrimary;
    return SizedBox(
      width: 18, height: 14,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _bar(width: 18, color: color),
          _bar(width: 12, color: color),
          _bar(width: 7, color: color),
        ],
      ),
    );
  }
  Widget _bar({required double width, required Color color}) => Container(
    height: 2, width: width,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
  );
}
