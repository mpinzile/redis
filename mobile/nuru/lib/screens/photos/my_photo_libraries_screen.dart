import '../../core/widgets/nuru_refresh_indicator.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/photo_libraries_service.dart';
import '../../core/services/user_services_service.dart';
import '../../core/services/social_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../home/widgets/home_notifications_tab.dart';
import 'photo_library_screen.dart';
import '../../core/widgets/video_thumbnail_image.dart';
import '../../core/widgets/nuru_search_bar.dart';

/// Photo Libraries - list (aggregate, per-service, or per-event).
///
/// [canCreate] controls whether the "Create New Library" CTA shows. Vendors
/// (service owners) see it; event organizers opening the screen from Manage
/// Event do not. Defaults to true when opened from a service context; false
/// when opened from an event context.
class MyPhotoLibrariesScreen extends StatefulWidget {
  final String? serviceId;
  final String? eventId;
  final String title;
  final bool? canCreate;

  const MyPhotoLibrariesScreen({
    super.key,
    this.serviceId,
    this.eventId,
    this.title = 'Photo Libraries',
    this.canCreate,
  });

  @override
  State<MyPhotoLibrariesScreen> createState() => _MyPhotoLibrariesScreenState();
}

class _MyPhotoLibrariesScreenState extends State<MyPhotoLibrariesScreen> {
  bool _loading = true;
  String? _error;
  String _search = '';
  Timer? _searchDebounce;
  int _tabIndex = 0;
  final ScrollController _tabsScrollCtrl = ScrollController();
  final List<GlobalKey> _tabKeys = List.generate(4, (_) => GlobalKey());

  // Filter state
  String _filterPrivacy = 'all'; // all | private | public
  String _filterOwnership = 'all'; // all | owner | shared

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _shared = [];
  List<Map<String, dynamic>> _favorites = [];

  bool get _showTabs => widget.eventId == null;
  bool get _canCreate => widget.canCreate ?? (widget.eventId == null);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabsScrollCtrl.dispose();
    super.dispose();
  }

  void _scrollActiveTabIntoView() {
    if (!mounted || _tabIndex >= _tabKeys.length) return;
    final ctx = _tabKeys[_tabIndex].currentContext;
    if (ctx == null || !_tabsScrollCtrl.hasClients) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final viewportWidth = _tabsScrollCtrl.position.viewportDimension;
    final tabOffset = box
        .localToGlobal(Offset.zero, ancestor: context.findRenderObject())
        .dx;
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

  void _onSearchChanged(String v) {
    // Client-side filter only - do NOT trigger a network reload on every
    // keystroke. Previously this called _load() which flipped _loading=true
    // and rebuilt the whole screen, making it feel like a full page reload.
    if (_search == v) return;
    setState(() => _search = v);
  }

  List<Map<String, dynamic>> get _activeLibraries {
    List<Map<String, dynamic>> src;
    if (!_showTabs) {
      src = _all;
    } else {
      switch (_tabIndex) {
        case 1:
          src = _mine;
          break;
        case 2:
          src = _shared;
          break;
        case 3:
          src = _favorites;
          break;
        default:
          src = _all;
      }
    }
    return _applyFilters(_searchFilter(src));
  }

  List<Map<String, dynamic>> _searchFilter(List<Map<String, dynamic>> src) {
    if (_search.trim().isEmpty) return src;
    final q = _search.toLowerCase();
    return src.where((lib) {
      final name = (lib['name'] ?? '').toString().toLowerCase();
      final eventName = (lib['event']?['name'] ?? '').toString().toLowerCase();
      return name.contains(q) || eventName.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> src) {
    return src.where((lib) {
      if (_filterPrivacy != 'all') {
        final p = (lib['privacy']?.toString() ?? 'event_creator_only')
            .toLowerCase();
        final isPublic = p == 'public';
        if (_filterPrivacy == 'public' && !isPublic) return false;
        if (_filterPrivacy == 'private' && isPublic) return false;
      }
      if (_filterOwnership != 'all') {
        final role =
            (lib['_owner_role'] ??
                    (lib['is_owner'] == true ? 'Owner' : 'Shared'))
                .toString()
                .toLowerCase();
        if (_filterOwnership == 'owner' && role != 'owner') return false;
        if (_filterOwnership == 'shared' && role == 'owner') return false;
      }
      return true;
    }).toList();
  }

  bool get _hasActiveFilter =>
      _filterPrivacy != 'all' || _filterOwnership != 'all';

  /// Try to populate lists from in-memory cache so the screen renders
  /// instantly while a background refresh runs. Returns true if any data
  /// was hydrated.
  bool _hydrateFromCache() {
    bool hydrated = false;
    if (widget.eventId != null) {
      // Event view has no cache hook today; skip.
      return false;
    }
    if (widget.serviceId != null) {
      final svcKey =
          'service:${widget.serviceId}:${_search.trim().toLowerCase()}';
      final svc = PhotoLibrariesService.cached(svcKey);
      if (svc != null) {
        _mine = _extract(
          svc,
        ).map((m) => {...m, '_owner_role': 'Owner'}).toList();
        hydrated = true;
      }
    }
    final fav = PhotoLibrariesService.cached('me:favorites');
    if (fav != null) {
      _favorites = _extract(fav);
      hydrated = true;
    }
    final shared = PhotoLibrariesService.cached('me:shared');
    if (shared != null) {
      _shared = _extract(
        shared,
      ).map((m) => {...m, '_owner_role': 'Shared'}).toList();
      hydrated = true;
    }
    if (hydrated) {
      final seen = <String>{};
      final all = <Map<String, dynamic>>[];
      for (final lib in [..._mine, ..._shared]) {
        final id = lib['id']?.toString() ?? '';
        if (id.isEmpty || seen.add(id)) all.add(lib);
      }
      _all = all;
    }
    return hydrated;
  }

  Future<void> _load({bool background = false}) async {
    if (!background) {
      // Try to hydrate from in-memory cache first so the user sees something
      // instantly. We still kick off a background refresh below.
      final hydrated = _hydrateFromCache();
      setState(() {
        _loading = !hydrated;
        _error = null;
      });
    }

    if (widget.eventId != null) {
      final res = await PhotoLibrariesService.getEventLibraries(
        widget.eventId!,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (res['success'] == true) {
          _all = _extract(res);
        } else if (_all.isEmpty) {
          _error = res['message']?.toString() ?? 'Unable to load libraries';
        }
      });
      return;
    }

    if (widget.serviceId != null) {
      final results = await Future.wait([
        PhotoLibrariesService.getServiceLibraries(
          widget.serviceId!,
          search: _search.isNotEmpty ? _search : null,
        ),
        PhotoLibrariesService.getMyFavorites(),
        PhotoLibrariesService.getSharedWithMe(),
      ]);
      if (!mounted) return;
      final svcRes = results[0];
      final favRes = results[1];
      final sharedRes = results[2];
      setState(() {
        _loading = false;
        if (svcRes['success'] == true) {
          _mine = _extract(
            svcRes,
          ).map((m) => {...m, '_owner_role': 'Owner'}).toList();
          _favorites = favRes['success'] == true
              ? _extract(favRes)
              : _favorites;
          _shared = sharedRes['success'] == true
              ? _extract(
                  sharedRes,
                ).map((m) => {...m, '_owner_role': 'Shared'}).toList()
              : _shared;
          final seen = <String>{};
          final all = <Map<String, dynamic>>[];
          for (final lib in [..._mine, ..._shared]) {
            final id = lib['id']?.toString() ?? '';
            if (id.isEmpty || seen.add(id)) all.add(lib);
          }
          _all = all;
        } else if (_all.isEmpty) {
          _error = svcRes['message']?.toString() ?? 'Unable to load libraries';
        }
      });
      return;
    }

    // Aggregate view: my services + favorites + shared.
    final servicesRes = await UserServicesService.getMyServices();
    if (!mounted) return;
    if (servicesRes['success'] != true) {
      setState(() {
        _loading = false;
        _error = 'Unable to load services';
      });
      return;
    }

    final services = servicesRes['data'] is List
        ? servicesRes['data'] as List
        : (servicesRes['data'] is Map
              ? (servicesRes['data']['services'] ?? [])
              : []);

    final mine = <Map<String, dynamic>>[];
    for (final svc in services) {
      if (!_isPhotographyService(svc)) continue;
      final svcId = svc['id']?.toString();
      if (svcId == null) continue;
      final res = await PhotoLibrariesService.getServiceLibraries(svcId);
      if (res['success'] == true) {
        for (final lib in _extract(res)) {
          mine.add({
            ...lib,
            '_service_name': svc['title'] ?? svc['name'] ?? 'Service',
            '_owner_role': 'Owner',
          });
        }
      }
    }

    final favRes = await PhotoLibrariesService.getMyFavorites();
    final sharedRes = await PhotoLibrariesService.getSharedWithMe();
    if (!mounted) return;

    final favorites = favRes['success'] == true
        ? _extract(favRes)
        : <Map<String, dynamic>>[];
    final shared = sharedRes['success'] == true
        ? _extract(
            sharedRes,
          ).map((m) => {...m, '_owner_role': 'Shared'}).toList()
        : <Map<String, dynamic>>[];

    final seen = <String>{};
    final all = <Map<String, dynamic>>[];
    for (final lib in [...mine, ...shared]) {
      final id = lib['id']?.toString() ?? '';
      if (id.isEmpty || seen.add(id)) all.add(lib);
    }

    setState(() {
      _loading = false;
      _all = all;
      _mine = mine;
      _shared = shared;
      _favorites = favorites;
    });
  }

  bool _isPhotographyService(dynamic service) {
    final s = service is Map<String, dynamic> ? service : <String, dynamic>{};
    final slug = (s['service_type_slug'] ?? s['service_type']?['slug'] ?? '')
        .toString()
        .toLowerCase();
    final name =
        (s['service_type_name'] ??
                s['category'] ??
                s['service_type']?['name'] ??
                '')
            .toString()
            .toLowerCase();
    return slug.contains('photo') ||
        slug.contains('video') ||
        name.contains('photo') ||
        name.contains('video');
  }

  List<Map<String, dynamic>> _extract(Map<String, dynamic> response) {
    final raw = response['data'];
    dynamic source;
    if (raw is Map) {
      source = raw['libraries'] ?? raw['items'];
    } else if (raw is List) {
      source = raw;
    } else if (response['libraries'] is List) {
      source = response['libraries'];
    }
    if (source is! List) return [];
    return source
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Future<void> _toggleFavorite(String libraryId) async {
    final res = await PhotoLibrariesService.toggleFavorite(libraryId);
    if (mounted && res['success'] == true) _load();
  }

  // ─── Notifications bell ─────────────────────────────────────────────
  Future<void> _openNotifications() async {
    // Push a temporary loading-aware screen that fetches & displays notifications.
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _NotificationsRoute()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: _loading
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        children: [
                          if (_canCreate) const _LibInfoSkeleton(),
                          if (_canCreate) const SizedBox(height: 16),
                          const _LibSearchSkeleton(),
                          const SizedBox(height: 16),
                          for (int i = 0; i < 5; i++) ...[
                            const _LibraryCardSkeleton(),
                            const SizedBox(height: 12),
                          ],
                        ],
                      )
                    : NuruRefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primary,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          children: [
                            if (_canCreate) _infoCard(),
                            if (_canCreate) const SizedBox(height: 16),
                            _searchRow(),
                            const SizedBox(height: 16),
                            if (_showTabs) _tabs(),
                            if (_showTabs) const SizedBox(height: 12),
                            if (_error != null)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  child: Text(
                                    _error!,
                                    style: appText(
                                      size: 13,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ),
                              )
                            else if (_activeLibraries.isEmpty)
                              _emptyState()
                            else
                              ..._activeLibraries.map(_libraryCard),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: SvgPicture.asset(
              'assets/icons/arrow-left-icon.svg',
              width: 22,
              height: 22,
              colorFilter: const ColorFilter.mode(
                AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                widget.title,
                style: appText(size: 17, weight: FontWeight.w700),
              ),
            ),
          ),
          IconButton(
            onPressed: _openNotifications,
            icon: SvgPicture.asset(
              'assets/icons/bell-icon.svg',
              width: 22,
              height: 22,
              colorFilter: const ColorFilter.mode(
                AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7DC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/image-icon.svg',
                width: 28,
                height: 28,
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
                  'Store, organize and share beautiful moments.',
                  style: appText(
                    size: 13,
                    weight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Built-in libraries make it easy to deliver photos and videos to your clients after every event.',
                  style: appText(size: 11, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _showCreateLibrarySheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/icons/plus-icon.svg',
                          width: 14,
                          height: 14,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Create New Library',
                          style: appText(
                            size: 12,
                            weight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchRow() {
    return Row(
      children: [
        Expanded(
          child: NuruSearchBar(
            hintText: 'Search libraries...',
            onChanged: _onSearchChanged,
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _openFilterSheet,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _hasActiveFilter ? AppColors.primarySoft : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hasActiveFilter
                    ? AppColors.primary
                    : const Color(0xFFEDEDEF),
              ),
            ),
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/menu-icon.svg',
                width: 18,
                height: 18,
                colorFilter: ColorFilter.mode(
                  _hasActiveFilter ? AppColors.primary : AppColors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String privacy = _filterPrivacy;
        String ownership = _filterOwnership;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Widget chip(String label, bool active, VoidCallback onTap) {
              return GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primarySoft : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Text(
                    label,
                    style: appText(
                      size: 12,
                      weight: FontWeight.w700,
                      color: active
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Filter libraries',
                      style: appText(size: 15, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Privacy',
                      style: appText(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        chip(
                          'All',
                          privacy == 'all',
                          () => setSheet(() => privacy = 'all'),
                        ),
                        chip(
                          'Private',
                          privacy == 'private',
                          () => setSheet(() => privacy = 'private'),
                        ),
                        chip(
                          'Public',
                          privacy == 'public',
                          () => setSheet(() => privacy = 'public'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Ownership',
                      style: appText(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        chip(
                          'All',
                          ownership == 'all',
                          () => setSheet(() => ownership = 'all'),
                        ),
                        chip(
                          'Owner',
                          ownership == 'owner',
                          () => setSheet(() => ownership = 'owner'),
                        ),
                        chip(
                          'Shared',
                          ownership == 'shared',
                          () => setSheet(() => ownership = 'shared'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setSheet(() {
                                privacy = 'all';
                                ownership = 'all';
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: Text(
                              'Reset',
                              style: appText(
                                size: 13,
                                weight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _filterPrivacy = privacy;
                                _filterOwnership = ownership;
                              });
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              elevation: 0,
                            ),
                            child: Text(
                              'Apply',
                              style: appText(
                                size: 13,
                                weight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _tabs() {
    const labels = [
      'All Libraries',
      'My Libraries',
      'Shared With Me',
      'Favorites',
    ];
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        controller: _tabsScrollCtrl,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: List.generate(labels.length, (i) {
            final active = i == _tabIndex;
            return GestureDetector(
              key: _tabKeys[i],
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _tabIndex = i);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _scrollActiveTabIntoView(),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: appText(
                          size: 13,
                          weight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.primary
                              : Colors.transparent,
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
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/icons/image-icon.svg',
              width: 56,
              height: 56,
              colorFilter: const ColorFilter.mode(
                AppColors.textHint,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _search.isNotEmpty || _hasActiveFilter
                  ? 'No libraries match'
                  : 'No libraries yet',
              style: appText(size: 15, weight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _search.isNotEmpty || _hasActiveFilter
                  ? 'Try a different keyword or clear filters'
                  : 'Create a library from your service events',
              style: appText(size: 12, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _libraryCard(Map<String, dynamic> lib) {
    final name = lib['name']?.toString() ?? 'Library';
    final eventDate =
        (lib['event']?['start_date'] ?? lib['created_at'])?.toString() ?? '';
    final privacy = (lib['privacy']?.toString() ?? 'event_creator_only')
        .toLowerCase();
    final ownerRole =
        (lib['_owner_role'] ?? (lib['is_owner'] == true ? 'Owner' : 'Shared'))
            .toString();
    final coverItem = _firstPhotoItem(lib);
    final coverUrl = coverItem?['url'] as String?;
    final coverIsVideo =
        (coverItem?['media_type']?.toString() ?? 'photo') == 'video';
    final totalSizeMb = _toDouble(lib['total_size_mb']) > 0
        ? _toDouble(lib['total_size_mb'])
        : (_toDouble(lib['total_size_bytes']) / (1024 * 1024));
    final double storageLimitMb = _toDouble(lib['storage_limit_mb']) > 0
        ? _toDouble(lib['storage_limit_mb'])
        : 200.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          final id = lib['id']?.toString();
          if (id != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PhotoLibraryScreen(libraryId: id, libraryName: name),
              ),
            ).then((_) => _load());
          }
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 64,
                  height: 64,
                  color: const Color(0xFFF3F4F6),
                  child: coverUrl != null
                      ? (coverIsVideo
                            ? VideoThumbnailImage(
                                videoUrl: coverUrl,
                                fit: BoxFit.cover,
                                width: 64,
                                height: 64,
                              )
                            : Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: SvgPicture.asset(
                                    'assets/icons/image-icon.svg',
                                    width: 24,
                                    height: 24,
                                    colorFilter: const ColorFilter.mode(
                                      AppColors.textHint,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ))
                      : Center(
                          child: SvgPicture.asset(
                            'assets/icons/image-icon.svg',
                            width: 24,
                            height: 24,
                            colorFilter: const ColorFilter.mode(
                              AppColors.textHint,
                              BlendMode.srcIn,
                            ),
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
                      name,
                      style: appText(size: 14, weight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _fmtDate(eventDate),
                          style: appText(
                            size: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ownerBadge(ownerRole),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _privacyChip(privacy),
                        const SizedBox(width: 10),
                        SvgPicture.asset(
                          'assets/icons/photos-icon.svg',
                          width: 12,
                          height: 12,
                          colorFilter: const ColorFilter.mode(
                            AppColors.textTertiary,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_fmtSize(totalSizeMb)} of ${_fmtSize(storageLimitMb)}',
                          style: appText(
                            size: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showLibraryActions(lib),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SvgPicture.asset(
                    'assets/icons/more-vertical-icon.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(
                      AppColors.textTertiary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ownerBadge(String role) {
    final isOwner = role.toLowerCase() == 'owner';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOwner ? const Color(0xFFFFF1C2) : const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        role,
        style: appText(
          size: 10,
          weight: FontWeight.w700,
          color: isOwner ? const Color(0xFFA86A00) : const Color(0xFF0369A1),
        ),
      ),
    );
  }

  Widget _privacyChip(String privacy) {
    final isPublic = privacy == 'public';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          isPublic
              ? 'assets/icons/earth-icon.svg'
              : 'assets/icons/lock-icon.svg',
          width: 12,
          height: 12,
          colorFilter: const ColorFilter.mode(
            AppColors.textTertiary,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          isPublic ? 'Public' : 'Private',
          style: appText(size: 11, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  void _showLibraryActions(Map<String, dynamic> lib) {
    final id = lib['id']?.toString();
    final isFav = lib['is_favorite'] == true;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: SvgPicture.asset(
                'assets/icons/view-icon.svg',
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  AppColors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
              title: Text(
                'Open library',
                style: appText(size: 14, weight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (id != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PhotoLibraryScreen(
                        libraryId: id,
                        libraryName: lib['name']?.toString(),
                      ),
                    ),
                  ).then((_) => _load());
                }
              },
            ),
            ListTile(
              leading: SvgPicture.asset(
                isFav
                    ? 'assets/icons/heart-filled-icon.svg'
                    : 'assets/icons/heart-icon.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  isFav ? AppColors.error : AppColors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
              title: Text(
                isFav ? 'Remove from favorites' : 'Add to favorites',
                style: appText(size: 14, weight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (id != null) _toggleFavorite(id);
              },
            ),
            ListTile(
              leading: SvgPicture.asset(
                'assets/icons/share-icon.svg',
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  AppColors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
              title: Text(
                'Share link',
                style: appText(size: 14, weight: FontWeight.w600),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final url = lib['share_url']?.toString();
                if (url != null && url.isNotEmpty && url.startsWith('http')) {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (!mounted) return;
                  AppSnackbar.success(context, 'Share link copied');
                } else {
                  AppSnackbar.error(context, 'Switch to Public to share link');
                }
              },
            ),

            if (lib['is_owner'] == true ||
                (lib['_owner_role']?.toString().toLowerCase() == 'owner'))
              ListTile(
                leading: SvgPicture.asset(
                  'assets/icons/delete-icon.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    AppColors.error,
                    BlendMode.srcIn,
                  ),
                ),
                title: Text(
                  'Delete library',
                  style: appText(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (id == null) return;
                  final res = await PhotoLibrariesService.deleteLibrary(id);
                  if (!mounted) return;
                  if (res['success'] == true) {
                    AppSnackbar.success(context, 'Library deleted');
                    _load();
                  } else {
                    AppSnackbar.error(
                      context,
                      res['message']?.toString() ?? 'Unable to delete',
                    );
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCreateLibrarySheet() {
    AppSnackbar.success(context, 'Open a service event to create a library');
  }

  Map<String, dynamic>? _firstPhotoItem(Map<String, dynamic> lib) {
    final photos = lib['photos'];
    if (photos is List) {
      for (final p in photos) {
        if (p is Map) {
          final u = p['url']?.toString();
          if (u != null && u.isNotEmpty) {
            return {
              'url': u,
              'media_type': p['media_type']?.toString() ?? 'photo',
            };
          }
        }
      }
    }
    final cover =
        lib['cover_image_url'] ??
        lib['cover_url'] ??
        lib['event']?['cover_image'];
    final s = cover?.toString();
    if (s != null && s.isNotEmpty) {
      return {'url': s, 'media_type': 'photo'};
    }
    return null;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _fmtSize(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso);
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

/// Wrapper screen that loads notifications then renders [HomeNotificationsTab].
class _NotificationsRoute extends StatefulWidget {
  const _NotificationsRoute();
  @override
  State<_NotificationsRoute> createState() => _NotificationsRouteState();
}

class _NotificationsRouteState extends State<_NotificationsRoute> {
  List<dynamic> _notifications = [];
  int _unread = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final res = await SocialService.getNotifications(limit: 30);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        _notifications = data is Map
            ? (data['notifications'] ?? [])
            : (data is List ? data : []);
        _unread = data is Map ? (data['unread_count'] ?? 0) : 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: HomeNotificationsTab(
        notifications: _notifications,
        unreadCount: _unread,
        isLoading: _loading,
        onRefresh: _load,
        onSearch: (_) => _load(),
        onTabChanged: (_) => Navigator.pop(context),
      ),
    );
  }
}

// ─── Skeleton loaders matching the real library list layout ──────────────────
class _SkBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const _SkBox({this.width, required this.height, this.radius = 8});
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF0F3),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class _LibInfoSkeleton extends StatelessWidget {
  const _LibInfoSkeleton();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.subtleShadow,
        ),
        child: Row(children: const [
          _SkBox(width: 40, height: 40, radius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkBox(width: 140, height: 12),
                SizedBox(height: 8),
                _SkBox(width: 200, height: 10),
              ],
            ),
          ),
        ]),
      );
}

class _LibSearchSkeleton extends StatelessWidget {
  const _LibSearchSkeleton();
  @override
  Widget build(BuildContext context) => const _SkBox(height: 44, radius: 14);
}

class _LibraryCardSkeleton extends StatelessWidget {
  const _LibraryCardSkeleton();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.subtleShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _SkBox(width: 64, height: 64, radius: 12),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkBox(width: 160, height: 13),
                  SizedBox(height: 8),
                  Row(children: [
                    _SkBox(width: 70, height: 10),
                    SizedBox(width: 8),
                    _SkBox(width: 50, height: 14, radius: 99),
                  ]),
                  SizedBox(height: 10),
                  Row(children: [
                    _SkBox(width: 80, height: 16, radius: 99),
                    SizedBox(width: 10),
                    _SkBox(width: 100, height: 10),
                  ]),
                ],
              ),
            ),
            SizedBox(width: 8),
            _SkBox(width: 18, height: 18, radius: 4),
          ],
        ),
      );
}
