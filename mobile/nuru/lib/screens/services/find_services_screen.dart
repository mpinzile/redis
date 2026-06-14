import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/events_service.dart';
import '../../core/services/user_services_service.dart';
import '../../core/utils/prefetch_helper.dart';
import 'public_service_screen.dart';
import '../../core/widgets/nuru_refresh.dart';
import '../../core/widgets/nuru_loader.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../core/widgets/nuru_search_bar.dart';

class FindServicesScreen extends StatefulWidget {
  /// When true, the screen opens already filtered to the user's saved vendors.
  /// Used by the Profile → "Saved Vendors" entry point.
  final bool initialSavedOnly;
  const FindServicesScreen({super.key, this.initialSavedOnly = false});

  @override
  State<FindServicesScreen> createState() => _FindServicesScreenState();
}

class _FindServicesScreenState extends State<FindServicesScreen> {
  bool _loading = true;
  List<dynamic> _services = [];
  List<dynamic> _categories = [];
  String? _selectedCategory;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _showTrustBanner = true;
  final Set<String> _favorites = <String>{};
  bool _savedOnly = false;
  static const _favoritesKey = 'saved_vendors_v1';

  // Top categories shown as fixed chips like the reference design.
  static const _topCategories = ['Catering', 'Decor', 'Photography'];

  @override
  void initState() {
    super.initState();
    _savedOnly = widget.initialSavedOnly;
    _loadFavorites();
    _load();
  }

  Future<void> _loadFavorites() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final saved = sp.getStringList(_favoritesKey) ?? const [];
      if (mounted) setState(() => _favorites..clear()..addAll(saved));
    } catch (_) {}
  }

  Future<void> _persistFavorites() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_favoritesKey, _favorites.toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final results = await Future.wait([
      EventsService.getServices(
        limit: 50,
        category: _selectedCategory,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      ),
      EventsService.getServiceCategories(),
    ]);
    if (mounted) {
      setState(() {
        if (!silent) _loading = false;
        final svcRes = results[0];
        if (svcRes['success'] == true) {
          final data = svcRes['data'];
          _services = data is List
              ? data
              : (data is Map ? (data['services'] ?? data['items'] ?? []) : []);
        }
        final catRes = results[1];
        if (catRes['success'] == true) {
          final data = catRes['data'];
          _categories = data is List ? data : [];
        }
      });
    }
  }

  String _str(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    if (v is String) return v.isEmpty ? fallback : v;
    if (v is Map) return (v['name'] ?? v['title'] ?? v['label'] ?? v.values.first)?.toString() ?? fallback;
    return v.toString();
  }

  TextStyle _f({
    required double size,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double height = 1.3,
    double? letterSpacing,
  }) =>
      GoogleFonts.inter(
        fontSize: size, fontWeight: weight, color: color,
        height: height, letterSpacing: letterSpacing);

  @override
  Widget build(BuildContext context) {
    final visibleServices = _savedOnly
        ? _services.where((s) {
            final id = (s is Map ? (s['id'] ?? s['service_id']) : null)?.toString() ?? '';
            return _favorites.contains(id);
          }).toList()
        : _services;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 56,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
            size: 24, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(_savedOnly ? 'Saved Vendors' : 'Vendors',
          style: _f(size: 17, weight: FontWeight.w700, letterSpacing: -0.2)),
        actions: [
          IconButton(
            tooltip: _savedOnly ? 'Show all vendors' : 'Show saved only',
            onPressed: () => setState(() => _savedOnly = !_savedOnly),
            icon: SvgPicture.asset(
              _savedOnly ? 'assets/icons/bookmark-filled-icon.svg' : 'assets/icons/bookmark-icon.svg',
              width: 22, height: 22,
              colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _searchBar(),
          const SizedBox(height: 14),
          _categoryChips(),
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const NuruSkeletonEventList(itemCount: 4)
                : NuruRefresh(
                    onRefresh: () => _load(silent: true),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      children: [
                        if (_showTrustBanner) ...[
                          _trustBanner(),
                          const SizedBox(height: 14),
                        ],
                        if (visibleServices.isEmpty)
                          _emptyState(
                            isFiltered: _savedOnly ||
                                _searchQuery.trim().isNotEmpty ||
                                _selectedCategory != null,
                            savedOnly: _savedOnly,
                          )
                        else
                          ...visibleServices.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _vendorCard(s as Map<String, dynamic>),
                          )),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: NuruSearchBar(
        controller: _searchCtrl,
        hintText: 'Search vendors or services',
        onChanged: (q) {
          setState(() => _searchQuery = q);
          _load();
        },
      ),
    );
  }

  Widget _categoryChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _filterChip('All', _selectedCategory == null, () {
            setState(() => _selectedCategory = null);
            _load();
          }),
          ..._topCategories.map((name) {
            final selected = _selectedCategory == name;
            return _filterChip(name, selected, () {
              setState(() => _selectedCategory = name);
              _load();
            });
          }),
          _moreChip(),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFEFEFEF),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(label,
              style: _f(size: 11, weight: FontWeight.w600,
                color: AppColors.textPrimary)),
          ),
        ),
      ),
    );
  }

  Widget _moreChip() {
    return GestureDetector(
      onTap: _showCategorySheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEFEFEF), width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('More',
            style: _f(size: 11, weight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded,
            size: 16, color: AppColors.textPrimary),
        ]),
      ),
    );
  }

  void _showCategorySheet() {
    if (_categories.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(minWidth: double.infinity),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('All categories', style: _f(size: 16, weight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
              children: _categories.map((c) {
                final name = _str(c['name']);
                final id = c['id']?.toString() ?? name;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _selectedCategory = id);
                    _load();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(name, style: _f(size: 13, weight: FontWeight.w600)),
                  ),
                );
              }).toList()),
          ]),
        ),
      ),
    );
  }

  Widget _trustBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46, height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
                bottomLeft: Radius.circular(23),
                bottomRight: Radius.circular(23),
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_rounded,
              size: 26, color: Colors.black),
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
                      child: Text('Trusted Vendors,\nPerfect Events',
                        style: _f(size: 14, weight: FontWeight.w800, height: 1.25)),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _showTrustBanner = false),
                      child: SvgPicture.asset('assets/icons/close-icon.svg',
                        width: 16, height: 16,
                        colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text('Book reliable vendors and make your event unforgettable.',
                        style: _f(size: 11, color: AppColors.textSecondary, height: 1.35)),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.2),
                      ),
                      child: Text('View Guide',
                        style: _f(size: 11, weight: FontWeight.w600, color: AppColors.primary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vendorCard(Map<String, dynamic> service) {
    final serviceId = service['id']?.toString() ?? '';
    final name = _str(service['title'], fallback: _str(service['name'], fallback: 'Vendor'));
    final category = _str(service['service_category'],
      fallback: _str(service['category_name'], fallback: _str(service['service_type_name'])));
    final rating = (service['rating'] ?? service['average_rating'] ?? 0).toDouble();
    final reviewCount = service['review_count'] ?? 0;
    final images = service['images'] as List? ?? [];
    final primaryImage = service['primary_image']?.toString();
    String? cover;
    if (primaryImage != null && primaryImage.isNotEmpty) {
      cover = primaryImage;
    } else if (images.isNotEmpty) {
      final first = images[0];
      cover = first is Map ? (first['image_url'] ?? first['url'])?.toString() : first?.toString();
    }
    final isFav = _favorites.contains(serviceId);

    return PrefetchOnVisible(
      onVisible: () {
        if (serviceId.isEmpty) return;
        PrefetchHelper.prefetch('service:$serviceId',
          () => UserServicesService.getServiceDetail(serviceId));
      },
      child: GestureDetector(
        onTap: serviceId.isEmpty
          ? null
          : () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PublicServiceScreen(serviceId: serviceId))),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEEEEF1), width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: cover != null
                  ? Image.network(cover, width: 88, height: 88, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(name))
                  : _imagePlaceholder(name),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: _f(size: 16, weight: FontWeight.w800))),
                      GestureDetector(
                        onTap: () => setState(() {
                          if (isFav) { _favorites.remove(serviceId); }
                          else { _favorites.add(serviceId); }
                          _persistFavorites();
                        }),
                        child: SvgPicture.asset(
                          isFav ? 'assets/icons/heart-filled-icon.svg'
                                : 'assets/icons/heart-icon.svg',
                          width: 20, height: 20,
                          colorFilter: ColorFilter.mode(
                            isFav ? AppColors.error : AppColors.textTertiary,
                            BlendMode.srcIn),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(category.isNotEmpty ? category : 'Service',
                      style: _f(size: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(Icons.star_rounded, size: 15, color: Colors.black),
                      const SizedBox(width: 4),
                      Text(rating > 0 ? rating.toStringAsFixed(1) : '-',
                        style: _f(size: 13, weight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      Text('(${reviewCount is num ? reviewCount.toInt() : 0})',
                        style: _f(size: 13, color: AppColors.textTertiary)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF6DD),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Book Now',
                          style: _f(size: 13, weight: FontWeight.w700, color: const Color(0xFF8A6A00))),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder(String name) {
    return Container(
      width: 72, height: 72, color: AppColors.surfaceVariant,
      child: Center(
        child: Text(
          name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase(),
          style: _f(size: 18, weight: FontWeight.w800, color: AppColors.textHint),
        ),
      ),
    );
  }

  Widget _emptyState({bool isFiltered = false, bool savedOnly = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SvgPicture.asset(
          savedOnly
              ? 'assets/icons/bookmark-icon.svg'
              : (isFiltered ? 'assets/icons/search-icon.svg' : 'assets/icons/package-icon.svg'),
          width: 44, height: 44,
          colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn),
        ),
        const SizedBox(height: 12),
        Text(savedOnly
              ? 'No saved vendors yet'
              : (isFiltered ? 'No results found' : 'No vendors yet'),
            style: _f(size: 14, color: AppColors.textTertiary)),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            savedOnly
                ? 'Tap the heart on any vendor to save it here for quick access.'
                : (isFiltered
                    ? 'Try a different keyword or clear your filters to see more vendors.'
                    : 'Vendors will appear here as soon as they join the platform.'),
            textAlign: TextAlign.center,
            style: _f(size: 12, color: AppColors.textHint),
          ),
        ),
      ]),
    );
  }
}
