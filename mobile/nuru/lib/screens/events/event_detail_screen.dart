import '../../core/widgets/nuru_refresh_indicator.dart';
import '../../core/widgets/nuru_scrollable_tabs.dart';

import '../../core/utils/money_format.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/events_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/ticketing_service.dart';
import '../../core/services/report_generator.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/event_cover_image.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../providers/auth_provider.dart';
import '../photos/my_photo_libraries_screen.dart';
import '../meetings/meetings_calendar_sheet.dart';
import 'widgets/event_guests_tab.dart';
import 'widgets/event_budget_tab.dart';
import 'widgets/event_checklist_tab.dart';
import 'widgets/event_contributions_tab.dart';
import 'widgets/event_expenses_tab.dart';
import 'widgets/event_rsvp_tab.dart';
import 'widgets/event_checkin_tab.dart';
import 'widgets/event_tickets_tab.dart';
import 'event_invitation_screen.dart';
import 'widgets/smart_rsvp_calls_screen.dart';
import 'widgets/event_committee_tab.dart';
import 'widgets/event_services_tab.dart';
import 'widgets/event_sponsors_tab.dart';
import 'widgets/event_meetings_tab.dart';

import 'widgets/event_automations_tab.dart';
import 'widgets/event_activity_screen.dart';
import 'create_event_screen.dart';
import 'widgets/share_event_to_feed_sheet.dart';
import 'widgets/venue_map_preview.dart';
import 'report_preview_screen.dart';
import 'budget_assistant_screen.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../core/services/event_groups_service.dart';
import '../event_groups/event_group_workspace_screen.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic>? initialData;
  final String? knownRole;

  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.initialData,
    this.knownRole,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen>
    with TickerProviderStateMixin {
  // Module-level in-memory cache so navigating away and back shows the
  // last-known event instantly while a background refresh runs.
  static final Map<String, Map<String, dynamic>> _eventCache = {};
  static final Map<String, DateTime> _eventCacheAt = {};

  static const List<String> _permissionFields = [
    'can_view_guests',
    'can_manage_guests',
    'can_send_invitations',
    'can_check_in_guests',
    'can_view_budget',
    'can_manage_budget',
    'can_view_contributions',
    'can_manage_contributions',
    'can_view_vendors',
    'can_manage_vendors',
    'can_approve_bookings',
    'can_edit_event',
    'can_manage_committee',
    'can_view_expenses',
    'can_manage_expenses',
  ];

  TabController? _tabCtrl;
  Map<String, dynamic>? _event;
  Map<String, dynamic>? _permissions;
  bool _loading = true;
  bool _permissionsResolved = false;
  String _permissionSource = 'unresolved';
  DateTime? _lastLoadAt;
  bool _loadInFlight = false;

  Map<String, dynamic> _contributionSummary = {};
  Map<String, dynamic> _budgetSummary = {};
  Map<String, dynamic> _expenseSummary = {};
  int _totalServices = 0;
  int _completedServices = 0;
  String? _currentUserName;
  List<dynamic> _ticketClasses = const [];
  double _sponsorRevenue = 0.0;
  Map<String, dynamic>?
  _overview; // unified backend KPIs (ticket sales, revenue, contribution status, sponsors)
  List<Map<String, dynamic>> _recentActivity = const [];
  String _activityFilter = 'all';

  List<String> _visibleTabs = const ['Overview'];
  static const Set<String> _creatorRoles = {'creator', 'organizer', 'owner'};
  static const Set<String> _committeeRoles = {'committee', 'member'};

  bool _asBool(dynamic value) =>
      value == true || value == 1 || value == '1' || value == 'true';
  num _asNum(dynamic value, [num fallback = 0]) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _asInt(dynamic value, [int fallback = 0]) =>
      _asNum(value, fallback).toInt();
  double _asDouble(dynamic value, [double fallback = 0]) =>
      _asNum(value, fallback).toDouble();

  String? _roleHint(dynamic value) {
    if (value == null) return null;
    final role = value.toString().trim().toLowerCase();
    return role.isEmpty ? null : role;
  }

  String? _ownerIdFrom(Map<String, dynamic>? data) {
    if (data == null) return null;
    final owner =
        data['user_id'] ??
        data['organizer_id'] ??
        data['owner_id'] ??
        data['created_by_id'] ??
        data['created_by'];
    final id = owner?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  void _seedRoleHintsFromNavigation() {
    final knownRoleHint = _roleHint(widget.knownRole);
    final initialRoleHint = _roleHint(
      widget.initialData?['role'] ??
          widget.initialData?['viewer_role'] ??
          widget.initialData?['my_role'],
    );
    final creatorHint =
        _creatorRoles.contains(knownRoleHint) ||
        _creatorRoles.contains(initialRoleHint) ||
        _asBool(widget.initialData?['is_creator']);
    final committeeHint =
        _committeeRoles.contains(knownRoleHint) ||
        _committeeRoles.contains(initialRoleHint);

    if (creatorHint) {
      _permissions = _creatorPermissions();
      _permissionsResolved = true;
      _permissionSource = 'navigation_creator';
      _rebuildTabs();
      return;
    }
    if (committeeHint) {
      _permissions = _normalizePermissions({'role': 'committee'});
      _permissionsResolved = true;
      _permissionSource = 'navigation_committee';
      _rebuildTabs();
    }
  }

  Map<String, dynamic> _creatorPermissions() {
    final map = <String, dynamic>{'is_creator': true, 'role': 'creator'};
    for (final field in _permissionFields) map[field] = true;
    return map;
  }

  Map<String, dynamic> _normalizePermissions(Map<String, dynamic>? raw) {
    final normalized = <String, dynamic>{'is_creator': false, 'role': null};
    for (final field in _permissionFields) normalized[field] = false;
    if (raw == null) return normalized;

    final role = raw['role']?.toString().toLowerCase();
    final isCreator =
        _asBool(raw['is_creator']) ||
        role == 'creator' ||
        role == 'organizer' ||
        role == 'owner';
    if (isCreator) return _creatorPermissions();

    normalized['role'] = raw['role'];
    for (final field in _permissionFields)
      normalized[field] = _asBool(raw[field]);
    return normalized;
  }

  bool get _isCreator => _asBool(_permissions?['is_creator']);
  bool get _hasCommitteePermissions =>
      _permissionFields.any((field) => _asBool(_permissions?[field]));
  bool get _isCommittee {
    final role = _permissions?['role']?.toString().toLowerCase();
    return !_isCreator &&
        ((role != null && role.isNotEmpty && role != 'guest') ||
            _hasCommitteePermissions);
  }

  bool get _hasManagementAccess => _isCreator || _isCommittee;

  List<String> _computeVisibleTabs() {
    if (_permissions == null) return ['overview'];
    if (!_hasManagementAccess) return ['overview'];
    final sellsTickets = _asBool((_event ?? {})['sells_tickets']);
    final isEnded = _isEventEnded();
    return [
      'overview',
      'checklist',
      'budget',
      'expenses',
      'services',
      'committee',
      'contributions',
      'sponsors',
      'guests',
      'rsvp',
      // schedule removed (was unused / dead UI)
      if (sellsTickets) 'tickets',
      if (_isCreator) 'reminders',
      if (_isCreator && !isEnded) 'check_in',
    ];
  }

  bool _isEventEnded() {
    final raw =
        (_event ?? {})['end_date']?.toString() ??
        (_event ?? {})['start_date']?.toString();
    if (raw == null || raw.isEmpty) return false;
    final d = DateTime.tryParse(raw);
    if (d == null) return false;
    return d.isBefore(DateTime.now());
  }

  void _rebuildTabs() {
    final newTabs = _computeVisibleTabs();
    if (_listsEqual(newTabs, _visibleTabs) &&
        _tabCtrl != null &&
        _tabCtrl!.length == newTabs.length)
      return;
    final previousIndex = _tabCtrl?.index ?? 0;
    _visibleTabs = newTabs;
    _tabCtrl?.dispose();
    _tabCtrl = TabController(
      length: _visibleTabs.length,
      vsync: this,
      initialIndex: previousIndex.clamp(0, _visibleTabs.length - 1).toInt(),
    );
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 1, vsync: this);
    // Seed from in-memory cache first (instant UI), then fall back to
    // navigation initialData. A background refresh runs unconditionally.
    final cached = _eventCache[widget.eventId];
    _event = cached ?? widget.initialData;
    if (_event != null) _loading = false;
    _lastLoadAt = _eventCacheAt[widget.eventId];
    _seedRoleHintsFromNavigation();
    _loadEvent();
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadEvent({bool force = false}) async {
    // Guard against accidental/duplicate triggers (e.g. an over-eager
    // pull-to-refresh while scrolling through the Overview tab). When data
    // is already on screen and a fetch ran very recently, skip silently
    // so the user does not see an unwanted reload spinner.
    if (_loadInFlight) return;
    if (!force && _event != null && _lastLoadAt != null) {
      final delta = DateTime.now().difference(_lastLoadAt!);
      if (delta.inSeconds < 8) return;
    }
    _loadInFlight = true;
    // Show loader only if we have nothing on screen yet. With initialData
    // (passed from the events list) we can render the header instantly.
    if (_event == null) setState(() => _loading = true);
    final fallbackErr = {
      'success': false,
      'message': 'Request failed',
      'data': null,
    };

    // ── Phase 1: ONE blocking call - essential event payload (with inline permissions) ──
    Map<String, dynamic> eventRes;
    try {
      eventRes = await EventsService.getEventById(widget.eventId);
    } catch (_) {
      eventRes = Map<String, dynamic>.from(fallbackErr);
    }

    if (!mounted) return;

    final eventData = (eventRes['success'] == true && eventRes['data'] is Map)
        ? (eventRes['data'] as Map).cast<String, dynamic>()
        : null;

    // Inline permissions returned by /user-events/{id}?fields=essential
    final inlinePermissions = (eventData?['permissions'] is Map)
        ? (eventData!['permissions'] as Map).cast<String, dynamic>()
        : null;

    final knownRoleHint = _roleHint(widget.knownRole);
    final initialRoleHint = _roleHint(
      widget.initialData?['role'] ??
          widget.initialData?['viewer_role'] ??
          widget.initialData?['my_role'],
    );
    final eventRoleHint = _roleHint(
      eventData?['role'] ?? eventData?['viewer_role'] ?? eventData?['my_role'],
    );
    final permissionRoleHint = _roleHint(inlinePermissions?['role']);
    // current_user.id is already cached in AuthProvider - no need for AuthApi.me()
    String? currentUserId;
    try {
      final auth = context.read<AuthProvider>();
      currentUserId = auth.user?['id']?.toString();
      _currentUserName = auth.user?['first_name']?.toString();
    } catch (_) {
      /* provider unavailable, fine */
    }
    final eventOwnerId = _ownerIdFrom(eventData);
    final initialOwnerId = _ownerIdFrom(widget.initialData);
    final ownerMatched =
        currentUserId != null &&
        currentUserId.isNotEmpty &&
        (eventOwnerId == currentUserId || initialOwnerId == currentUserId);

    final creatorHint =
        _isCreator ||
        _asBool(widget.initialData?['is_creator']) ||
        _asBool(eventData?['is_creator']) ||
        _asBool(inlinePermissions?['is_creator']) ||
        _creatorRoles.contains(knownRoleHint) ||
        _creatorRoles.contains(initialRoleHint) ||
        _creatorRoles.contains(eventRoleHint) ||
        _creatorRoles.contains(permissionRoleHint) ||
        ownerMatched;

    final committeeHint =
        _committeeRoles.contains(knownRoleHint) ||
        _committeeRoles.contains(initialRoleHint) ||
        _committeeRoles.contains(eventRoleHint) ||
        _committeeRoles.contains(permissionRoleHint);

    if (creatorHint) {
      _permissions = _creatorPermissions();
      _permissionSource = ownerMatched ? 'owner_match' : 'creator_hint';
    } else if (inlinePermissions != null) {
      _permissions = _normalizePermissions(inlinePermissions);
      _permissionSource = 'inline_permissions';
    } else if (committeeHint) {
      _permissions = _normalizePermissions({'role': 'committee'});
      _permissionSource = 'committee_hint';
    } else {
      _permissions = _normalizePermissions(null);
      _permissionSource = 'fallback_guest';
    }
    _permissionsResolved = true;
    _rebuildTabs();

    setState(() {
      _loading = false;
      if (eventData != null) _event = eventData;
    });
    _lastLoadAt = DateTime.now();
    if (eventData != null) {
      _eventCache[widget.eventId] = eventData;
      _eventCacheAt[widget.eventId] = _lastLoadAt!;
    }
    _loadInFlight = false;

    // ── Phase 2: Fire-and-forget overview summaries ──
    // These hydrate the stat cards on the Overview tab WITHOUT blocking the UI.
    // Each setState is independent so the cards fill in as data arrives.
    _hydrateOverviewSummaries();
  }

  Future<void> _hydrateOverviewSummaries() async {
    final eid = widget.eventId;
    final fallbackErr = {
      'success': false,
      'message': 'Request failed',
      'data': null,
    };

    // Run summary calls in parallel but don't block the UI on them.
    final futures = await Future.wait([
      EventsService.getContributions(eid).catchError((_) => fallbackErr),
      EventsService.getBudget(eid).catchError((_) => fallbackErr),
      EventsService.getExpenses(eid).catchError((_) => fallbackErr),
      EventsService.getEventServices(eid).catchError((_) => fallbackErr),
      EventsService.getManagementOverview(eid).catchError((_) => fallbackErr),
    ]);

    if (!mounted) return;

    var contributionSummary =
        (futures[0]['success'] == true && futures[0]['data'] is Map)
        ? (((futures[0]['data'] as Map)['summary'] as Map?)
                  ?.cast<String, dynamic>() ??
              <String, dynamic>{})
        : <String, dynamic>{};
    final budgetSummary =
        (futures[1]['success'] == true && futures[1]['data'] is Map)
        ? (((futures[1]['data'] as Map)['summary'] as Map?)
                  ?.cast<String, dynamic>() ??
              <String, dynamic>{})
        : <String, dynamic>{};
    final expenseSummary =
        (futures[2]['success'] == true && futures[2]['data'] is Map)
        ? (((futures[2]['data'] as Map)['summary'] as Map?)
                  ?.cast<String, dynamic>() ??
              <String, dynamic>{})
        : <String, dynamic>{};
    final servicesData = futures[3]['data'];
    final servicesItems = servicesData is List
        ? servicesData
        : (servicesData is Map
              ? ((servicesData['items'] is List)
                    ? servicesData['items'] as List
                    : ((servicesData['services'] is List)
                          ? servicesData['services'] as List
                          : <dynamic>[]))
              : <dynamic>[]);
    final completedServices = servicesItems.where((s) {
      if (s is! Map) return false;
      return s['service_status'] == 'completed' || s['status'] == 'completed';
    }).length;

    // Unified management overview (authoritative numbers)
    Map<String, dynamic>? overview;
    final ovData = futures[4]['data'];
    if (futures[4]['success'] == true && ovData is Map) {
      overview = ovData.cast<String, dynamic>();
    }

    // Derive ticket classes + sponsor revenue from the overview payload so
    // every value the UI shows comes straight from the backend.
    List<dynamic> ticketClasses = const [];
    double sponsorRevenue = 0.0;
    if (overview != null) {
      final ts = overview['ticket_sales'];
      if (ts is Map && ts['classes'] is List)
        ticketClasses = ts['classes'] as List;
      final rv = overview['revenue_summary'];
      if (rv is Map) sponsorRevenue = _asDouble(rv['sponsors']);
    }

    // Merge authoritative numbers from /management-overview into the
    // contribution summary so Financial Overview + Revenue Summary always
    // reflect real backend totals (paid/pledged counts and amounts).
    if (overview != null) {
      final cs = (overview['contribution_status'] is Map)
          ? (overview['contribution_status'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final rv = (overview['revenue_summary'] is Map)
          ? (overview['revenue_summary'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      contributionSummary = {
        ...contributionSummary,
        'total_paid':
            rv['contributions'] ??
            cs['paid_total'] ??
            contributionSummary['total_paid'] ??
            0,
        'total_pledged':
            cs['pledged_total'] ??
            contributionSummary['total_pledged'] ??
            contributionSummary['total_amount'] ??
            0,
        'paid_count':
            cs['paid_count'] ?? contributionSummary['paid_count'] ?? 0,
        'pledged_count':
            cs['pledged_count'] ?? contributionSummary['pledged_count'] ?? 0,
      };
    }

    // Compute clamped outstanding per-contributor (matches Contributors
    // Report logic) so the Financial Overview never understates the
    // amount owed when some pledgers overpay.
    try {
      final ecRes = await EventsService.getEventContributors(eid, limit: 5000);
      if (ecRes['success'] == true && ecRes['data'] is Map) {
        final list = ((ecRes['data'] as Map)['event_contributors'] as List?) ??
            ((ecRes['data'] as Map)['items'] as List?) ??
            const [];
        double clamped = 0;
        for (final entry in list) {
          if (entry is! Map) continue;
          final ec = entry.cast<String, dynamic>();
          final pledged = _asDouble(ec['pledge_amount']);
          final paid = _asDouble(ec['total_paid'] ?? ec['amount']);
          final fallback = (pledged - paid).clamp(0, double.infinity).toDouble();
          final bal = ec['balance'] != null ? _asDouble(ec['balance']) : fallback;
          clamped += bal < 0 ? 0 : bal;
        }
        contributionSummary['outstanding_clamped'] = clamped;
      }
    } catch (_) {/* best-effort */}

    setState(() {
      _contributionSummary = contributionSummary;
      _budgetSummary = budgetSummary;
      _expenseSummary = expenseSummary;
      _totalServices = servicesItems.length;
      _completedServices = completedServices;
      _ticketClasses = ticketClasses;
      _sponsorRevenue = sponsorRevenue;
      _overview = overview;
    });

    // Recent activity - fetched separately from the unified backend endpoint
    try {
      final res = await EventsService.getRecentActivity(eid, limit: 8);
      if (!mounted) return;
      if (res['success'] == true && res['data'] is Map) {
        final items = ((res['data'] as Map)['items'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();
        setState(() => _recentActivity = items);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body:
            (_loading && _event == null) ||
                (!_permissionsResolved && _event != null)
            ? const NuruSkeletonEventDetail()
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final e = _event ?? {};
    final title = extractStr(e['title'], fallback: 'Event');
    final cover = e['cover_image']?.toString();
    final status = extractStr(e['status'], fallback: 'draft');
    final location = extractStr(e['location']);
    final venue = extractStr(e['venue']);
    final startDate = extractStr(e['start_date']);
    final startTime = extractStr(e['start_time']);
    final eventType = extractStr(e['event_type']);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
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
                      'Manage Event',
                      style: appText(size: 16, weight: FontWeight.w700),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _showEventActions,
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EventCoverImage(
                  event: e,
                  url: cover,
                  width: 72,
                  height: 72,
                  borderRadius: BorderRadius.circular(14),
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
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: appText(
                                size: 15,
                                weight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _statusBadge(status),
                        ],
                      ),
                      if (startDate.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SvgPicture.asset(
                              'assets/icons/calendar-icon.svg',
                              width: 11,
                              height: 11,
                              colorFilter: const ColorFilter.mode(
                                AppColors.textTertiary,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _formatDate(startDate) +
                                    (startTime.isNotEmpty
                                        ? '  •  $startTime'
                                        : ''),
                                style: appText(
                                  size: 11,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (location.isNotEmpty || venue.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            SvgPicture.asset(
                              'assets/icons/location-icon.svg',
                              width: 11,
                              height: 11,
                              colorFilter: const ColorFilter.mode(
                                AppColors.textTertiary,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                [
                                  venue,
                                  location,
                                ].where((s) => s.isNotEmpty).join(', '),
                                style: appText(
                                  size: 11,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
          ),
          _UnderlineTabs(
            labels: _visibleTabs.map((t) => context.trw(t)).toList(),
            controller: _tabCtrl!,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: _visibleTabs
                  .map((tab) => _buildTabContent(tab))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(String tab) {
    switch (tab) {
      case 'overview':
        return _overviewTab();
      case 'checklist':
        return EventChecklistTab(
          eventId: widget.eventId,
          eventTypeId:
              _event?['event_type_id']?.toString() ??
              _event?['event_type']?['id']?.toString(),
        );
      case 'budget':
        return EventBudgetTab(
          eventId: widget.eventId,
          permissions: _permissions,
          eventTitle: extractStr((_event ?? {})['title']),
          eventBudget: (_event?['budget'] is num)
              ? (_event!['budget'] as num).toDouble()
              : double.tryParse((_event?['budget'] ?? '').toString()),
        );
      case 'expenses':
        return EventExpensesTab(
          eventId: widget.eventId,
          permissions: _permissions,
          eventTitle: extractStr((_event ?? {})['title']),
          eventBudget: (_event?['budget'] is num)
              ? (_event!['budget'] as num).toDouble()
              : double.tryParse((_event?['budget'] ?? '').toString()),
        );
      case 'services':
        return EventServicesTab(
          eventId: widget.eventId,
          permissions: _permissions,
          eventTypeId:
              _event?['event_type_id']?.toString() ??
              _event?['event_type']?['id']?.toString(),
          eventCoverImage: _event?['cover_image']?.toString(),
        );
      case 'committee':
        return EventCommitteeTab(
          eventId: widget.eventId,
          permissions: _permissions,
          eventTitle: extractStr((_event ?? {})['title']),
        );
      case 'contributions':
        return EventContributionsTab(
          eventId: widget.eventId,
          permissions: _permissions,
          eventTitle: extractStr((_event ?? {})['title']),
          eventBudget: (_event?['budget'] is num)
              ? (_event!['budget'] as num).toDouble()
              : double.tryParse((_event?['budget'] ?? '').toString()),
          isCreator: _permissions?['is_creator'] == true,
        );
      case 'sponsors':
        return EventSponsorsTab(eventId: widget.eventId, isCreator: _isCreator);
      case 'guests':
        return EventGuestsTab(
          eventId: widget.eventId,
          permissions: _permissions,
        );
      case 'rsvp':
        return EventRsvpTab(eventId: widget.eventId);
      // 'schedule' tab removed
      // 'meetings' moved out of tabs - accessible from Quick Actions sheet
      case 'tickets':
        return EventTicketsTab(
          eventId: widget.eventId,
          permissions: _permissions,
        );
      case 'reminders':
        return EventAutomationsTab(
          eventId: widget.eventId,
          isCreator: _isCreator,
        );
      // workspace tab removed - Group Chat lives on the overview as a CTA card
      // invitation tab moved to the "..." actions sheet (opens full screen)
      case 'check_in':
        return EventCheckinTab(
          eventId: widget.eventId,
          permissions: _permissions,
          eventTitle: extractStr((_event ?? {})['title']),
          eventDate: extractStr((_event ?? {})['start_date']),
          eventLocation: extractStr((_event ?? {})['location']),
          guestCount:
              (_event ?? {})['guest_count'] ??
              (_event ?? {})['total_guests'] ??
              (_event ?? {})['expected_guests'] ??
              0,
          confirmedCount: (_event ?? {})['confirmed_guest_count'] ?? 0,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  bool _hasVenueCoordinates() {
    final vc = (_event ?? {})['venue_coordinates'];
    if (vc is! Map) return false;
    final lat = double.tryParse(vc['latitude']?.toString() ?? '');
    final lng = double.tryParse(vc['longitude']?.toString() ?? '');
    return lat != null && lng != null && lat != 0 && lng != 0;
  }

  Widget _overviewTab() {
    final e = _event ?? {};
    final description = extractStr(e['description']);
    final guestCount =
        e['guest_count'] ?? e['total_guests'] ?? e['expected_guests'] ?? 0;
    final expectedGuests = e['expected_guests'] ?? 0;
    final confirmedGuests = e['confirmed_guest_count'] ?? 0;
    final budget = e['budget'];
    final budgetNum = budget != null
        ? (budget is num
              ? budget.toDouble()
              : double.tryParse(budget.toString()) ?? 0.0)
        : 0.0;

    final totalPledged = _asDouble(
      _contributionSummary['total_pledged'] ??
          _contributionSummary['total_amount'],
    );
    final totalPaid = _asDouble(
      _contributionSummary['total_paid'] ??
          _contributionSummary['total_confirmed'],
    );
    final pledgedCount = _asInt(
      _contributionSummary['pledged_count'] ??
          _contributionSummary['confirmed_count'],
    );
    final paidCount = _asInt(_contributionSummary['paid_count']);
    final unpledged = budgetNum > 0
        ? (budgetNum - totalPledged).clamp(0, double.infinity)
        : 0.0;
    // Prefer the per-contributor clamped outstanding (matches Contributors
    // Report). Falls back to summary subtraction only when unavailable.
    final outstandingClamped = _contributionSummary['outstanding_clamped'];
    final outstanding = outstandingClamped != null
        ? _asDouble(outstandingClamped)
        : (totalPledged - totalPaid).clamp(0, double.infinity).toDouble();
    final collectionRate = totalPledged > 0
        ? ((totalPaid / totalPledged) * 100).round()
        : 0;

    // Days to go
    int daysToGo = 0;
    final sd = extractStr(e['start_date']);
    if (sd.isNotEmpty) {
      try {
        final d = DateTime.parse(sd);
        daysToGo = d.difference(DateTime.now()).inDays;
        if (daysToGo < 0) daysToGo = 0;
      } catch (_) {}
    }

    // ── Authoritative numbers from backend overview (no client recomputation) ──
    final ov = _overview ?? const {};
    final ovKpis = (ov['kpis'] is Map)
        ? (ov['kpis'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final ovTickets = (ov['ticket_sales'] is Map)
        ? (ov['ticket_sales'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final ovRevenue = (ov['revenue_summary'] is Map)
        ? (ov['revenue_summary'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    int ticketsSold = _asInt(ovKpis['tickets_sold'] ?? ovTickets['total_sold']);
    int ticketsCapacity = _asInt(
      ovKpis['tickets_capacity'] ?? ovTickets['total_capacity'],
    );
    final donutSlices = <_DonutSlice>[];
    const sliceColors = [
      Color(0xFFE7A622), // gold
      Color(0xFF111827), // black
      Color(0xFF6B7280), // gray
      Color(0xFFD1D5DB), // light gray
    ];
    for (int i = 0; i < _ticketClasses.length; i++) {
      final tc = _ticketClasses[i];
      if (tc is! Map) continue;
      final sold = _asInt(tc['sold']);
      donutSlices.add(
        _DonutSlice(
          label: extractStr(tc['name'], fallback: 'Tier ${i + 1}'),
          value: sold.toDouble(),
          color: sliceColors[i % sliceColors.length],
        ),
      );
    }
    final isTicketed =
        (ov['is_ticketed'] == true) ||
        _ticketClasses.isNotEmpty ||
        (e['has_tickets'] == true) ||
        (e['sells_tickets'] == true);

    final ticketRevenue = _asDouble(ovRevenue['tickets']);
    final totalRevenue = _asDouble(ovRevenue['total_revenue']);
    daysToGo = _asInt(ovKpis['days_to_go'] ?? daysToGo);
    final contributionsCount = _asInt(
      ovKpis['contributions_count'] ?? pledgedCount,
    );

    return NuruRefreshIndicator(
      onRefresh: () => _loadEvent(force: true),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ─── Section: Financial Overview ───
          Text(
            'Financial Overview',
            style: appText(size: 15, weight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _cashInHandCard(
            totalPaid,
            paidCount,
            outstanding.toDouble(),
            collectionRate,
          ),
          const SizedBox(height: 12),
          _financialCard(
            label: 'Budget',
            value: budgetNum > 0 ? formatTZS(budgetNum) : 'Not set',
            subtitle: 'Total budget allocated',
            iconBg: const Color(0xFFDBEAFE),
            iconColor: const Color(0xFF2563EB),
            icon: Icons.account_balance_wallet_rounded,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _financialCard(
                  label: 'Pledged',
                  value: formatTZS(totalPledged),
                  subtitle: '$pledgedCount contributors',
                  iconBg: const Color(0xFFF3E8FF),
                  iconColor: const Color(0xFF9333EA),
                  icon: Icons.people_alt_rounded,
                ),
              ),
              if (budgetNum > 0) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _financialCard(
                    label: 'Unpledged',
                    value: formatTZS(unpledged.toDouble()),
                    subtitle: 'Budget − pledged',
                    iconBg: const Color(0xFFFEE2E2),
                    iconColor: const Color(0xFFDC2626),
                    icon: Icons.money_off_rounded,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _progressCard()),
              const SizedBox(width: 8),
              Expanded(
                child: _financialCard(
                  label: 'Guests',
                  value: '$guestCount',
                  subtitle: 'of $expectedGuests expected',
                  iconBg: const Color(0xFFDCFCE7),
                  iconColor: const Color(0xFF16A34A),
                  icon: Icons.people_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ─── Section: Event Overview ───
          Text(
            'Event Overview',
            style: appText(size: 15, weight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 78,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                if (isTicketed) ...[
                  _kpiCard(value: '$ticketsSold', label: 'Tickets Sold'),
                  const SizedBox(width: 10),
                ],
                _kpiCard(
                  value:
                      '${getActiveCurrency()} ${_compactMoney(totalRevenue)}',
                  label: 'Total Revenue',
                ),
                const SizedBox(width: 10),
                _kpiCard(value: '$contributionsCount', label: 'Contributions'),
                const SizedBox(width: 10),
                _kpiCard(value: '$daysToGo', label: 'Days to Go'),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ─── Ticket Sales (Donut) + Revenue Summary ───
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _overview == null
                    ? _donutSkeletonCard()
                    : _ticketSalesCard(
                        isTicketed,
                        ticketsSold,
                        ticketsCapacity,
                        donutSlices,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _overview == null
                    ? _revenueSkeletonCard()
                    : _revenueSummaryCard(
                        totalRevenue,
                        ticketRevenue,
                        totalPaid,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (_isCreator) ...[
            _EventGroupCta(eventId: widget.eventId),
            const SizedBox(height: 18),
          ],

          // ─── Quick Actions ───
          Row(
            children: [
              Expanded(
                child: Text(
                  'Quick Actions',
                  style: appText(size: 15, weight: FontWeight.w700),
                ),
              ),
              GestureDetector(
                onTap: _openQuickActionsSheet,
                child: Row(children: [
                  Text('More',
                      style: appText(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.primary,
                      )),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.primary),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _quickAction(
                  'assets/icons/pen-icon.svg',
                  'Edit Event',
                  _editEvent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickAction(
                  'assets/icons/video-icon.svg',
                  'Meetings',
                  _openMeetingsScreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickAction(
                  'assets/icons/ticket-icon.svg',
                  'Tickets',
                  () => _tabCtrl?.animateTo(
                    _visibleTabs
                        .indexOf('services')
                        .clamp(0, _visibleTabs.length - 1),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickAction(
                  'assets/icons/share-upload-icon.svg',
                  'Share Event',
                  () {
                    if (_event != null)
                      ShareEventToFeedSheet.show(context, _event!);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (description.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About',
                    style: appText(
                      size: 11,
                      color: AppColors.textTertiary,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: appText(
                      size: 14,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_hasVenueCoordinates()) ...[
            const SizedBox(height: 16),
            VenueMapPreview(
              latitude: double.parse(
                e['venue_coordinates']['latitude'].toString(),
              ),
              longitude: double.parse(
                e['venue_coordinates']['longitude'].toString(),
              ),
              venueName: extractStr(e['venue']).isNotEmpty
                  ? extractStr(e['venue'])
                  : (extractStr(e['location']).isNotEmpty
                        ? extractStr(e['location'])
                        : null),
              address: extractStr(e['venue_address']).isNotEmpty
                  ? extractStr(e['venue_address'])
                  : null,
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent Activity',
                  style: appText(size: 15, weight: FontWeight.w800),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EventActivityScreen(
                      eventId: widget.eventId,
                      eventTitle: _event?['title']?.toString(),
                      eventCover: _event?['cover_image']?.toString(),
                      eventStatus: _event?['status']?.toString(),
                    ),
                  ));
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View all',
                      style: appText(
                        size: 12,
                        weight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded,
                        size: 18, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _activityFilterPills(),
          const SizedBox(height: 12),
          _recentActivityCard(),
        ],
      ),
    );
  }

  // ─── Mockup widgets ──────────────────────────────────────────

  Widget _kpiCard({required String value, required String label}) {
    return Container(
      width: 132,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: appText(
                size: 16,
                weight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: appText(
              size: 11,
              color: AppColors.textTertiary,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ticketSalesCard(
    bool isTicketed,
    int sold,
    int capacity,
    List<_DonutSlice> slices,
  ) {
    // If non-ticketed, build a contribution donut from contribution status counts
    final List<_DonutSlice> donutData;
    final int centerNumber;
    final String centerLabel;
    if (isTicketed && slices.any((s) => s.value > 0)) {
      donutData = slices;
      centerNumber = sold;
      centerLabel = 'Total Sold';
    } else {
      // Contribution-based donut - backend overview is the source of truth
      final cs = (_overview != null && _overview!['contribution_status'] is Map)
          ? (_overview!['contribution_status'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final fullyPaid = _asInt(cs['fully_paid_count'] ?? cs['paid_count'] ?? _contributionSummary['paid_count']);
      final inProgress = _asInt(cs['in_progress_count']);
      final outstanding = _asInt(
        cs['outstanding_count'] ??
            ((_asInt(cs['pledged_count']) - fullyPaid - inProgress).clamp(0, 1 << 30)),
      );
      donutData = [
        _DonutSlice(
          label: 'Paid',
          value: fullyPaid.toDouble(),
          color: const Color(0xFF16A34A),
        ),
        _DonutSlice(
          label: 'In Progress',
          value: inProgress.toDouble(),
          color: const Color(0xFFE7A622),
        ),
        _DonutSlice(
          label: 'Outstanding',
          value: outstanding.toDouble(),
          color: const Color(0xFFDC2626),
        ),
      ];
      centerNumber = fullyPaid + inProgress + outstanding;
      centerLabel = 'Contributions';
    }
    final hasData = donutData.fold<double>(0, (a, b) => a + b.value) > 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isTicketed ? 'Ticket Sales' : 'Contribution Status',
            style: appText(size: 13, weight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 130,
              height: 130,
              child: hasData
                  ? CustomPaint(
                      painter: _DonutPainter(donutData),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$centerNumber',
                              style: appText(size: 22, weight: FontWeight.w800),
                            ),
                            Text(
                              centerLabel,
                              style: appText(
                                size: 10,
                                color: AppColors.textTertiary,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        'No data yet',
                        style: appText(size: 11, color: AppColors.textTertiary),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          for (final s in donutData)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.label,
                      style: appText(size: 11, weight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${s.value.toInt()}',
                    style: appText(size: 11, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _revenueSummaryCard(
    double totalRevenue,
    double ticketRev,
    double contribRev,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Revenue Summary',
            style: appText(size: 13, weight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total Revenue',
                  style: appText(
                    size: 11,
                    color: AppColors.textTertiary,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${getActiveCurrency()} ${_compactMoney(totalRevenue)}',
              style: appText(size: 18, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.borderLight),
          const SizedBox(height: 10),
          _revRow(
            'Tickets',
            '${getActiveCurrency()} ${_compactMoney(ticketRev)}',
          ),
          Container(
            height: 1,
            color: AppColors.borderLight,
            margin: const EdgeInsets.symmetric(vertical: 8),
          ),
          _revRow(
            'Contributions',
            '${getActiveCurrency()} ${_compactMoney(contribRev)}',
          ),
          Container(
            height: 1,
            color: AppColors.borderLight,
            margin: const EdgeInsets.symmetric(vertical: 8),
          ),
          _revRow(
            'Sponsors',
            '${getActiveCurrency()} ${_compactMoney(_sponsorRevenue)}',
          ),
        ],
      ),
    );
  }

  Widget _revRow(String label, String value) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: appText(
            size: 11,
            color: AppColors.textSecondary,
            weight: FontWeight.w600,
          ),
        ),
      ),
      Text(value, style: appText(size: 11, weight: FontWeight.w700)),
    ],
  );

  Widget _shimmerBox({double? w, double h = 12, double r = 6}) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: const Color(0xFFEEF1F4),
      borderRadius: BorderRadius.circular(r),
    ),
  );

  Widget _donutSkeletonCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(w: 100, h: 12),
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFEEF1F4), width: 16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEEF1F4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _shimmerBox(h: 10)),
                  const SizedBox(width: 8),
                  _shimmerBox(w: 24, h: 10),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _revenueSkeletonCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(w: 110, h: 12),
          const SizedBox(height: 14),
          _shimmerBox(w: 80, h: 10),
          const SizedBox(height: 8),
          _shimmerBox(w: 130, h: 18),
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.borderLight),
          const SizedBox(height: 12),
          for (int i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(child: _shimmerBox(w: 60, h: 10)),
                  _shimmerBox(w: 70, h: 10),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickAction(String svgAsset, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 86,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SvgPicture.asset(
                  svgAsset,
                  width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(
                      AppColors.textPrimary, BlendMode.srcIn),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appText(
                size: 10,
                weight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMeetingsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            leading: IconButton(
              icon: SvgPicture.asset('assets/icons/arrow-left-icon.svg',
                  width: 22, height: 22,
                  colorFilter: const ColorFilter.mode(
                      AppColors.textPrimary, BlendMode.srcIn)),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text('Event Meetings',
                style: appText(size: 16, weight: FontWeight.w700)),
            centerTitle: true,
            actions: [
              IconButton(
                icon: SvgPicture.asset('assets/icons/calendar-icon.svg',
                    width: 22, height: 22,
                    colorFilter: const ColorFilter.mode(
                        AppColors.textPrimary, BlendMode.srcIn)),
                onPressed: () => MeetingsCalendarSheet.show(
                  context,
                  eventId: widget.eventId,
                  eventName: extractStr((_event ?? {})['title']),
                  isCreator: _isCreator,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: EventMeetingsTab(
            eventId: widget.eventId,
            isCreator: _isCreator,
            permissions: _permissions,
            eventName: extractStr((_event ?? {})['title']),
            eventCover: (_event ?? {})['cover_image']?.toString(),
            eventDate: extractStr((_event ?? {})['start_date']),
            eventLocation: extractStr((_event ?? {})['location']).isNotEmpty
                ? extractStr((_event ?? {})['location'])
                : extractStr((_event ?? {})['venue']),
          ),
        ),
      ),
    );
  }

  void _openQuickActionsSheet() {
    final items = <_QaItem>[
      _QaItem('assets/icons/video-icon.svg', 'Meetings', _openMeetingsScreen),
      _QaItem('assets/icons/contributors-icon.svg', 'Committee',
          () => _jumpToTab('committee')),
      _QaItem('assets/icons/heart-icon.svg', 'Sponsors',
          () => _jumpToTab('sponsors')),
      _QaItem('assets/icons/user-icon.svg', 'Guests',
          () => _jumpToTab('guests')),
      _QaItem('assets/icons/package-icon.svg', 'Services',
          () => _jumpToTab('services')),
      _QaItem('assets/icons/pen-icon.svg', 'Edit Event', _editEvent),
      _QaItem('assets/icons/chat-icon.svg', 'Voice RSVP Calls', () {
        Navigator.of(context).pop();
        final id = (_event ?? {})['id']?.toString();
        if (id == null || id.isEmpty) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SmartRsvpCallsScreen(
            eventId: id,
            eventTitle: extractStr((_event ?? {})['title']),
          ),
        ));
      }),
      _QaItem('assets/icons/share-upload-icon.svg', 'Share Event', () {
        if (_event != null) ShareEventToFeedSheet.show(context, _event!);
      }),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38, height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E2E8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Quick Actions',
                    style: appText(size: 17, weight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Jump to anywhere in this event',
                    style: appText(
                      size: 12,
                      color: AppColors.textTertiary,
                      weight: FontWeight.w500,
                    )),
                const SizedBox(height: 18),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 4,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                  children: items.map((it) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.pop(ctx);
                        it.onTap();
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: SvgPicture.asset(
                                it.icon,
                                width: 22, height: 22,
                                colorFilter: const ColorFilter.mode(
                                    AppColors.textPrimary, BlendMode.srcIn),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            it.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: appText(
                              size: 11,
                              weight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _jumpToTab(String key) {
    final idx = _visibleTabs.indexOf(key);
    if (idx >= 0) {
      _tabCtrl?.animateTo(idx.clamp(0, _visibleTabs.length - 1));
    }
  }

  List<Map<String, dynamic>> get _filteredRecentActivity {
    if (_activityFilter == 'all') return _recentActivity;
    return _recentActivity
        .where((a) => (a['type'] ?? '').toString() == _activityFilter)
        .toList();
  }

  Widget _activityFilterPills() {
    final tabs = const [
      ('all', 'All', Icons.apps_rounded, null),
      ('rsvp', 'RSVP', null, 'double-check'),
      ('ticket', 'Tickets', null, 'ticket'),
      ('expense', 'Expenses', null, 'report'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = tabs[i];
          final active = _activityFilter == t.$1;
          return GestureDetector(
            onTap: () => setState(() => _activityFilter = t.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? AppColors.primary.withOpacity(0.10) : Colors.white,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.borderLight,
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (t.$3 != null)
                    Icon(t.$3, size: 14,
                        color: active ? AppColors.primary : AppColors.textSecondary)
                  else
                    AppIcon(t.$4!, size: 13,
                        color: active ? AppColors.primary : AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(t.$2,
                      style: appText(size: 12, weight: FontWeight.w700,
                          color: active ? AppColors.primary : AppColors.textPrimary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _recentActivityCard() {
    final items = _filteredRecentActivity;
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: AppIcon('thunder', size: 19, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _recentActivity.isEmpty
                  ? 'No recent activity yet'
                  : 'No activity in this category',
              style: appText(size: 13, color: AppColors.textPrimary, weight: FontWeight.w700),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final a in items.take(5)) ...[
          _activityRow(a),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _activityRow(Map<String, dynamic> a) {
    final amount = a['amount'];
    final type = (a['type'] ?? '').toString();
    final subtype = (a['subtype'] ?? '').toString();
    String icon = 'thunder';
    Color tint = AppColors.primary;
    Color tintBg = AppColors.primary.withOpacity(0.10);
    String? badgeText;
    Color? badgeTint;
    Color? badgeBg;
    if (type == 'rsvp') {
      icon = 'double-check';
      tint = const Color(0xFF16A34A);
      tintBg = const Color(0xFFE7F8EE);
      badgeText = 'RSVP';
      badgeTint = const Color(0xFF16A34A);
      badgeBg = const Color(0xFFE7F8EE);
    } else if (type == 'ticket') {
      icon = 'ticket';
      tint = const Color(0xFFD97706);
      tintBg = const Color(0xFFFFF7E6);
    } else if (type == 'expense') {
      icon = 'report';
      tint = const Color(0xFFDC2626);
      tintBg = const Color(0xFFFEF2F2);
    } else if (type == 'contribution') {
      icon = subtype == 'payment' ? 'money' : 'donation';
      tint = const Color(0xFF7C3AED);
      tintBg = const Color(0xFFF3EBFF);
    }
    final time = _shortTime(a['time']?.toString());
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: tintBg, borderRadius: BorderRadius.circular(12)),
            child: Center(child: AppIcon(icon, size: 18, color: tint)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a['title']?.toString() ?? 'Activity',
                  style: appText(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  (a['subtitle']?.toString().isNotEmpty == true)
                      ? a['subtitle'].toString()
                      : _relativeTime(a['time']?.toString()),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: appText(size: 11.5, color: AppColors.textTertiary, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (amount != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: tintBg, borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    '${getActiveCurrency()} ${_compactMoney((amount is num) ? amount.toDouble() : double.tryParse(amount.toString()) ?? 0)}',
                    style: appText(size: 11, weight: FontWeight.w800, color: tint),
                  ),
                )
              else if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(99)),
                  child: Text(badgeText,
                      style: appText(size: 11, weight: FontWeight.w800, color: badgeTint!)),
                ),
              const SizedBox(height: 6),
              Text(time,
                  style: appText(size: 10.5, color: AppColors.textTertiary, weight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  String _shortTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    var s = iso.trim();
    final hasTz = s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasTz) s = '${s}Z';
    final dt = DateTime.tryParse(s)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (d == today) return '$hh:$mm';
    final diff = today.difference(d).inDays;
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff}d ago';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month-1]} ${dt.day} • $hh:$mm';
  }


  String _relativeTime(String? iso) {
    if (iso == null || iso.isEmpty) return 'Just now';
    // Backend timestamps are stored in UTC but often serialized without a
    // timezone suffix. DateTime.tryParse on a naive string treats it as
    // local, which makes "x minutes ago" wildly wrong (e.g. shows "3h ago"
    // for events that just happened in EAT). Force-tag as UTC when missing.
    var s = iso.trim();
    final hasTz = s.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasTz) s = '${s}Z';
    final dt = DateTime.tryParse(s);
    if (dt == null) return 'Just now';
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.day}/${local.month}/${local.year}';
  }

  String _compactMoney(double n) {
    if (n >= 1000000)
      return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return n.toStringAsFixed(0);
  }

  Widget _cashInHandCard(
    double totalPaid,
    int paidCount,
    double outstanding,
    int collectionRate,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.trw('cash_in_hand'),
                      style: appText(size: 11, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatTZS(totalPaid),
                      style: appText(
                        size: 22,
                        weight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 22,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _cashStat(
                    '$paidCount',
                    context.trw('paid_contributors'),
                  ),
                ),
                Container(width: 1, height: 36, color: AppColors.border),
                Expanded(
                  child: _cashStat(
                    '${getActiveCurrency()} ${_compactMoney(outstanding)}',
                    context.trw('outstanding'),
                  ),
                ),
                Container(width: 1, height: 36, color: AppColors.border),
                Expanded(
                  child: _cashStat(
                    '$collectionRate%',
                    context.trw('collection_rate'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.trw('event_progress'),
            style: appText(size: 11, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 6),
          Text(
            '$_completedServices/$_totalServices ${context.trw('services')}',
            style: appText(size: 15, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _totalServices > 0
                  ? _completedServices / _totalServices
                  : 0,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) =>
      Text(title, style: appText(size: 15, weight: FontWeight.w700));

  Widget _financialCard({
    required String label,
    required String value,
    required String subtitle,
    required Color iconBg,
    required Color iconColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: appText(size: 11, color: AppColors.textTertiary),
                ),
                const SizedBox(height: 4),
                Text(value, style: appText(size: 15, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: appText(size: 10, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
        ],
      ),
    );
  }

  Widget _cashStat(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: appText(size: 14, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appText(size: 9.5, color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final isPublished = status == 'published' || status == 'confirmed';
    final isCompleted = status == 'completed';
    final isCancelled = status == 'cancelled';
    // Draft / default status uses amber instead of gray so badges stay vibrant.
    Color c = const Color(0xFFB45309);
    Color bg = const Color(0xFFFEF3C7);
    if (isPublished) {
      c = const Color(0xFF15803D);
      bg = const Color(0xFFDCFCE7);
    } else if (isCompleted) {
      c = AppColors.blue;
      bg = const Color(0xFFDBEAFE);
    } else if (isCancelled) {
      c = AppColors.error;
      bg = const Color(0xFFFEE2E2);
    }
    final label = status.isEmpty
        ? ''
        : status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPublished)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(Icons.check_circle, size: 11, color: c),
            ),
          Text(
            label,
            style: appText(size: 10, weight: FontWeight.w700, color: c),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String svgAsset, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            svgAsset,
            width: 14,
            height: 14,
            colorFilter: const ColorFilter.mode(
              AppColors.textSecondary,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: appText(
                size: 12,
                color: AppColors.textSecondary,
                weight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showEventActions() {
    final isCreator = _permissions?['is_creator'] == true;
    final canEdit = _permissions?['can_edit_event'] == true || isCreator;
    final status = extractStr(_event?['status'], fallback: 'draft');
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            if (canEdit)
              _svgActionTile(
                'assets/icons/pen-icon.svg',
                context.trw('edit_event_btn'),
                () {
                  Navigator.pop(ctx);
                  _editEvent();
                },
              ),
            _svgActionTile(
              'assets/icons/video-icon.svg',
              'Meetings',
              () {
                Navigator.pop(ctx);
                _openMeetingsScreen();
              },
            ),
            if (_permissions?['can_send_invitations'] == true || isCreator)
              _svgActionTile(
                'assets/icons/send-icon.svg',
                'Create Invitation',
                () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EventInvitationScreen(
                        eventId: widget.eventId,
                        eventTypeKey: (_event?['event_type'] is Map
                                ? (_event!['event_type']['key'] ??
                                    _event!['event_type']['name'])
                                : null)
                            ?.toString()
                            .toLowerCase(),
                        themeColorHex: _event?['theme_color']?.toString(),
                        eventTitle: extractStr(_event?['title']),
                      ),
                    ),
                  );
                },
              ),
            if (isCreator)
              _svgActionTile(
                'assets/icons/photos-icon.svg',
                context.trw('event_photo_libraries'),
                () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MyPhotoLibrariesScreen(
                        eventId: widget.eventId,
                        title: context.trw('event_photo_libraries'),
                      ),
                    ),
                  );
                },
              ),
            if (isCreator && status == 'draft')
              _svgActionTile(
                'assets/icons/thunder-icon.svg',
                context.trw('publish_event_btn'),
                () {
                  Navigator.pop(ctx);
                  _changeStatus('published');
                },
              ),
            if (isCreator && status == 'published')
              _svgActionTile(
                'assets/icons/close-circle-icon.svg',
                context.trw('cancel_event'),
                () {
                  Navigator.pop(ctx);
                  _changeStatus('cancelled');
                },
              ),
            _svgActionTile(
              'assets/icons/print-icon.svg',
              context.trw('event_summary_report'),
              () {
                Navigator.pop(ctx);
                _generateFullReport();
              },
            ),
            _svgActionTile(
              'assets/icons/thunder-icon.svg',
              context.trw('ai_budget_assistant'),
              () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BudgetAssistantScreen(
                      eventType: _event?['event_type_id']?.toString(),
                      eventTypeName: extractStr(_event?['event_type']),
                      eventTitle: extractStr(_event?['title']),
                      location: extractStr(_event?['location']),
                      expectedGuests: (_event?['expected_guests'] ?? '')
                          .toString(),
                      budget: (_event?['budget'] ?? '').toString(),
                      firstName: _currentUserName,
                      onSaveBudget: (total) {
                        final amount = double.tryParse(total);
                        if (amount != null) {
                          EventsService.updateEvent(
                            widget.eventId,
                            budget: amount,
                          ).then((_) => _loadEvent());
                          AppSnackbar.success(
                            context,
                            'Budget updated to ${getActiveCurrency()} $total',
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            ),
            if (isCreator)
              _svgActionTile(
                'assets/icons/delete-icon.svg',
                context.trw('delete_event'),
                () {
                  Navigator.pop(ctx);
                  _confirmDelete();
                },
                isDestructive: true,
              ),
            _svgActionTile(
                'assets/icons/share-upload-icon.svg',
                context.trw('share_event'), () {
              Navigator.pop(ctx);
              if (_event != null) {
                ShareEventToFeedSheet.show(context, _event!);
              }
            }),
            const SizedBox(height: 16),
          ],
        ),
        ),
      ),
    );
  }

  Widget _svgActionTile(
    String svgAsset,
    String label,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    final color =
        isDestructive ? AppColors.error : AppColors.textSecondary;
    return ListTile(
      leading: SvgPicture.asset(
        svgAsset,
        width: 22,
        height: 22,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
      title: Text(
        label,
        style: appText(
          size: 15,
          weight: FontWeight.w600,
          color: isDestructive ? AppColors.error : AppColors.textPrimary,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _actionTile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? AppColors.error : AppColors.textSecondary,
        size: 22,
      ),
      title: Text(
        label,
        style: appText(
          size: 15,
          weight: FontWeight.w600,
          color: isDestructive ? AppColors.error : AppColors.textPrimary,
        ),
      ),
      onTap: onTap,
    );
  }

  void _editEvent() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateEventScreen(editEvent: _event)),
    ).then((result) {
      if (result == true) _loadEvent();
    });
  }

  void _generateFullReport() {
    _showReportFormatPicker(context.trw('event_summary_report'), (
      format,
    ) async {
      AppSnackbar.success(context, context.trw('generating_report'));
      final res = await ReportGenerator.generateEventReport(
        widget.eventId,
        format: format,
        eventData: _event,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        if (format == 'pdf' && res['bytes'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportPreviewScreen(
                title: context.trw('event_summary_report'),
                pdfBytes: res['bytes'] as Uint8List,
                filePath: res['path'] as String?,
              ),
            ),
          );
        } else if (res['path'] != null) {
          AppSnackbar.success(context, context.trw('report_saved'));
        }
      } else {
        AppSnackbar.error(context, res['message'] ?? 'Failed');
      }
    });
  }

  void _showReportFormatPicker(
    String title,
    Future<void> Function(String format) onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                title,
                style: appText(size: 16, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(child: AppIcon('pdf-file-type', size: 22)),
              ),
              title: Text(
                context.trw('pdf_report'),
                style: appText(size: 14, weight: FontWeight.w600),
              ),
              subtitle: Text(
                context.trw('preview_and_share'),
                style: appText(size: 12, color: AppColors.textTertiary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onSelect('pdf');
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(child: AppIcon('excel-document', size: 22)),
              ),
              title: Text(
                context.trw('excel_report'),
                style: appText(size: 14, weight: FontWeight.w600),
              ),
              subtitle: Text(
                context.trw('open_in_spreadsheet'),
                style: appText(size: 12, color: AppColors.textTertiary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onSelect('xlsx');
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _changeStatus(String newStatus) async {
    final res = await EventsService.updateEventStatus(
      widget.eventId,
      newStatus,
    );
    if (mounted) {
      if (res['success'] == true) {
        AppSnackbar.success(
          context,
          'Event ${newStatus == 'published' ? 'published' : 'cancelled'}',
        );
        _loadEvent();
      } else {
        AppSnackbar.error(context, res['message'] ?? 'Failed');
      }
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          context.trw('delete_event_confirm'),
          style: appText(size: 18, weight: FontWeight.w700),
        ),
        content: Text(
          context.trw('action_cannot_undone'),
          style: appText(size: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              context.trw('cancel'),
              style: appText(
                size: 14,
                weight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await EventsService.deleteEvent(widget.eventId);
              if (mounted) {
                if (res['success'] == true) {
                  AppSnackbar.success(context, context.trw('event_deleted'));
                  Navigator.pop(context);
                } else {
                  AppSnackbar.error(context, res['message'] ?? 'Failed');
                }
              }
            },
            child: Text(
              context.trw('delete'),
              style: appText(
                size: 14,
                weight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final PreferredSizeWidget tabBar;
  _TabBarDelegate(this.tabBar);
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(color: AppColors.surface, child: tabBar);
  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}

/// YouTube-style pill tabs (black selected, gray unselected). Horizontally
/// scrollable so all event-management tabs fit on small screens.
class _UnderlineTabs extends StatelessWidget implements PreferredSizeWidget {
  final List<String> labels;
  final TabController controller;
  const _UnderlineTabs({required this.labels, required this.controller});
  @override
  Size get preferredSize => const Size.fromHeight(58);
  @override
  Widget build(BuildContext context) {
    return NuruPillTabBar(controller: controller, labels: labels);
  }
}


/// Premium CTA card on the Event Overview tab. Shows "Open Group Chat" when
/// a group already exists, otherwise "Create Group Chat".
class _EventGroupCta extends StatefulWidget {
  final String eventId;
  const _EventGroupCta({required this.eventId});
  @override
  State<_EventGroupCta> createState() => _EventGroupCtaState();
}

class _EventGroupCtaState extends State<_EventGroupCta> {
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _group;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final res = await EventGroupsService.getForEvent(widget.eventId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _group = (res['success'] == true && res['data'] is Map<String, dynamic>)
          ? res['data'] as Map<String, dynamic>
          : null;
    });
  }

  Future<void> _createOrOpen() async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await EventGroupsService.openOrCreateForEvent(widget.eventId);
    if (!mounted) return;
    setState(() => _busy = false);
    final id = res['data']?['id']?.toString();
    if (id != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EventGroupWorkspaceScreen(groupId: id),
        ),
      ).then((_) => _refresh());
    } else {
      AppSnackbar.error(
        context,
        res['message']?.toString() ?? 'Could not create group',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final hasGroup = _group != null;
    final memberCount = ((_group?['member_count'] as num?) ?? 0).toInt();
    final unread = ((_group?['unread_count'] as num?) ?? 0).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.12),
            AppColors.primary.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            child: SvgPicture.asset(
              'assets/icons/group-chat-icon.svg',
              width: 22,
              height: 22,
              colorFilter: const ColorFilter.mode(
                AppColors.primary,
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasGroup ? 'Group Chat' : 'Create the Group Chat',
                  style: appText(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasGroup
                      ? '$memberCount members${unread > 0 ? " - $unread unread" : ""}'
                      : 'Private chat for your organizer team, committee and contributors · with a live contribution scoreboard.',
                  style: appText(
                    size: 11,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _busy ? null : _createOrOpen,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              elevation: 0,
            ),
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    hasGroup ? 'Open' : 'Create',
                    style: appText(
                      size: 12,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Donut chart helpers ─────────────────────────────────────────
class _DonutSlice {
  final String label;
  final double value;
  final Color color;
  const _DonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSlice> slices;
  _DonutPainter(this.slices);
  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0) return;
    final stroke = 16.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    // Background ring
    final bg = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 6.2831853, false, bg);
    double start = -1.5707963; // -PI/2
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = (s.value / total) * 6.2831853;
      final p = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}

class _QaItem {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _QaItem(this.icon, this.label, this.onTap);
}
