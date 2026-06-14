import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/api_service.dart';
import '../../core/services/events_service.dart';
import '../../core/services/social_service.dart';
import '../../core/services/messages_service.dart';
import '../../core/services/ticketing_service.dart';
import '../../core/services/user_services_service.dart';
import '../../core/services/app_update_service.dart';
import '../../core/widgets/premium_button.dart';
import '../../core/widgets/nuru_refresh.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../providers/auth_provider.dart';
import '../events/event_detail_screen.dart' show EventDetailScreen;
import '../events/event_public_view_screen.dart';
import '../events/widgets/my_contributions_tab.dart';
import '../search/search_screen.dart';
import '../tickets/my_tickets_screen.dart';
import '../profile/profile_screen.dart';
import 'widgets/moment_card.dart';
import 'widgets/post_detail_modal.dart';
import 'widgets/trending_rail.dart';
import 'widgets/glimpses_rail.dart';
import 'widgets/glimpse_composer_screen.dart';
import 'widgets/glimpse_viewer_screen.dart';
import 'widgets/glimpse_group_card.dart';
import 'widgets/create_post_box.dart';
import 'widgets/event_card.dart';
import 'widgets/stats_row.dart';
import 'widgets/pill_tabs.dart';
import 'widgets/shared_widgets.dart';
import 'widgets/home_header.dart';
import 'widgets/home_bottom_nav.dart';
import 'widgets/home_left_drawer.dart';
import '../../core/widgets/nuru_search_bar.dart';
import 'widgets/home_right_drawer.dart';
import 'widgets/home_notifications_tab.dart';
import '../../core/services/moments_service.dart';
import '../../core/utils/home_cache.dart';
import '../../core/utils/feed_persistent_cache.dart';
import '../../core/utils/media_prefetcher.dart';
import '../../core/services/feed_interaction_tracker.dart';
import '../../core/l10n/l10n_helper.dart';
import '../onboarding/country_confirm_sheet.dart';
import '../migration/migration_welcome_sheet.dart';
import '../../providers/migration_provider.dart';
import '../events/create_event_screen.dart';
import 'home_tab_controller.dart';
import '../../core/utils/notification_center.dart';
import '../../core/widgets/global_transfers_badge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _loading = true;
  bool _showCreatePost = false; // Hidden by default - toggled via pill above feed
  Map<String, dynamic>? _profile;
  List<dynamic> _feedPosts = [];
  bool _feedLoading = true;
  bool _feedFallbackTried = false;
  bool _feedLoadingMore = false;
  int _feedPage = 1;
  int _feedTotalPages = 1;
  // Session id for ranked feed - clearing it resets server impression history.
  String _feedSessionId = FeedInteractionTracker.sessionId;
  int _feedRequestId = 0;
  List<dynamic> _myEvents = [];
  List<dynamic> _invitedEvents = [];
  List<dynamic> _committeeEvents = [];
  bool _eventsLoading = true; // first-load skeleton for the Events tab
  List<dynamic> _notifications = [];
  int _unreadNotifications = 0;
  bool _notificationsLoading = true;
  List<dynamic> _followSuggestions = [];
  int _unreadMessages = 0;
  List<dynamic> _upcomingTickets = [];
  List<dynamic> _ticketedEvents = [];
  List<dynamic> _myServices = [];
  int _eventsSubTab = 0;
  String _eventsSearch = '';
  Timer? _eventsSearchDebounce;
  Timer? _myEventsPollTimer; // periodic refresh of all event lists
  bool _eventsSearchOpen = false;
  bool _eventsPollInProgress = false; // prevents overlapping background polls
  final TextEditingController _eventsSearchCtl = TextEditingController();
  final GlobalKey<MyTicketsScreenState> _ticketsKey = GlobalKey<MyTicketsScreenState>();
  final GlobalKey<MyContributionsTabState> _myContribKey = GlobalKey<MyContributionsTabState>();

  // Feed pill tabs: 0 All, 1 Moments, 2 Events, 3 Glimpses
  int _feedTab = 0;
  List<dynamic> _glimpses = [];
  bool _glimpsesLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeTabController.requestSeq.addListener(_onTabRequest);
    NotificationCenter.unreadCount.addListener(_onNotifCenterChange);
    // Seed from cache so re-entering Home is instant; refresh in background.
    if (HomeCache.feedPosts != null && HomeCache.feedPosts!.isNotEmpty) {
      _feedPosts = List<dynamic>.from(HomeCache.feedPosts!);
      _feedPage = HomeCache.feedPage;
      _feedTotalPages = HomeCache.feedTotalPages;
      _feedLoading = false;
    }
    if (HomeCache.glimpses != null) {
      _glimpses = _pruneExpiredGlimpses(List<dynamic>.from(HomeCache.glimpses!));
      _glimpsesLoading = false;
    }
    if (HomeCache.profile != null) _profile = HomeCache.profile;
    if (HomeCache.myEvents != null) { _myEvents = List<dynamic>.from(HomeCache.myEvents!); _eventsLoading = false; }
    if (HomeCache.invitedEvents != null) _invitedEvents = List<dynamic>.from(HomeCache.invitedEvents!);
    if (HomeCache.committeeEvents != null) _committeeEvents = List<dynamic>.from(HomeCache.committeeEvents!);
    if (HomeCache.notifications != null) {
      _notifications = List<dynamic>.from(HomeCache.notifications!);
      _unreadNotifications = HomeCache.unreadNotifications;
      _notificationsLoading = false;
    }
    if (HomeCache.followSuggestions != null) _followSuggestions = List<dynamic>.from(HomeCache.followSuggestions!);
    _unreadMessages = HomeCache.unreadMessages;
    if (HomeCache.upcomingTickets != null) _upcomingTickets = List<dynamic>.from(HomeCache.upcomingTickets!);
    if (HomeCache.ticketedEvents != null) _ticketedEvents = List<dynamic>.from(HomeCache.ticketedEvents!);
    if (HomeCache.myServices != null) _myServices = List<dynamic>.from(HomeCache.myServices!);

    // Once Home has loaded for this session, never show the full-page
    // skeleton again on re-entry - refresh silently in the background like
    // WhatsApp/feed apps do.
    final silent = HomeCache.hasLoadedOnce ||
        (HomeCache.feedPosts != null && HomeCache.feedPosts!.isNotEmpty);
    if (silent) _loading = false;
    // Hydrate the chronological feed list from disk so re-launches render
    // instantly. Falls through to a silent network refresh below.
    if (_feedPosts.isEmpty) {
      FeedPersistentCache.readFeed().then((cached) {
        if (!mounted || cached == null || cached.posts.isEmpty) return;
        setState(() {
          _feedPosts = _dedupePosts(cached.posts);
          _feedPage = cached.page;
          _feedTotalPages = cached.totalPages;
          _feedLoading = false;
        });
        HomeCache.feedPosts = _feedPosts;
      });
    }
    if (_glimpses.isEmpty) {
      FeedPersistentCache.readGlimpses().then((cached) {
        if (!mounted || cached == null) return;
        final pruned = _pruneExpiredGlimpses(cached);
        setState(() {
          _glimpses = pruned;
          _glimpsesLoading = false;
        });
        HomeCache.glimpses = _glimpses;
      });
    }
    _loadAllData(silent: silent);
    // Continuous background polling of the user's event lists so newly
    // accepted invites, RSVP/check-in changes and freshly created events
    // appear without forcing a pull-to-refresh.  Overlapping polls are
    // skipped so the UI never stutters.
    _myEventsPollTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!mounted) return;
      // Prune expired glimpses every tick so the rail self-clears at the 24h
      // mark even when the user hasn't pulled to refresh.
      final pruned = _pruneExpiredGlimpses(_glimpses);
      if (pruned.length != _glimpses.length) {
        setState(() => _glimpses = pruned);
        HomeCache.glimpses = _glimpses;
        FeedPersistentCache.saveGlimpses(_glimpses);
      }
      if (_eventsPollInProgress) return;
      _eventsPollInProgress = true;
      _loadEvents(silent: true).whenComplete(() => _eventsPollInProgress = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppUpdateService.checkAndPrompt(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventsSearchDebounce?.cancel();
    _myEventsPollTimer?.cancel();
    _eventsSearchCtl.dispose();
    HomeTabController.requestSeq.removeListener(_onTabRequest);
    NotificationCenter.unreadCount.removeListener(_onNotifCenterChange);
    super.dispose();
  }

  /// Refresh live data when the app returns from background so the user
  /// never sees stale My Events / notifications / unread counts after
  /// switching apps. Runs silently - no skeleton flash.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadEvents(silent: true);
      _loadNotifications(silent: true);
      _loadUnreadMessages();
    }
  }

  /// Mirror central unread count into local state so the existing
  /// AppBar wiring (which reads `_unreadNotifications`) stays in sync
  /// when another screen (Profile, notifications tab) updates the badge.
  void _onNotifCenterChange() {
    if (!mounted) return;
    final v = NotificationCenter.unreadCount.value;
    if (v != _unreadNotifications) {
      setState(() => _unreadNotifications = v);
      HomeCache.unreadNotifications = v;
    }
  }

  Future<void> _loadAllData({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    await Future.wait([
      _loadProfile(),
      _loadFeed(silent: silent),
      _loadEvents(),
      _loadNotifications(silent: silent),
      _loadFollowSuggestions(),
      _loadUnreadMessages(),
      _loadUpcomingTickets(),
      _loadTicketedEvents(),
      _loadMyServices(),
      _loadGlimpses(silent: silent),
    ]);
    if (mounted && !silent) setState(() => _loading = false);
    HomeCache.hasLoadedOnce = true;
  }

  Future<void> _loadGlimpses({bool silent = false}) async {
    if (mounted && !silent) setState(() => _glimpsesLoading = true);
    final res = await MomentsService.getFeed();
    if (!mounted) return;
    final data = res['data'];
    final fresh = _pruneExpiredGlimpses(data is List ? data : const []);
    setState(() {
      _glimpses = fresh;
      _glimpsesLoading = false;
    });
    HomeCache.glimpses = _glimpses;
    FeedPersistentCache.saveGlimpses(_glimpses);
  }

  /// Remove moments whose `expires_at` has already passed, and drop authors
  /// whose moments are all gone. Stops stale cached glimpses from lingering on
  /// screen after their 24h window has lapsed.
  List<dynamic> _pruneExpiredGlimpses(List<dynamic> glimpses) {
    final now = DateTime.now();
    final out = <dynamic>[];
    for (final r in glimpses) {
      if (r is! Map) continue;
      final moments = (r['moments'] is List) ? List<dynamic>.from(r['moments']) : <dynamic>[];
      moments.removeWhere((m) {
        if (m is! Map) return true;
        final exp = m['expires_at']?.toString();
        if (exp == null || exp.isEmpty) return false;
        var s = exp.trim();
        final hasTz = s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
        if (!hasTz) s = '${s}Z';
        final dt = DateTime.tryParse(s);
        if (dt == null) return false;
        return dt.toLocal().isBefore(now);
      });
      if (moments.isEmpty) continue;
      final copy = Map<String, dynamic>.from(r);
      copy['moments'] = moments;
      copy['all_seen'] = moments.every((m) => m is Map && m['has_seen'] == true);
      out.add(copy);
    }
    return out;
  }

  /// Listener for [HomeTabController] requests coming from any screen.
  /// When fired, pop any pushed routes back to the Home shell, then switch
  /// the bottom-nav tab. Used by "My Tickets" buttons in Profile / Drawer
  /// / Browse Tickets so they activate the Tickets tab instead of pushing
  /// a new full-screen route.
  void _onTabRequest() {
    if (!mounted) return;
    final target = HomeTabController.requestedTab;
    final subTab = HomeTabController.requestedEventsSubTab;
    HomeTabController.requestedEventsSubTab = null;
    // Pop only routes stacked above this Home shell. Never pop back to Splash.
    final homeRoute = ModalRoute.of(context);
    Navigator.of(context).popUntil((route) => identical(route, homeRoute) || route.isFirst);
    setState(() {
      if (_tab != target) _tab = target;
      if (target == HomeTabController.events && subTab != null) {
        _eventsSubTab = subTab;
      }
    });
  }

  Future<void> _loadProfile() async {
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
    if (mounted && userData != null) {
      setState(() => _profile = userData);
      HomeCache.profile = userData;
      _maybePromptCountry(userData);
      _loadMigrationStatus(userData);
    }
  }

  bool _countryPrompted = false;
  bool _migrationPrompted = false;

  void _maybePromptCountry(Map<String, dynamic> user) {
    if (_countryPrompted) return;
    final cc = (user['country_code'] ?? user['country'])?.toString();
    if (cc != null && cc.isNotEmpty) return;
    _countryPrompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showCountryConfirmSheet(context);
    });
  }

  Future<void> _loadMigrationStatus(Map<String, dynamic> user) async {
    final id = user['id']?.toString();
    if (id == null) return;
    final mig = context.read<MigrationProvider>();
    await mig.load(id);
    if (!mounted || _migrationPrompted) return;
    if (await mig.shouldShowWelcome()) {
      _migrationPrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // If country isn't set yet, the country sheet takes priority.
        final cc = (user['country_code'] ?? user['country'])?.toString();
        if (cc == null || cc.isEmpty) return;
        showMigrationWelcomeSheet(context);
      });
    }
  }

  Future<void> _loadFeed({bool refresh = true, bool resetSession = false, bool silent = false}) async {
    if (refresh) {
      if (resetSession) {
        FeedInteractionTracker.resetSession();
        _feedSessionId = FeedInteractionTracker.sessionId;
      }
      if (!silent) {
        setState(() {
          // Only show the full skeleton when we have nothing on screen.
          // If posts are already rendered (from memory or disk cache), refresh
          // silently so the feed never blanks out.
          if (_feedPosts.isEmpty) _feedLoading = true;
          _feedFallbackTried = false;
          _feedPage = 1;
        });
      } else {
        _feedFallbackTried = false;
        _feedPage = 1;
      }
    }
    final reqId = ++_feedRequestId;
    final res = await SocialService.getFeed(page: _feedPage, limit: 15, sessionId: _feedSessionId);
    if (!mounted || reqId != _feedRequestId) return;
    List<dynamic> items = const [];
    Map? pagination;
    if (res['success'] == true) {
      final data = res['data'];
      final raw = data is Map ? (data['items'] ?? data['posts'] ?? []) : (data is List ? data : []);
      items = raw is List ? raw : const [];
      pagination = data is Map ? (data['pagination'] as Map?) : null;
    }
    setState(() {
      if (refresh) {
        // During a silent refresh, never wipe existing posts if the new
        // fetch returned empty (transient/network glitch). Keeps content
        // visible while we silently retry.
        if (items.isEmpty && _feedPosts.isNotEmpty) {
          // keep existing
        } else {
          _feedPosts = _dedupePosts(items);
        }
      } else {
        _feedPosts = _dedupePosts([..._feedPosts, ...items]);
      }
      _feedPage = (pagination?['page'] as int?) ?? _feedPage;
      _feedTotalPages = (pagination?['pages'] as int?) ?? 1;
      if (_feedPosts.isNotEmpty) {
        _feedLoading = false;
      }
    });
    HomeCache.feedPosts = _feedPosts;
    HomeCache.feedPage = _feedPage;
    HomeCache.feedTotalPages = _feedTotalPages;
    FeedPersistentCache.saveFeed(
      posts: _feedPosts,
      page: _feedPage,
      totalPages: _feedTotalPages,
    );
    if (_feedPosts.isEmpty && refresh && !_feedFallbackTried && !silent) {
      _feedFallbackTried = true;
      await _loadTrendingFallback();
      if (mounted) setState(() => _feedLoading = false);
    } else if (_feedPosts.isEmpty && refresh && !silent) {
      if (mounted) setState(() => _feedLoading = false);
    }
  }

  List<dynamic> _dedupePosts(List<dynamic> posts) {
    final seen = <String>{};
    final out = <dynamic>[];
    for (final p in posts) {
      final id = (p is Map ? (p['id'] ?? p['post_id']) : null)?.toString();
      if (id == null || id.isEmpty) { out.add(p); continue; }
      if (seen.add(id)) out.add(p);
    }
    return out;
  }

  Future<void> _loadTrendingFallback() async {
    final res = await SocialService.getExplore(limit: 15);
    if (mounted && res['success'] == true) {
      final data = res['data'];
      final items = data is List ? data : (data is Map ? (data['posts'] ?? data['items'] ?? []) : []);
      setState(() => _feedPosts = _dedupePosts(items is List ? items : const []));
    }
  }

  Future<void> _loadMoreFeed() async {
    if (_feedLoadingMore || _feedPage >= _feedTotalPages) return;
    setState(() => _feedLoadingMore = true);
    _feedPage++;
    final res = await SocialService.getFeed(page: _feedPage, limit: 15, sessionId: _feedSessionId);
    if (mounted) {
      setState(() {
        _feedLoadingMore = false;
        if (res['success'] == true) {
          final data = res['data'];
          final items = data is Map ? (data['items'] ?? data['posts'] ?? []) : (data is List ? data : []);
          _feedPosts = _dedupePosts([..._feedPosts, ...(items is List ? items : const [])]);
          final pagination = data is Map ? data['pagination'] : null;
          _feedTotalPages = pagination?['pages'] ?? _feedTotalPages;
        }
      });
    }
  }

  /// Lightweight equality check for event lists so background polls only
  /// call [setState] when data actually changed.
  bool _eventsListsEqual(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final am = a[i] is Map ? a[i] as Map : null;
      final bm = b[i] is Map ? b[i] as Map : null;
      if ((am?['id']?.toString()) != (bm?['id']?.toString())) return false;
      if ((am?['updated_at']?.toString()) != (bm?['updated_at']?.toString())) return false;
    }
    return true;
  }

  Future<void> _loadEvents({bool silent = false}) async {
    final results = await Future.wait([
      EventsService.getMyEvents(limit: 20),
      EventsService.getInvitedEvents(limit: 20),
      EventsService.getCommitteeEvents(limit: 20),
    ]);
    if (!mounted) return;

    // IMPORTANT: if a background poll request fails (timeout/network/5xx),
    // _extractEvents returns null. We MUST keep the previously-loaded list
    // instead of clobbering it with []. Otherwise the My Events tab flashes
    // an empty state ("No events · Create event") until the next pull-to-
    // refresh succeeds. Only update lists whose request actually succeeded.
    final newMyEvents = _extractEvents(results[0]);
    final newInvitedEvents = _extractEvents(results[1]);
    final newCommitteeEvents = _extractEvents(results[2]);

    final myEventsNext = newMyEvents ?? _myEvents;
    final invitedNext = newInvitedEvents ?? _invitedEvents;
    final committeeNext = newCommitteeEvents ?? _committeeEvents;

    final unchanged = _eventsListsEqual(_myEvents, myEventsNext) &&
        _eventsListsEqual(_invitedEvents, invitedNext) &&
        _eventsListsEqual(_committeeEvents, committeeNext);

    if (!unchanged) {
      setState(() {
        _myEvents = myEventsNext;
        _invitedEvents = invitedNext;
        _committeeEvents = committeeNext;
        _eventsLoading = false;
      });
      HomeCache.myEvents = _myEvents;
      HomeCache.invitedEvents = _invitedEvents;
      HomeCache.committeeEvents = _committeeEvents;
    } else if (_eventsLoading) {
      setState(() => _eventsLoading = false);
    }
  }

  String _notificationsSearch = '';

  Future<void> _loadNotifications({String? search, bool silent = false}) async {
    if (search != null) _notificationsSearch = search;
    final hasCache = _notifications.isNotEmpty;
    if (!silent && !hasCache) setState(() => _notificationsLoading = true);
    final res = await SocialService.getNotifications(
      limit: 30,
      search: _notificationsSearch.isNotEmpty ? _notificationsSearch : null,
    );
    if (mounted) {
      setState(() {
        _notificationsLoading = false;
        if (res['success'] == true) {
          final data = res['data'];
          _notifications = data is Map ? (data['notifications'] ?? []) : (data is List ? data : []);
          _unreadNotifications = data is Map ? (data['unread_count'] ?? 0) : 0;
          HomeCache.notifications = _notifications;
          HomeCache.unreadNotifications = _unreadNotifications;
          // Broadcast to every app-bar badge in the app (Profile, etc).
          NotificationCenter.setUnread(_unreadNotifications);
        }
      });
    }
  }

  Future<void> _loadFollowSuggestions() async {
    final res = await SocialService.getFollowSuggestions(limit: 5);
    if (mounted && res['success'] == true) {
      final data = res['data'];
      setState(() => _followSuggestions = data is List ? data : []);
      HomeCache.followSuggestions = _followSuggestions;
    }
  }

  Future<void> _loadUnreadMessages() async {
    final count = await MessagesService.getUnreadCount();
    if (mounted) setState(() => _unreadMessages = count);
    HomeCache.unreadMessages = count;
  }

  Future<void> _loadUpcomingTickets() async {
    final res = await TicketingService.getMyUpcomingTickets();
    if (mounted && res['success'] == true) {
      final data = res['data'];
      setState(() => _upcomingTickets = data is List ? data : (data is Map ? (data['tickets'] ?? []) : []));
      HomeCache.upcomingTickets = _upcomingTickets;
    }
  }

  Future<void> _loadTicketedEvents() async {
    final res = await TicketingService.getTicketedEvents(limit: 5);
    if (mounted && res['success'] == true) {
      final data = res['data'];
      setState(() => _ticketedEvents = data is List ? data : (data is Map ? (data['events'] ?? []) : []));
      HomeCache.ticketedEvents = _ticketedEvents;
    }
  }

  Future<void> _loadMyServices() async {
    final res = await UserServicesService.getServiceProviders(limit: 20);
    if (!mounted) return;
    final data = res['data'] ?? res;
    if (data is List) {
      setState(() => _myServices = data);
      HomeCache.myServices = _myServices;
      return;
    }
    if (data is Map) {
      final nested = data['data'];
      final services = data['services'] ?? data['items'] ?? (nested is Map ? (nested['services'] ?? nested['items']) : nested);
      setState(() => _myServices = services is List ? services : []);
      HomeCache.myServices = _myServices;
      return;
    }
    setState(() => _myServices = []);
    HomeCache.myServices = _myServices;
  }

  /// Returns the events list on success, or `null` when the API call failed.
  /// Callers must treat `null` as "keep the existing list" and never replace
  /// the on-screen events with an empty array on transient failures.
  List<dynamic>? _extractEvents(Map<String, dynamic> res) {
    if (res['success'] != true) return null;
    final data = res['data'];
    if (data is List) return data;
    if (data is Map) return data['events'] ?? [];
    return [];
  }

  // ── Premium 4-bucket KPI counts (matches web My Events) ──
  bool _isCancelledOrDraft(dynamic e) {
    final s = (e is Map ? e['status']?.toString() : '') ?? '';
    return s == 'cancelled' || s == 'draft';
  }

  DateTime? _eventStart(dynamic e) {
    final d = (e is Map ? e['start_date']?.toString() : '') ?? '';
    if (d.isEmpty) return null;
    try { return DateTime.parse(d); } catch (_) { return null; }
  }

  int get _kpiUpcoming => _myEvents.where((e) {
    if (_isCancelledOrDraft(e)) return false;
    final d = _eventStart(e);
    return d == null || d.isAfter(DateTime.now());
  }).length;

  int get _kpiThisMonth => _myEvents.where((e) {
    if (_isCancelledOrDraft(e)) return false;
    final d = _eventStart(e);
    final now = DateTime.now();
    return d != null && d.year == now.year && d.month == now.month;
  }).length;

  int get _kpiDrafts => _myEvents.where((e) =>
      (e is Map ? e['status']?.toString() : '') == 'draft').length;

  int get _kpiPast => _myEvents.where((e) {
    if (_isCancelledOrDraft(e)) return false;
    final d = _eventStart(e);
    return d != null && d.isBefore(DateTime.now());
  }).length;

  int get _kpiCompleted => _myEvents.where((e) {
    final status = (e is Map ? e['status']?.toString() : '') ?? '';
    if (status == 'completed') return true;
    if (_isCancelledOrDraft(e)) return false;
    final d = _eventStart(e);
    return d != null && d.isBefore(DateTime.now());
  }).length;

  int get _kpiTotalGuests => _myEvents.fold<int>(0, (sum, e) {
    if (e is! Map) return sum;
    final raw = e['expected_guests'] ?? e['guest_count'] ?? 0;
    if (raw is num) return sum + raw.toInt();
    return sum + (int.tryParse(raw.toString()) ?? 0);
  });

  // Backward-compat (used by ProfileScreen)
  int get _totalEvents => _myEvents.length;
  int get _upcomingEvents => _kpiUpcoming;

  bool _isUserVerified() {
    final p = _profile ?? const {};
    if (p['is_identity_verified'] == true ||
        p['identity_verified'] == true ||
        p['kyc_verified'] == true ||
        p['is_verified'] == true) return true;
    final status = (p['verification_status'] ?? p['identity_status'] ?? p['kyc_status'])
        ?.toString()
        .toLowerCase();
    return status == 'verified' || status == 'approved';
  }


  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = _profile?['first_name'] ?? auth.userName ?? '';
    final avatar = (_profile?['avatar'] as String?) ?? auth.userAvatar;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.surface,
        extendBody: true,
        extendBodyBehindAppBar: true,
        drawer: HomeLeftDrawer(
          currentTab: _tab,
          unreadMessages: _unreadMessages,
          unreadNotifications: _unreadNotifications,
          profile: _profile,
          onTabSelected: (i) => setState(() => _tab = i),
          onRefresh: () => _loadAllData(silent: true),
        ),
        endDrawer: HomeRightDrawer(
          myEvents: _myEvents,
          invitedEvents: _invitedEvents,
          committeeEvents: _committeeEvents,
          upcomingTickets: _upcomingTickets,
          ticketedEvents: _ticketedEvents,
          myServices: _myServices,
          followSuggestions: _followSuggestions,
          onFollowChanged: () => setState(() => _loadFollowSuggestions()),
          userName: name,
          userAvatar: avatar,
          isVerified: _isUserVerified(),
        ),

        body: Column(
          children: [
            // Global header is only shown on tabs that need it (Home, Events).
            // Tickets (3) and Profile (4) own their headers per design.
            if (_tab == 0 || _tab == 1 || _tab == 3)
              HomeHeader(
                name: name,
                avatar: avatar,
                title: _tab == 1
                    ? context.tr('my_events')
                    : (_tab == 3 ? context.tr('my_tickets') : null),
                unreadNotifications: _unreadNotifications,
                onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                onSearchTap: () {
                  if (_tab == 1) {
                    if (_eventsSubTab == 3) {
                      _myContribKey.currentState?.toggleSearch();
                    } else {
                      setState(() => _eventsSearchOpen = !_eventsSearchOpen);
                    }
                  } else if (_tab == 3) {
                    _ticketsKey.currentState?.toggleSearch();
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
                  }
                },
                onNotificationsTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: AppColors.surface,
                      body: HomeNotificationsTab(
                        notifications: _notifications,
                        unreadCount: _unreadNotifications,
                        isLoading: _notificationsLoading,
                        onRefresh: () => _loadNotifications(silent: true),
                        onSearch: (q) => _loadNotifications(search: q),
                        onTabChanged: (i) {
                          Navigator.pop(context);
                          setState(() => _tab = i);
                        },
                      ),
                    ),
                  ),
                ).then((_) => _loadNotifications()),
                onRightPanelTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                onProfileTap: () => setState(() => _tab = 4),
                onMomentTap: _tab == 0
                    ? () => setState(() => _showCreatePost = !_showCreatePost)
                    : null,
                momentActive: _tab == 0 && _showCreatePost,
              ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _feedContent(),
                  _eventsContent(),
                  // Index 2 is reserved for the center "+" create action.
                  const SizedBox.shrink(),
                  MyTicketsScreen(key: _ticketsKey),
                  _profileContent(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: const GlobalTransfersBadge(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: HomeBottomNav(
          currentTab: _tab,
          unreadMessages: _unreadMessages,
          unreadNotifications: _unreadNotifications,
          onCreateTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateEventScreen()),
            );
          },
          onTabChanged: (i) {
            // Center "+" is handled by onCreateTap; ignore stray index 2 taps.
            if (i == 2) return;
            final wasEvents = _tab == HomeTabController.events;
            setState(() => _tab = i);
            // Re-entering My Events should always reflect the latest backend
            // state, not a stale list cached on first load. Re-fire when the
            // user re-selects the same tab too.
            if (i == HomeTabController.events) {
              _loadEvents(silent: _myEvents.isNotEmpty || wasEvents);
            }
          },
        ),
      ),
    );
  }

  List<dynamic> get _filteredFeed {
    bool isEventShare(dynamic p) {
      if (p is! Map) return false;
      final pt = (p['post_type'] ?? p['type'] ?? '').toString();
      return pt == 'event_share' || p['shared_event'] != null;
    }
    bool isGlimpse(dynamic p) {
      if (p is! Map) return false;
      final pt = (p['post_type'] ?? p['type'] ?? '').toString();
      return pt == 'glimpse' || pt == 'moment_share' || p['moment'] != null || p['moment_id'] != null;
    }
    bool isMoment(dynamic p) {
      // Plain user posts/feeds - exclude event-shares & glimpses
      if (p is! Map) return false;
      if (isEventShare(p) || isGlimpse(p)) return false;
      return true;
    }
    if (_feedTab == 1) return _feedPosts.where(isMoment).toList();
    if (_feedTab == 2) return _feedPosts.where(isEventShare).toList();
    if (_feedTab == 3) return _feedPosts.where(isGlimpse).toList();
    // All tab: hide individual glimpse posts (they're already grouped in the rail above).
    return _feedPosts.where((p) => !isGlimpse(p)).toList();
  }

  void _openGlimpseViewer(int authorIndex) {
    if (authorIndex < 0 || authorIndex >= _glimpses.length) return;
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => GlimpseViewerScreen(
        glimpses: _glimpses,
        initialAuthorIndex: authorIndex,
      ),
    )).then((_) => _loadGlimpses());
  }

  void _openCreateGlimpse() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const GlimpseComposerScreen(),
    ));
    if (created == true) {
      await _loadGlimpses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your glimpse is live for 24 hours')),
        );
      }
    }
  }

  Widget _feedContent() {
    final isGlimpsesTab = _feedTab == 3;
    final filtered = isGlimpsesTab ? const <dynamic>[] : _filteredFeed;
    final glimpseGroups = isGlimpsesTab ? _glimpses : const <dynamic>[];
    final listLen = isGlimpsesTab ? glimpseGroups.length : filtered.length;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.pixels >= notification.metrics.maxScrollExtent - 300 &&
            _feedPage < _feedTotalPages && !_feedLoadingMore && !isGlimpsesTab) {
          _loadMoreFeed();
        }
        return false;
      },
      child: NuruRefresh(
        onRefresh: () async {
          await Future.wait([
            _loadFeed(refresh: true, resetSession: true, silent: true),
            _loadGlimpses(silent: true),
          ]);
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: listLen + 4 + (_feedLoadingMore && !isGlimpsesTab ? 1 : 0) + (!_feedLoading && _feedFallbackTried && listLen == 0 ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GlimpsesRail(
                  glimpses: _glimpses,
                  loading: false,
                  myAvatar: (_profile?['avatar'] as String?),
                  onCreateTap: _openCreateGlimpse,
                  onAuthorTap: _openGlimpseViewer,
                ),
              );
            }
            if (index == 1) {
              if (!_showCreatePost) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CreatePostBox(onPostCreated: () {
                  setState(() => _showCreatePost = false);
                  _loadFeed(refresh: true);
                }),
              );
            }
            if (index == 2) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: PillTabs(
                  tabs: const ['All', 'Moments', 'Events', 'Glimpses'],
                  selected: _feedTab,
                  onChanged: (i) => setState(() => _feedTab = i),
                ),
              );
            }
            if (index == 3) return _feedTab == 3 ? const TrendingRail() : const SizedBox.shrink();
            if (index == 4 && (_feedLoading || (_feedPosts.isEmpty && !_feedFallbackTried) || (listLen == 0 && !_feedFallbackTried))) {
              return NuruSkeletonPostList(
                itemCount: 4,
                variant: _feedTab == 1
                    ? FeedSkeletonVariant.moment
                    : _feedTab == 2
                        ? FeedSkeletonVariant.event
                        : _feedTab == 3
                            ? FeedSkeletonVariant.glimpse
                            : FeedSkeletonVariant.post,
              );
            }
            if (index == 4 && listLen == 0) {
              return EmptyState(
                icon: _feedTab == 3 ? Icons.auto_awesome_rounded : Icons.dynamic_feed_rounded,
                title: _feedTab == 1
                    ? 'No moments yet'
                    : _feedTab == 2
                        ? 'No event posts'
                        : _feedTab == 3
                            ? 'No glimpses in your circle'
                            : 'No posts yet',
                subtitle: _feedTab == 0
                    ? 'Be the first to share something with the community!'
                    : 'Check back soon or follow more people to see updates here.',
              );
            }
            final itemIndex = index - 4;
            if (itemIndex >= listLen) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))));
            }
            if (isGlimpsesTab) {
              final group = glimpseGroups[itemIndex];
              if (group is! Map) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GlimpseGroupCard(
                  group: group,
                  onOpen: (_) => _openGlimpseViewer(itemIndex),
                ),
              );
            }
            final post = filtered[itemIndex];
            final postMap = post is Map<String, dynamic> ? post : <String, dynamic>{};
            final postId = (postMap['id'] ?? postMap['post_id'] ?? '').toString();
            // Log a one-time view for ranking + warm media for the next few cards.
            if (postId.isNotEmpty) {
              FeedInteractionTracker.logView(postId);
            }
            MediaPrefetcher.prefetchUpcoming(context, filtered, itemIndex + 1);
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: MomentCard(
                key: ValueKey('moment_${postId.isNotEmpty ? postId : itemIndex}'),
                post: postMap,
                onTap: () {
                  if (postId.isNotEmpty) {
                    FeedInteractionTracker.log(postId, 'click_image');
                  }
                  PostDetailModal.show(context, postMap);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _eventsContent() {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final rawEvents = _eventsSubTab == 0 ? _myEvents : _eventsSubTab == 1 ? _invitedEvents : _committeeEvents;
        final q = _eventsSearch.trim().toLowerCase();
        final events = (_eventsSubTab == 0 && q.isNotEmpty)
            ? rawEvents.where((e) {
                if (e is! Map) return false;
                final hay = [e['title'], e['name'], e['location'], e['venue'], e['description']]
                    .whereType<Object>()
                    .map((x) => x.toString().toLowerCase())
                    .join(' ');
                return hay.contains(q);
              }).toList()
            : rawEvents;

        // Sticky header (tabs + optional search). Each tab body owns its
        // own scrollable so switching tabs preserves scroll offset and the
        // tab bar stays pinned - mirrors the event-detail screen pattern.
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _UnderlineTabs(
                  tabs: const ['My Events', 'Invited', 'Committee', 'My Contributions'],
                  selected: _eventsSubTab,
                  onChanged: (i) => setLocalState(() => _eventsSubTab = i),
                ),
                const SizedBox(height: 14),
                if (_eventsSubTab == 0 && _eventsSearchOpen) ...[
                  SizedBox(width: double.infinity, child: _eventsSearchBar(setLocalState)),
                  const SizedBox(height: 14),
                ],
              ]),
            ),
            Expanded(
              child: _eventsSubTab == 3
                  ? MyContributionsTab(key: _myContribKey)
                  : NuruRefresh(
                      onRefresh: () async => await _loadEvents(silent: true),
                      child: (_loading || _eventsLoading)
                          ? const NuruSkeletonEventList(
                              itemCount: 4,
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 120),
                              physics: AlwaysScrollableScrollPhysics(),
                            )
                          : events.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
                                  children: [
                                    EmptyState(
                                      icon: _eventsSubTab == 0
                                          ? Icons.calendar_month_outlined
                                          : _eventsSubTab == 1
                                              ? Icons.mail_outline_rounded
                                              : null,
                                      iconAsset: _eventsSubTab == 2
                                          ? 'assets/icons/users-icon.svg'
                                          : null,
                                      title: _eventsSubTab == 0
                                          ? (_eventsSearch.isNotEmpty ? 'No matches' : 'No Events Yet')
                                          : _eventsSubTab == 1
                                              ? 'No invitations'
                                              : 'Not in any committee',
                                      subtitle: _eventsSubTab == 0
                                          ? (_eventsSearch.isNotEmpty
                                              ? 'Nothing matched "$_eventsSearch". Try a different keyword.'
                                              : 'Create your first event to start planning, managing guests, and tracking contributions.')
                                          : _eventsSubTab == 1
                                              ? 'No invitations yet'
                                              : 'You are currently not part of any event committee. When you are added to a committee, the related events will appear here.',
                                      action: _eventsSubTab == 0 && _eventsSearch.isEmpty
                                          ? SizedBox(width: 200, child: PremiumButton(label: 'Create Your First Event', icon: Icons.add_rounded, onPressed: () {
                                              Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEventScreen()));
                                            }, height: 44))
                                          : null,
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  key: PageStorageKey<String>('events_tab_$_eventsSubTab'),
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                                  itemCount: events.length,
                                  itemBuilder: (_, i) {
                                    final e = events[i];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: EventCard(
                                        event: e,
                                        role: _eventsSubTab == 0 ? 'creator' : _eventsSubTab == 1 ? 'guest' : 'committee',
                                        onTap: () {
                                          final role = _eventsSubTab == 0 ? 'creator' : _eventsSubTab == 1 ? 'guest' : 'committee';
                                          Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => role == 'guest'
                                                ? EventPublicViewScreen(eventId: e['id']?.toString() ?? '', initialData: e)
                                                : EventDetailScreen(eventId: e['id']?.toString() ?? '', initialData: e, knownRole: role),
                                          ));
                                        },
                                        onView: () {
                                          Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => EventPublicViewScreen(eventId: e['id']?.toString() ?? '', initialData: e),
                                          ));
                                        },
                                        onEdit: () {
                                          Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => CreateEventScreen(editEvent: e),
                                          )).then((_) => _loadEvents(silent: true));
                                        },
                                        onShare: () {
                                          final id = e['id']?.toString() ?? '';
                                          final title = (e['title'] ?? e['name'] ?? 'Event').toString();
                                          final url = 'https://nuru.tz/events/$id';
                                          Share.share('$title\n$url', sharePositionOrigin: sharePositionOrigin(context));
                                        },
                                        onStatusChange: (newStatus) async {
                                          final res = await EventsService.updateEventStatus(e['id']?.toString() ?? '', newStatus);
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                            content: Text(res['success'] == true ? 'Event updated' : (res['message']?.toString() ?? 'Could not update')),
                                          ));
                                          if (res['success'] == true) _loadEvents(silent: true);
                                        },
                                        onDelete: () async {
                                          final res = await EventsService.deleteEvent(e['id']?.toString() ?? '');
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                            content: Text(res['success'] == true ? 'Event deleted' : (res['message']?.toString() ?? 'Could not delete')),
                                          ));
                                          if (res['success'] == true) _loadEvents(silent: true);
                                        },
                                      ),
                                    );
                                  },
                                ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _profileContent() {
    return ProfileScreen(
      profile: _profile,
      myEventsCount: _myEvents.length,
      ticketsCount: _upcomingTickets.length,
      onRefresh: () => _loadAllData(silent: true),
    );
  }

  // (legacy _heroStat / _heroDivider removed - Events tab now uses clean white layout)

  Widget _eventsSearchBar(StateSetter setLocalState) {
    return NuruSearchBar(
      controller: _eventsSearchCtl,
      hintText: 'Search by title, location…',
      debounce: const Duration(milliseconds: 200),
      onChanged: (v) {
        _eventsSearch = v;
        setLocalState(() {});
      },
      onClear: () {
        _eventsSearch = '';
        setLocalState(() {});
      },
    );
  }

}

/// Mockup-faithful underline tab bar used by the Events tab.
/// Active tab gets a yellow (secondary) underline and bold text.
class _UnderlineTabs extends StatefulWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;
  const _UnderlineTabs({required this.tabs, required this.selected, required this.onChanged});

  @override
  State<_UnderlineTabs> createState() => _UnderlineTabsState();
}

class _UnderlineTabsState extends State<_UnderlineTabs> {
  final ScrollController _scrollCtrl = ScrollController();
  final List<GlobalKey> _tabKeys = [];

  void _ensureKeys() {
    while (_tabKeys.length < widget.tabs.length) _tabKeys.add(GlobalKey());
  }

  @override
  void initState() {
    super.initState();
    _ensureKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveIntoView());
  }

  @override
  void didUpdateWidget(covariant _UnderlineTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureKeys();
    if (oldWidget.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveIntoView());
    }
  }

  void _scrollActiveIntoView() {
    if (!mounted || widget.selected >= _tabKeys.length) return;
    final ctx = _tabKeys[widget.selected].currentContext;
    if (ctx == null || !_scrollCtrl.hasClients) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final viewportWidth = _scrollCtrl.position.viewportDimension;
    final tabOffset = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject()).dx;
    final tabWidth = box.size.width;
    final tabCenterAbs = _scrollCtrl.offset + tabOffset + tabWidth / 2;
    final target = (tabCenterAbs - viewportWidth / 2).clamp(
      _scrollCtrl.position.minScrollExtent,
      _scrollCtrl.position.maxScrollExtent,
    );
    _scrollCtrl.animateTo(target,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureKeys();
    return SingleChildScrollView(
      controller: _scrollCtrl,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: List.generate(widget.tabs.length, (i) {
          final active = i == widget.selected;
          return GestureDetector(
            key: _tabKeys[i],
            onTap: () {
              widget.onChanged(i);
              WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveIntoView());
            },
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
                widget.tabs[i],
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
}
