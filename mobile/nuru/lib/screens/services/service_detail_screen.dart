import '../../core/widgets/nuru_refresh_indicator.dart';
import '../../core/utils/money_format.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/services/api_service.dart';
import '../../core/services/user_services_service.dart';
import '../../core/widgets/app_snackbar.dart';
import 'public_service_screen.dart';
import 'service_verification_screen.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../core/utils/haptics.dart';
import '../../widgets/received_payments_panel.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../widgets/app_select.dart';

/// Owner's Service Detail - matches web ServiceDetail.tsx
/// Tabs: Overview, Calendar, Reviews, Payments
class ServiceDetailScreen extends StatefulWidget {
  final String serviceId;
  const ServiceDetailScreen({super.key, required this.serviceId});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  static String get _baseUrl => ApiService.baseUrl;
  bool _loading = true;
  Map<String, dynamic> _service = {};
  List<dynamic> _packages = [];
  List<dynamic> _reviews = [];
  List<dynamic> _bookedDates = [];
  List<dynamic> _introMedia = [];
  bool _calendarLoading = true;
  bool _reviewsLoading = false;
  int _activeTab = 0; // 0=overview, 1=calendar, 2=reviews, 3=payments
  DateTime _currentMonth = DateTime.now();

  // ─── Theme tokens (mockup-matched, mirrors PublicServiceScreen) ─────
  static const _bg = Colors.white;
  static const _gold = AppColors.primary;
  static const _ink = Color(0xFF1C1C24);
  static const _muted = Color(0xFF6B7280);
  static const _hairline = Color(0xFFE5E7EB);
  static const _goldInk = Color(0xFF3A2E07);

  TextStyle _f({required double size, FontWeight weight = FontWeight.w500, Color color = _ink, double height = 1.3}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Track which tabs have already been loaded so we never refetch.
  bool _calendarLoaded = false;
  bool _reviewsLoaded = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await UserServicesService.getServiceDetail(widget.serviceId);
    if (!mounted) return;
    final data = res['data'];
    Map<String, dynamic> svc = {};
    if (res['success'] == true && data is Map<String, dynamic>) {
      svc = (data['service'] is Map<String, dynamic>) ? data['service'] as Map<String, dynamic> : data;
    }
    setState(() {
      _loading = false;
      _service = svc;
      _packages = svc['packages'] is List ? svc['packages'] as List : [];
      _introMedia = svc['intro_media'] is List ? svc['intro_media'] as List : [];
      // Calendar is hidden behind a tab - don't show its skeleton on first paint.
      _calendarLoading = false;
    });
    // Only fetch intro media separately if it wasn't already inlined in the payload.
    if (_introMedia.isEmpty) _loadIntroMedia();
  }

  /// Lazy: fetch calendar data the first time the calendar tab is opened.
  void _ensureCalendarLoaded() {
    if (_calendarLoaded) return;
    _calendarLoaded = true;
    _loadCalendar();
  }

  /// Lazy: fetch reviews the first time the reviews tab is opened.
  void _ensureReviewsLoaded() {
    if (_reviewsLoaded) return;
    _reviewsLoaded = true;
    _loadReviews();
  }


  Future<void> _loadCalendar() async {
    setState(() => _calendarLoading = true);
    try {
      final headers = await _headers();
      final res = await http.get(Uri.parse('$_baseUrl/services/${widget.serviceId}/calendar'), headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final d = data['data'] ?? data;
        setState(() => _bookedDates = d['booked_dates'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _calendarLoading = false);
  }

  Future<void> _loadReviews() async {
    setState(() => _reviewsLoading = true);
    try {
      final headers = await _headers();
      final res = await http.get(Uri.parse('$_baseUrl/services/${widget.serviceId}/reviews?limit=10'), headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final d = data['data'] ?? data;
        setState(() => _reviews = d['reviews'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _reviewsLoading = false);
  }

  Future<void> _loadIntroMedia() async {
    try {
      final headers = await _headers();
      final res = await http.get(Uri.parse('$_baseUrl/user-services/${widget.serviceId}/intro-media'), headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final d = data['data'] ?? data;
        if (d is List && mounted) setState(() => _introMedia = d);
      }
    } catch (_) {}
  }

  List<String> _getImages() {
    final images = <String>[];
    final imgs = _service['images'];
    if (imgs is List) {
      for (final img in imgs) {
        if (img is String && img.isNotEmpty) images.add(img);
        if (img is Map) {
          final url = img['url']?.toString() ?? img['image_url']?.toString() ?? '';
          if (url.isNotEmpty) images.add(url);
        }
      }
    }
    if (images.isEmpty) {
      final p = _service['primary_image'];
      if (p is String && p.isNotEmpty) images.add(p);
      if (p is Map) {
        final url = p['url']?.toString() ?? '';
        if (url.isNotEmpty) images.add(url);
      }
    }
    return images;
  }

  /// Format price with comma separators, no decimals
  String _fmtPrice(dynamic p) {
    if (p == null) return 'Price on request';
    final n = (p is num) ? p.toInt() : (int.tryParse(p.toString().replaceAll(RegExp(r'[^\d]'), '')) ?? 0);
    if (n == 0) return '-';
    return '${getActiveCurrency()} ${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: NuruSubPageAppBar(title: context.tr('services')),
        body: const NuruSkeletonEventDetail(),
      );
    }

    final s = _service;
    final title = s['title']?.toString() ?? 'Service';
    final images = _getImages();
    final isVerified = s['verification_status'] == 'verified';
    final isPending = s['verification_status'] == 'pending';
    final rating = (s['rating'] ?? s['average_rating'] ?? 0);
    final reviewCount = s['review_count'] ?? _reviews.length;
    final category = _safeNestedString(s['service_category'], 'name') ?? s['category']?.toString() ?? '';
    final location = s['location']?.toString() ?? '';
    final serviceTypeSlug = (s['service_type_slug'] ?? _safeNestedString(s['service_category'], 'slug') ?? _safeNestedString(s['service_type'], 'slug') ?? '').toString().toLowerCase();
    final upcomingBookings = _bookedDates.where((b) {
      final date = DateTime.tryParse(b['date']?.toString() ?? '');
      return date != null && date.isAfter(DateTime.now().subtract(const Duration(days: 1)));
    }).toList()..sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? ''));
    final totalRevenue = _bookedDates.where((b) => b['agreed_price'] != null && (b['status'] == 'confirmed' || b['status'] == 'completed'))
        .fold<double>(0.0, (sum, b) => sum + ((b['agreed_price'] is num) ? (b['agreed_price'] as num).toDouble() : 0.0));

    return Scaffold(
      backgroundColor: _bg,
      body: NuruRefreshIndicator(
        onRefresh: _load,
        color: _gold,
        child: CustomScrollView(slivers: [
          // Hero gallery
          SliverToBoxAdapter(child: _heroGallery(images, title, category, isPending, location)),

          // Title block under hero (chips)
          SliverToBoxAdapter(child: _titleBlock(title, category, rating, reviewCount, location, isPending)),

          // KPI Dashboard - 6 metrics mirroring web ServiceDetail
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(children: [
              Row(children: [
                _kpiCard('Revenue', totalRevenue > 0 ? _fmtPrice(totalRevenue.toInt()) : '-', const Color(0xFF1B9E47), Icons.attach_money_rounded),
                const SizedBox(width: 10),
                _kpiCard('Rating', rating is num && rating > 0 ? (rating as num).toStringAsFixed(1) : '-', const Color(0xFFB45309), Icons.star_rounded),
                const SizedBox(width: 10),
                _kpiCard('Reviews', '$reviewCount', const Color(0xFF2563EB), Icons.rate_review_outlined),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _kpiCard('Upcoming', '${upcomingBookings.length}', _goldInk, Icons.calendar_today_rounded),
                const SizedBox(width: 10),
                _kpiCard('Completed', '${s['completed_events'] ?? 0}', const Color(0xFF2563EB), Icons.check_circle_outline_rounded),
                const SizedBox(width: 10),
                _kpiCard(
                  'Completion',
                  () {
                    final done = (s['completed_events'] is num) ? (s['completed_events'] as num).toInt() : 0;
                    final total = done + upcomingBookings.length;
                    if (total == 0) return '-';
                    return '${((done / total) * 100).round()}%';
                  }(),
                  const Color(0xFF1B9E47), Icons.trending_up_rounded,
                ),
              ]),
            ]),
          )),

          // Quick Actions (horizontal scroll, white pills)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _quickAction('Public View', 'assets/icons/search-icon.svg', () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PublicServiceScreen(serviceId: widget.serviceId),
                  ));
                }),
                const SizedBox(width: 8),
                if (!isVerified)
                  _quickAction('Edit', 'assets/icons/settings-icon.svg', () => _showEditServiceSheet(s)),
                if (!isVerified) const SizedBox(width: 8),
                if (isVerified)
                  _quickAction('Add Package', 'assets/icons/settings-icon.svg', () => _showAddPackageSheet()),
                if (isVerified) const SizedBox(width: 8),
                _quickAction('KYC Status', 'assets/icons/shield-icon.svg', () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ServiceVerificationScreen(serviceId: widget.serviceId, serviceType: serviceTypeSlug),
                  ));
                }),
              ]),
            ),
          )),

          // Tabs
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF1F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: List.generate(4, (i) {
                final labels = ['Overview', 'Calendar', 'Reviews ($reviewCount)', 'Payments'];
                final active = _activeTab == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Haptics.selection();
                      setState(() => _activeTab = i);
                      if (i == 1) _ensureCalendarLoaded();
                      if (i == 2) _ensureReviewsLoaded();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: active
                            ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 1))]
                            : null,
                      ),
                      child: Text(labels[i], textAlign: TextAlign.center,
                          style: _f(size: 12.5, weight: FontWeight.w800, color: active ? _ink : _muted)),
                    ),
                  ),
                );
              })),
            ),
          )),

          // Tab Content
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: _activeTab == 0
                ? _overviewTab(s)
                : _activeTab == 1
                    ? _calendarTab()
                    : _activeTab == 2
                        ? _reviewsTab()
                        : ReceivedPaymentsPanel(
                            source: ReceivedPaymentsSource.service,
                            targetId: widget.serviceId,
                            title: 'Payments received for this service',
                          ),
          )),
        ]),
      ),
    );
  }

  // Title block under hero - chips for category, rating, location
  Widget _titleBlock(String title, String category, dynamic rating, dynamic reviewCount, String location, bool isPending) {
    final ratingNum = rating is num ? rating.toDouble() : 0.0;
    final hasRating = ratingNum > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: _f(size: 22, weight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (category.isNotEmpty)
            _chip(label: category, bg: _gold.withOpacity(0.18), fg: _goldInk),
          if (hasRating)
            _chip(
              iconWidget: const Icon(Icons.star_rounded, size: 13, color: Color(0xFFB45309)),
              label: '${ratingNum.toStringAsFixed(1)} ($reviewCount ${reviewCount == 1 ? 'review' : 'reviews'})',
              bg: const Color(0xFFFFF7E0), fg: _goldInk,
            ),
          if (location.isNotEmpty)
            _chip(
              iconWidget: SvgPicture.asset('assets/icons/location-icon.svg',
                  width: 12, height: 12, colorFilter: const ColorFilter.mode(_muted, BlendMode.srcIn)),
              label: location, bg: const Color(0xFFF1F2F6), fg: _ink,
            ),
          if (isPending)
            _chip(
              iconWidget: const Icon(Icons.pending_outlined, size: 13, color: Color(0xFFB45309)),
              label: 'Pending Review', bg: const Color(0xFFFFF1E0), fg: const Color(0xFF92400E),
            ),
        ]),
      ]),
    );
  }

  Widget _chip({String? label, Widget? iconWidget, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (iconWidget != null) ...[iconWidget, const SizedBox(width: 5)],
        if (label != null) Text(label, style: _f(size: 11.5, weight: FontWeight.w700, color: fg)),
      ]),
    );
  }

  Widget _heroGallery(List<String> images, String title, String category, bool isPending, String location) {
    return Container(
      color: _bg,
      child: Column(children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _circleBtn(asset: 'assets/icons/chevron-left-icon.svg', onTap: () => Navigator.pop(context)),
              _circleBtn(icon: Icons.more_horiz_rounded, onTap: () => _showEditServiceSheet(_service)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 240, width: double.infinity,
              child: images.isEmpty
                  ? _heroPlaceholder(title)
                  : Stack(children: [
                      images.length == 1
                          ? CachedNetworkImage(imageUrl: images[0], fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _heroPlaceholder(title))
                          : PageView.builder(
                              itemCount: images.length,
                              itemBuilder: (_, i) => CachedNetworkImage(imageUrl: images[i], fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _heroPlaceholder(title)),
                            ),
                      if (images.length > 1)
                        Positioned(top: 12, right: 12, child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(999)),
                          child: Text('${images.length} photos',
                              style: _f(size: 11, weight: FontWeight.w700, color: Colors.white)),
                        )),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _heroPlaceholder(String title) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [_gold.withOpacity(0.3), _gold.withOpacity(0.1)]),
    ),
    child: const Center(child: Icon(Icons.work_outline, size: 56, color: _goldInk)),
  );

  Widget _circleBtn({String? asset, IconData? icon, Color iconColor = _ink, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: Colors.white, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Center(child: asset != null
            ? SvgPicture.asset(asset, width: 18, height: 18, colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn))
            : Icon(icon, size: 19, color: iconColor)),
      ),
    );
  }

  // Legacy alias - kept for downstream call sites
  Widget _backBtn() => _circleBtn(asset: 'assets/icons/chevron-left-icon.svg', onTap: () => Navigator.pop(context));

  Widget _kpiCard(String label, String value, Color color, IconData icon) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 15, color: color)),
        const SizedBox(height: 8),
        Text(value, style: _f(size: 15, weight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 1),
        Text(label, style: _f(size: 10.5, color: _muted, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    ));
  }

  Widget _quickAction(String label, String svgAsset, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 1))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SvgPicture.asset(svgAsset, width: 14, height: 14,
            colorFilter: const ColorFilter.mode(_goldInk, BlendMode.srcIn)),
          const SizedBox(width: 6),
          Text(label, style: _f(size: 12.5, weight: FontWeight.w800, color: _ink)),
        ]),
      ),
    );
  }

  // ─── OVERVIEW TAB ───
  Widget _overviewTab(Map<String, dynamic> s) {
    final desc = s['description']?.toString() ?? '';
    final upcomingBookings = _bookedDates.where((b) {
      final date = DateTime.tryParse(b['date']?.toString() ?? '');
      return date != null && date.isAfter(DateTime.now().subtract(const Duration(days: 1)));
    }).toList()..sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? ''));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // About
      if (desc.isNotEmpty) ...[
        _sectionCard('About This Service', child: Text(desc, style: _f(size: 13, color: AppColors.textSecondary, height: 1.5))),
        const SizedBox(height: 12),
      ],

      // Intro Media
      if (_introMedia.isNotEmpty) ...[
        _sectionCard('Intro Clip', svgIcon: 'assets/icons/play-icon.svg', child: Column(children: _introMedia.map((media) {
          final type = media['media_type']?.toString() ?? '';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                child: Center(child: SvgPicture.asset('assets/icons/play-icon.svg', width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)))),
              const SizedBox(width: 10),
              Expanded(child: Text(type == 'video' ? 'Video Introduction' : 'Audio Introduction', style: _f(size: 13, weight: FontWeight.w600))),
            ]),
          );
        }).toList())),
        const SizedBox(height: 12),
      ],

      // Quick info cards
      _infoGrid(s),
      const SizedBox(height: 12),

      // Upcoming assignments
      if (upcomingBookings.isNotEmpty) ...[
        _sectionCard('Upcoming Assignments', trailing: '${upcomingBookings.length}', child: Column(
          children: upcomingBookings.take(5).map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                color: _statusColor(b['status']?.toString() ?? ''),
                shape: BoxShape.circle,
              )),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b['event_name']?.toString() ?? 'Event', style: _f(size: 13, weight: FontWeight.w600)),
                Text(_formatDate(b['date']?.toString() ?? ''), style: _f(size: 11, color: AppColors.textTertiary)),
              ])),
              if (b['agreed_price'] != null)
                Text(_fmtPrice(b['agreed_price']), style: _f(size: 12, weight: FontWeight.w700, color: AppColors.primary)),
            ]),
          )).toList(),
        )),
        const SizedBox(height: 12),
      ],

      // Packages
      _packagesSection(),
    ]);
  }

  Widget _sectionCard(String title, {Widget? child, String? svgIcon, IconData? icon, String? trailing}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (svgIcon != null) ...[
            Container(width: 28, height: 28, decoration: BoxDecoration(color: _gold.withOpacity(0.18), borderRadius: BorderRadius.circular(8)),
              child: Center(child: SvgPicture.asset(svgIcon, width: 14, height: 14,
                colorFilter: const ColorFilter.mode(_goldInk, BlendMode.srcIn)))),
            const SizedBox(width: 10),
          ] else if (icon != null) ...[
            Container(width: 28, height: 28, decoration: BoxDecoration(color: _gold.withOpacity(0.18), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 15, color: _goldInk)),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(title, style: _f(size: 15.5, weight: FontWeight.w800, color: _ink))),
          if (trailing != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFF1F2F6), borderRadius: BorderRadius.circular(999)),
              child: Text(trailing, style: _f(size: 11, weight: FontWeight.w800, color: _ink)),
            ),
        ]),
        if (child != null) ...[const SizedBox(height: 12), child],
      ]),
    );
  }

  /// Safely access a nested key on a value that might be a Map or a String/other type
  String? _safeNestedString(dynamic value, String key) {
    if (value is Map) return value[key]?.toString();
    return null;
  }

  Widget _infoGrid(Map<String, dynamic> s) {
    final items = [
      {'label': 'Category', 'value': _safeNestedString(s['service_category'], 'name') ?? s['category']?.toString() ?? '-'},
      {'label': 'On Nuru', 'value': _timeOnPlatform(s['created_at']?.toString())},
      {'label': 'Location', 'value': s['location']?.toString() ?? '-'},
      {'label': 'Availability', 'value': s['availability']?.toString() ?? 'available'},
    ];
    return Row(children: items.map((m) => Expanded(child: Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m['label']!, style: _f(size: 9, color: AppColors.textTertiary)),
        const SizedBox(height: 2),
        Text(m['value']!, style: _f(size: 11, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    ))).toList());
  }

  Widget _packagesSection() {
    return _sectionCard('Packages', child: _packages.isEmpty
        ? Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No packages yet', style: _f(size: 13, color: AppColors.textTertiary)),
          ))
        : Column(children: _packages.asMap().entries.map((e) {
            final idx = e.key;
            final pkg = e.value is Map<String, dynamic> ? e.value as Map<String, dynamic> : <String, dynamic>{};
            final features = pkg['features'] is List ? (pkg['features'] as List) : [];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: idx == 0 ? AppColors.primary.withOpacity(0.03) : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Row(children: [
                    Flexible(child: Text(pkg['name']?.toString() ?? 'Package', style: _f(size: 13, weight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                    if (idx == 0) ...[
                      const SizedBox(width: 6),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text('Top', style: _f(size: 9, weight: FontWeight.w700, color: AppColors.primary))),
                    ],
                  ])),
                  Text(_fmtPrice(pkg['price']), style: _f(size: 13, weight: FontWeight.w700, color: AppColors.primary)),
                ]),
                if ((pkg['description']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(pkg['description'].toString(), style: _f(size: 11, color: AppColors.textTertiary)),
                ],
                if (features.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                      const SizedBox(width: 6),
                      Expanded(child: Text(f.toString(), style: _f(size: 11, color: AppColors.textSecondary))),
                    ]),
                  )),
                ],
              ]),
            );
          }).toList()),
    );
  }

  // ─── CALENDAR TAB ───
  Widget _calendarTab() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final firstDay = DateTime(year, month, 1).weekday % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final today = DateTime.now();
    final months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    final days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: _calendarLoading
          ? const Padding(padding: EdgeInsets.all(16), child: NuruSkeletonList(itemCount: 4, showAvatar: false, padding: EdgeInsets.zero))
          : Column(children: [
              Row(children: [
                Container(width: 28, height: 28, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Padding(padding: const EdgeInsets.all(5), child: SvgPicture.asset('assets/icons/calendar-icon.svg',
                    colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)))),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Availability Calendar', style: _f(size: 14, weight: FontWeight.w700)),
                  Text('Real-time view of your bookings', style: _f(size: 10, color: AppColors.textTertiary)),
                ])),
              ]),
              const SizedBox(height: 16),

              // Month nav
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                GestureDetector(
                  onTap: () => setState(() => _currentMonth = DateTime(year, month - 1)),
                  child: Container(width: 32, height: 32, decoration: BoxDecoration(border: Border.all(color: AppColors.borderLight), borderRadius: BorderRadius.circular(10)),
                    child: Padding(padding: const EdgeInsets.all(6), child: SvgPicture.asset('assets/icons/chevron-left-icon.svg', colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)))),
                ),
                Text('${months[month - 1]} $year', style: _f(size: 15, weight: FontWeight.w700)),
                GestureDetector(
                  onTap: () => setState(() => _currentMonth = DateTime(year, month + 1)),
                  child: Container(width: 32, height: 32, decoration: BoxDecoration(border: Border.all(color: AppColors.borderLight), borderRadius: BorderRadius.circular(10)),
                    child: Padding(padding: const EdgeInsets.all(6), child: SvgPicture.asset('assets/icons/chevron-right-icon.svg', colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)))),
                ),
              ]),
              const SizedBox(height: 12),

              // Day headers
              Row(children: days.map((d) => Expanded(child: Center(
                child: Text(d, style: _f(size: 10, weight: FontWeight.w600, color: AppColors.textTertiary)),
              ))).toList()),
              const SizedBox(height: 6),

              // Calendar grid
              ...List.generate(6, (week) {
                return Row(children: List.generate(7, (dow) {
                  final idx = week * 7 + dow;
                  final dayNum = idx - firstDay + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) return const Expanded(child: SizedBox(height: 40));

                  final dateStr = '${year.toString()}-${month.toString().padLeft(2, '0')}-${dayNum.toString().padLeft(2, '0')}';
                  final isToday = today.year == year && today.month == month && today.day == dayNum;
                  final isPast = DateTime(year, month, dayNum).isBefore(DateTime(today.year, today.month, today.day));
                  final booking = _bookedDates.cast<dynamic>().firstWhere((b) => b['date'] == dateStr, orElse: () => null);
                  final isBooked = booking != null;

                  return Expanded(child: GestureDetector(
                    onTap: isBooked ? () => _showBookingPopup(booking) : null,
                    child: Container(
                      height: 40,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: isToday ? AppColors.primary.withOpacity(0.1) :
                               isBooked ? _statusColor(booking['status']?.toString() ?? '') :
                               !isPast ? const Color(0xFFF0FDF4) : null,
                        borderRadius: BorderRadius.circular(10),
                        border: isToday ? Border.all(color: AppColors.primary, width: 2) : null,
                      ),
                      child: Center(child: Text('$dayNum',
                        style: _f(size: 12, weight: FontWeight.w600,
                          color: isToday ? AppColors.primary :
                                 isBooked ? Colors.white :
                                 isPast ? AppColors.textHint : const Color(0xFF15803D)),
                      )),
                    ),
                  ));
                }));
              }),
              const SizedBox(height: 12),

              // Legend
              Row(children: [
                _legendDot('Pending', AppColors.warning),
                const SizedBox(width: 12),
                _legendDot('Confirmed', AppColors.success),
                const SizedBox(width: 12),
                _legendDot('Available', const Color(0xFFF0FDF4), border: true),
                const SizedBox(width: 12),
                _legendDot('Today', AppColors.primary.withOpacity(0.1), border: true, borderColor: AppColors.primary),
              ]),
            ]),
    );
  }

  Widget _legendDot(String label, Color color, {bool border = false, Color? borderColor}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(3),
        border: border ? Border.all(color: borderColor ?? AppColors.borderLight) : null,
      )),
      const SizedBox(width: 4),
      Text(label, style: _f(size: 10, color: AppColors.textTertiary)),
    ]);
  }

  void _showBookingPopup(dynamic booking) {
    if (booking == null) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(booking['event_name']?.toString() ?? 'Event', style: _f(size: 15, weight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (booking['event_location'] != null)
          Row(children: [
            SvgPicture.asset('assets/icons/location-icon.svg', width: 14, height: 14,
              colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
            const SizedBox(width: 4),
            Text(booking['event_location'].toString(), style: _f(size: 12, color: AppColors.textTertiary)),
          ]),
        const SizedBox(height: 6),
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderLight), borderRadius: BorderRadius.circular(4)),
            child: Text(booking['status']?.toString() ?? '', style: _f(size: 10, weight: FontWeight.w600)),
          ),
          if (booking['agreed_price'] != null) ...[
            const SizedBox(width: 8),
            Text(_fmtPrice(booking['agreed_price']), style: _f(size: 12, weight: FontWeight.w700, color: AppColors.primary)),
          ],
        ]),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: _f(size: 13, weight: FontWeight.w600, color: AppColors.primary)))],
    ));
  }

  // ─── REVIEWS TAB ───
  Widget _reviewsTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 28, height: 28, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.people_outline_rounded, size: 14, color: AppColors.primary)),
          const SizedBox(width: 8),
          Text('Client Reviews', style: _f(size: 14, weight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        if (_reviewsLoading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: NuruSkeletonList(itemCount: 3, padding: EdgeInsets.zero))
        else if (_reviews.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Icon(Icons.star_outline_rounded, size: 40, color: AppColors.textHint.withOpacity(0.3)),
              const SizedBox(height: 8),
              Text('No reviews yet', style: _f(size: 13, color: AppColors.textTertiary)),
              Text('Reviews appear after completing events', style: _f(size: 11, color: AppColors.textHint)),
            ]),
          ))
        else
          ..._reviews.map((r) {
            final review = r is Map<String, dynamic> ? r : <String, dynamic>{};
            final name = review['user_name']?.toString() ?? 'Anonymous';
            final ratingVal = review['rating'] ?? 0;
            final comment = review['comment']?.toString() ?? '';
            final date = review['created_at']?.toString() ?? '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 16, backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'A', style: _f(size: 11, weight: FontWeight.w700, color: AppColors.primary))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: _f(size: 13, weight: FontWeight.w600)),
                      if (date.isNotEmpty) Text(_formatDate(date), style: _f(size: 10, color: AppColors.textTertiary)),
                    ])),
                    Row(children: List.generate(5, (i) => Icon(
                      i < (ratingVal is num ? ratingVal.round() : 0) ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 14, color: Colors.amber,
                    ))),
                  ]),
                  if (comment.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(comment, style: _f(size: 12, color: AppColors.textSecondary, height: 1.4)),
                  ],
                ])),
              ]),
            );
          }),
      ]),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed': case 'completed': case 'accepted': return AppColors.success;
      case 'pending': return AppColors.warning;
      case 'cancelled': return AppColors.error;
      default: return AppColors.success;
    }
  }

  String _timeOnPlatform(String? created) {
    if (created == null || created.isEmpty) return 'New';
    final days = DateTime.now().difference(DateTime.parse(created)).inDays;
    if (days < 1) return 'Today';
    if (days < 30) return '${days}d';
    final m = days ~/ 30;
    if (m < 12) return '${m}mo';
    return '${m ~/ 12}yr';
  }

  String _formatDate(String date) {
    try {
      final d = DateTime.parse(date);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) { return date; }
  }

  // ─── ADD PACKAGE (matches web and MyServicesScreen) ───
  Future<void> _showAddPackageSheet() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final featuresCtrl = TextEditingController();
    bool submitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Text('Add Service Package', style: _f(size: 18, weight: FontWeight.w700)),
                const SizedBox(height: 12),
                _sheetField(nameCtrl, 'Package Name', 'e.g. Basic, Premium, Gold'),
                const SizedBox(height: 10),
                _sheetField(descCtrl, 'Description', 'Brief description...', maxLines: 2),
                const SizedBox(height: 10),
                _sheetField(priceCtrl, 'Price (TZS)', 'e.g. 150000', keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                _sheetField(featuresCtrl, 'Features (comma-separated)', 'e.g. 5 hours, 200 photos, Gallery', maxLines: 2),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity, height: 46,
                  child: ElevatedButton(
                    onPressed: submitting ? null : () async {
                      if (nameCtrl.text.trim().isEmpty) { AppSnackbar.error(context, 'Package name required'); return; }
                      if (priceCtrl.text.trim().isEmpty) { AppSnackbar.error(context, 'Price required'); return; }
                      setSheet(() => submitting = true);
                      try {
                        final headers = await _headers();
                        final res = await http.post(
                          Uri.parse('$_baseUrl/user-services/${widget.serviceId}/packages'),
                          headers: headers,
                          body: jsonEncode({
                            'name': nameCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                            'price': num.tryParse(priceCtrl.text.trim()) ?? 0,
                            'features': featuresCtrl.text.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty).toList(),
                          }),
                        );
                        if (res.statusCode >= 200 && res.statusCode < 300) {
                          if (mounted) { Navigator.pop(ctx); AppSnackbar.success(context, 'Package added!'); _load(); }
                        } else {
                          setSheet(() => submitting = false);
                          AppSnackbar.error(context, 'Failed to add package');
                        }
                      } catch (e) {
                        setSheet(() => submitting = false);
                        AppSnackbar.error(context, 'Failed to add package');
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Save Package', style: _f(size: 13, weight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose(); descCtrl.dispose(); priceCtrl.dispose(); featuresCtrl.dispose();
  }

  // ─── EDIT SERVICE (comprehensive like web) ───
  Future<void> _showEditServiceSheet(Map<String, dynamic> service) async {
    final serviceId = service['id']?.toString() ?? '';
    if (serviceId.isEmpty) return;
    final titleCtrl = TextEditingController(text: (service['title'] ?? service['name'] ?? '').toString());
    final descCtrl = TextEditingController(text: (service['description'] ?? '').toString());
    final minPriceCtrl = TextEditingController(text: (service['min_price'] ?? service['starting_price'] ?? service['price'] ?? '').toString());
    final maxPriceCtrl = TextEditingController(text: (service['max_price'] ?? '').toString());
    final locationCtrl = TextEditingController(text: (service['location'] ?? '').toString());
    String status = (service['status']?.toString() ?? 'active').toLowerCase();
    String availability = (service['availability']?.toString() ?? 'available').toLowerCase();
    bool submitting = false;

    // Load categories and types
    List<dynamic> categories = [];
    List<dynamic> serviceTypes = [];
    String selectedCategoryId = (service['service_category_id'] ?? _safeNestedString(service['service_category'], 'id') ?? '').toString();
    String selectedTypeId = (service['service_type_id'] ?? _safeNestedString(service['service_type'], 'id') ?? '').toString();

    final catRes = await UserServicesService.getServiceCategories();
    if (catRes['success'] == true) {
      final d = catRes['data'];
      categories = d is List ? d : (d is Map ? (d['categories'] ?? []) : []);
    }

    Future<List<dynamic>> loadTypes(String catId) async {
      if (catId.isEmpty) return [];
      try {
        final headers = await _headers();
        final res = await http.get(Uri.parse('$_baseUrl/services/categories/$catId/types'), headers: headers);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body);
          final d = data['data'] ?? data;
          return d is List ? d : (d is Map ? (d['types'] ?? d['service_types'] ?? []) : []);
        }
      } catch (_) {}
      return [];
    }

    if (selectedCategoryId.isNotEmpty) {
      serviceTypes = await loadTypes(selectedCategoryId);
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Text('Edit Service', style: _f(size: 18, weight: FontWeight.w700)),
                Text('Update your service details and information', style: _f(size: 12, color: AppColors.textTertiary)),
                const SizedBox(height: 16),
                _sheetField(titleCtrl, 'Service Title', 'e.g. Professional Photography'),
                const SizedBox(height: 10),
                // Category selector
                Text('Service Category', style: _f(size: 12, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                AppSelect.fromItems<String>(
                  value: categories.any((c) => c['id']?.toString() == selectedCategoryId) ? selectedCategoryId : null,
                  hint: 'Select a category',
                  title: 'Service Category',
                  borderRadius: 12,
                  fillColor: AppColors.surfaceVariant,
                  fontSize: 14,
                  searchable: true,
                  enabled: !submitting,
                  items: categories.map<DropdownMenuItem<String>>((c) => DropdownMenuItem(
                    value: c['id']?.toString() ?? '',
                    child: Text(c['name']?.toString() ?? '', style: _f(size: 14)),
                  )).toList(),
                  onChanged: submitting ? null : (v) async {
                    setSheet(() { selectedCategoryId = v ?? ''; selectedTypeId = ''; });
                    final types = await loadTypes(v ?? '');
                    setSheet(() => serviceTypes = types);
                  },
                ),
                const SizedBox(height: 10),
                // Type selector
                Text('Service Type', style: _f(size: 12, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                AppSelect.fromItems<String>(
                  value: serviceTypes.any((t) => t['id']?.toString() == selectedTypeId) ? selectedTypeId : null,
                  hint: 'Select a type',
                  title: 'Service Type',
                  borderRadius: 12,
                  fillColor: AppColors.surfaceVariant,
                  fontSize: 14,
                  searchable: true,
                  enabled: !submitting,
                  items: serviceTypes.map<DropdownMenuItem<String>>((t) => DropdownMenuItem(
                    value: t['id']?.toString() ?? '',
                    child: Text(t['name']?.toString() ?? '', style: _f(size: 14)),
                  )).toList(),
                  onChanged: submitting ? null : (v) => setSheet(() => selectedTypeId = v ?? ''),
                ),
                const SizedBox(height: 10),
                _sheetField(descCtrl, 'Description', 'Describe your service...', maxLines: 4),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _sheetField(minPriceCtrl, 'Min Price (TZS)', 'e.g. 50000', keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: _sheetField(maxPriceCtrl, 'Max Price (TZS)', 'e.g. 200000', keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 10),
                _sheetField(locationCtrl, 'Location', 'e.g. Dar es Salaam'),
                const SizedBox(height: 10),
                // Status dropdown
                Text('Status', style: _f(size: 12, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                AppSelect.fromItems<String>(
                  value: status,
                  title: 'Status',
                  borderRadius: 12,
                  fillColor: AppColors.surfaceVariant,
                  fontSize: 14,
                  enabled: !submitting,
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: submitting ? null : (v) => setSheet(() => status = v ?? 'active'),
                ),
                const SizedBox(height: 10),
                // Availability dropdown
                Text('Availability', style: _f(size: 12, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                AppSelect.fromItems<String>(
                  value: availability,
                  title: 'Availability',
                  borderRadius: 12,
                  fillColor: AppColors.surfaceVariant,
                  fontSize: 14,
                  enabled: !submitting,
                  items: const [
                    DropdownMenuItem(value: 'available', child: Text('Available')),
                    DropdownMenuItem(value: 'busy', child: Text('Busy')),
                    DropdownMenuItem(value: 'unavailable', child: Text('Unavailable')),
                  ],
                  onChanged: submitting ? null : (v) => setSheet(() => availability = v ?? 'available'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity, height: 46,
                  child: ElevatedButton(
                    onPressed: submitting ? null : () async {
                      setSheet(() => submitting = true);
                      final minNum = num.tryParse(minPriceCtrl.text.trim().replaceAll(',', ''));
                      final maxNum = num.tryParse(maxPriceCtrl.text.trim().replaceAll(',', ''));
                      final payload = <String, dynamic>{
                        'title': titleCtrl.text.trim(),
                        'description': descCtrl.text.trim(),
                        'status': status,
                        'availability': availability,
                        'location': locationCtrl.text.trim(),
                        if (minNum != null) 'min_price': minNum,
                        if (maxNum != null) 'max_price': maxNum,
                        if (selectedCategoryId.isNotEmpty) 'service_category_id': selectedCategoryId,
                        if (selectedTypeId.isNotEmpty) 'service_type_id': selectedTypeId,
                      };
                      final res = await UserServicesService.updateService(serviceId, payload);
                      if (!mounted) return;
                      if (res['success'] == true) {
                        Navigator.pop(ctx);
                        AppSnackbar.success(context, 'Service updated');
                        _load();
                      } else {
                        setSheet(() => submitting = false);
                        AppSnackbar.error(context, res['message']?.toString() ?? 'Unable to update service');
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Save Changes', style: _f(size: 13, weight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    titleCtrl.dispose(); descCtrl.dispose(); minPriceCtrl.dispose(); maxPriceCtrl.dispose(); locationCtrl.dispose();
  }

  Widget _sheetField(TextEditingController ctrl, String label, String hint, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: _f(size: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
