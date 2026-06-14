import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/api_service.dart';
import '../../core/services/events_service.dart';
import '../../core/services/event_contributors_service.dart';
import '../../core/services/social_service.dart';
import '../../core/services/ticketing_service.dart';
import '../settings/settings_screen.dart';
import '../settings/identity_verification_screen.dart';
import '../saved/saved_posts_screen.dart';
import '../services/find_services_screen.dart';
import '../wallet/payment_history_screen.dart';
import '../wallet/payout_profile_screen.dart';
import '../home/widgets/home_notifications_tab.dart';
import '../home/home_tab_controller.dart';
import '../../core/widgets/nuru_refresh.dart';
import '../../core/utils/notification_center.dart';

/// Premium profile redesign matching the reference mock.
class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final int myEventsCount;
  final int ticketsCount;
  final VoidCallback? onRefresh;

  const ProfileScreen({
    super.key,
    this.profile,
    this.myEventsCount = 0,
    this.ticketsCount = 0,
    this.onRefresh,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profileData;
  bool _profileLoading = true;
  int _eventsCount = 0;
  int _ticketsCount = 0;
  int _contributionsCount = 0;
  int _savedCount = 0;
  int _unreadNotifications = 0;
  List<dynamic> _notifications = [];
  bool _notificationsLoading = false;

  @override
  void initState() {
    super.initState();
    _eventsCount = widget.myEventsCount;
    _ticketsCount = widget.ticketsCount;
    _loadProfileDetails();
    _loadCounts();
    // Seed badge from the central source so we don't briefly show stale
    // counts before the network call completes.
    _unreadNotifications = NotificationCenter.unreadCount.value;
    NotificationCenter.unreadCount.addListener(_onNotifCenterChange);
    _loadNotifications();
  }

  @override
  void dispose() {
    NotificationCenter.unreadCount.removeListener(_onNotifCenterChange);
    super.dispose();
  }

  void _onNotifCenterChange() {
    if (!mounted) return;
    final v = NotificationCenter.unreadCount.value;
    if (v != _unreadNotifications) setState(() => _unreadNotifications = v);
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myEventsCount != widget.myEventsCount ||
        oldWidget.ticketsCount != widget.ticketsCount) {
      setState(() {
        _eventsCount = widget.myEventsCount;
        _ticketsCount = widget.ticketsCount;
      });
    }
  }

  Future<void> _loadCounts() async {
    // Pull real lists for accurate counts (server profile counts are unreliable).
    final results = await Future.wait([
      EventContributorsService.getMyContributions(),
      SocialService.getSavedPosts(),
      TicketingService.getMyTickets(limit: 100),
    ]);
    if (!mounted) return;
    int contribs = _contributionsCount;
    int saved = _savedCount;
    int tickets = _ticketsCount;

    final cRes = results[0];
    if (cRes['success'] == true) {
      final d = cRes['data'];
      if (d is List) {
        contribs = d.length;
      } else if (d is Map) {
        // Backend returns { events: [...], count: N }
        final list = (d['events'] ?? d['contributions'] ?? d['items'] ?? []) as List? ?? const [];
        contribs = (d['count'] is int) ? d['count'] as int : list.length;
      }
    }

    final bRes = results[1];
    if (bRes['success'] == true) {
      final d = bRes['data'];
      if (d is List) {
        saved = d.length;
      } else if (d is Map) {
        // Backend returns { saved_posts: [...], pagination: { total_items } }
        final list = (d['saved_posts'] ?? d['bookmarks'] ?? d['items'] ?? []) as List? ?? const [];
        final pag = d['pagination'];
        int? total;
        if (pag is Map) {
          total = (pag['total_items'] ?? pag['total'] ?? pag['total_count']) as int?;
        }
        saved = total ?? list.length;
      }
    }

    final tRes = results[2];
    if (tRes['success'] == true) {
      final d = tRes['data'];
      if (d is List) {
        tickets = d.length;
      } else if (d is Map) {
        final list = (d['tickets'] ?? d['items'] ?? []) as List? ?? const [];
        final pag = d['pagination'];
        int? total;
        if (pag is Map) {
          total = (pag['total_items'] ?? pag['total'] ?? pag['total_count']) as int?;
        }
        tickets = total ?? list.length;
      }
    }

    setState(() {
      _contributionsCount = contribs;
      _savedCount = saved;
      _ticketsCount = tickets;
    });
  }

  Future<void> _loadNotifications() async {
    if (mounted) setState(() => _notificationsLoading = true);
    final res = await SocialService.getNotifications(limit: 30);
    if (!mounted) return;
    setState(() {
      _notificationsLoading = false;
      if (res['success'] == true) {
        final data = res['data'];
        _notifications = data is Map ? (data['notifications'] ?? []) : (data is List ? data : []);
        _unreadNotifications = data is Map ? (data['unread_count'] ?? 0) : 0;
      }
    });
    // Broadcast so Home (and any other surface) shares the same count.
    NotificationCenter.setUnread(_unreadNotifications);
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.surface,
          body: HomeNotificationsTab(
            notifications: _notifications,
            unreadCount: _unreadNotifications,
            isLoading: _notificationsLoading,
            onRefresh: _loadNotifications,
            onSearch: (_) => _loadNotifications(),
            onTabChanged: (_) => Navigator.pop(context),
          ),
        ),
      ),
    ).then((_) => _loadNotifications());
  }

  Future<void> _loadProfileDetails() async {
    // Seed from anything we already have so an offline open never blanks
    // out the name / avatar that was loaded before the network dropped.
    final seeded = _profileData ?? widget.profile;
    if (mounted) {
      setState(() {
        _profileData = seeded;
        _profileLoading = _profileData == null;
      });
    }
    final meRes = await AuthApi.me();
    Map<String, dynamic>? userData;
    if (meRes['success'] == true && meRes['data'] is Map<String, dynamic>) {
      userData = meRes['data'] as Map<String, dynamic>;
    } else if (meRes['data'] is Map<String, dynamic> && meRes['data']['id'] != null) {
      userData = meRes['data'] as Map<String, dynamic>;
    }
    final profileRes = await EventsService.getProfile();
    if (profileRes['success'] == true && profileRes['data'] is Map<String, dynamic>) {
      userData = {...(userData ?? {}), ...profileRes['data'] as Map<String, dynamic>};
    }
    if (!mounted) return;
    setState(() {
      _profileLoading = false;
      // Only replace cached data when we actually got something back. A
      // network failure (offline) must NEVER blank the user's name into
      // the "Your name" placeholder.
      if (userData != null && userData.isNotEmpty) {
        _profileData = userData;
      }
    });
  }

  TextStyle _f({required double size, FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary, double height = 1.3, double? letterSpacing}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color,
      height: height, letterSpacing: letterSpacing);

  void _openShellTab(int tab, {int? eventsSubTab}) {
    if (tab == HomeTabController.tickets) HomeTabController.openTickets();
    if (tab == HomeTabController.events && eventsSubTab == 0) HomeTabController.openMyEvents();
    if (tab == HomeTabController.events && eventsSubTab == 1) HomeTabController.openInvitations();
    if (tab == HomeTabController.events && eventsSubTab == 3) HomeTabController.openMyContributions();
  }

  bool get _isVerified {
    final p = _profileData ?? widget.profile ?? const {};
    final v = p['is_identity_verified'] ?? p['identity_verified'] ?? p['kyc_verified'];
    if (v == true) return true;
    final status = (p['verification_status'] ?? p['identity_status'] ?? p['kyc_status'])
      ?.toString().toLowerCase();
    return status == 'verified' || status == 'approved';
  }

  @override
  Widget build(BuildContext context) {
    // Three-tier fallback so an offline open never shows "Your name":
    //   1. Freshly-fetched _profileData
    //   2. The profile blob the parent (home) passed in (cached on launch)
    //   3. AuthProvider.user - populated from secure storage + cached_user
    //      prefs the very first frame after the splash, even when offline.
    final cached = context.watch<AuthProvider>().user;
    final p = _profileData ?? widget.profile ?? cached ?? <String, dynamic>{};
    final firstName = p['first_name']?.toString() ?? '';
    final lastName = p['last_name']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();
    final avatar = (p['avatar'] as String?) ?? (cached?['avatar'] as String?);
    final phone = p['phone']?.toString() ?? '';
    final email = p['email']?.toString() ?? '';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          _topBar(p),
          Expanded(
            child: NuruRefresh(
              onRefresh: () async {
                widget.onRefresh?.call();
                await _loadProfileDetails();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(0, 4, 0, 140 + MediaQuery.of(context).padding.bottom),
                children: [
                  _identityCard(fullName, avatar, email, phone, p),
                  const SizedBox(height: 18),
                  _statsRow(),
                  const SizedBox(height: 18),
                  _actionList(),
                  const SizedBox(height: 18),
                  if (!_isVerified && !_profileLoading) _verifyCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(Map<String, dynamic> p) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: topPadding + 8, left: 20, right: 12, bottom: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 0.5)),
      ),
      child: SizedBox(
        height: 44,
        child: Row(children: [
          Expanded(child: Text('Profile',
            style: _f(size: 22, weight: FontWeight.w800, letterSpacing: -0.4))),
          _topIcon('assets/icons/bell-icon.svg', _openNotifications, badge: _unreadNotifications),
          const SizedBox(width: 6),
          _topIcon('assets/icons/settings-icon.svg', () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => SettingsScreen(profile: p,
                onProfileUpdated: () => widget.onRefresh?.call())));
          }),
        ]),
      ),
    );
  }

  Widget _topIcon(String svg, VoidCallback onTap, {int badge = 0}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        width: 40, height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            SvgPicture.asset(svg, width: 22, height: 22,
              colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
            if (badge > 0)
              Positioned(
                top: 6, right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: Colors.white, height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _identityCard(String name, String? avatar, String email, String phone, Map<String, dynamic> p) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => SettingsScreen(profile: p,
          onProfileUpdated: () => widget.onRefresh?.call()))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Row(children: [
          _avatar(avatar, name),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name.isNotEmpty ? name : 'Your name',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: _f(size: 18, weight: FontWeight.w800))),
              const SizedBox(width: 8),
              if (_isVerified) _verifiedPill(),
            ]),
            const SizedBox(height: 4),
            if (email.isNotEmpty)
              Text(email, style: _f(size: 13, color: AppColors.textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(phone, style: _f(size: 13, color: AppColors.textSecondary)),
            ],
          ])),
          SvgPicture.asset('assets/icons/chevron-right-icon.svg',
            width: 18, height: 18,
            colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
        ]),
      ),
    );
  }

  Widget _avatar(String? avatar, String name) {
    final initials = name.trim().isEmpty ? 'U'
      : name.trim().split(RegExp(r'\s+')).take(2).map((s) => s[0]).join().toUpperCase();
    return SizedBox(
      width: 64, height: 64,
      child: ClipOval(
        child: Container(
          width: 64, height: 64,
          color: AppColors.surfaceVariant,
          child: avatar != null && avatar.isNotEmpty
            ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover,
                width: 64, height: 64,
                errorWidget: (_, __, ___) => _avatarFallback(initials),
                placeholder: (_, __) => _avatarFallback(initials))
            : _avatarFallback(initials),
        ),
      ),
    );
  }

  Widget _avatarFallback(String initials) => Center(child: Text(initials,
    style: _f(size: 22, weight: FontWeight.w800, color: AppColors.textTertiary)));

  Widget _verifiedPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.verified_rounded, size: 12, color: AppColors.primary),
        const SizedBox(width: 4),
        Text('Verified', style: _f(size: 10, weight: FontWeight.w700, color: AppColors.primary)),
      ]),
    );
  }

  Widget _statsRow() {
    final items = [
      _StatItem(label: 'Events', value: _eventsCount),
      _StatItem(label: 'Tickets', value: _ticketsCount),
      _StatItem(label: 'Contributions', value: _contributionsCount),
      _StatItem(label: 'Saved', value: _savedCount),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEF1), width: 1)),
        child: Row(children: [
          for (int i = 0; i < items.length; i++) ...[
            Expanded(
              child: Column(children: [
                () {
                  final v = items[i].value;
                  final str = v < 100 ? v.toString().padLeft(2, '0') : v.toString();
                  // Shrink font as the number grows so 4-5 digit counts don't overflow.
                  final size = str.length <= 2
                      ? 18.0
                      : str.length == 3
                          ? 16.0
                          : str.length == 4
                              ? 14.0
                              : 12.0;
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(str, maxLines: 1,
                      style: _f(size: size, weight: FontWeight.w800)),
                  );
                }(),
                const SizedBox(height: 4),
                Text(items[i].label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: _f(size: 11, color: AppColors.textTertiary)),
              ]),
            ),
            if (i < items.length - 1)
              Container(width: 1, height: 32, color: const Color(0xFFEEEEF1)),
          ],
        ]),
      ),
    );
  }

  Widget _actionList() {
    final items = <_ActionItem>[
      // Switches to the Events bottom-nav tab pinned on "My Events".
      _ActionItem(svg: 'assets/icons/calendar-icon.svg', label: 'My Events',
        onTap: () => _openShellTab(HomeTabController.events, eventsSubTab: 0)),
      // Switches to the Tickets bottom-nav tab.
      _ActionItem(svg: 'assets/icons/ticket-icon.svg', label: 'My Tickets',
        onTap: () => _openShellTab(HomeTabController.tickets)),
      // Events tab → My Contributions sub-tab.
      _ActionItem(svg: 'assets/icons/card-icon.svg', label: 'My Contributions',
        onTap: () => _openShellTab(HomeTabController.events, eventsSubTab: 3)),
      // Dedicated screen - push it on top of the Home shell.
      _ActionItem(svg: 'assets/icons/wallet-icon.svg', label: 'Payment History',
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()))),
      _ActionItem(svg: 'assets/icons/bookmark-icon.svg', label: 'Saved Vendors',
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const FindServicesScreen(initialSavedOnly: true)))),
      // Manage saved mobile money / bank payout accounts.
      _ActionItem(svg: 'assets/icons/card-icon.svg', label: 'Payment Methods',
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const PayoutProfileScreen()))),
      // Events tab → Invited sub-tab.
      _ActionItem(svg: 'assets/icons/calendar-icon.svg', label: 'My Invitations',
        onTap: () => _openShellTab(HomeTabController.events, eventsSubTab: 1)),
      _ActionItem(svg: 'assets/icons/bookmark-filled-icon.svg', label: 'Saved Posts',
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const SavedPostsScreen()))),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEF1), width: 1)),
        child: Column(children: List.generate(items.length, (i) {
          final it = items[i];
          return InkWell(
            onTap: it.onTap,
            borderRadius: BorderRadius.vertical(
              top: i == 0 ? const Radius.circular(16) : Radius.zero,
              bottom: i == items.length - 1 ? const Radius.circular(16) : Radius.zero),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: i == items.length - 1 ? null
                  : const Border(bottom: BorderSide(color: Color(0xFFF1F1F4), width: 1))),
              child: Row(children: [
                SvgPicture.asset(it.svg, width: 20, height: 20,
                  colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
                const SizedBox(width: 14),
                Expanded(child: Text(it.label, style: _f(size: 14, weight: FontWeight.w400))),
                SvgPicture.asset('assets/icons/chevron-right-icon.svg',
                  width: 16, height: 16,
                  colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
              ]),
            ),
          );
        })),
      ),
    );
  }

  Widget _verifyCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const IdentityVerificationScreen())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF6DD), borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: SvgPicture.asset('assets/icons/shield-icon.svg',
                width: 22, height: 22,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Verify Identity', style: _f(size: 15, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('Unlock trust badges & full features',
                style: _f(size: 12, color: AppColors.textSecondary)),
            ])),
            const Icon(Icons.arrow_forward_rounded, color: AppColors.textPrimary, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _StatItem {
  final String label;
  final int value;
  const _StatItem({required this.label, required this.value});
}

class _ActionItem {
  final String svg;
  final String label;
  final VoidCallback onTap;
  const _ActionItem({required this.svg, required this.label, required this.onTap});
}
