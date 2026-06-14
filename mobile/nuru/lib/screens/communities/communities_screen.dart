import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/nuru_refresh_indicator.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../core/services/social_service.dart';
import '../../core/l10n/l10n_helper.dart';
import 'community_detail_screen.dart';
import '../../core/widgets/nuru_search_bar.dart';

/// Communities - pixel match to mockup.
/// Purple hero • My Communities horizontal scroll • Recommended for You list.
class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  List<dynamic> _recommendedAll = [];
  List<dynamic> _mine = [];
  bool _loading = true;
  bool _hasError = false;
  bool _searchOpen = false;
  String _search = '';
  final _searchCtl = TextEditingController();
  final GlobalKey _recommendedKey = GlobalKey();

  void _scrollToRecommended() {
    final ctx = _recommendedKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    final results = await Future.wait([
      SocialService.getRecommendedCommunities(limit: 30),
      SocialService.getMyCommunities(),
    ]);
    if (!mounted) return;
    final recOk = results[0]['success'] == true;
    final mineOk = results[1]['success'] == true;
    setState(() {
      _loading = false;
      _hasError = !recOk && !mineOk;
      if (recOk) {
        final d = results[0]['data'];
        _recommendedAll = d is List ? d : (d is Map ? (d['communities'] ?? []) : []);
      } else {
        _recommendedAll = [];
      }
      if (mineOk) {
        final d = results[1]['data'];
        _mine = d is List ? d : (d is Map ? (d['communities'] ?? []) : []);
      }
    });
  }

  bool _matches(Map c) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return (c['name']?.toString().toLowerCase().contains(q) ?? false) ||
        (c['description']?.toString().toLowerCase().contains(q) ?? false) ||
        (c['tagline']?.toString().toLowerCase().contains(q) ?? false);
  }

  List<dynamic> get _recommended {
    // Server-ranked. Apply only the local search filter on top.
    return _recommendedAll
        .where((c) => c is Map && _matches(c))
        .toList();
  }

  List<dynamic> get _myFiltered =>
      _mine.where((c) => c is Map && _matches(c)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: NuruSubPageAppBar(
        title: context.trw('communities'),
        actions: [
          IconButton(
            icon: SvgPicture.asset(
              _searchOpen
                  ? 'assets/icons/close-icon.svg'
                  : 'assets/icons/search-icon.svg',
              width: 22,
              height: 22,
              colorFilter: const ColorFilter.mode(
                AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _searchCtl.clear();
                _search = '';
              }
            }),
          ),
          GestureDetector(
            onTap: _showCreateSheet,
            child: Container(
              margin: const EdgeInsets.only(right: 12, left: 4),
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/plus-icon.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    Colors.black,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? _loadingSkeleton()
          : NuruRefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                children: [
                  if (_searchOpen) _searchBar(),
                  _purpleHero(),
                  const SizedBox(height: 22),
                  if (_myFiltered.isNotEmpty) ...[
                    _sectionHeader(
                      'My Communities',
                      onSeeAll: () => _showAllMine(),
                    ),
                    const SizedBox(height: 12),
                    _myCommunitiesRail(),
                    const SizedBox(height: 22),
                  ],
                  KeyedSubtree(
                    key: _recommendedKey,
                    child: _sectionHeader('Recommended for You'),
                  ),
                  const SizedBox(height: 8),
                  if (_hasError && _recommendedAll.isEmpty)
                    _errorState()
                  else if (_recommended.isEmpty)
                    _empty()
                  else
                    ..._recommended.map(
                      (c) => _recommendedRow(
                        c is Map<String, dynamic>
                            ? c
                            : Map<String, dynamic>.from(c as Map),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // ─── Search ───────────────────────────────────────────────────────────────

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: NuruSearchBar(
        controller: _searchCtl,
        hintText: 'Search communities…',
        debounce: const Duration(milliseconds: 200),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  // ─── Hero (purple) ────────────────────────────────────────────────────────

  Widget _purpleHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 8, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF6B21A8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Discover. Learn.\nGrow Together',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join communities that match your interests and connect with amazing people.',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Colors.white.withOpacity(0.9),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: _scrollToRecommended,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Explore Communities',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 120,
              height: 120,
              child: SvgPicture.asset(
                'assets/illustrations/group_discussion.svg',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Sections ─────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See All',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _myCommunitiesRail() {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _myFiltered.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) =>
            _myCommunityCard(Map<String, dynamic>.from(_myFiltered[i] as Map)),
      ),
    );
  }

  Widget _myCommunityCard(Map<String, dynamic> c) {
    final name = c['name']?.toString() ?? 'Community';
    final cover = c['image']?.toString() ?? c['cover_image']?.toString();
    final memberCount = c['member_count'] ?? 0;
    final id = c['id']?.toString() ?? '';

    return GestureDetector(
      onTap: () {
        if (id.isEmpty) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CommunityDetailScreen(
              communityId: id,
              communityName: name,
              coverImage: cover,
            ),
          ),
        );
      },
      child: SizedBox(
        width: 134,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: cover != null && cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: cover,
                          width: 134,
                          height: 110,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _coverFallback(110),
                        )
                      : _coverFallback(110),
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Color(0xFF111114),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatMembers(memberCount) + ' Members',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMembers(dynamic count) {
    final n = (count is int) ? count : int.tryParse(count.toString()) ?? 0;
    if (n >= 1000)
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return '$n';
  }

  Widget _coverFallback(double height) {
    return Container(
      width: double.infinity,
      height: height,
      color: AppColors.primary.withOpacity(0.12),
      child: Icon(
        Icons.groups_2_outlined,
        size: 28,
        color: AppColors.primary.withOpacity(0.55),
      ),
    );
  }

  // ─── Recommended row ─────────────────────────────────────────────────────

  Widget _recommendedRow(Map<String, dynamic> c, {bool? forceMember}) {
    final name = c['name']?.toString() ?? 'Community';
    final tagline = c['tagline']?.toString().trim().isNotEmpty == true
        ? c['tagline'].toString()
        : (c['description']?.toString() ?? '');
    final memberCount = c['member_count'] ?? 0;
    final cover = c['image']?.toString() ?? c['cover_image']?.toString();
    final id = c['id']?.toString() ?? '';

    final myIds = _mine.map((m) => m is Map ? m['id']?.toString() : '').toSet();
    final isMember =
        forceMember ?? (myIds.contains(id) || c['is_member'] == true);

    void openDetail() {
      if (id.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommunityDetailScreen(
            communityId: id,
            communityName: name,
            coverImage: cover,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: openDetail,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            ClipOval(
              child: cover != null && cover.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: cover,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _coverFallback(48),
                    )
                  : _coverFallback(48),
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
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if ((c['category']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            c['category'].toString(),
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (tagline.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    '${_formatMembers(memberCount)} Members',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                if (isMember) {
                  openDetail();
                  return;
                }
                final res = await SocialService.joinCommunity(id);
                if (!mounted) return;
                if (res['success'] == true) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Joined $name')));
                  await _load();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        res['message']?.toString() ?? 'Could not join',
                      ),
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isMember ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary, width: 1.2),
                ),
                child: Text(
                  isMember ? 'Open' : 'Join',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: isMember ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Loading skeleton (matches real layout) ───────────────────────────────
  Widget _loadingSkeleton() {
    Widget bar(double w, double h, {double r = 6}) => NuruSkeleton(
          width: w,
          height: h,
          borderRadius: BorderRadius.circular(r),
        );

    Widget railCard() => Container(
          width: 200,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEEF0F4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NuruSkeleton(
                width: 200,
                height: 90,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(140, 12),
                    const SizedBox(height: 8),
                    bar(90, 10),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget recRow() => Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              NuruSkeleton(
                width: 56,
                height: 56,
                borderRadius: BorderRadius.circular(14),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(160, 13),
                    const SizedBox(height: 8),
                    bar(220, 10),
                    const SizedBox(height: 6),
                    bar(80, 10),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              bar(72, 30, r: 16),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        // Purple hero placeholder
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: NuruSkeleton(
            width: double.infinity,
            height: 140,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(height: 22),
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [bar(140, 14), bar(50, 12)],
          ),
        ),
        const SizedBox(height: 12),
        // Horizontal rail
        SizedBox(
          height: 170,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [railCard(), railCard(), railCard()],
          ),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: bar(180, 14),
        ),
        const SizedBox(height: 12),
        recRow(),
        recRow(),
        recRow(),
        recRow(),
        recRow(),
      ],
    );
  }

  Widget _empty() {

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        children: [
          SizedBox(
            width: 160,
            height: 130,
            child: SvgPicture.asset(
              'assets/illustrations/group_discussion.svg',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No communities to recommend',
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check back later for new communities',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F0),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_off_rounded,
                color: Color(0xFFD93025), size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            "Couldn't load recommendations",
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check your connection and try again.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: Color(0xFFEDEDF2)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              textStyle: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _showAllMine() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'My Communities',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_mine.length}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: _mine.length,
                itemBuilder: (_, i) => _recommendedRow(
                  _mine[i] is Map<String, dynamic>
                      ? _mine[i] as Map<String, dynamic>
                      : Map<String, dynamic>.from(_mine[i] as Map),
                  forceMember: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateSheet() {
    final nameCtrl = TextEditingController();
    final taglineCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool submitting = false;
    bool isPublic = true;
    String? selectedCategory;
    File? coverFile;

    const categories = <Map<String, String>>[
      {'label': 'Wedding', 'icon': 'assets/icons/heart-icon.svg'},
      {'label': 'Send-off', 'icon': 'assets/icons/love-icon.svg'},
      {'label': 'Funeral', 'icon': 'assets/icons/circle-icon.svg'},
      {'label': 'Decor', 'icon': 'assets/icons/love-icon.svg'},
      {'label': 'Catering', 'icon': 'assets/icons/package-icon.svg'},
      {'label': 'Music', 'icon': 'assets/icons/microphone-icon.svg'},
      {'label': 'Photography', 'icon': 'assets/icons/camera-icon.svg'},
      {'label': 'Other', 'icon': 'assets/icons/communities-icon.svg'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> pickCover() async {
            try {
              final picker = ImagePicker();
              final picked = await picker.pickImage(
                source: ImageSource.gallery,
                maxWidth: 1600,
                imageQuality: 85,
              );
              if (picked != null) setSheet(() => coverFile = File(picked.path));
            } catch (_) {}
          }

          InputDecoration deco(String hint, {Widget? prefix}) =>
              InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: const Color(0xFFA1A1AA),
                ),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                prefixIcon: prefix,
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.primary.withOpacity(0.6),
                    width: 1.2,
                  ),
                ),
              );

          Widget svgPrefix(String path) => Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: SvgPicture.asset(
              path,
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(
                AppColors.textSecondary.withOpacity(0.8),
                BlendMode.srcIn,
              ),
            ),
          );

          Widget sectionLabel(String t) => Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 18, left: 2),
            child: Text(
              t,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          );

          Widget coverPicker() {
            return GestureDetector(
              onTap: pickCover,
              child: Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  image: coverFile != null
                      ? DecorationImage(
                          image: FileImage(coverFile!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  border: Border.all(
                    color: coverFile != null
                        ? Colors.transparent
                        : AppColors.primary.withOpacity(0.35),
                    width: 1.2,
                  ),
                ),
                child: coverFile != null
                    ? Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: GestureDetector(
                            onTap: () => setSheet(() => coverFile = null),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: SvgPicture.asset(
                                'assets/icons/close-icon.svg',
                                width: 14,
                                height: 14,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.10),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: SvgPicture.asset(
                                'assets/icons/camera-icon.svg',
                                width: 22,
                                height: 22,
                                colorFilter: const ColorFilter.mode(
                                  AppColors.primary,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add cover image',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap to upload (JPG, PNG)',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
              ),
            );
          }

          Widget categoryChip(Map<String, String> c) {
            final active = selectedCategory == c['label'];
            return GestureDetector(
              onTap: () =>
                  setSheet(() => selectedCategory = active ? null : c['label']),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : const Color(0xFFF7F7F8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active ? AppColors.primary : const Color(0xFFEDEDF2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      c['icon']!,
                      width: 14,
                      height: 14,
                      colorFilter: ColorFilter.mode(
                        active ? Colors.white : AppColors.textSecondary,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      c['label']!,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 18,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withOpacity(0.7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/icons/communities-icon.svg',
                            width: 22,
                            height: 22,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start a community',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bring your people together around what matters.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF4F4F6),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/icons/close-icon.svg',
                              width: 12,
                              height: 12,
                              colorFilter: const ColorFilter.mode(
                                AppColors.textPrimary,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  sectionLabel('COVER'),
                  coverPicker(),
                  sectionLabel('NAME'),
                  TextField(
                    controller: nameCtrl,
                    autocorrect: false,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: deco(
                      'e.g. Decorators Hub',
                      prefix: svgPrefix('assets/icons/communities-icon.svg'),
                    ),
                  ),
                  sectionLabel('TAGLINE'),
                  TextField(
                    controller: taglineCtrl,
                    autocorrect: false,
                    maxLength: 80,
                    style: GoogleFonts.inter(fontSize: 14),
                    decoration: deco(
                      'Short one-liner (optional)',
                      prefix: svgPrefix('assets/icons/echo-icon.svg'),
                    ).copyWith(counterText: ''),
                  ),
                  sectionLabel('DESCRIPTION'),
                  TextField(
                    controller: descCtrl,
                    maxLines: 4,
                    autocorrect: false,
                    style: GoogleFonts.inter(fontSize: 14, height: 1.4),
                    decoration: deco('What is this community about?'),
                  ),
                  sectionLabel('CATEGORY'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map(categoryChip).toList(),
                  ),
                  sectionLabel('VISIBILITY'),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              isPublic
                                  ? 'assets/icons/communities-icon.svg'
                                  : 'assets/icons/block-icon.svg',
                              width: 18,
                              height: 18,
                              colorFilter: const ColorFilter.mode(
                                AppColors.primary,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPublic
                                    ? 'Public community'
                                    : 'Private community',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                isPublic
                                    ? 'Anyone can find and join this community.'
                                    : 'Only invited members can join.',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: isPublic,
                          activeColor: AppColors.primary,
                          onChanged: (v) => setSheet(() => isPublic = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: submitting
                          ? null
                          : () async {
                              if (nameCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please enter a community name',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setSheet(() => submitting = true);
                              final res = await SocialService.createCommunity(
                                name: nameCtrl.text.trim(),
                                description: descCtrl.text.trim(),
                                tagline: taglineCtrl.text.trim().isEmpty
                                    ? null
                                    : taglineCtrl.text.trim(),
                                category: selectedCategory,
                                isPublic: isPublic,
                                coverImagePath: coverFile?.path,
                              );
                              if (!mounted) return;
                              final success = res['success'] == true;
                              setSheet(() => submitting = false);
                              if (success) {
                                Navigator.pop(ctx);
                                _load();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Community created'),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      res['message']?.toString() ??
                                          'Failed to create community',
                                    ),
                                  ),
                                );
                              }
                            },
                      child: submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Create Community',
                              style: GoogleFonts.inter(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
