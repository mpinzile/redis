import '../../core/utils/money_format.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/nuru_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import 'widgets/venue_map_preview.dart';
import 'directions_screen.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/events_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/event_cover_image.dart';
import '../photos/my_photo_libraries_screen.dart';
import 'invitation_qr_screen.dart';
import '../tickets/select_tickets_screen.dart';
import '../../core/services/reminder_service.dart';
import '../../core/theme/text_styles.dart';

/// Public event view for invited guests - mirrors web EventView.
/// Shows event details, RSVP actions, schedule, dress code, and photo libraries.
/// Does NOT show management tabs (budget, committee, expenses, etc.)
class EventPublicViewScreen extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic>? initialData;

  const EventPublicViewScreen({
    super.key,
    required this.eventId,
    this.initialData,
  });

  @override
  State<EventPublicViewScreen> createState() => _EventPublicViewScreenState();
}

class _EventPublicViewScreenState extends State<EventPublicViewScreen> {
  Map<String, dynamic>? _event;
  bool _loading = true;
  String _rsvpStatus = 'pending';
  bool _isInvited = false;
  String? _respondingTo;
  String? _invitationCode;
  Map<String, dynamic>? _reminder;
  bool _savingReminder = false;
  bool _saved = false;
  bool _aboutExpanded = false;
  bool _highlightTickets = false;

  void _pulseTicketsCta() {
    setState(() => _highlightTickets = true);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightTickets = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _event = widget.initialData;
    _loadEvent();
    _loadInvitation();
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    final reminder = await ReminderService.getReminder(widget.eventId);
    if (mounted) setState(() => _reminder = reminder);
  }

  String _reminderSubtitle() {
    if (_reminder == null) return 'Get reminded before the event';
    final label = _reminder?['reminder_label']?.toString() ?? 'Reminder set';
    final at = DateTime.tryParse(_reminder?['reminder_time']?.toString() ?? '');
    if (at == null) return label;
    return '$label • ${ReminderService.formatReminderDate(at)}';
  }

  Future<void> _saveReminder(
    DateTime eventStart,
    String label,
    DateTime time,
  ) async {
    if (_savingReminder) return;
    setState(() => _savingReminder = true);
    await ReminderService.setReminder(
      eventId: widget.eventId,
      eventTitle: extractStr(_event?['title'], fallback: 'Event'),
      reminderTime: time,
      reminderLabel: label,
      eventStart: eventStart,
    );
    final reminder = await ReminderService.getReminder(widget.eventId);
    if (mounted) {
      setState(() {
        _savingReminder = false;
        _reminder = reminder;
      });
      AppSnackbar.success(context, 'Reminder updated');
    }
  }

  Future<void> _deleteReminder() async {
    if (_savingReminder) return;
    setState(() => _savingReminder = true);
    await ReminderService.removeReminder(widget.eventId);
    if (mounted) {
      setState(() {
        _savingReminder = false;
        _reminder = null;
      });
      AppSnackbar.success(context, 'Reminder removed');
    }
  }

  void _showReminderSheet() {
    final e = _event;
    if (e == null) return;

    final startDate = extractStr(e['start_date']);
    final startTime = extractStr(e['start_time']);
    if (startDate.isEmpty) {
      AppSnackbar.error(context, 'Event date is missing');
      return;
    }

    final dateTimeString = startTime.isNotEmpty
        ? '${startDate}T$startTime:00'
        : startDate;
    final eventStart =
        DateTime.tryParse(dateTimeString) ?? DateTime.tryParse(startDate);

    if (eventStart == null || eventStart.isBefore(DateTime.now())) {
      AppSnackbar.error(context, 'This event has already started or ended');
      return;
    }

    final options = ReminderService.getReminderOptions(eventStart);
    if (options.isEmpty) {
      AppSnackbar.error(context, 'Event is too close to set a reminder');
      return;
    }

    final activeLabel = _reminder?['reminder_label']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.78,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.14),
                      AppColors.primary.withOpacity(0.04),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/icons/bell-icon.svg',
                          width: 20,
                          height: 20,
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
                            'Event reminder',
                            style: appText(size: 15, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            extractStr(e['title'], fallback: 'Event'),
                            style: appText(
                              size: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final opt = options[i];
                    final label = opt['label'] as String;
                    final time = opt['time'] as DateTime;
                    final selected = label == activeLabel;
                    return GestureDetector(
                      onTap: _savingReminder
                          ? null
                          : () async {
                              await _saveReminder(eventStart, label, time);
                              if (mounted) Navigator.pop(ctx);
                            },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withOpacity(0.08)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? AppColors.primary.withOpacity(0.45)
                                : AppColors.borderLight,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.primary.withOpacity(0.14)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary.withOpacity(0.3)
                                      : AppColors.borderLight,
                                ),
                              ),
                              child: Center(
                                child: SvgPicture.asset(
                                  'assets/icons/clock-icon.svg',
                                  width: 18,
                                  height: 18,
                                  colorFilter: ColorFilter.mode(
                                    selected
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
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
                                    label,
                                    style: appText(
                                      size: 14,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    ReminderService.formatReminderDate(time),
                                    style: appText(
                                      size: 11,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              SvgPicture.asset(
                                'assets/icons/verified-icon.svg',
                                width: 16,
                                height: 16,
                                colorFilter: const ColorFilter.mode(
                                  AppColors.primary,
                                  BlendMode.srcIn,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Row(
                  children: [
                    if (_reminder != null)
                      Expanded(
                        child: GestureDetector(
                          onTap: _savingReminder
                              ? null
                              : () async {
                                  await _deleteReminder();
                                  if (mounted) Navigator.pop(ctx);
                                },
                          child: Container(
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.error.withOpacity(0.25),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'Remove reminder',
                                style: appText(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_reminder != null) const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Center(
                            child: Text(
                              'Close',
                              style: appText(
                                size: 13,
                                weight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadEvent() async {
    final res = await EventsService.getEventById(widget.eventId);
    if (mounted) {
      setState(() {
        _loading = false;
        if (res['success'] == true) {
          _event = res['data'];
          _saved = _event?['is_saved'] == true || _event?['has_saved'] == true;
        }
      });
    }
  }

  void _shareEvent() {
    final title = extractStr(_event?['title'], fallback: 'Event');
    final location = extractStr(_event?['location']);
    Share.share([title, location].where((s) => s.isNotEmpty).join('\n'), sharePositionOrigin: sharePositionOrigin(context));
  }

  void _toggleSaved() {
    setState(() => _saved = !_saved);
    AppSnackbar.success(
      context,
      _saved ? 'Event saved' : 'Event removed from saved',
    );
  }

  Future<void> _loadInvitation() async {
    final res = await EventsService.getInvitedEvents(limit: 100);
    if (mounted && res['success'] == true) {
      final events = res['data'];
      List<dynamic> eventList = [];
      if (events is List) {
        eventList = events;
      } else if (events is Map) {
        eventList = events['events'] ?? events['data'] ?? events['items'] ?? [];
      }
      for (final e in eventList) {
        if (e['id']?.toString() == widget.eventId) {
          final inv = e['invitation'] ?? e;
          setState(() {
            _isInvited = true;
            _rsvpStatus = inv['rsvp_status']?.toString() ?? 'pending';
            _invitationCode =
                inv['invitation_code']?.toString() ??
                e['invitation_code']?.toString();
          });
          break;
        }
      }
    }
  }

  Future<void> _handleRSVP(String status) async {
    setState(() => _respondingTo = status);
    final res = await EventsService.respondToInvitation(widget.eventId, status);
    if (mounted) {
      setState(() => _respondingTo = null);
      if (res['success'] == true) {
        setState(() => _rsvpStatus = status);
        AppSnackbar.success(
          context,
          status == 'confirmed'
              ? 'You have accepted the invitation!'
              : 'You have declined the invitation.',
        );
      } else {
        AppSnackbar.error(context, res['message'] ?? 'Failed to update RSVP');
      }
    }
  }

  bool _hasVenueCoordinates(Map<String, dynamic> event) {
    final vc = event['venue_coordinates'];
    if (vc is! Map) return false;
    final lat = double.tryParse(vc['latitude']?.toString() ?? '');
    final lng = double.tryParse(vc['longitude']?.toString() ?? '');
    return lat != null && lng != null && lat != 0 && lng != 0;
  }

  void _openLocationInMaps(
    String location,
    String venue,
    Map<String, dynamic> event,
  ) {
    final vc = event['venue_coordinates'];
    double? lat;
    double? lng;
    if (vc is Map) {
      lat = double.tryParse(vc['latitude']?.toString() ?? '');
      lng = double.tryParse(vc['longitude']?.toString() ?? '');
    }

    if (lat != null && lng != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DirectionsScreen(
            destinationLat: lat!,
            destinationLng: lng!,
            venueName: venue.isNotEmpty
                ? venue
                : (location.isNotEmpty ? location : null),
            address: event['venue_address']?.toString(),
          ),
        ),
      );
      return;
    }

    AppSnackbar.error(
      context,
      'Directions are only available when the event venue has map coordinates.',
    );
  }

  String _formatDate(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      // weekday short names defined inline below

      final months = [
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
      const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${wd[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          surfaceTintColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
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
          title: Text(
            'Event Details',
            style: appText(size: 18, weight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          centerTitle: false,
          actions: [
            IconButton(
              onPressed: _shareEvent,
              icon: SvgPicture.asset(
                'assets/icons/share-icon.svg',
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  AppColors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),
            IconButton(
              onPressed: _toggleSaved,
              icon: SvgPicture.asset(
                _saved
                    ? 'assets/icons/bookmark-filled-icon.svg'
                    : 'assets/icons/bookmark-icon.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  _saved ? AppColors.primary : AppColors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: _loading && _event == null
            ? const NuruSkeletonEventDetail()
            : _event == null
            ? _emptyState()
            : Stack(children: [
                NuruRefresh(
                  onRefresh: () async {
                    await _loadEvent();
                  },
                  child: _buildContent(),
                ),
                _buildStickyTicketBar(),
              ]),
      ),
    );
  }

  Widget _buildStickyTicketBar() {
    final e = _event;
    if (e == null) return const SizedBox.shrink();
    final hasTickets =
        (e['has_tickets'] == true) ||
        (e['sells_tickets'] == true) ||
        (e['ticket_class_count'] is num &&
            (e['ticket_class_count'] as num) > 0) ||
        (e['min_price'] != null);
    if (!hasTickets) return const SizedBox.shrink();
    final minPrice = e['min_price'];
    final currency = (e['currency']?.toString().isNotEmpty ?? false)
        ? e['currency'].toString()
        : getActiveCurrency();
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.borderLight)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (minPrice != null)
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'From ',
                            style: appText(
                              size: 13,
                              color: AppColors.textTertiary,
                              weight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: '$currency ${_fmtPrice(minPrice)}',
                            style: appText(
                              size: 16,
                              weight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_loading)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'From ',
                          style: appText(
                            size: 13,
                            color: AppColors.textTertiary,
                            weight: FontWeight.w500,
                          ),
                        ),
                        Container(
                          width: 110,
                          height: 16,
                          decoration: BoxDecoration(
                            color: AppColors.borderLight.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Get Tickets',
                      style: appText(
                        size: 16,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    'Tickets are selling fast!',
                    style: appText(size: 12, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedScale(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                scale: _highlightTickets ? 1.06 : 1.0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _highlightTickets
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.55),
                              blurRadius: 22,
                              spreadRadius: 2,
                            ),
                          ]
                        : const [],
                  ),
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SelectTicketsScreen(
                              eventId: widget.eventId,
                              eventName: extractStr(e['title'], fallback: 'Event'),
                              coverImage: e['cover_image']?.toString(),
                              startDate: e['start_date']?.toString(),
                              startTime: e['start_time']?.toString(),
                              location: e['location']?.toString(),
                              eventType: extractStr(e['event_type']),
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textPrimary,
                        disabledForegroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        textStyle: appText(
                          size: 14,
                          weight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/ticket-icon.svg',
                            width: 18,
                            height: 18,
                            colorFilter: ColorFilter.mode(
                              AppColors.textPrimary,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Get Tickets',
                            style: appText(
                              size: 14,
                              weight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtPrice(dynamic v) {
    final n = v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
    return n
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  Widget _emptyState() {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon('event-calendar-check', size: 44, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              'Event not found',
              style: appText(size: 16, weight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'This event may have been removed',
              style: appText(size: 13, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Go Back',
                  style: appText(
                    size: 13,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final e = _event!;
    final title = extractStr(e['title'], fallback: 'Event');
    final cover = e['cover_image']?.toString();
    final location = extractStr(e['location']);
    final venue = extractStr(e['venue']);
    final startDate = extractStr(e['start_date']);
    final startTime = extractStr(e['start_time']);
    final description = extractStr(e['description']);
    final dressCode = extractStr(e['dress_code']);
    final specialInstructions = extractStr(e['special_instructions']);
    final guestOfHonor = extractStr(e['guest_of_honor']);
    final rawExtras = e['extra_details'];
    final extraDetails = <Map<String, String>>[
      if (rawExtras is List)
        for (final it in rawExtras)
          if (it is Map &&
              (it['label'] ?? '').toString().trim().isNotEmpty &&
              (it['details'] ?? it['description'] ?? '').toString().trim().isNotEmpty)
            {
              'label': (it['label']).toString().trim(),
              'details': (it['details'] ?? it['description']).toString().trim(),
            },
      // Backwards compatibility - surface legacy fields only when the new
      // ``extra_details`` payload has nothing of its own.
      if ((rawExtras is! List || (rawExtras).isEmpty) && dressCode.isNotEmpty)
        {'label': 'Dress code', 'details': dressCode},
      if ((rawExtras is! List || (rawExtras).isEmpty) && specialInstructions.isNotEmpty)
        {'label': 'Special instructions', 'details': specialInstructions},
    ];
    final eventType = extractStr(e['event_type']);
    final schedule = e['schedule'] is List ? e['schedule'] as List : [];
    final hasReminder = _reminder != null;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // ─── Big rounded hero image ───
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                    bottom: Radius.circular(18),
                  ),
                  child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: EventCoverImage(event: e, fit: BoxFit.cover),
                  ),
                ),
                Positioned(right: 14, bottom: 14, child: _attendanceBadge(e)),
              ],
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + type
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: appText(
                          size: 22,
                          weight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    if (eventType.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          eventType,
                          style: appText(
                            size: 11,
                            weight: FontWeight.w600,
                            color: const Color(0xFF7C3AED),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Quick row: date • time • location with vertical separators (mockup style)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (startDate.isNotEmpty)
                        _metaInline(
                          'assets/icons/calendar-icon.svg',
                          _formatDate(startDate),
                        ),
                      if (startTime.isNotEmpty) ...[
                        _metaDivider(),
                        _metaInline('assets/icons/clock-icon.svg', startTime),
                      ],
                      if (location.isNotEmpty || venue.isNotEmpty) ...[
                        _metaDivider(),
                        Expanded(
                          child: _metaInline(
                            'assets/icons/location-icon.svg',
                            [
                              venue,
                              location,
                            ].where((s) => s.isNotEmpty).join('\n'),
                            multiline: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _friendsGoingCard(e),
                const SizedBox(height: 14),

                // ─── RSVP Card (only when user is invited) ───
                if (_isInvited) ...[
                  _rsvpCard(),
                  const SizedBox(height: 14),
                ],

                // ─── QR Code button (existing) ───
                if (_rsvpStatus == 'confirmed' &&
                    _invitationCode != null &&
                    _invitationCode!.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              InvitationQRScreen(eventId: widget.eventId),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const AppIcon(
                              'card',
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your Invitation QR Code',
                                  style: appText(
                                    size: 14,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Show this at check-in',
                                  style: appText(
                                    size: 11,
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
                              AppColors.textHint,
                              BlendMode.srcIn,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ─── Reminder Button ───
                GestureDetector(
                  onTap: _showReminderSheet,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: hasReminder
                          ? LinearGradient(
                              colors: [
                                AppColors.primary.withOpacity(0.12),
                                AppColors.primary.withOpacity(0.04),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: hasReminder ? null : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasReminder
                            ? AppColors.primary.withOpacity(0.24)
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: hasReminder
                                  ? AppColors.primary.withOpacity(0.2)
                                  : AppColors.borderLight,
                            ),
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/icons/bell-icon.svg',
                              width: 21,
                              height: 21,
                              colorFilter: ColorFilter.mode(
                                hasReminder
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hasReminder
                                    ? 'Reminder Active'
                                    : 'Set Reminder',
                                style: appText(
                                  size: 14,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _reminderSubtitle(),
                                style: appText(
                                  size: 11,
                                  color: AppColors.textTertiary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        SvgPicture.asset(
                          'assets/icons/chevron-right-icon.svg',
                          width: 18,
                          height: 18,
                          colorFilter: const ColorFilter.mode(
                            AppColors.textHint,
                            BlendMode.srcIn,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ─── Event Details Cards ───
                Row(
                  children: [
                    if (startDate.isNotEmpty)
                      Expanded(
                        child: _detailCard(
                          'assets/icons/calendar-icon.svg',
                          'Date',
                          _formatDate(startDate),
                        ),
                      ),
                    if (startDate.isNotEmpty && startTime.isNotEmpty)
                      const SizedBox(width: 10),
                    if (startTime.isNotEmpty)
                      Expanded(
                        child: _detailCard(
                          'assets/icons/clock-icon.svg',
                          'Time',
                          startTime,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                if (location.isNotEmpty || venue.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _openLocationInMaps(location, venue, e),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: SvgPicture.asset(
                                'assets/icons/location-icon.svg',
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
                                  'Location',
                                  style: appText(
                                    size: 11,
                                    color: AppColors.textTertiary,
                                    weight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    venue,
                                    location,
                                  ].where((s) => s.isNotEmpty).join(', '),
                                  style: appText(
                                    size: 13,
                                    weight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A73E8),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppIcon(
                                  'location',
                                  color: Colors.white,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Directions',
                                  style: appText(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                if (_hasVenueCoordinates(e)) ...[
                  const SizedBox(height: 10),
                  VenueMapPreview(
                    latitude: double.parse(
                      e['venue_coordinates']['latitude'].toString(),
                    ),
                    longitude: double.parse(
                      e['venue_coordinates']['longitude'].toString(),
                    ),
                    venueName: venue.isNotEmpty
                        ? venue
                        : (location.isNotEmpty ? location : null),
                    address: e['venue_address']?.toString(),
                  ),
                ],
                const SizedBox(height: 10),

                // ─── Description ───
                if (description.isNotEmpty) ...[
                  _aboutCard(description),
                  const SizedBox(height: 14),
                ],

                ..._expectCard(e),

                _galleryStrip(e, cover),
                const SizedBox(height: 14),

                // ─── Guest of honor ───
                if (guestOfHonor.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Icon(Icons.workspace_premium_rounded, size: 22, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          'Guest of honor',
                          style: appText(size: 11, weight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 0.3),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          guestOfHonor,
                          style: appText(size: 15.5, weight: FontWeight.w700),
                        ),
                      ])),
                    ]),
                  ),

                // ─── Extra details (user-defined label/details rows) ───
                if (extraDetails.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < extraDetails.length; i++) ...[
                          if (i > 0)
                            Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              color: AppColors.borderLight,
                            ),
                          Text(
                            extraDetails[i]['label']!,
                            style: appText(
                              size: 11,
                              weight: FontWeight.w700,
                              color: AppColors.textTertiary,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            extraDetails[i]['details']!,
                            style: appText(size: 14.5, weight: FontWeight.w500, height: 1.4),
                          ),
                        ],
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                if (extraDetails.isNotEmpty)
                  const SizedBox(height: 14),

                // ─── Schedule ───
                if (schedule.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
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
                          'Event Schedule',
                          style: appText(size: 15, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        ...schedule.map((item) {
                          final sTime = item['start_time']?.toString() ?? '';
                          final sTitle = item['title']?.toString() ?? '';
                          final sDesc = item['description']?.toString() ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    sTime.length > 5
                                        ? sTime.substring(0, 5)
                                        : sTime,
                                    style: appText(
                                      size: 13,
                                      weight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 2,
                                  height: 36,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sTitle,
                                        style: appText(
                                          size: 13,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                      if (sDesc.isNotEmpty)
                                        Text(
                                          sDesc,
                                          style: appText(
                                            size: 12,
                                            color: AppColors.textTertiary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metaChip(String icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SvgPicture.asset(
            icon,
            width: 13,
            height: 13,
            colorFilter: const ColorFilter.mode(
              AppColors.textSecondary,
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: appText(
            size: 12,
            weight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _metaInline(String icon, String label, {bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            icon,
            width: 14,
            height: 14,
            colorFilter: const ColorFilter.mode(
              AppColors.textSecondary,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: multiline ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: appText(
                size: 12.5,
                weight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaDivider() {
    return Container(width: 1, height: 22, color: AppColors.borderLight);
  }

  Widget _attendanceBadge(Map<String, dynamic> e) {
    final n =
        e['going_count'] ??
        e['attendee_count'] ??
        e['confirmed_guest_count'] ??
        e['guest_count'] ??
        0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/icons/user-icon.svg',
            width: 14,
            height: 14,
            colorFilter: const ColorFilter.mode(
              AppColors.textPrimary,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 5),
          Text('$n', style: appText(size: 12, weight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _friendsGoingCard(Map<String, dynamic> e) {
    final count =
        (e['going_count'] ??
                e['friends_going_count'] ??
                e['confirmed_guest_count'] ??
                e['guest_count'] ??
                0)
            as num;
    if (count <= 0) return const SizedBox.shrink();
    final rawAvatars = (e['going_avatars'] is List)
        ? (e['going_avatars'] as List)
        : const [];
    final fallbackColors = [
      AppColors.primarySoft,
      AppColors.infoSoft,
      AppColors.successSoft,
      AppColors.warningSoft,
    ];
    final shown = rawAvatars.take(4).toList();
    final slots = shown.isNotEmpty
        ? shown.length
        : (count >= 4 ? 4 : count.toInt());
    final avatars = <Widget>[];
    for (int i = 0; i < slots; i++) {
      final a = i < shown.length ? (shown[i] as Map?) ?? {} : {};
      final url = (a['avatar'] ?? '').toString();
      final name = (a['name'] ?? '').toString();
      final initial = name.isNotEmpty
          ? name.trim()[0].toUpperCase()
          : String.fromCharCode(65 + i);
      avatars.add(
        Positioned(
          left: i * 18.0,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fallbackColors[i % fallbackColors.length],
              border: Border.all(color: Colors.white, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: url.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: url,
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                    imageBuilder: (_, provider) => Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(image: provider, fit: BoxFit.cover),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Center(
                      child: Text(
                        initial,
                        style: appText(
                          size: 11,
                          weight: FontWeight.w800,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      initial,
                      style: appText(
                        size: 11,
                        weight: FontWeight.w800,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
          ),
        ),
      );
    }
    final stackWidth = slots == 0 ? 0.0 : (slots - 1) * 18.0 + 34.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: stackWidth,
            height: 34,
            child: Stack(children: avatars),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Builder(builder: (_) {
              final extra = (count.toInt() - shown.length).clamp(0, 1 << 30);
              final label = extra > 0
                  ? '+$extra more attending'
                  : (count.toInt() == 1 ? '1 person attending' : '${count.toInt()} people attending');
              return Text(
                label,
                style: appText(
                  size: 13,
                  weight: FontWeight.w700,
                  color: const Color(0xFF78350F),
                ),
              );
            }),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pulseTicketsCta,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text(
                'Join them',
                style: appText(
                  size: 12,
                  weight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutCard(String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About This Event',
            style: appText(size: 15, weight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            maxLines: _aboutExpanded ? null : 3,
            overflow: _aboutExpanded
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: appText(
              size: 14,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _aboutExpanded = !_aboutExpanded),
            child: Text(
              _aboutExpanded ? 'Show Less' : 'Read More',
              style: appText(
                size: 13,
                weight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the organiser-defined "What to Expect" block. Returns an
  /// empty list when neither items nor notes are provided so the section
  /// is hidden entirely (no hardcoded fallback content).
  List<Widget> _expectCard(Map<String, dynamic> e) {
    final rawItems = e['what_to_expect'];
    final notes = (e['what_to_expect_notes'] ?? '').toString().trim();
    final items = <Map<String, String>>[];
    if (rawItems is List) {
      for (final it in rawItems) {
        if (it is Map) {
          final label = (it['label'] ?? it['title'] ?? '').toString().trim();
          if (label.isEmpty) continue;
          items.add({
            'icon': (it['icon'] ?? 'sparkle').toString(),
            'label': label,
            'description': (it['description'] ?? '').toString().trim(),
          });
        }
      }
    }
    if (items.isEmpty && notes.isEmpty) return const [];

    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What to Expect',
                style: appText(size: 15, weight: FontWeight.w800)),
            if (items.isNotEmpty) const SizedBox(height: 12),
            ...items.map(
              (it) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/icons/${it['icon']}-icon.svg',
                        width: 16, height: 16,
                        colorFilter: const ColorFilter.mode(
                          AppColors.primary, BlendMode.srcIn),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it['label']!,
                          style: appText(size: 13, weight: FontWeight.w700)),
                      if ((it['description'] ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(it['description']!,
                            style: appText(size: 12, color: AppColors.textTertiary)),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
            if (notes.isNotEmpty) ...[
              if (items.isNotEmpty) const SizedBox(height: 6),
              Text(notes,
                  style: appText(size: 13, color: AppColors.textSecondary, height: 1.5)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
    ];
  }

  Widget _galleryStrip(Map<String, dynamic> e, String? cover) {
    final raw = e['gallery'] ?? e['images'] ?? e['photos'] ?? [];
    final urls = <String>[];
    if (cover != null && cover.isNotEmpty) urls.add(cover);
    if (raw is List) {
      for (final item in raw) {
        final url = item is Map
            ? (item['url'] ?? item['image_url'] ?? item['file_url'])?.toString()
            : item?.toString();
        if (url != null && url.isNotEmpty && !urls.contains(url)) urls.add(url);
      }
    }
    if (urls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Event Gallery',
                style: appText(size: 15, weight: FontWeight.w800),
              ),
            ),
            GestureDetector(
              onTap: () => _openGalleryViewer(urls, 0),
              child: Text(
                'View All',
                style: appText(
                  size: 12,
                  weight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.take(8).length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _openGalleryViewer(urls, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 118,
                  height: 92,
                  child: CachedNetworkImage(
                    imageUrl: urls[i],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openGalleryViewer(List<String> urls, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _GalleryViewerScreen(urls: urls, initialIndex: initialIndex),
      ),
    );
  }

  Widget _rsvpCard() {
    final statusColor = _rsvpStatus == 'confirmed'
        ? AppColors.success
        : _rsvpStatus == 'declined'
        ? AppColors.error
        : const Color(0xFFE6A817);

    final statusBg = _rsvpStatus == 'confirmed'
        ? AppColors.success.withOpacity(0.08)
        : _rsvpStatus == 'declined'
        ? AppColors.error.withOpacity(0.08)
        : const Color(0xFFE6A817).withOpacity(0.08);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.25)),
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
                      'Your RSVP Status',
                      style: appText(
                        size: 11,
                        weight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            _rsvpStatus == 'confirmed'
                                ? 'double-check'
                                : _rsvpStatus == 'declined'
                                ? 'close-circle'
                                : 'clock',
                            size: 12,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _rsvpStatus[0].toUpperCase() +
                                _rsvpStatus.substring(1),
                            style: appText(
                              size: 12,
                              weight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Action buttons
          if (_rsvpStatus == 'pending')
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    'Accept',
                    AppColors.primary,
                    Colors.white,
                    'double-check',
                    () => _handleRSVP('confirmed'),
                    loadingFor: 'confirmed',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionButton(
                    'Decline',
                    Colors.white,
                    AppColors.error,
                    'close-circle',
                    () => _handleRSVP('declined'),
                    outlined: true,
                    loadingFor: 'declined',
                  ),
                ),
              ],
            ),
          if (_rsvpStatus == 'confirmed')
            _actionButton(
              'Cancel RSVP',
              Colors.white,
              AppColors.error,
              'close-circle',
              () => _handleRSVP('declined'),
              outlined: true,
              loadingFor: 'declined',
            ),
          if (_rsvpStatus == 'declined')
            _actionButton(
              'Accept Instead',
              AppColors.primary,
              Colors.white,
              'double-check',
              () => _handleRSVP('confirmed'),
              loadingFor: 'confirmed',
            ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String label,
    Color bg,
    Color fg,
    String iconName,
    VoidCallback onTap, {
    bool outlined = false,
    String? loadingFor,
  }) {
    final isBusy = _respondingTo != null;
    final isThisLoading = loadingFor != null && _respondingTo == loadingFor;
    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : bg,
          borderRadius: BorderRadius.circular(12),
          border: outlined
              ? Border.all(color: fg.withOpacity(0.3), width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isThisLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: outlined ? fg : Colors.white,
                ),
              )
            else ...[
              AppIcon(iconName, size: 14, color: outlined ? fg : Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: appText(
                  size: 13,
                  weight: FontWeight.w700,
                  color: outlined ? fg : Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailCard(String svgIcon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: SvgPicture.asset(
                svgIcon,
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
                  label,
                  style: appText(
                    size: 11,
                    color: AppColors.textTertiary,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: appText(size: 13, weight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailCardIcon(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: appText(
                    size: 11,
                    color: AppColors.textTertiary,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: appText(size: 13, weight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: appText(size: 15, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            content,
            style: appText(
              size: 14,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryViewerScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _GalleryViewerScreen({required this.urls, required this.initialIndex});

  @override
  State<_GalleryViewerScreen> createState() => _GalleryViewerScreenState();
}

class _GalleryViewerScreenState extends State<_GalleryViewerScreen> {
  late PageController _ctrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.urls.length}',
          style: appText(size: 14, weight: FontWeight.w700, color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
