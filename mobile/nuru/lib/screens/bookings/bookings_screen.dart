import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/widgets/amount_input.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';

import '../../core/services/user_services_service.dart';
import '../../core/utils/money_format.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../providers/wallet_provider.dart';
import '../migration/migration_banner.dart';
import 'booking_detail_screen.dart';
import 'sponsor_requests_screen.dart';
import '../../core/widgets/nuru_refresh.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../core/widgets/nuru_search_bar.dart';

enum BookingsMode { vendor, organizer }

/// Bookings inbox.
/// - vendor (Manage Bookings):  incoming requests on services I offer (clients booking me).
/// - organizer (Vendor Bookings): vendors I've booked for my events.
/// Layout: header → tabs → KPI cards → "<Tab> Bookings" section title → list.
class BookingsScreen extends StatefulWidget {
  final BookingsMode mode;
  const BookingsScreen({super.key, this.mode = BookingsMode.organizer});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  // Backend status filter per visible tab.
  static const _tabFilters = ['pending', 'accepted', 'completed', 'cancelled'];
  static const _tabLabels = ['Upcoming', 'Ongoing', 'Completed', 'Cancelled'];

  int _activeTab = 0;
  String _search = '';
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();

  List<dynamic> _bookings = [];
  Map<String, dynamic> _summary = {};
  bool _loading = true;

  bool get _isVendor => widget.mode == BookingsMode.vendor;
  // Organizer = "Vendor Bookings" (vendors I booked). Vendor mode = "Manage Bookings".
  String get _title => _isVendor ? 'Manage Bookings' : 'Vendor Bookings';

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

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = _isVendor
        ? await UserServicesService.getIncomingBookings(
            status: _tabFilters[_activeTab],
            search: _search.isNotEmpty ? _search : null,
          )
        : await UserServicesService.getBookings(
            status: _tabFilters[_activeTab],
            search: _search.isNotEmpty ? _search : null,
          );
    if (!mounted) return;
    setState(() {
      if (!silent) _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        if (data is Map) {
          final all = (data['bookings'] ?? []) as List;
          _summary = (data['summary'] ?? {}) as Map<String, dynamic>;
          _bookings = _isVendor
              ? all
              : all.where((b) {
                  final s = (b is Map ? b['status']?.toString() : null) ?? '';
                  return s == _tabFilters[_activeTab];
                }).toList();
        } else if (data is List) {
          _bookings = data;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const MigrationBanner(surface: MigrationSurface.bookings),
            _StatusTabs(
              labels: _tabLabels,
              active: _activeTab,
              onChange: (i) {
                setState(() => _activeTab = i);
                _load();
              },
            ),
            const SizedBox(height: 14),
            _KpiCards(summary: _summary, isVendor: _isVendor),
            if (_isVendor) _SponsorEntryCard(
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SponsorRequestsScreen(),
                ));
              },
            ),
            if (_searchOpen) _buildInlineSearch(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_tabLabels[_activeTab]} Bookings',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (_bookings.isNotEmpty)
                    Text('${_bookings.length}',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary,
                        )),
                ],
              ),
            ),
            Expanded(
              child: NuruRefresh(
                onRefresh: () => _load(silent: true),
                child: _loading
                    ? _skeletonList()
                    : (_bookings.isEmpty
                        ? _emptyState(
                            'No ${_tabLabels[_activeTab].toLowerCase()} bookings',
                            _isVendor
                                ? 'New booking requests will appear here'
                                : "Bookings you've made will appear here",
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _bookings.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) {
                              final b = _bookings[i];
                              return _BookingCard(
                                booking: b is Map<String, dynamic> ? b : <String, dynamic>{},
                                isVendor: _isVendor,
                                onAfterAction: _load,
                              );
                            },
                          )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SvgPicture.asset('assets/icons/arrow-left-icon.svg',
                width: 22, height: 22,
                colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
          ),
        ),
        Expanded(
          child: Center(
            child: Text(
              _title,
              style: GoogleFonts.inter(
                fontSize: 17, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen && _search.isNotEmpty) {
                _search = '';
                _searchCtrl.clear();
                _load();
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SvgPicture.asset(
                _searchOpen
                    ? 'assets/icons/close-icon.svg'
                    : 'assets/icons/search-icon.svg',
                width: 20, height: 20,
                colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
          ),
        ),
      ]),
    );
  }

  Widget _buildInlineSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: NuruSearchBar(
        controller: _searchCtrl,
        hintText: 'Search bookings, clients, services',
        debounce: const Duration(milliseconds: 300),
        onChanged: (v) {
          _search = v;
          _load();
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// KPI tiles (4 horizontal cards in a row, SVG icons)
// ─────────────────────────────────────────────────────────────

class _KpiCards extends StatelessWidget {
  final Map<String, dynamic> summary;
  final bool isVendor;
  const _KpiCards({required this.summary, required this.isVendor});

  @override
  Widget build(BuildContext context) {
    final total = (summary['total'] as num?)?.toInt() ?? 0;
    final pending = (summary['pending'] as num?)?.toInt() ?? 0;
    final ongoing = (summary['accepted'] as num?)?.toInt() ?? 0;
    final completed = (summary['completed'] as num?)?.toInt() ?? 0;

    final tiles = <_KpiData>[
      _KpiData('$total', isVendor ? 'Total Bookings' : 'Total',
          'assets/icons/calendar-icon.svg', const Color(0xFFF59E0B)),
      _KpiData('$pending', 'Upcoming',
          'assets/icons/clock-icon.svg', const Color(0xFF3B82F6)),
      _KpiData('$ongoing', 'Ongoing',
          'assets/icons/play-icon.svg', const Color(0xFFEC4899)),
      _KpiData('$completed', 'Completed',
          'assets/icons/verified-icon.svg', const Color(0xFF10B981)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            Expanded(child: _kpiTile(tiles[i])),
            if (i < tiles.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _kpiTile(_KpiData d) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: d.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(d.iconPath,
                width: 20, height: 20,
                colorFilter: ColorFilter.mode(d.color, BlendMode.srcIn)),
          ),
          const SizedBox(height: 10),
          Text(d.value,
              style: GoogleFonts.sora(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary, height: 1.1,
              )),
          const SizedBox(height: 2),
          Text(d.label,
              textAlign: TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10.5, fontWeight: FontWeight.w500,
                color: AppColors.textTertiary, height: 1.4,
              )),
        ],
      ),
    );
  }
}

class _KpiData {
  final String value;
  final String label;
  final String iconPath;
  final Color color;
  const _KpiData(this.value, this.label, this.iconPath, this.color);
}

// ─────────────────────────────────────────────────────────────
// Underline tab strip (active = black bold text + yellow underline under label)
// ─────────────────────────────────────────────────────────────

class _StatusTabs extends StatelessWidget {
  final List<String> labels;
  final int active;
  final ValueChanged<int> onChange;
  const _StatusTabs({
    required this.labels,
    required this.active,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 1),
        ),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = i == active;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChange(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                child: Column(
                  children: [
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color:
                            selected ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

Widget _skeletonList() {
  return const NuruSkeletonEventList(
    itemCount: 4,
    padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
    physics: AlwaysScrollableScrollPhysics(),
  );
}

Widget _emptyState(String title, String subtitle) {
  return ListView(
    children: [
      const SizedBox(height: 80),
      Center(
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(32),
              ),
              alignment: Alignment.center,
              child: SvgPicture.asset('assets/icons/calendar-icon.svg',
                  width: 26, height: 26,
                  colorFilter: const ColorFilter.mode(
                      AppColors.textHint, BlendMode.srcIn)),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                )),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────
// Booking card
// ─────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool isVendor;
  final Future<void> Function() onAfterAction;

  const _BookingCard({required this.booking, required this.isVendor, required this.onAfterAction});

  @override
  Widget build(BuildContext context) {
    final currency =
        context.select<WalletProvider, String>((w) => w.currency);

    final service = booking['service'] is Map ? booking['service'] as Map : const {};
    final event = booking['event'] is Map ? booking['event'] as Map : const {};
    final provider = booking['provider'] is Map ? booking['provider'] as Map : const {};
    final client = booking['client'] is Map ? booking['client'] as Map : const {};

    final eventName = (booking['event_name']?.toString() ??
            event['name']?.toString() ??
            event['title']?.toString() ??
            '')
        .trim();
    final serviceName = (service['title']?.toString() ??
            service['name']?.toString() ??
            booking['service_name']?.toString() ??
            'Service')
        .trim();

    // Headline + sub: show BOTH event and service in both modes.
    final headline = isVendor
        ? (serviceName.isNotEmpty ? serviceName : eventName)
        : (eventName.isNotEmpty ? eventName : serviceName);
    final subline = isVendor
        ? (eventName.isNotEmpty && eventName != headline ? eventName : '')
        : (serviceName.isNotEmpty && serviceName != headline ? serviceName : '');

    final category = service['category']?.toString() ??
        service['category_name']?.toString() ??
        booking['service_category']?.toString() ??
        booking['category']?.toString() ??
        '';

    String pickImage(List<String?> candidates) {
      for (final c in candidates) {
        final s = c?.trim();
        if (s != null && s.isNotEmpty) return s;
      }
      return '';
    }

    final eventImg = pickImage([
      event['image']?.toString(),
      event['cover_image']?.toString(),
      event['featured_image']?.toString(),
      event['image_url']?.toString(),
    ]);
    final serviceImg = pickImage([
      service['primary_image']?.toString(),
      service['cover_image']?.toString(),
      service['image']?.toString(),
      service['thumbnail_url']?.toString(),
      service['image_url']?.toString(),
      booking['cover_image']?.toString(),
    ]);
    // Prefer event image when an event exists.
    final cover = eventImg.isNotEmpty ? eventImg : serviceImg;

    final status = booking['status']?.toString() ?? 'pending';
    final date = booking['event_date']?.toString() ??
        event['start_date']?.toString() ??
        event['date']?.toString() ??
        booking['created_at']?.toString() ??
        '';
    final time = booking['event_time']?.toString() ??
        event['start_time']?.toString() ??
        '';
    final location = booking['location']?.toString() ??
        event['location']?.toString() ??
        event['venue']?.toString() ??
        booking['city']?.toString() ??
        '';

    // Other party: vendor view → client; organizer view → service provider.
    final otherName = isVendor
        ? (client['name']?.toString() ??
            booking['client_name']?.toString() ??
            booking['requester']?['name']?.toString() ??
            'Client')
        : (provider['name']?.toString() ??
            booking['vendor']?['name']?.toString() ??
            service['provider_name']?.toString() ??
            (service['user'] is Map ? service['user']['name']?.toString() : null) ??
            'Vendor');
    final otherAvatar = isVendor
        ? (client['avatar']?.toString() ??
            booking['client_avatar']?.toString())
        : (provider['avatar']?.toString() ??
            booking['vendor']?['avatar']?.toString() ??
            service['provider_avatar']?.toString());

    num? toNum(dynamic v) {
      if (v == null) return null;
      if (v is bool) return null; // guard against deposit_paid bool
      if (v is num) return v;
      return num.tryParse(v.toString());
    }

    final agreed = toNum(booking['final_price']) ??
        toNum(booking['quoted_price']) ??
        toNum(booking['total_amount']) ??
        toNum(booking['amount']);
    final paid = toNum(booking['amount_paid']) ??
        toNum(booking['paid_amount']) ??
        toNum(booking['paid']);
    final id = booking['id']?.toString() ?? '';
    final dateLabel = _formatDateTime(date, time);

    return GestureDetector(
      onTap: id.isEmpty
          ? null
          : () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BookingDetailScreen(
                  bookingId: id,
                  startAsVendor: isVendor,
                ),
              ));
              await onAfterAction();
            },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 84,
                    height: 84,
                    color: AppColors.surfaceVariant,
                    child: cover.isNotEmpty
                        ? Image.network(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _imgPlaceholder(),
                          )
                        : _imgPlaceholder(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              headline,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ),
                          SvgPicture.asset(
                            'assets/icons/chevron-right-icon.svg',
                            width: 16, height: 16,
                            colorFilter: const ColorFilter.mode(
                                AppColors.textTertiary, BlendMode.srcIn),
                          ),
                        ],
                      ),
                      if (category.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE9FE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(category,
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF7C3AED),
                              )),
                        ),
                      ],
                      if (subline.isNotEmpty)
                        _metaRow(
                          isVendor
                              ? 'assets/icons/calendar-icon.svg'
                              : 'assets/icons/package-icon.svg',
                          subline,
                        ),
                      if (dateLabel.isNotEmpty)
                        _metaRow('assets/icons/calendar-icon.svg', dateLabel),
                      if (location.isNotEmpty)
                        _metaRow('assets/icons/location-icon.svg', location),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.borderLight),
            const SizedBox(height: 10),
            Row(
              children: [
                _Avatar(name: otherName, url: otherAvatar, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isVendor ? 'Booked by' : 'Service Provider',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: AppColors.textTertiary,
                          )),
                      Text(otherName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          )),
                    ],
                  ),
                ),
                if (agreed != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(isVendor ? 'Earnings' : 'Agreed',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: AppColors.textTertiary,
                          )),
                      Text(
                        formatMoney(agreed, currency: currency),
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isVendor
                              ? AppColors.success
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (!isVendor && paid != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Paid ${formatMoney(paid, currency: currency)}',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            if (isVendor && status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _btn('Accept', AppColors.primary,
                        AppColors.textPrimary,
                        () => _showRespond(context, 'accepted')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _btn('Decline', AppColors.surfaceVariant,
                        AppColors.textSecondary,
                        () => _showRespond(context, 'rejected')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Center(
        child: SvgPicture.asset('assets/icons/image-icon.svg',
            width: 22, height: 22,
            colorFilter: const ColorFilter.mode(
                AppColors.textHint, BlendMode.srcIn)),
      );

  Widget _metaRow(String iconPath, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(children: [
        SvgPicture.asset(iconPath,
            width: 12, height: 12,
            colorFilter: const ColorFilter.mode(
                AppColors.textTertiary, BlendMode.srcIn)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: AppColors.textTertiary,
                height: 1.4,
              )),
        ),
      ]),
    );
  }

  String _formatDateTime(String date, String time) {
    if (date.isEmpty) return '';
    final d = date.contains('T') ? date.split('T').first : date;
    return time.isEmpty ? d : '$d • $time';
  }

  Widget _btn(String label, Color bg, Color fg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  void _showRespond(BuildContext context, String status) {
    final id = booking['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final messageCtrl = TextEditingController(
      text: status == 'accepted'
          ? 'Thanks for your request. Happy to take it on.'
          : "Thanks for reaching out. Unfortunately I can't take this one.",
    );
    final priceCtrl = TextEditingController();
    final depositCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            status == 'accepted' ? 'Accept booking' : 'Decline booking',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status == 'accepted') ...[
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: amountFormatters,
                    decoration: const InputDecoration(labelText: 'Quoted price'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: depositCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: amountFormatters,
                    decoration: const InputDecoration(labelText: 'Deposit required'),
                  ),
                  const SizedBox(height: 8),
                ],
                if (status == 'rejected') ...[
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(labelText: 'Reason'),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: messageCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Message to client'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.inter(color: AppColors.textTertiary)),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setS(() => submitting = true);
                      final res = await UserServicesService.respondToBooking(
                        id,
                        status: status,
                        message: messageCtrl.text.trim(),
                        quotedPrice: parseAmount(priceCtrl.text),
                        depositRequired: parseAmount(depositCtrl.text),
                        reason: reasonCtrl.text.trim(),
                      );
                      setS(() => submitting = false);
                      if (!ctx.mounted) return;
                      if (res['success'] == true) {
                        Navigator.pop(ctx);
                        await onAfterAction();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(status == 'accepted'
                                ? 'Booking accepted'
                                : 'Booking declined'),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              res['message']?.toString() ?? 'Failed to respond',
                            ),
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    status == 'accepted' ? AppColors.primary : AppColors.error,
                foregroundColor:
                    status == 'accepted' ? AppColors.textPrimary : Colors.white,
              ),
              child: Text(submitting
                  ? 'Sending…'
                  : (status == 'accepted' ? 'Accept' : 'Decline')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  const _Avatar({required this.name, this.url, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withOpacity(0.10),
        image: (url != null && url!.isNotEmpty)
            ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: (url == null || url!.isEmpty)
          ? Text(
              initial,
              style: GoogleFonts.sora(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Sponsor inbox entry (vendor mode only)
// ─────────────────────────────────────────────────────────────
class _SponsorEntryCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SponsorEntryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  'assets/icons/thunder-icon.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                      Color(0xFF92400E), BlendMode.srcIn),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sponsorship Requests',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Invitations to sponsor events',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              SvgPicture.asset(
                'assets/icons/chevron-right-icon.svg',
                width: 18,
                height: 18,
                colorFilter: const ColorFilter.mode(
                    AppColors.textTertiary, BlendMode.srcIn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
