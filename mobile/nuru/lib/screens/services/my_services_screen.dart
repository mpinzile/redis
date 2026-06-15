import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/widgets/amount_input.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/api_service.dart';
import '../../core/services/events_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../core/services/user_services_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/agreement_gate.dart';
import '../photos/my_photo_libraries_screen.dart';
import 'service_detail_screen.dart';
import 'add_service_screen.dart';
import 'edit_service_screen.dart';
import 'manage_photos_screen.dart';
import 'manage_intro_clip_screen.dart';
import 'public_service_screen.dart';
import '../bookings/bookings_screen.dart';
import 'service_verification_screen.dart';
import '../../core/widgets/nuru_refresh.dart';
import '../../core/l10n/l10n_helper.dart';
import '../migration/migration_banner.dart';

/// MyServicesScreen - 2026 redesign matching the mockup pixel-close.
///
/// Layout (per mockup):
///   • AppBar: "My Services" + search action + gold "Add New" link
///   • Yellow vendor hero card: avatar + name + verified badge + headline
///     + rating + 3 stats (Services / Bookings / Completion Rate)
///   • "My Services" section heading
///   • Stack of compact service rows: 70×70 thumbnail · title · description
///     · "From TZS X" · 3-dot menu · gold Edit pill
///   • Verification banner (compact) when not verified - keeps activation
///     flow visible (critical, do not remove)
///   • "Recent Reviews" link → opens reviews bottom sheet (relocated, not
///     removed)
///
/// Every existing feature (View / Edit / Manage Photos / Intro Clip /
/// Add Package / My Events / Photo Libraries / Verification / Reviews) is
/// reachable through the per-card 3-dot menu sheet - nothing was deleted.
class MyServicesScreen extends StatefulWidget {
  const MyServicesScreen({super.key});

  @override
  State<MyServicesScreen> createState() => _MyServicesScreenState();
}

class _MyServicesScreenState extends State<MyServicesScreen> {
  List<dynamic> _services = [];
  List<dynamic> _recentReviews = [];
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _vendor = {};
  Map<String, dynamic> _profile = {};
  bool _loading = true;
  String _search = '';

  /// Locally-stored "Save Draft" payload from add_service_screen, if any.
  Map<String, dynamic>? _serviceDraft;
  static const String _draftKey = 'add_service_draft_v2';

  @override
  void initState() {
    super.initState();
    _load();
    _loadDraft();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final authUser = context.read<AuthProvider>().user;
    final results = await Future.wait<Map<String, dynamic>>([
      UserServicesService.getMyServices(
        search: _search.isEmpty ? null : _search,
        forceRefresh: true,
      ),
      EventsService.getProfile().catchError((_) => <String, dynamic>{'success': false}),
    ]);
    final res = results[0];
    final profileRes = results[1];
    if (!mounted) return;
    setState(() {
      if (!silent) _loading = false;
      final nextProfile = <String, dynamic>{};
      if (authUser != null) nextProfile.addAll(authUser);
      if (profileRes['success'] == true && profileRes['data'] is Map<String, dynamic>) {
        nextProfile.addAll(profileRes['data'] as Map<String, dynamic>);
      }
      _profile = nextProfile;
      if (res['success'] == true) {
        final data = res['data'];
        if (data is List) {
          _services = data;
        } else if (data is Map) {
          _services = data['services'] ?? [];
          _recentReviews = data['recent_reviews'] ?? [];
          _summary = data['summary'] is Map<String, dynamic>
              ? data['summary'] as Map<String, dynamic>
              : {};
          _vendor = data['vendor_profile'] is Map<String, dynamic>
              ? data['vendor_profile'] as Map<String, dynamic>
              : {};
        } else {
          _services = [];
        }
      }
    });
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw.isEmpty) {
        if (mounted) setState(() => _serviceDraft = null);
        return;
      }
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic> && mounted) {
        setState(() => _serviceDraft = data);
      }
    } catch (_) {}
  }

  Future<void> _discardDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
    if (mounted) setState(() => _serviceDraft = null);
  }

  TextStyle _f({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double height = 1.3,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  String get _currency {
    try {
      return context.read<WalletProvider>().currency;
    } catch (_) {
      return '';
    }
  }

  String _fmtPrice(dynamic p) {
    if (p == null) return 'Price on request';
    final n = (p is num)
        ? p.toInt()
        : (int.tryParse(p.toString().replaceAll(RegExp(r'[^\d]'), '')) ?? 0);
    if (n == 0) return 'Price on request';
    final body = n.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    final cur = _currency;
    return cur.isEmpty ? body : '$cur $body';
  }

  static String get _baseUrl => ApiService.baseUrl;

  Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _onAddNew() async {
    final ok = await AgreementGate.checkAndPrompt(context, 'vendor_agreement');
    if (!ok || !mounted) return;
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const AddServiceScreen()));
    if (result == true) _load();
    _loadDraft();
  }

  /// True when the vendor has ≥1 *approved* (verified) service in the
  /// Photography / Videography / Photography & Videography categories.
  /// Drives visibility of the Photo Libraries quick action.
  bool _hasApprovedPhotoVideoService() {
    for (final raw in _services) {
      if (raw is! Map) continue;
      final s = raw as Map<String, dynamic>;
      final verified = s['is_verified'] == true ||
          (s['verification_status']?.toString() ?? '') == 'verified';
      if (!verified) continue;
      final blob = [
        s['service_type_slug'],
        s['service_category']?['slug'],
        s['service_category']?['name'],
        s['service_type']?['slug'],
        s['service_type']?['name'],
        s['category'],
        s['category_name'],
      ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
      if (blob.contains('photo') || blob.contains('video')) return true;
    }
    return false;
  }

  String? _firstPhotoVideoServiceId() {
    for (final raw in _services) {
      if (raw is! Map) continue;
      final s = raw as Map<String, dynamic>;
      final verified = s['is_verified'] == true ||
          (s['verification_status']?.toString() ?? '') == 'verified';
      if (!verified) continue;
      final blob = [
        s['service_type_slug'],
        s['service_category']?['slug'],
        s['service_category']?['name'],
        s['service_type']?['slug'],
        s['service_type']?['name'],
      ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
      if (blob.contains('photo') || blob.contains('video')) {
        return s['id']?.toString();
      }
    }
    return null;
  }

  void _openAllPhotoLibraries() {
    final sid = _firstPhotoVideoServiceId();
    if (sid == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyPhotoLibrariesScreen(
          serviceId: sid,
          title: 'Photo Libraries',
        ),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leadingWidth: 56,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded,
              size: 24, color: AppColors.textPrimary),
        ),
        title: Text(
          context.tr('my_services'),
          style: _f(size: 17, weight: FontWeight.w700),
        ),
        actions: [
          if (_hasApprovedPhotoVideoService())
            IconButton(
              tooltip: 'Photo Libraries',
              onPressed: _openAllPhotoLibraries,
              icon: SvgPicture.asset(
                'assets/icons/photos-icon.svg',
                width: 22,
                height: 22,
                colorFilter: const ColorFilter.mode(
                    AppColors.textPrimary, BlendMode.srcIn),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 2),
            child: Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _onAddNew,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/icons/plus-icon.svg',
                      width: 16,
                      height: 16,
                      colorFilter: const ColorFilter.mode(
                          Color(0xFF1C1C24), BlendMode.srcIn),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: NuruRefresh(
        onRefresh: () => _load(silent: true),
        child: _loading
            ? ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _heroSkeleton(),
                  const SizedBox(height: 18),
                  ...List.generate(4, (_) => _rowSkeleton()),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  const MigrationBanner(
                    surface: MigrationSurface.services,
                    margin: EdgeInsets.only(bottom: 12),
                  ),
                  _vendorHero(),
                  const SizedBox(height: 18),
                  if (_serviceDraft != null) ...[
                    _draftCard(),
                    const SizedBox(height: 18),
                  ],
                  if (_services.isEmpty)
                    _emptyState(isFiltered: _search.trim().isNotEmpty)
                  else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('My Services',
                              style: _f(size: 16, weight: FontWeight.w800)),
                          if (_recentReviews.isNotEmpty)
                            GestureDetector(
                              onTap: _openReviewsSheet,
                              child: Row(
                                children: [
                                  const Icon(Icons.star_rounded,
                                      size: 14, color: Colors.amber),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Reviews (${_recentReviews.length})',
                                    style: _f(
                                      size: 12,
                                      weight: FontWeight.w700,
                                      color: const Color(0xFFB45309),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    ...List.generate(_services.length, (i) =>
                        _serviceRow(_services[i], isLast: i == _services.length - 1)),
                  ],
                ],
              ),
      ),
    );
  }

  // ─── Vendor hero (yellow card per mockup) ────────────────────────
  Widget _vendorHero() {
    final fullName = _firstNonEmpty([
      _vendor['full_name'],
      _vendor['name'],
      '${_vendor['first_name'] ?? _profile['first_name'] ?? ''} ${_vendor['last_name'] ?? _profile['last_name'] ?? ''}'.trim(),
      _profile['full_name'],
      _profile['name'],
      _profile['username'],
    ]);
    final headline = _firstNonEmpty([
      _vendor['headline'],
      _vendor['bio'],
      _profile['headline'],
      _profile['bio'],
      _profile['profession'],
      _profile['role'],
    ]);
    final avatar = _firstNonEmpty([
      _vendor['avatar_url'],
      _vendor['avatar'],
      _vendor['profile_picture_url'],
      _profile['avatar'],
      _profile['avatar_url'],
      _profile['profile_picture_url'],
    ]);
    final isVerified = _isIdentityVerified(_vendor) || _isIdentityVerified(_profile);
    final rating = _numValue([
      _vendor['average_rating'],
      _vendor['rating'],
      _summary['average_rating'],
      _summary['rating'],
    ]);
    final reviews = _intValue([
      _vendor['total_reviews'],
      _vendor['review_count'],
      _vendor['reviews_count'],
      _summary['total_reviews'],
      _summary['review_count'],
      _summary['reviews_count'],
      _recentReviews.length,
    ]);
    final svcCount = _services.length;
    final bookings = (_summary['total_bookings'] as num?)?.toInt() ?? 0;
    final pendingBookings = _intValue([
      _summary['pending_bookings'],
      _summary['pending_bookings_count'],
      _summary['bookings_pending'],
    ]);
    final completionRate =
        (_summary['completion_rate'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFECA08).withOpacity(0.85), // darker top-left
            const Color(0xFFFFD93D).withOpacity(0.65),
            const Color(0xFFFFE57A).withOpacity(0.55), // softer bottom-right
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // Top row: avatar + name + headline
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                clipBehavior: Clip.antiAlias,
                child: avatar.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatar,
                        fit: BoxFit.cover,
                        width: 52,
                        height: 52,
                        errorWidget: (_, __, ___) => _avatarFallback(fullName),
                      )
                    : _avatarFallback(fullName),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fullName.isEmpty ? 'Vendor Profile' : fullName,
                            style: _f(
                              size: 16,
                              weight: FontWeight.w800,
                              color: const Color(0xFF1C1C24),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4D6),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    size: 12, color: Color(0xFFE89A0C)),
                                const SizedBox(width: 4),
                                Text('Verified Vendor',
                                    style: _f(
                                      size: 10,
                                      weight: FontWeight.w700,
                                      color: const Color(0xFFB45309),
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headline.isEmpty ? 'Service Provider' : headline,
                      style: _f(
                        size: 12,
                        color: const Color(0xFF1C1C24),
                        weight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 14, color: Color(0xFF1C1C24)),
                        const SizedBox(width: 4),
                        Text(
                          '${rating.toStringAsFixed(1)} ($reviews ${reviews == 1 ? "review" : "reviews"})',
                          style: _f(
                            size: 12,
                            weight: FontWeight.w600,
                            color: const Color(0xFF1C1C24),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Stats row (3 stats per mockup)
          Row(
            children: [
              Expanded(child: _heroStat('$svcCount', 'Services')),
              _heroDivider(),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openBookings,
                  child: _heroStat('$bookings', 'Bookings'),
                ),
              ),
              _heroDivider(),
              Expanded(child: _heroStat('$completionRate%', 'Completion Rate')),
            ],
          ),
          // Manage Bookings CTA - only shown when there are pending bookings.
          if (pendingBookings > 0) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _openBookings,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C24),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inbox_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Manage Bookings',
                        style: _f(
                          size: 13.5,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('$pendingBookings',
                          style: _f(
                            size: 11,
                            weight: FontWeight.w800,
                            color: const Color(0xFF1C1C24),
                          )),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: Colors.white70, size: 13),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openBookings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BookingsScreen(mode: BookingsMode.vendor)),
    );
  }

  Widget _avatarFallback(String name) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'V';
    return Container(
      color: AppColors.primary.withOpacity(0.15),
      alignment: Alignment.center,
      child: Text(letter,
          style: _f(
            size: 20,
            weight: FontWeight.w800,
            color: const Color(0xFFB45309),
          )),
    );
  }

  Widget _heroStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: _f(
              size: 18,
              weight: FontWeight.w800,
              color: const Color(0xFF1C1C24),
            )),
        const SizedBox(height: 2),
        Text(label,
            style: _f(
              size: 10.5,
              weight: FontWeight.w600,
              color: const Color(0xFF3A2E07),
            )),
      ],
    );
  }

  Widget _heroDivider() => Container(
        width: 1,
        height: 30,
        color: const Color(0xFF3A2E07).withOpacity(0.18),
      );

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return '';
  }

  bool _isIdentityVerified(Map<String, dynamic> data) {
    final flag = data['is_identity_verified'] ??
        data['identity_verified'] ??
        data['kyc_verified'] ??
        data['is_verified'];
    if (flag == true) return true;
    final status = (data['verification_status'] ??
            data['identity_status'] ??
            data['kyc_status'])
        ?.toString()
        .toLowerCase();
    return status == 'verified' || status == 'approved';
  }

  num _numValue(List<dynamic> values) {
    for (final value in values) {
      if (value is num) return value;
      final parsed = num.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  int _intValue(List<dynamic> values) => _numValue(values).toInt();

  // ─── Service row (mockup: thumbnail + title + desc + From TZS + edit) ──
  Widget _serviceRow(dynamic service, {bool isLast = false}) {
    final s = service is Map<String, dynamic> ? service : <String, dynamic>{};
    final serviceId = s['id']?.toString() ?? '';
    final name =
        s['title']?.toString() ?? s['name']?.toString() ?? 'Service';
    final isVerified = s['is_verified'] == true ||
        s['verification_status'] == 'verified';
    final isPending =
        (s['verification_status']?.toString() ?? '') == 'pending';
    final verificationProgress = s['verification_progress'] ?? 0;
    final images = _extractImages(s);
    final price = s['min_price'] ?? s['starting_price'] ?? s['price'];
    final description = s['description']?.toString() ??
        s['short_description']?.toString() ??
        '';
    final priceUnit = s['price_unit']?.toString() ?? '';
    final categoryName = _firstNonEmpty([
      s['service_category']?['name'],
      s['category_name'],
      s['category'],
      s['service_type']?['name'],
    ]);
    final serviceTypeNames = <String>[];
    final rawTypes = s['service_types'] ?? s['types'] ?? s['offered_services'];
    if (rawTypes is List) {
      for (final t in rawTypes) {
        if (t is String && t.trim().isNotEmpty) serviceTypeNames.add(t.trim());
        if (t is Map) {
          final n = (t['name'] ?? t['label'] ?? t['title'] ?? '').toString().trim();
          if (n.isNotEmpty) serviceTypeNames.add(n);
        }
      }
    }

    // Borderless row with a thin hairline divider that starts at the
    // right edge of the thumbnail and ends at the right edge of the card.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceDetailScreen(serviceId: serviceId),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 78,
                      height: 78,
                      child: images.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: images.first,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  _thumbFallback(),
                              placeholder: (_, __) => _thumbFallback(),
                            )
                          : _thumbFallback(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Body
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 5,
                          runSpacing: 2,
                          children: [
                            Text(
                              name,
                              style: _f(
                                  size: 13.5, weight: FontWeight.w800),
                            ),
                            if (isVerified && !isPending)
                              const Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: Color(0xFFFECA08),
                              ),
                          ],
                        ),
                        if (categoryName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            categoryName,
                            style: _f(
                              size: 11.5,
                              color: AppColors.primaryDark,
                              weight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (serviceTypeNames.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: serviceTypeNames.take(4).map((t) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4F4F6),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(t,
                                    style: _f(
                                      size: 10.5,
                                      weight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    )),
                              );
                            }).toList(),
                          ),
                        ] else if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: _f(
                              size: 12,
                              color: AppColors.textSecondary,
                              weight: FontWeight.w500,
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 14, color: Color(0xFFFECA08)),
                            const SizedBox(width: 3),
                            Text(
                              '${_numValue([s['rating'], s['average_rating']]).toStringAsFixed(1)} (${_intValue([s['review_count'], s['reviews_count'], s['total_reviews']])} ${_intValue([s['review_count'], s['reviews_count'], s['total_reviews']]) == 1 ? "review" : "reviews"})',
                              style: _f(
                                size: 11.5,
                                weight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('From ',
                                      style: _f(
                                        size: 12,
                                        weight: FontWeight.w600,
                                        color: AppColors.textTertiary,
                                      )),
                                  Flexible(
                                    child: Text(
                                      _fmtPrice(price),
                                      style: _f(
                                        size: 12.5,
                                        weight: FontWeight.w800,
                                        color: AppColors.success,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (priceUnit.isNotEmpty)
                                    Text(' / $priceUnit',
                                        style: _f(
                                          size: 11.5,
                                          weight: FontWeight.w600,
                                          color: AppColors.textTertiary,
                                        )),
                                ],
                              ),
                            ),
                            // Edit pill - fully rounded, primary colored text & border
                            GestureDetector(
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EditServiceScreen(service: s),
                                  ),
                                );
                                if (result == true) _load();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.primaryDark,
                                      width: 1),
                                ),
                                child: Text('Edit',
                                    style: _f(
                                      size: 12,
                                      weight: FontWeight.w600,
                                      color: AppColors.primaryDark,
                                    )),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Three-dot menu pinned to the far-right edge of the card
                  GestureDetector(
                    onTap: () => _openManageSheet(s),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 6, top: 2, right: 0),
                      child: Icon(
                        Icons.more_vert_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Inline activation banner - preserved (critical flow).
          if (!isVerified)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ServiceVerificationScreen(serviceId: serviceId),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPending
                            ? Icons.access_time_rounded
                            : Icons.bolt_rounded,
                        size: 14,
                        color: const Color(0xFFB45309),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isPending
                              ? 'Activation in review'
                              : 'Activate ($verificationProgress%)',
                          style: _f(
                            size: 11.5,
                            weight: FontWeight.w800,
                            color: const Color(0xFFB45309),
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 16, color: Color(0xFFB45309)),
                    ],
                  ),
                ),
              ),
            ),
          // Hairline divider - starts where the thumbnail ends, runs to the right edge.
          if (!isLast)
            Padding(
              padding: const EdgeInsets.only(left: 94, right: 4),
              child: Container(
                height: 1,
                color: const Color(0xFFEFEFF3),
              ),
            ),
        ],
      );
  }

  Widget _thumbFallback() => Container(
        color: const Color(0xFFF1F2F6),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined,
            color: AppColors.textTertiary, size: 22),
      );

  // ─── Empty state ─────────────────────────────────────────────────
  Widget _emptyState({bool isFiltered = false}) {
    return _emptyStateImpl(isFiltered: isFiltered);
  }

  Widget _draftCard() {
    final d = _serviceDraft ?? const <String, dynamic>{};
    final title = (d['title'] ?? '').toString().trim();
    final step = (d['step'] is int) ? d['step'] as int : 0;
    final stepLabels = ['Personal Info', 'Business Info', 'Documents'];
    final stepLabel = stepLabels[step.clamp(0, 2)];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.edit_note_rounded, size: 22, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Continue draft', style: _f(size: 13.5, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            title.isNotEmpty ? '$title · $stepLabel' : 'Unfinished service · $stepLabel',
            style: _f(size: 12, color: AppColors.textSecondary),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ])),
        TextButton(
          onPressed: _discardDraft,
          child: Text('Discard', style: _f(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: _onAddNew,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text('Resume', style: _f(size: 12, weight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _emptyStateImpl({bool isFiltered = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(38),
              ),
              child: Center(
                child: SvgPicture.asset(
                  isFiltered
                      ? 'assets/icons/search-icon.svg'
                      : 'assets/icons/package-icon.svg',
                  width: 30,
                  height: 30,
                  colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(isFiltered ? 'No results found' : 'No services yet',
                style: _f(size: 18, weight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              isFiltered
                  ? 'No services match your search. Try a different keyword or clear the search to see all your services.'
                  : 'Add your first service so clients can find you and send bookings.',
              style: _f(size: 13, color: AppColors.textTertiary, height: 1.45),
              textAlign: TextAlign.center,
            ),
            if (!isFiltered) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _onAddNew,
                  icon: SvgPicture.asset(
                    'assets/icons/plus-icon.svg',
                    width: 16,
                    height: 16,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                  label: Text('Add Service',
                      style: _f(size: 14, weight: FontWeight.w700, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Skeletons ───────────────────────────────────────────────────
  Widget _heroSkeleton() => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFECA08).withOpacity(0.85),
              const Color(0xFFFFD93D).withOpacity(0.65),
              const Color(0xFFFFE57A).withOpacity(0.55),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 180,
                        height: 11,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 100,
                        height: 11,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: List.generate(3, (i) {
                return Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 32,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 60,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      );
  Widget _skBox(double w, double h, {double r = 6, double opacity = 1}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: const Color(0xFFEDEEF2).withOpacity(opacity),
          borderRadius: BorderRadius.circular(r),
        ),
      );

  Widget _rowSkeleton() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 78x78 thumbnail w/ 14 radius (matches _serviceRow)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _skBox(78, 78, r: 14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skBox(160, 13.5, r: 5),
                  const SizedBox(height: 8),
                  _skBox(100, 11.5, r: 5, opacity: 0.85),
                  const SizedBox(height: 8),
                  // type chips row
                  Row(children: [
                    _skBox(54, 18, r: 999, opacity: 0.7),
                    const SizedBox(width: 6),
                    _skBox(70, 18, r: 999, opacity: 0.7),
                    const SizedBox(width: 6),
                    _skBox(44, 18, r: 999, opacity: 0.7),
                  ]),
                  const SizedBox(height: 8),
                  // rating line
                  _skBox(110, 11, r: 5, opacity: 0.7),
                  const SizedBox(height: 10),
                  // price + edit pill
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _skBox(95, 12, r: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFE7E8EE), width: 1),
                        ),
                        child: _skBox(26, 10, r: 4, opacity: 0.7),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _skBox(20, 20, r: 10, opacity: 0.7),
          ],
        ),
      );

  // ─── Image extraction (unchanged) ────────────────────────────────
  List<String> _extractImages(Map<String, dynamic> s) {
    final result = <String>[];
    final images = s['images'];
    if (images is List) {
      for (final img in images) {
        if (img is String && img.isNotEmpty) result.add(img);
        if (img is Map) {
          final url = img['thumbnail_url']?.toString() ??
              img['url']?.toString() ??
              img['image_url']?.toString() ??
              img['file_url']?.toString() ??
              '';
          if (url.isNotEmpty) result.add(url);
        }
      }
    }
    if (result.isEmpty) {
      final primary = s['primary_image'];
      if (primary is String && primary.isNotEmpty) result.add(primary);
      if (primary is Map) {
        final url = primary['thumbnail_url']?.toString() ??
            primary['url']?.toString() ??
            '';
        if (url.isNotEmpty) result.add(url);
      }
    }
    return result;
  }

  // ─── Reviews bottom sheet (relocated, not removed) ───────────────
  void _openReviewsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7E8EE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 18),
                    const SizedBox(width: 6),
                    Text('Recent Reviews',
                        style: _f(size: 16, weight: FontWeight.w800)),
                  ],
                ),
              ),
              const Divider(height: 22),
              Expanded(
                child: _recentReviews.isEmpty
                    ? Center(
                        child: Text('No reviews yet',
                            style: _f(
                                size: 13,
                                color: AppColors.textTertiary)),
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: _recentReviews.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 22),
                        itemBuilder: (_, i) {
                          final r = _recentReviews[i] is Map<String, dynamic>
                              ? _recentReviews[i] as Map<String, dynamic>
                              : <String, dynamic>{};
                          final name =
                              r['user_name']?.toString() ?? 'User';
                          final rating = r['rating'] ?? 0;
                          final comment = r['comment']?.toString() ?? '';
                          final svc = r['service_title']?.toString() ?? '';
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor:
                                    AppColors.primary.withOpacity(0.15),
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : 'U',
                                  style: _f(
                                    size: 13,
                                    weight: FontWeight.w800,
                                    color: const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(name,
                                            style: _f(
                                                size: 13,
                                                weight: FontWeight.w700)),
                                        const SizedBox(width: 6),
                                        ...List.generate(
                                          5,
                                          (idx) => Icon(
                                            idx <
                                                    (rating is num
                                                        ? rating.round()
                                                        : 0)
                                                ? Icons.star_rounded
                                                : Icons.star_outline_rounded,
                                            size: 12,
                                            color: Colors.amber,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (svc.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(svc,
                                          style: _f(
                                            size: 11,
                                            color: AppColors.textTertiary,
                                            weight: FontWeight.w600,
                                          )),
                                    ],
                                    if (comment.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(comment,
                                          style: _f(
                                            size: 12.5,
                                            color: AppColors.textSecondary,
                                            height: 1.4,
                                          )),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Manage sheet (3-dot menu) - every existing per-card action ──
  Future<void> _openManageSheet(Map<String, dynamic> service) async {
    final serviceId = service['id']?.toString() ?? '';
    if (serviceId.isEmpty) return;
    final name = service['title']?.toString() ?? 'Service';
    final isVerified = service['is_verified'] == true ||
        service['verification_status'] == 'verified';
    final serviceTypeSlug = (service['service_type_slug'] ??
            service['service_category']?['slug'] ??
            service['service_type']?['slug'] ??
            '')
        .toString()
        .toLowerCase();
    final isPhotographyService = serviceTypeSlug.contains('photo');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7E8EE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(name,
                    style: _f(size: 14, weight: FontWeight.w800)),
              ),
              _sheetItem(
                svg: 'assets/icons/info-icon.svg',
                label: 'View Service',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PublicServiceScreen(serviceId: serviceId),
                    ),
                  );
                },
              ),
              _sheetItem(
                svg: 'assets/icons/pen-icon.svg',
                label: 'Manage Service',
                onTap: () async {
                  Navigator.pop(ctx);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          EditServiceScreen(service: service),
                    ),
                  );
                  if (result == true) _load();
                },
              ),
              if (_intValue([
                    service['pending_bookings_count'],
                    service['pending_bookings'],
                  ]) >
                  0)
                _sheetItem(
                  svg: 'assets/icons/bag-icon.svg',
                  label:
                      'Manage Bookings (${_intValue([service['pending_bookings_count'], service['pending_bookings']])})',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openBookings();
                  },
                ),
              _sheetItem(
                svg: 'assets/icons/image-icon.svg',
                label: 'Manage Photos',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManagePhotosScreen(
                        serviceId: serviceId,
                        serviceName: name,
                      ),
                    ),
                  );
                },
              ),
              _sheetItem(
                svg: 'assets/icons/camera-icon.svg',
                label: 'Manage Intro Clip',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManageIntroClipScreen(
                        serviceId: serviceId,
                        serviceName: name,
                      ),
                    ),
                  );
                },
              ),
              if (isVerified)
                _sheetItem(
                  svg: 'assets/icons/package-icon.svg',
                  label: 'Add Package',
                  onTap: () {
                    Navigator.pop(ctx);
                    _addPackageSheet(serviceId);
                  },
                ),
              if (isPhotographyService && isVerified)
                _sheetItem(
                  svg: 'assets/icons/photos-icon.svg',
                  label: 'Photo Libraries',
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MyPhotoLibrariesScreen(
                          serviceId: serviceId,
                          title: '$name · Photos',
                        ),
                      ),
                    );
                  },
                ),
              _sheetItem(
                svg: 'assets/icons/calendar-icon.svg',
                label: 'My Events',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ServiceDetailScreen(serviceId: serviceId),
                    ),
                  );
                },
              ),
              if (!isVerified)
                _sheetItem(
                  svg: 'assets/icons/rocket-icon.svg',
                  iconColor: const Color(0xFFB45309),
                  label: 'Continue Activation',
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ServiceVerificationScreen(serviceId: serviceId),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetItem({
    IconData? icon,
    String? svg,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final tint = iconColor ?? AppColors.textSecondary;
    final leading = svg != null
        ? SvgPicture.asset(svg,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(tint, BlendMode.srcIn))
        : Icon(icon ?? Icons.circle_outlined, size: 20, color: tint);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: _f(size: 13.5, weight: FontWeight.w700)),
            ),
            SvgPicture.asset(
              'assets/icons/chevron-right-icon.svg',
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(
                  AppColors.textTertiary, BlendMode.srcIn),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Add Package sheet (preserved verbatim) ──────────────────────
  Future<void> _addPackageSheet(String serviceId) async {
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
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Add Service Package',
                      style: _f(size: 18, weight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  _sheetField(nameCtrl, 'Package Name',
                      'e.g. Basic, Premium, Gold'),
                  const SizedBox(height: 10),
                  _sheetField(descCtrl, 'Description',
                      'Brief description...',
                      maxLines: 2),
                  const SizedBox(height: 10),
                  _sheetField(priceCtrl, 'Price (TZS)', 'e.g. 150,000',
                      keyboardType: TextInputType.number, inputFormatters: amountFormatters),
                  const SizedBox(height: 10),
                  _sheetField(featuresCtrl,
                      'Features (comma-separated)',
                      'e.g. 5 hours, 200 photos, Gallery',
                      maxLines: 2),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              if (nameCtrl.text.trim().isEmpty) {
                                AppSnackbar.error(
                                    context, 'Package name required');
                                return;
                              }
                              if (priceCtrl.text.trim().isEmpty) {
                                AppSnackbar.error(
                                    context, 'Price required');
                                return;
                              }
                              setSheet(() => submitting = true);
                              try {
                                final headers = await _headers();
                                final res = await http.post(
                                  Uri.parse(
                                      '$_baseUrl/user-services/$serviceId/packages'),
                                  headers: headers,
                                  body: jsonEncode({
                                    'name': nameCtrl.text.trim(),
                                    'description': descCtrl.text.trim(),
                                    'price': parseAmount(priceCtrl.text) ?? 0,
                                    'features': featuresCtrl.text
                                        .split(',')
                                        .map((f) => f.trim())
                                        .where((f) => f.isNotEmpty)
                                        .toList(),
                                  }),
                                );
                                if (res.statusCode >= 200 &&
                                    res.statusCode < 300) {
                                  if (mounted) {
                                    Navigator.pop(ctx);
                                    AppSnackbar.success(
                                        context, 'Package added!');
                                    _load();
                                  }
                                } else {
                                  setSheet(() => submitting = false);
                                  AppSnackbar.error(
                                      context, 'Failed to add package');
                                }
                              } catch (e) {
                                setSheet(() => submitting = false);
                                AppSnackbar.error(
                                    context, 'Failed to add package');
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: const Color(0xFF1C1C24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Color(0xFF1C1C24), strokeWidth: 2),
                            )
                          : Text('Save Package',
                              style: _f(
                                size: 13,
                                weight: FontWeight.w800,
                                color: const Color(0xFF1C1C24),
                              )),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    descCtrl.dispose();
    priceCtrl.dispose();
    featuresCtrl.dispose();
  }

  Widget _sheetField(
    TextEditingController ctrl,
    String label,
    String hint, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }
}
