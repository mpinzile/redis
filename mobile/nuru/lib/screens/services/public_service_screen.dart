import '../../core/widgets/nuru_refresh_indicator.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/user_services_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/messages_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../providers/wallet_provider.dart';
import '../../core/widgets/nuru_skeleton.dart';

import '../messages/messages_screen.dart';
import '../../core/l10n/l10n_helper.dart';

/// Public Service Detail - 2026 redesign matching the customer-facing
/// service mockup pixel-close.
///
/// Layout (per mockup):
///   • Image carousel hero with circle back button + favorite button +
///     "1/N" dot indicator (no overlay text on image)
///   • Title + category chip + rating chip + location chip row (under hero)
///   • White vendor card with avatar + name + verified pill + headline
///   • "About This Service" section card
///   • "What's Included" checkmark list (sourced from packages features +
///     service-level inclusions)
///   • Service Packages - relocated, kept fully functional
///   • Availability Calendar - kept fully functional
///   • Write a Review + Client Reviews - kept fully functional
///   • Trust badges - kept
///   • Sticky bottom bar: Chat (outlined) + Book This Service (gold)
///     with "Starting from TZS …" label
class PublicServiceScreen extends StatefulWidget {
  final String serviceId;
  const PublicServiceScreen({super.key, required this.serviceId});

  @override
  State<PublicServiceScreen> createState() => _PublicServiceScreenState();
}

class _PublicServiceScreenState extends State<PublicServiceScreen> {
  static String get _baseUrl => ApiService.baseUrl;
  bool _loading = true;
  bool _booking = false;
  bool _startingChat = false;
  bool _favorited = false;
  Map<String, dynamic> _service = {};
  List<dynamic> _packages = [];
  List<dynamic> _reviews = [];
  List<dynamic> _bookedDates = [];
  List<dynamic> _introMedia = [];
  bool _calendarLoading = true;
  bool _reviewsLoading = false;
  DateTime _currentMonth = DateTime.now();
  int _heroIndex = 0;
  final PageController _heroCtrl = PageController();

  // Review form
  int _reviewRating = 0;
  final _reviewCtrl = TextEditingController();
  bool _submittingReview = false;

  // ─── Theme tokens (mockup-matched) ─────────────────────────────
  static const _bg = Color(0xFFF6F7FB);
  static const _gold = AppColors.primary; // brand yellow
  static const _ink = Color(0xFF1C1C24);
  static const _muted = Color(0xFF6B7280);
  static const _hairline = Color(0xFFE5E7EB);
  static const _goldInk = Color(0xFF3A2E07);

  TextStyle _f({
    required double size,
    FontWeight weight = FontWeight.w500,
    Color color = _ink,
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    _heroCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final headers = await _headers();
      final res = await http.get(
        Uri.parse('$_baseUrl/services/${widget.serviceId}'),
        headers: headers,
      );
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body);
        final data = body['data'] ?? body;
        Map<String, dynamic> svc = {};
        if (data is Map<String, dynamic>) {
          svc = (data['service'] is Map<String, dynamic>)
              ? data['service'] as Map<String, dynamic>
              : data;
        }
        setState(() {
          _loading = false;
          _service = svc;
          _packages = svc['packages'] is List ? svc['packages'] as List : [];
          _introMedia =
              svc['intro_media'] is List ? svc['intro_media'] as List : [];
        });
      } else {
        // Fallback to user-services endpoint
        final res2 =
            await UserServicesService.getServiceDetail(widget.serviceId);
        if (!mounted) return;
        final data = res2['data'];
        Map<String, dynamic> svc = {};
        if (res2['success'] == true && data is Map<String, dynamic>) {
          svc = (data['service'] is Map<String, dynamic>)
              ? data['service'] as Map<String, dynamic>
              : data;
        }
        setState(() {
          _loading = false;
          _service = svc;
          _packages = svc['packages'] is List ? svc['packages'] as List : [];
          _introMedia =
              svc['intro_media'] is List ? svc['intro_media'] as List : [];
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    _loadCalendar();
    _loadReviews();
  }

  Future<void> _loadCalendar() async {
    setState(() => _calendarLoading = true);
    try {
      final headers = await _headers();
      final res = await http.get(
        Uri.parse('$_baseUrl/services/${widget.serviceId}/calendar'),
        headers: headers,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final d = data['data'] ?? data;
        setState(() => _bookedDates = d['booked_dates'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _calendarLoading = false);
  }

  Future<void> _loadReviews([int page = 1]) async {
    setState(() => _reviewsLoading = true);
    try {
      final headers = await _headers();
      final res = await http.get(
        Uri.parse(
          '$_baseUrl/services/${widget.serviceId}/reviews?page=$page&limit=10',
        ),
        headers: headers,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final d = data['data'] ?? data;
        setState(() => _reviews = d['reviews'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _reviewsLoading = false);
  }

  Future<void> _messageProvider() async {
    final s = _service;
    final provider = s['provider'] is Map<String, dynamic>
        ? s['provider'] as Map<String, dynamic>
        : (s['user'] is Map<String, dynamic>
            ? s['user'] as Map<String, dynamic>
            : <String, dynamic>{});
    final providerId = provider['id']?.toString() ??
        s['user_id']?.toString() ??
        s['provider_id']?.toString() ??
        '';
    if (providerId.isEmpty) {
      AppSnackbar.error(context, 'Provider info missing');
      return;
    }

    setState(() => _startingChat = true);
    final serviceTitle =
        s['title']?.toString() ?? s['name']?.toString() ?? 'service';
    final res = await MessagesService.startConversation(
      recipientId: providerId,
      serviceId: widget.serviceId,
      message:
          'Hi, I\'m interested in your service "$serviceTitle". I\'d like to discuss booking details.',
    );
    if (!mounted) return;
    setState(() => _startingChat = false);

    if (res['success'] == true) {
      final data = res['data'];
      final convId =
          (data is Map ? (data['id'] ?? data['conversation_id']) : null)
              ?.toString();
      final first = provider['first_name']?.toString() ?? '';
      final last = provider['last_name']?.toString() ?? '';
      final name = '$first $last'.trim().isNotEmpty
          ? '$first $last'.trim()
          : (provider['name']?.toString() ?? 'Provider');
      // Detect vendor verification across various API shapes so the chat
      // shows the verified-vendor banner + checkmark immediately, matching
      // the experience when the user opens the same thread from the inbox.
      final bool isVerified = provider['is_verified'] == true ||
          provider['verified'] == true ||
          provider['kyc_verified'] == true ||
          (s['verification_status']?.toString().toLowerCase() == 'verified') ||
          s['is_verified'] == true;
      // Build a service summary so the in-chat service-context card renders
      // (image + title + venue + View button) without an extra round-trip.
      final List images = (s['images'] is List) ? s['images'] as List : const [];
      String? primaryImage;
      if (images.isNotEmpty) {
        final first = images.first;
        if (first is Map) {
          primaryImage = first['image_url']?.toString() ?? first['url']?.toString();
        } else if (first is String) {
          primaryImage = first;
        }
      }
      primaryImage ??= s['cover_image']?.toString() ??
          s['primary_image']?.toString() ??
          s['image']?.toString();
      final serviceSummary = <String, dynamic>{
        'id': widget.serviceId,
        'title': serviceTitle,
        'image': primaryImage,
        'location': s['location']?.toString(),
      };
      final providerAvatar = (provider['avatar']?.toString().isNotEmpty == true
              ? provider['avatar']?.toString()
              : null) ??
          provider['avatar_url']?.toString() ??
          provider['profile_image']?.toString() ??
          provider['profile_picture']?.toString() ??
          provider['photo_url']?.toString() ??
          s['owner_avatar']?.toString() ??
          s['provider_avatar']?.toString();
      if (convId != null && convId.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              conversationId: convId,
              name: name,
              avatar: providerAvatar,
              isVendor: true,
              isVerifiedVendor: isVerified,
              isVerified: isVerified,
              service: serviceSummary,
            ),
          ),
        );
      }
    } else {
      AppSnackbar.error(context, res['message'] ?? 'Unable to start chat');
    }
  }

  Future<void> _submitReview() async {
    if (_reviewRating == 0) {
      AppSnackbar.error(context, 'Please select a rating');
      return;
    }
    if (_reviewCtrl.text.trim().length < 10) {
      AppSnackbar.error(context, 'Review must be at least 10 characters');
      return;
    }
    setState(() => _submittingReview = true);
    try {
      final headers = await _headers();
      final res = await http.post(
        Uri.parse('$_baseUrl/services/${widget.serviceId}/reviews'),
        headers: headers,
        body: jsonEncode({
          'rating': _reviewRating,
          'comment': _reviewCtrl.text.trim(),
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        AppSnackbar.success(context, 'Review submitted!');
        setState(() {
          _reviewRating = 0;
          _reviewCtrl.clear();
        });
        _loadReviews();
      } else {
        AppSnackbar.error(context, 'Failed to submit review');
      }
    } catch (_) {
      AppSnackbar.error(context, 'Failed to submit review');
    }
    if (mounted) setState(() => _submittingReview = false);
  }

  List<String> _getImages() {
    final images = <String>[];
    final imgs = _service['images'];
    if (imgs is List) {
      for (final img in imgs) {
        if (img is String && img.isNotEmpty) images.add(img);
        if (img is Map) {
          final url =
              img['url']?.toString() ?? img['image_url']?.toString() ?? '';
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
    final svcCur = _service['currency_code']?.toString() ?? '';
    final cur = svcCur.isNotEmpty ? svcCur : _currency;
    return cur.isEmpty ? body : '$cur $body';
  }

  String _formatPriceDisplay() {
    final min =
        _service['min_price'] ?? _service['starting_price'] ?? _service['price'];
    if (min != null) return 'From ${_fmtPrice(min)}';
    return 'Price on request';
  }

  /// Aggregate "What's Included" items from service-level inclusions and
  /// the first (default) package's features. De-duped, max 8.
  List<String> _whatsIncluded() {
    final items = <String>{};
    final svcInc = _service['inclusions'] ?? _service['features'];
    if (svcInc is List) {
      for (final x in svcInc) {
        final s = x?.toString().trim() ?? '';
        if (s.isNotEmpty) items.add(s);
      }
    }
    if (_packages.isNotEmpty) {
      final p0 = _packages.first;
      if (p0 is Map && p0['features'] is List) {
        for (final x in (p0['features'] as List)) {
          final s = x?.toString().trim() ?? '';
          if (s.isNotEmpty) items.add(s);
        }
      }
    }
    return items.take(8).toList();
  }

  // Plain mockup-aligned AppBar: clean chevron-left back arrow,
  // centered title, optional heart + share actions (no bordered tiles).
  PreferredSizeWidget _plainAppBar({bool showActions = false}) {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leadingWidth: 56,
      leading: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded,
            size: 24, color: _ink),
      ),
      title: Text(
        'Service Details',
        style: _f(size: 17, weight: FontWeight.w700, color: _ink),
      ),
      actions: showActions
          ? [
              IconButton(
                tooltip: 'Favorite',
                icon: Icon(
                  _favorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _favorited ? const Color(0xFFE11D48) : _ink,
                  size: 22,
                ),
                onPressed: () => setState(() => _favorited = !_favorited),
              ),
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share_rounded,
                    color: _ink, size: 21),
                onPressed: () {},
              ),
              const SizedBox(width: 4),
            ]
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _plainAppBar(),
        body: _detailSkeleton(),
      );
    }

    final s = _service;
    final title = s['title']?.toString() ?? s['name']?.toString() ?? 'Service';
    final description = s['description']?.toString() ?? '';
    final rating = (s['rating'] ?? s['average_rating'] ?? 0);
    final reviewCount =
        s['review_count'] ?? s['reviews_count'] ?? _reviews.length;
    final images = _getImages();
    final included = _whatsIncluded();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _plainAppBar(showActions: true),
      body: NuruRefreshIndicator(
        onRefresh: _load,
        color: _gold,
        child: CustomScrollView(
          slivers: [
            // ─── Hero gallery (full-width, dots + 1/N badge)
            SliverToBoxAdapter(child: _heroGallery(images)),

            // ─── Title + price row
            SliverToBoxAdapter(
              child: _titlePriceRow(title),
            ),

            // ─── Vendor row (avatar + name + rating)
            SliverToBoxAdapter(child: _vendorRow()),

            // ─── Feature highlight chips (per mockup)
            SliverToBoxAdapter(
              child: _highlightChipsRow(),
            ),

            // ─── About (plain section per mockup - no card chrome)
            if (description.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('About this Service',
                          style: _f(
                            size: 15.5,
                            weight: FontWeight.w800,
                            color: _ink,
                          )),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: _f(
                          size: 13.5,
                          color: _muted,
                          height: 1.55,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ─── What's Included (plain section per mockup)
            if (included.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("What's Included",
                          style: _f(
                            size: 15.5,
                            weight: FontWeight.w800,
                            color: _ink,
                          )),
                      const SizedBox(height: 10),
                      ...included.map((it) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 18,
                                  height: 18,
                                  margin: const EdgeInsets.only(top: 1),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF1B9E47),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(it,
                                      style: _f(
                                        size: 13.5,
                                        weight: FontWeight.w600,
                                        color: _ink,
                                        height: 1.4,
                                      )),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ),

            // ─── Intro media (relocated, preserved)
            if (_introMedia.isNotEmpty)
              SliverToBoxAdapter(
                child: _sectionCard(
                  title: 'Introduction',
                  iconAsset: 'assets/icons/play-icon.svg',
                  child: Column(
                    children: _introMedia.map((media) {
                      final type = (media is Map ? media['media_type'] : '')
                              ?.toString() ??
                          '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAF7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _hairline),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _gold.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: SvgPicture.asset(
                                  'assets/icons/play-icon.svg',
                                  width: 18,
                                  height: 18,
                                  colorFilter: const ColorFilter.mode(
                                      _goldInk, BlendMode.srcIn),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                type == 'video'
                                    ? 'Video Introduction'
                                    : 'Audio Introduction',
                                style: _f(
                                    size: 13, weight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            // ─── Packages
            if (_packages.isNotEmpty)
              SliverToBoxAdapter(child: _packagesSection()),

            // ─── Calendar
            SliverToBoxAdapter(child: _calendarSection()),

            // ─── Write review
            SliverToBoxAdapter(child: _writeReviewSection()),

            // ─── Reviews
            SliverToBoxAdapter(child: _reviewsSection(reviewCount, rating)),

            // ─── Trust badges
            SliverToBoxAdapter(child: _trustBadges(s)),

            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  /// Full-page skeleton that mirrors the final layout: hero gallery, title +
  /// price row, vendor row, highlight chips, about block, packages, calendar,
  /// reviews, sticky bottom bar. Keeps the perceived load fast and on-brand.
  Widget _detailSkeleton() {
    return NuruSkeletonGroup(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Hero
                NuruSkeleton.box(height: 260, radius: 0),
                const SizedBox(height: 18),
                // Title + price
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NuruSkeleton.text(width: 220, height: 18),
                            const SizedBox(height: 10),
                            NuruSkeleton.text(width: 140, height: 12),
                          ],
                        ),
                      ),
                      NuruSkeleton.box(width: 90, height: 22, radius: 6),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Vendor row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      NuruSkeleton.circle(size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NuruSkeleton.text(width: 160, height: 14),
                            const SizedBox(height: 6),
                            NuruSkeleton.text(width: 110, height: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                // Highlight chips
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: 4,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, __) =>
                        NuruSkeleton.box(width: 92, height: 32, radius: 16),
                  ),
                ),
                const SizedBox(height: 22),
                // About
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NuruSkeleton.text(width: 160, height: 16),
                      const SizedBox(height: 12),
                      NuruSkeleton.text(width: double.infinity, height: 10),
                      const SizedBox(height: 8),
                      NuruSkeleton.text(width: double.infinity, height: 10),
                      const SizedBox(height: 8),
                      NuruSkeleton.text(width: 220, height: 10),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                // What's included
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NuruSkeleton.text(width: 170, height: 16),
                      const SizedBox(height: 12),
                      for (int i = 0; i < 3; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            NuruSkeleton.circle(size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: NuruSkeleton.text(
                                  width: double.infinity, height: 10),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                // Packages
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      for (int i = 0; i < 2; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NuruSkeleton.box(height: 96, radius: 16),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Calendar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: NuruSkeleton.box(height: 220, radius: 18),
                ),
                const SizedBox(height: 22),
                // Reviews
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NuruSkeleton.text(width: 150, height: 16),
                      const SizedBox(height: 12),
                      for (int i = 0; i < 2; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NuruSkeleton.box(height: 78, radius: 14),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
          // Sticky bottom bar mirror
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _hairline, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(child: NuruSkeleton.box(height: 50, radius: 14)),
                const SizedBox(width: 10),
                Expanded(child: NuruSkeleton.box(height: 50, radius: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // HERO GALLERY
  // ════════════════════════════════════════════════════════════════
  Widget _heroGallery(List<String> images) {
    // Full-width hero image immediately under the app bar.
    // 1/N counter sits bottom-right; animated dot indicators bottom-center.
    return SizedBox(
      height: 280,
      width: double.infinity,
      child: images.isEmpty
          ? _heroPlaceholder()
          : Stack(
              children: [
                PageView.builder(
                  controller: _heroCtrl,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _heroIndex = i),
                  itemBuilder: (_, i) => CachedNetworkImage(
                    imageUrl: images[i],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorWidget: (_, __, ___) => _heroPlaceholder(),
                    placeholder: (_, __) => _heroPlaceholder(),
                  ),
                ),
                if (images.length > 1)
                  Positioned(
                    bottom: 14,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_heroIndex + 1}/${images.length}',
                        style: _f(
                          size: 11,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                if (images.length > 1)
                  Positioned(
                    bottom: 14,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        images.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin:
                              const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _heroIndex ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _heroIndex
                                ? Colors.white
                                : Colors.white60,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _heroPlaceholder() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _gold.withOpacity(0.3),
              _gold.withOpacity(0.1),
            ],
          ),
        ),
        child: const Center(
          child: Icon(Icons.work_outline, size: 56, color: _goldInk),
        ),
      );

  // (Removed unused _circleBtn - replaced by AppBar IconButtons.)

  // ════════════════════════════════════════════════════════════════
  // TITLE BLOCK
  // ════════════════════════════════════════════════════════════════
  // ════════════════════════════════════════════════════════════════
  // TITLE + PRICE ROW (mockup: title left, "From / TZS … / per event" right)
  // ════════════════════════════════════════════════════════════════
  Widget _titlePriceRow(String title) {
    final min = _service['min_price'] ??
        _service['starting_price'] ??
        _service['price'];
    final unit = (_service['price_unit']?.toString() ?? 'event').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: _f(
                size: 22,
                weight: FontWeight.w800,
                color: _ink,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('From',
                  style: _f(
                      size: 11,
                      weight: FontWeight.w600,
                      color: _muted)),
              const SizedBox(height: 2),
              Text(
                min == null ? 'On request' : _fmtPrice(min),
                style: _f(
                    size: 17,
                    weight: FontWeight.w800,
                    color: _ink),
              ),
              if (unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('/ $unit',
                      style: _f(
                          size: 11,
                          weight: FontWeight.w600,
                          color: _muted)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // VENDOR ROW (avatar · name + verified · rating row) - clean inline,
  // no card/shadow per mockup.
  // ════════════════════════════════════════════════════════════════
  Widget _vendorRow() {
    final s = _service;
    final provider = s['provider'] is Map
        ? s['provider'] as Map
        : (s['user'] is Map ? s['user'] as Map : {});
    final first = provider['first_name']?.toString() ?? '';
    final last = provider['last_name']?.toString() ?? '';
    final ownerName = '$first $last'.trim().isNotEmpty
        ? '$first $last'.trim()
        : (s['owner_name']?.toString() ??
            provider['name']?.toString() ??
            'Service Provider');
    final ownerAvatar = s['owner_avatar']?.toString() ??
        provider['avatar']?.toString() ??
        '';
    final isVerified = s['is_verified'] == true ||
        provider['is_verified'] == true ||
        s['verification_status'] == 'verified';
    final ratingNum = ((s['rating'] ?? s['average_rating'] ?? 0) as num)
        .toDouble();
    final reviewCount =
        (s['review_count'] ?? s['reviews_count'] ?? _reviews.length) ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gold.withOpacity(0.15),
            ),
            clipBehavior: Clip.antiAlias,
            child: ownerAvatar.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: ownerAvatar,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        _avatarFallback(ownerName),
                  )
                : _avatarFallback(ownerName),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        ownerName,
                        style: _f(
                            size: 13.5,
                            weight: FontWeight.w800,
                            color: _ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF6CF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded,
                                size: 11, color: Color(0xFF1B9E47)),
                            const SizedBox(width: 3),
                            Text('Verified Vendor',
                                style: _f(
                                  size: 9.5,
                                  weight: FontWeight.w800,
                                  color: _goldInk,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (ratingNum > 0) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 13, color: Color(0xFFB45309)),
                      const SizedBox(width: 3),
                      Text(
                        '${ratingNum.toStringAsFixed(1)} ($reviewCount ${reviewCount == 1 ? 'review' : 'reviews'})',
                        style: _f(
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // (Removed _chipsRow - superseded by _highlightChipsRow per mockup.)


  // ════════════════════════════════════════════════════════════════
  // FEATURE HIGHLIGHT CHIPS (per mockup: Custom Design, Premium Quality,
  // On-time Setup, 24/7 Support - sourced from service highlights or
  // package features. Shows up to 4 thin-icon pill chips.)
  // ════════════════════════════════════════════════════════════════
  Widget _highlightChipsRow() {
    final raw = <String>[];
    final h = _service['highlights'];
    if (h is List) {
      for (final x in h) {
        final s = x?.toString().trim() ?? '';
        if (s.isNotEmpty) raw.add(s);
      }
    }
    if (raw.isEmpty) {
      // Fallback: first features from inclusions
      final inc = _whatsIncluded();
      raw.addAll(inc);
    }
    if (raw.isEmpty) return const SizedBox.shrink();
    final items = raw.take(4).toList();

    IconData _iconFor(String label) {
      final l = label.toLowerCase();
      if (l.contains('design')) return Icons.brush_outlined;
      if (l.contains('premium') || l.contains('quality')) {
        return Icons.workspace_premium_outlined;
      }
      if (l.contains('time') || l.contains('setup') || l.contains('fast')) {
        return Icons.schedule_outlined;
      }
      if (l.contains('support') || l.contains('24')) {
        return Icons.support_agent_outlined;
      }
      if (l.contains('verified') || l.contains('trust')) {
        return Icons.verified_outlined;
      }
      return Icons.check_circle_outline;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items
            .map((label) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconFor(label), size: 13, color: _muted),
                      const SizedBox(width: 5),
                      Text(label,
                          style: _f(
                              size: 11.5,
                              weight: FontWeight.w600,
                              color: _ink)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  // (Removed unused _chip helper.)

  // (Removed unused _vendorCard - superseded by inline _vendorRow above.)

  Widget _avatarFallback(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'P';
    return Center(
      child: Text(initial,
          style: _f(size: 18, weight: FontWeight.w800, color: _goldInk)),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // SECTION CARD
  // ════════════════════════════════════════════════════════════════
  Widget _sectionCard({
    required String title,
    String? iconAsset,
    IconData? iconData,
    Widget? trailing,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (iconAsset != null) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: SvgPicture.asset(iconAsset,
                          width: 14,
                          height: 14,
                          colorFilter: const ColorFilter.mode(
                              _goldInk, BlendMode.srcIn)),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (iconData != null) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(iconData, size: 15, color: _goldInk),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(title,
                      style: _f(
                          size: 15.5,
                          weight: FontWeight.w800,
                          color: _ink)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // PACKAGES (relocated, full feature parity)
  // ════════════════════════════════════════════════════════════════
  Widget _packagesSection() {
    return _sectionCard(
      title: 'Service Packages',
      iconData: Icons.inventory_2_outlined,
      child: Column(
        children: _packages.asMap().entries.map((e) {
          final idx = e.key;
          final pkg = e.value is Map<String, dynamic>
              ? e.value as Map<String, dynamic>
              : <String, dynamic>{};
          final features =
              pkg['features'] is List ? (pkg['features'] as List) : [];
          final isTop = idx == 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isTop
                  ? const Color(0xFFFFF8E0)
                  : const Color(0xFFFAFAF7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: isTop ? _gold.withOpacity(0.4) : _hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              pkg['name']?.toString() ?? 'Package',
                              style: _f(
                                  size: 14, weight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isTop) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _gold,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Most Popular',
                                style: _f(
                                  size: 9,
                                  weight: FontWeight.w800,
                                  color: _goldInk,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      _fmtPrice(pkg['price']),
                      style: _f(
                          size: 13.5,
                          weight: FontWeight.w800,
                          color: _ink),
                    ),
                  ],
                ),
                if ((pkg['description']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(pkg['description'].toString(),
                      style: _f(
                          size: 11.5,
                          color: _muted,
                          weight: FontWeight.w500)),
                ],
                if (features.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...features.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_rounded,
                                size: 14, color: Color(0xFF1B9E47)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(f.toString(),
                                  style: _f(
                                      size: 11.5,
                                      color: _ink,
                                      weight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // CALENDAR (preserved logic, restyled)
  // ════════════════════════════════════════════════════════════════
  Widget _calendarSection() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final firstDay = DateTime(year, month, 1).weekday % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final today = DateTime.now();
    final months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December',
    ];
    final dayLabels = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];

    return _sectionCard(
      title: 'Availability',
      iconAsset: 'assets/icons/calendar-icon.svg',
      child: _calendarLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(color: _gold),
              ),
            )
          : Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _miniIconBtn(
                      asset: 'assets/icons/chevron-left-icon.svg',
                      onTap: () => setState(
                          () => _currentMonth = DateTime(year, month - 1)),
                    ),
                    Text('${months[month - 1]} $year',
                        style: _f(size: 14.5, weight: FontWeight.w800)),
                    _miniIconBtn(
                      asset: 'assets/icons/chevron-right-icon.svg',
                      onTap: () => setState(
                          () => _currentMonth = DateTime(year, month + 1)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: dayLabels
                      .map((d) => Expanded(
                            child: Center(
                              child: Text(d,
                                  style: _f(
                                      size: 10.5,
                                      weight: FontWeight.w700,
                                      color: _muted)),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 4),
                ...List.generate(6, (week) {
                  return Row(
                    children: List.generate(7, (dow) {
                      final idx = week * 7 + dow;
                      final dayNum = idx - firstDay + 1;
                      if (dayNum < 1 || dayNum > daysInMonth) {
                        return const Expanded(child: SizedBox(height: 38));
                      }
                      final dateStr =
                          '$year-${month.toString().padLeft(2, '0')}-${dayNum.toString().padLeft(2, '0')}';
                      final isToday = today.year == year &&
                          today.month == month &&
                          today.day == dayNum;
                      final isPast = DateTime(year, month, dayNum).isBefore(
                          DateTime(today.year, today.month, today.day));
                      final isBooked = _bookedDates
                          .any((b) => b is Map && b['date'] == dateStr);

                      return Expanded(
                        child: Container(
                          height: 38,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isToday
                                ? _gold.withOpacity(0.15)
                                : isBooked
                                    ? const Color(0xFFFEE2E2)
                                    : !isPast
                                        ? const Color(0xFFEAFBEE)
                                        : null,
                            borderRadius: BorderRadius.circular(10),
                            border: isToday
                                ? Border.all(color: _gold, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              '$dayNum',
                              style: _f(
                                size: 12,
                                weight: FontWeight.w700,
                                color: isToday
                                    ? _goldInk
                                    : isBooked
                                        ? const Color(0xFFDC2626)
                                        : isPast
                                            ? const Color(0xFFB6BAC2)
                                            : const Color(0xFF15803D),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                }),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _legendDot('Available', const Color(0xFFEAFBEE)),
                    const SizedBox(width: 12),
                    _legendDot('Booked', const Color(0xFFFEE2E2)),
                    const SizedBox(width: 12),
                    _legendDot('Today', _gold.withOpacity(0.15),
                        borderColor: _gold),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _miniIconBtn(
      {required String asset, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F2F6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SvgPicture.asset(asset,
              colorFilter: const ColorFilter.mode(_ink, BlendMode.srcIn)),
        ),
      ),
    );
  }

  Widget _legendDot(String label, Color color, {Color? borderColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor ?? _hairline),
          ),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: _f(size: 10.5, color: _muted, weight: FontWeight.w600)),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // WRITE REVIEW (preserved)
  // ════════════════════════════════════════════════════════════════
  Widget _writeReviewSection() {
    return _sectionCard(
      title: 'Write a Review',
      iconData: Icons.rate_review_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Only available if this service was on your event',
            style: _f(size: 11, color: _muted, weight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Text('Your Rating',
              style: _f(size: 12.5, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: List.generate(
              5,
              (i) => GestureDetector(
                onTap: () => setState(() => _reviewRating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    i < _reviewRating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 30,
                    color: i < _reviewRating
                        ? const Color(0xFFB45309)
                        : const Color(0xFFCBD0DA),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reviewCtrl,
            maxLines: 4,
            maxLength: 2000,
            style: _f(size: 13),
            decoration: InputDecoration(
              hintText: 'Share your experience (min 10 characters)…',
              hintStyle: _f(size: 13, color: const Color(0xFFA8AEBC)),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border, width: 1),
              ),
              contentPadding: const EdgeInsets.all(14),
              counterStyle: _f(size: 10, color: _muted),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _submittingReview ||
                      _reviewRating == 0 ||
                      _reviewCtrl.text.trim().length < 10
                  ? null
                  : _submitReview,
              icon: _submittingReview
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _goldInk),
                    )
                  : const Icon(Icons.send_rounded, size: 16, color: _goldInk),
              label: Text(
                _submittingReview ? 'Submitting…' : 'Submit Review',
                style: _f(
                    size: 13.5, weight: FontWeight.w800, color: _goldInk),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _goldInk,
                disabledBackgroundColor: _gold.withOpacity(0.4),
                disabledForegroundColor: _goldInk.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // REVIEWS (preserved)
  // ════════════════════════════════════════════════════════════════
  Widget _reviewsSection(dynamic reviewCount, dynamic rating) {
    final ratingNum = rating is num ? rating.toDouble() : 0.0;
    return _sectionCard(
      title: 'Client Reviews',
      iconData: Icons.people_outline_rounded,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F2F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            const Icon(Icons.star_rounded,
                size: 12, color: Color(0xFFB45309)),
            const SizedBox(width: 3),
            Text(
              ratingNum > 0 ? ratingNum.toStringAsFixed(1) : '-',
              style:
                  _f(size: 11, weight: FontWeight.w800, color: _ink),
            ),
            const SizedBox(width: 4),
            Text('· $reviewCount',
                style: _f(size: 11, weight: FontWeight.w600, color: _muted)),
          ],
        ),
      ),
      child: _reviewsLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: _gold),
              ),
            )
          : _reviews.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.star_outline_rounded,
                            size: 36, color: _muted.withOpacity(0.4)),
                        const SizedBox(height: 6),
                        Text('No reviews yet. Be the first!',
                            style: _f(size: 12, color: _muted)),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: _reviews.map((r) {
                    final review = r is Map<String, dynamic>
                        ? r
                        : <String, dynamic>{};
                    final name =
                        review['user_name']?.toString() ?? 'Anonymous';
                    final ratingVal = review['rating'] ?? 0;
                    final comment = review['comment']?.toString() ?? '';
                    final date = review['created_at']?.toString() ?? '';
                    final avatar = review['user_avatar']?.toString();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: _gold.withOpacity(0.15),
                            backgroundImage:
                                avatar != null && avatar.isNotEmpty
                                    ? NetworkImage(avatar)
                                    : null,
                            child: avatar == null || avatar.isEmpty
                                ? Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : 'A',
                                    style: _f(
                                        size: 12,
                                        weight: FontWeight.w800,
                                        color: _goldInk),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(name,
                                              style: _f(
                                                  size: 13,
                                                  weight:
                                                      FontWeight.w700)),
                                          if (date.isNotEmpty)
                                            Text(_formatDate(date),
                                                style: _f(
                                                    size: 10.5,
                                                    color: _muted)),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      children: List.generate(
                                        5,
                                        (i) => Icon(
                                          i <
                                                  (ratingVal is num
                                                      ? ratingVal.round()
                                                      : 0)
                                              ? Icons.star_rounded
                                              : Icons
                                                  .star_outline_rounded,
                                          size: 14,
                                          color: const Color(0xFFB45309),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (comment.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(comment,
                                      style: _f(
                                          size: 12.5,
                                          color: _muted,
                                          height: 1.45,
                                          weight: FontWeight.w500)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // TRUST BADGES (preserved)
  // ════════════════════════════════════════════════════════════════
  Widget _trustBadges(Map<String, dynamic> s) {
    return _sectionCard(
      title: 'Why Book Through Nuru',
      iconData: Icons.shield_outlined,
      child: Column(
        children: [
          _trustRow('assets/icons/shield-icon.svg',
              const Color(0xFF1B9E47), 'Verified & trusted on Nuru'),
          const SizedBox(height: 12),
          _trustRow(
              'assets/icons/verified-icon.svg',
              _goldInk,
              _timeOnPlatformFull(s['created_at']?.toString())),
          const SizedBox(height: 12),
          _trustRow('assets/icons/calendar-icon.svg',
              const Color(0xFF2563EB), 'Responds quickly to booking requests'),
        ],
      ),
    );
  }

  Widget _trustRow(String svgAsset, Color color, String text) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: SvgPicture.asset(
              svgAsset,
              width: 16,
              height: 16,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: _f(
                  size: 12.5, color: _ink, weight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // BOTTOM BAR (sticky Chat + Book)
  // ════════════════════════════════════════════════════════════════
  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: _hairline, width: 1),
          ),
        ),
        child: Row(
          children: [
            // Chat outlined (white bordered) - equal width
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _startingChat ? null : _messageProvider,
                  icon: _startingChat
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _ink),
                        )
                      : SvgPicture.asset(
                          'assets/icons/chat-icon.svg',
                          width: 16, height: 16,
                          colorFilter: const ColorFilter.mode(_ink, BlendMode.srcIn),
                        ),
                  label: Text(_startingChat ? 'Opening…' : 'Chat with Vendor',
                      style: _f(
                          size: 13.5,
                          weight: FontWeight.w700,
                          color: _ink)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: _hairline),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Book primary (gold filled) - equal width
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _booking ? null : _messageProvider,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _goldInk,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    elevation: 0,
                  ),
                  child: _booking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _goldInk),
                        )
                      : Text('Book This Service',
                          style: _f(
                              size: 13.5,
                              weight: FontWeight.w800,
                              color: _goldInk)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // Utils
  // ════════════════════════════════════════════════════════════════
  String _timeOnPlatform(String? created) {
    if (created == null || created.isEmpty) return 'New';
    try {
      final days =
          DateTime.now().difference(DateTime.parse(created)).inDays;
      if (days < 1) return 'Today';
      if (days < 30) return '${days}d on Nuru';
      final m = days ~/ 30;
      if (m < 12) return '${m}mo on Nuru';
      return '${m ~/ 12}yr on Nuru';
    } catch (_) {
      return 'On Nuru';
    }
  }

  String _timeOnPlatformFull(String? created) {
    if (created == null || created.isEmpty) return 'Member of Nuru';
    try {
      final days =
          DateTime.now().difference(DateTime.parse(created)).inDays;
      if (days < 1) return 'Joined Nuru today';
      if (days < 30) return '$days days on Nuru';
      final m = days ~/ 30;
      if (m < 12) return '$m ${m == 1 ? 'month' : 'months'} on Nuru';
      final years = m ~/ 12;
      return '$years ${years == 1 ? 'year' : 'years'} on Nuru';
    } catch (_) {
      return 'Member of Nuru';
    }
  }

  String _formatDate(String date) {
    try {
      final d = DateTime.parse(date);
      const months = [
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec',
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return date;
    }
  }
}

// Suppress unused l10n import warning if locale lookups aren't applied
// directly inside this file (kept for downstream extension).
// ignore: unused_element
void _kL10n(BuildContext c) => c.tr('services');
