// DARK_THEME_DRAWER
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/event_image.dart';
import '../../events/event_detail_screen.dart';
import '../../events/event_public_view_screen.dart';
import '../../services/public_service_screen.dart';
import '../../services/find_services_screen.dart';
import '../../tickets/browse_tickets_screen.dart';
import '../../tickets/my_tickets_screen.dart';
import '../../event_groups/my_groups_screen.dart';
import '../../meetings/meeting_room_screen.dart';
import '../../../core/services/social_service.dart';
import '../../../core/services/event_groups_service.dart';
import '../../event_groups/event_group_workspace_screen.dart';
import '../../../core/services/meetings_service.dart';
import '../../public_profile/public_profile_screen.dart';
import '../../../core/l10n/l10n_helper.dart';
import '../../../core/utils/avatar_url.dart';
import '../home_tab_controller.dart';

class HomeRightDrawer extends StatelessWidget {
  final List<dynamic> myEvents;
  final List<dynamic> invitedEvents;
  final List<dynamic> committeeEvents;
  final List<dynamic> upcomingTickets;
  final List<dynamic> ticketedEvents;
  final List<dynamic> myServices;
  final List<dynamic> followSuggestions;
  final VoidCallback? onFollowChanged;
  final String? userName;
  final String? userAvatar;
  final bool isVerified;

  const HomeRightDrawer({
    super.key,
    required this.myEvents,
    required this.invitedEvents,
    required this.committeeEvents,
    required this.upcomingTickets,
    required this.ticketedEvents,
    required this.myServices,
    required this.followSuggestions,
    this.onFollowChanged,
    this.userName,
    this.userAvatar,
    this.isVerified = false,
  });

  List<Map<String, dynamic>> _mergeUpcomingEvents() {
    final now = DateTime.now();
    final items = <Map<String, dynamic>>[];
    for (final e in myEvents) {
      if (_isFuture(e, now)) items.add({'event': e, 'role': 'creator'});
    }
    for (final e in invitedEvents) {
      if (_isFuture(e, now)) items.add({'event': e, 'role': 'guest'});
    }
    for (final e in committeeEvents) {
      if (_isFuture(e, now)) items.add({'event': e, 'role': 'committee'});
    }
    items.sort((a, b) {
      final da = a['event']['start_date']?.toString() ?? '';
      final db = b['event']['start_date']?.toString() ?? '';
      return da.compareTo(db);
    });
    return items;
  }

  bool _isFuture(dynamic e, DateTime now) {
    final d = e['start_date']?.toString() ?? '';
    if (d.isEmpty) return true;
    try {
      return DateTime.parse(d).isAfter(now);
    } catch (_) {
      return false;
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;

    if (h >= 5 && h < 12) return 'Good Morning';
    if (h >= 12 && h < 17) return 'Good Afternoon';
    if (h >= 17 && h < 21) return 'Good Evening';

    return 'Good Night';
  }

  @override
  Widget build(BuildContext context) {
    final upcomingEvents = _mergeUpcomingEvents();
    final drawerWidth = MediaQuery.of(context).size.width < 430
        ? MediaQuery.of(context).size.width * 0.82
        : 360.0;
    return Drawer(
      width: drawerWidth,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Column(
        children: [
          // ── Profile Header ──
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 18,
              left: 22,
              right: 18,
              bottom: 22,
            ),
            decoration: const BoxDecoration(color: AppColors.surface),
            child: Row(
              children: [
                // Avatar with golden ring + verified badge (only for verified users)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary,
                          width: 1.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: (userAvatar != null && userAvatar!.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: userAvatar!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: AppColors.primary.withOpacity(0.15),
                                  child: const Icon(
                                    Icons.person,
                                    color: AppColors.primary,
                                    size: 28,
                                  ),
                                ),
                              )
                            : Container(
                                color: AppColors.primary.withOpacity(0.15),
                                child: const Icon(
                                  Icons.person,
                                  color: AppColors.primary,
                                  size: 28,
                                ),
                              ),
                      ),
                    ),
                    if (isVerified)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primarySoft,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.verified_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_greeting()},',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              (userName?.isNotEmpty ?? false)
                                  ? userName!
                                  : 'Welcome',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.sora(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Quick Actions Grid ──
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
            child: Row(
              children: [
                _QuickTile(
                  iconAsset: 'assets/icons/calendar-icon.svg',
                  label: context.trw('events'),
                  onTap: () {
                    Navigator.pop(context);
                    HomeTabController.openEvents();
                  },
                ),
                const SizedBox(width: 10),
                _QuickTile(
                  iconAsset: 'assets/icons/users-icon.svg',
                  label: 'Groups',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MyGroupsScreen()),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _QuickTile(
                  iconAsset: 'assets/icons/ticket-icon.svg',
                  label: context.trw('tickets'),
                  onTap: () {
                    Navigator.pop(context);
                    HomeTabController.openTickets();
                  },
                ),
                const SizedBox(width: 10),
                _QuickTile(
                  iconAsset: 'assets/icons/bag-icon.svg',
                  label: 'Providers',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FindServicesScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // ── Content ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
              children: [
                _SectionHeaderAction(
                  title: context.trw('upcoming_events'),
                  action: 'View all',
                  onAction: () {
                    Navigator.pop(context);
                    HomeTabController.openEvents();
                  },
                ),
                const SizedBox(height: 12),
                ...upcomingEvents
                    .take(2)
                    .map((item) => _UpcomingEventCard(item: item)),
                const SizedBox(height: 16),
                const _MomentsPromoCard(),
                const SizedBox(height: 28),

                // My Meetings
                const _MyMeetingsSection(),

                // My Groups (Event Workspaces)
                const _MyGroupsSection(),

                // My Tickets
                if (upcomingTickets.isNotEmpty) ...[
                  _SectionHeaderAction(
                    icon: 'assets/icons/ticket-icon.svg',
                    title: context.trw('my_tickets'),
                    action: context.trw('view_all'),
                    onAction: () {
                      Navigator.pop(context);
                      HomeTabController.openTickets();
                    },
                  ),
                  const SizedBox(height: 12),
                  ...upcomingTickets.take(3).map((t) => _TicketCard(ticket: t)),
                  const SizedBox(height: 28),
                ],

                _SectionHeaderAction(
                  icon: 'assets/icons/ticket-icon.svg',
                  title: context.trw('events_with_tickets'),
                  action: context.trw('view_all'),
                  onAction: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BrowseTicketsScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                ...ticketedEvents
                    .take(5)
                    .map((e) => _TicketedEventCard(event: e)),
                const SizedBox(height: 28),

                _SectionHeaderAction(
                  title: context.trw('service_providers'),
                  action: 'See all',
                  onAction: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FindServicesScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (myServices.isNotEmpty) _ServicesGrid(services: myServices),
                const SizedBox(height: 28),

                _SectionHeaderAction(
                  title: context.trw('suggested_for_you'),
                  action: 'See all',
                  onAction: () {},
                ),
                const SizedBox(height: 12),
                if (followSuggestions.isNotEmpty)
                  _SuggestedUsersRow(
                    users: followSuggestions,
                    onFollowChanged: onFollowChanged,
                  ),

                // Empty state
                if (upcomingEvents.isEmpty &&
                    followSuggestions.isEmpty &&
                    upcomingTickets.isEmpty &&
                    myServices.isEmpty)
                  _EmptyState(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Section Headers
// ═══════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String? icon;
  final IconData? iconData;
  final String title;
  final int? count;

  const _SectionHeader({
    this.icon,
    this.iconData,
    required this.title,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: icon != null
              ? Center(
                  child: SvgPicture.asset(
                    icon!,
                    width: 16,
                    height: 16,
                    colorFilter: const ColorFilter.mode(
                      AppColors.primary,
                      BlendMode.srcIn,
                    ),
                  ),
                )
              : Icon(iconData, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.sora(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              letterSpacing: 0,
              height: 1.2,
            ),
          ),
        ),
        if (count != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionHeaderAction extends StatelessWidget {
  final String? icon;
  final IconData? iconData;
  final String title;
  final String action;
  final VoidCallback onAction;

  const _SectionHeaderAction({
    this.icon,
    this.iconData,
    required this.title,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null || iconData != null) ...[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: icon != null
                  ? SvgPicture.asset(
                      icon!,
                      width: 15,
                      height: 15,
                      colorFilter: const ColorFilter.mode(
                        AppColors.primary,
                        BlendMode.srcIn,
                      ),
                    )
                  : Icon(iconData, size: 15, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.sora(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFE0A82E),
              height: 1.2,
            ),
          ),
        ),
        GestureDetector(
          onTap: onAction,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFE0A82E),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0xFFE0A82E),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// Event Card
// ═══════════════════════════════════════════════

class _UpcomingEventCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _UpcomingEventCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final e = item['event'] as Map<String, dynamic>;
    final role = item['role'] as String;
    final title = e['title'] ?? e['name'] ?? 'Untitled';
    final date = e['start_date'] ?? '';
    final cover = e['cover_image'] as String?;
    final location = e['location']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => role == 'guest'
                  ? EventPublicViewScreen(
                      eventId: e['id'].toString(),
                      initialData: e,
                    )
                  : EventDetailScreen(
                      eventId: e['id'].toString(),
                      initialData: e,
                      knownRole: role,
                    ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _Thumbnail(
                imageUrl: resolveEventImageUrl(e),
                fallbackSvg: 'assets/icons/calendar-icon.svg',
                size: 72,
                radius: 15,
                useEventFallback: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toString(),
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SvgPicture.asset(
                          'assets/icons/clock-icon.svg',
                          width: 11,
                          height: 11,
                          colorFilter: const ColorFilter.mode(
                            AppColors.textTertiary,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDateShort(date.toString()),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 2),
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
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                                height: 1.2,
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
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: role == 'creator'
                          ? AppColors.primary.withOpacity(0.16)
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      role,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: role == 'creator'
                            ? AppColors.primary
                            : const Color(0xFFD7C2FF),
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.14),
                      border: Border.all(color: AppColors.surface),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Ticket Cards
// ═══════════════════════════════════════════════

class _TicketCard extends StatelessWidget {
  final dynamic ticket;
  const _TicketCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final t = ticket is Map<String, dynamic> ? ticket : <String, dynamic>{};
    final event = t['event'] is Map<String, dynamic>
        ? t['event'] as Map<String, dynamic>
        : t;
    final eventName =
        event['name']?.toString() ?? t['event_name']?.toString() ?? 'Event';
    final coverImage = event['cover_image']?.toString() ?? '';
    final startDate = event['start_date']?.toString() ?? '';
    final ticketCode = t['ticket_code']?.toString() ?? '';
    final status = t['status']?.toString() ?? 'pending';
    final quantity = t['quantity'] ?? 1;
    DateTime? d;
    try {
      d = DateTime.parse(startDate);
    } catch (_) {}
    final isToday =
        d != null &&
        d.year == DateTime.now().year &&
        d.month == DateTime.now().month &&
        d.day == DateTime.now().day;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          final eventId = event['id']?.toString();
          if (eventId != null && eventId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EventPublicViewScreen(eventId: eventId),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  _Thumbnail(
                    imageUrl: resolveEventImageUrl(event),
                    fallbackSvg: 'assets/icons/ticket-icon.svg',
                    size: 44,
                    radius: 10,
                    useEventFallback: true,
                  ),
                  if (isToday)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eventName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isToday
                          ? context.trw('today')
                          : (d != null
                                ? _formatDateShort(startDate)
                                : 'Date TBD'),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (ticketCode.isNotEmpty) _CodeBadge(code: ticketCode),
                        _StatusBadge(status: status),
                        if (quantity > 1)
                          Text(
                            '×$quantity',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              color: AppColors.textTertiary,
                            ),
                          ),
                      ],
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
}

class _TicketedEventCard extends StatelessWidget {
  final dynamic event;
  const _TicketedEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final e = event is Map<String, dynamic> ? event : <String, dynamic>{};
    final coverImage = e['cover_image']?.toString() ?? '';
    final eventName =
        e['name']?.toString() ?? e['title']?.toString() ?? 'Event';
    final startDate = e['start_date']?.toString() ?? '';
    final minPrice = e['min_price'];
    final soldOut = (e['total_available'] ?? 0) <= 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          final eventId = e['id']?.toString();
          if (eventId != null && eventId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EventPublicViewScreen(eventId: eventId),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _Thumbnail(
                imageUrl: resolveEventImageUrl(e),
                fallbackSvg: 'assets/icons/ticket-icon.svg',
                size: 48,
                radius: 12,
                useEventFallback: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eventName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (startDate.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatDateShort(startDate),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: AppColors.textTertiary,
                          height: 1.2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (minPrice != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.borderLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${context.trw('from')} ${_formatCompactMoney(minPrice)}',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        if (soldOut) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              context.trw('sold_out'),
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ],
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
}

// ═══════════════════════════════════════════════
// Services Grid
// ═══════════════════════════════════════════════

class _ServicesGrid extends StatelessWidget {
  final List<dynamic> services;
  const _ServicesGrid({required this.services});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: services.take(10).length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final service = services[index];
          final s = service is Map<String, dynamic>
              ? service
              : <String, dynamic>{};
          final title =
              s['title']?.toString() ?? s['name']?.toString() ?? 'Service';
          final initials = title
              .split(' ')
              .map((w) => w.isNotEmpty ? w[0] : '')
              .join('')
              .toUpperCase();
          final imgUrl = _extractServiceImage(s);
          return GestureDetector(
            onTap: () {
              final svcId = s['id']?.toString();
              Navigator.pop(context);
              if (svcId != null && svcId.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PublicServiceScreen(serviceId: svcId),
                  ),
                );
              }
            },
            child: Container(
              width: 116,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.borderLight,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      height: 82,
                      color: AppColors.borderLight,
                      child: imgUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imgUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Center(
                                child: Text(
                                  initials,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                initials,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

class _MomentsPromoCard extends StatelessWidget {
  const _MomentsPromoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.surface,
            AppColors.surfaceVariant.withOpacity(0.36),
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Everything you need\n'),
                  const TextSpan(text: 'to create '),
                  TextSpan(
                    text: 'unforgettable\n',
                    style: GoogleFonts.inter(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: 'moments.'),
                ],
              ),
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C55C7).withOpacity(0.35),
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 16,
                  child: _Orb(size: 34, color: const Color(0xFFB998FF)),
                ),
                Positioned(
                  left: 42,
                  top: 8,
                  child: _Orb(size: 44, color: const Color(0xFF8D63DC)),
                ),
                Positioned(
                  right: 4,
                  bottom: 14,
                  child: _Orb(size: 18, color: const Color(0xFFD7B8FF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  const _Orb({required this.size, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withOpacity(0.95), color.withOpacity(0.45)],
      ),
      boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 16)],
    ),
  );
}

// ═══════════════════════════════════════════════
// Suggestion Card
// ═══════════════════════════════════════════════

class _SuggestedUsersRow extends StatelessWidget {
  final List<dynamic> users;
  final VoidCallback? onFollowChanged;
  const _SuggestedUsersRow({required this.users, this.onFollowChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: users.take(12).length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, index) => _SuggestionMiniCard(
          user: users[index],
          onFollowChanged: onFollowChanged,
        ),
      ),
    );
  }
}

class _SuggestionMiniCard extends StatefulWidget {
  final dynamic user;
  final VoidCallback? onFollowChanged;
  const _SuggestionMiniCard({required this.user, this.onFollowChanged});

  @override
  State<_SuggestionMiniCard> createState() => _SuggestionMiniCardState();
}

class _SuggestionMiniCardState extends State<_SuggestionMiniCard> {
  bool _followed = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user is Map ? widget.user as Map : <String, dynamic>{};
    final firstName = user['first_name']?.toString() ?? '';
    final lastName = user['last_name']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();
    final username = user['username']?.toString() ?? '';
    final avatar = effectiveAvatarUrl(
        (user['avatar'] ?? user['profile_picture_url'] ?? user['avatar_url'])
            ?.toString());
    final initial = (fullName.isNotEmpty ? fullName : username).isNotEmpty
        ? (fullName.isNotEmpty ? fullName : username)[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: () {
        final uid = user['id']?.toString() ?? '';
        if (uid.isEmpty) return;
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: uid)),
        );
      },
      child: Container(
        width: 136,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primary.withOpacity(0.10),
              backgroundImage: (avatar != null && avatar.isNotEmpty)
                  ? CachedNetworkImageProvider(avatar)
                  : null,
              child: (avatar == null || avatar.isEmpty)
                  ? Text(
                      initial,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            Text(
              fullName.isNotEmpty
                  ? fullName
                  : (username.isNotEmpty ? '@$username' : '-'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              username.isNotEmpty ? '@$username' : ' ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _loading || _followed
                  ? null
                  : () async {
                      final id = user['id']?.toString() ?? '';
                      if (id.isEmpty) return;
                      setState(() => _loading = true);
                      await SocialService.followUser(id);
                      if (mounted)
                        setState(() {
                          _loading = false;
                          _followed = true;
                        });
                      widget.onFollowChanged?.call();
                    },
              child: Container(
                width: double.infinity,
                height: 30,
                decoration: BoxDecoration(
                  gradient: _followed
                      ? null
                      : LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.primary.withOpacity(0.85),
                          ],
                        ),
                  color: _followed ? AppColors.surface : null,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _followed
                        ? AppColors.borderLight
                        : Colors.transparent,
                  ),
                ),
                child: Center(
                  child: _loading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : Text(
                          _followed
                              ? context.trw('following')
                              : '+ ${context.trw('follow')}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
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
}

class _SuggestionCard extends StatefulWidget {
  final dynamic user;
  final VoidCallback? onFollowChanged;
  const _SuggestionCard({required this.user, this.onFollowChanged});

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  bool _followed = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final firstName = user['first_name'] ?? '';
    final lastName = user['last_name'] ?? '';
    final fullName = '$firstName $lastName'.trim();
    final username = user['username'] ?? '';
    final avatar = effectiveAvatarUrl(
        (user['avatar'] ?? user['profile_picture_url'] ?? user['avatar_url'])
            as String?);
    final bio = user['bio'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          final uid = user['id']?.toString() ?? '';
          if (uid.isEmpty) return;
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: uid)),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: avatar == null || avatar.isEmpty
                      ? LinearGradient(
                          colors: [
                            AppColors.primary.withOpacity(0.15),
                            AppColors.primary.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: avatar != null && avatar.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatar,
                        fit: BoxFit.cover,
                        width: 48,
                        height: 48,
                        errorWidget: (_, __, ___) =>
                            _SmallAvatar(name: fullName),
                      )
                    : Center(
                        child: Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              // Name + username + bio
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName.isNotEmpty ? fullName : '@$username',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (username.isNotEmpty && fullName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '@$username',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (bio.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          bio,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Follow button
              GestureDetector(
                onTap: _loading || _followed
                    ? null
                    : () async {
                        final id = user['id']?.toString() ?? '';
                        if (id.isEmpty) return;
                        setState(() => _loading = true);
                        await SocialService.followUser(id);
                        if (mounted)
                          setState(() {
                            _loading = false;
                            _followed = true;
                          });
                        widget.onFollowChanged?.call();
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _followed
                        ? AppColors.borderLight
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : Text(
                          _followed
                              ? context.trw('following')
                              : context.trw('follow'),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _followed
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
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
}

// ═══════════════════════════════════════════════
// Empty State
// ═══════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/panel-right-icon.svg',
                width: 28,
                height: 28,
                colorFilter: const ColorFilter.mode(
                  AppColors.textSecondary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.trw('all_caught_up'),
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.trw('nothing_here_yet'),
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textTertiary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// My Meetings Section (stateful)
// ═══════════════════════════════════════════════

class _MyMeetingsSection extends StatefulWidget {
  const _MyMeetingsSection();

  @override
  State<_MyMeetingsSection> createState() => _MyMeetingsSectionState();
}

class _MyMeetingsSectionState extends State<_MyMeetingsSection> {
  List<Map<String, dynamic>> _meetings = [];
  bool _loaded = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await MeetingsService().myMeetings();
      if (res['success'] == true && res['data'] != null) {
        final all = List<Map<String, dynamic>>.from(res['data']);
        final active = all
            .where((m) => m['status'] != 'ended')
            .take(5)
            .toList();
        if (mounted)
          setState(() {
            _meetings = active;
            _loaded = true;
          });
      } else {
        if (mounted) setState(() => _loaded = true);
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _meetings.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with meeting icon
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/video_chat_icon.svg',
                  width: 14,
                  height: 14,
                  colorFilter: const ColorFilter.mode(
                    AppColors.primary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.trw('my_meetings').toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary,
                  letterSpacing: 1.2,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        ..._meetings.map((m) {
          final isLive = m['status'] == 'in_progress';
          final title = m['title'] ?? 'Meeting';
          final eventName = m['event_name'] ?? '';
          final scheduledAt = m['scheduled_at'];
          final participantCount = m['participant_count'] ?? 0;
          String dateStr = '';
          String timeStr = '';
          if (scheduledAt != null) {
            try {
              final dt = DateTime.parse(scheduledAt).toLocal();
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
              dateStr = '${months[dt.month - 1]} ${dt.day}';
              timeStr =
                  '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            } catch (_) {}
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MeetingRoomScreen(
                      eventId: m['event_id']?.toString() ?? '',
                      meetingId: m['id']?.toString() ?? '',
                      roomId: m['room_id']?.toString() ?? '',
                      eventName:
                          m['event_name']?.toString() ??
                          m['event_title']?.toString(),
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isLive
                      ? const Color(0x0A22C55E)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isLive
                        ? const Color(0x4D22C55E)
                        : AppColors.borderLight,
                    width: isLive ? 1.5 : 1,
                  ),
                  boxShadow: isLive
                      ? [
                          const BoxShadow(
                            color: Color(0x0D22C55E),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isLive
                            ? const Color(0x1A22C55E)
                            : AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/icons/video_chat_icon.svg',
                          width: 20,
                          height: 20,
                          colorFilter: ColorFilter.mode(
                            isLive
                                ? const Color(0xFF22C55E)
                                : AppColors.primary,
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                    height: 1.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isLive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'LIVE',
                                    style: GoogleFonts.inter(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (eventName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              eventName,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                                height: 1.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              SvgPicture.asset(
                                'assets/icons/clock-icon.svg',
                                width: 10,
                                height: 10,
                                colorFilter: const ColorFilter.mode(
                                  AppColors.textTertiary,
                                  BlendMode.srcIn,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$dateStr · $timeStr',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SvgPicture.asset(
                                'assets/icons/user-icon.svg',
                                width: 10,
                                height: 10,
                                colorFilter: const ColorFilter.mode(
                                  AppColors.textTertiary,
                                  BlendMode.srcIn,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '$participantCount',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 28),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// Shared Widgets
// ═══════════════════════════════════════════════

class _Thumbnail extends StatelessWidget {
  final String? imageUrl;
  final String fallbackSvg;
  final double size;
  final double radius;

  /// When true, missing/broken images render the branded Nuru event default
  /// asset instead of the SVG glyph.
  final bool useEventFallback;

  const _Thumbnail({
    this.imageUrl,
    required this.fallbackSvg,
    required this.size,
    this.radius = 10,
    this.useEventFallback = false,
  });

  Widget _fallback() {
    if (useEventFallback) {
      return Image.asset(
        'assets/images/event-default.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    return Center(
      child: SvgPicture.asset(
        fallbackSvg,
        width: 18,
        height: 18,
        colorFilter: const ColorFilter.mode(
          AppColors.textSecondary,
          BlendMode.srcIn,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.borderLight, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }
}

class _SmallAvatar extends StatelessWidget {
  final String name;
  const _SmallAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      color: AppColors.borderLight,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _CodeBadge extends StatelessWidget {
  final String code;
  const _CodeBadge({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        code,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiary),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════

String _formatDateShort(String dateStr) {
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  } catch (_) {
    return dateStr;
  }
}

String _formatCompactMoney(dynamic amount) {
  if (amount == null) return '';
  final n =
      (amount is String ? double.tryParse(amount) : amount.toDouble()) ?? 0.0;
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
  return n.toStringAsFixed(0);
}

String? _extractServiceImage(Map<String, dynamic> s) {
  final primary = s['primary_image'];
  if (primary is Map)
    return primary['thumbnail_url']?.toString() ?? primary['url']?.toString();
  if (primary is String && primary.isNotEmpty) return primary;
  final images = s['images'];
  if (images is List && images.isNotEmpty) {
    final first = images.first;
    if (first is Map)
      return first['thumbnail_url']?.toString() ?? first['url']?.toString();
    if (first is String) return first;
  }
  return s['cover_image']?.toString() ?? s['image_url']?.toString();
}

// ═══════════════════════════════════════════════
// My Groups Section (stateful)
// ═══════════════════════════════════════════════

class _MyGroupsSection extends StatefulWidget {
  const _MyGroupsSection();

  @override
  State<_MyGroupsSection> createState() => _MyGroupsSectionState();
}

class _MyGroupsSectionState extends State<_MyGroupsSection> {
  List<dynamic> _groups = [];
  bool _loaded = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await EventGroupsService.listMyGroups();
      if (!mounted) return;
      if (res['success'] == true) {
        final data = res['data'];
        final groups = data is Map ? (data['groups'] ?? []) : [];
        setState(() {
          _groups = groups is List ? groups : [];
          _loaded = true;
        });
      } else {
        setState(() => _loaded = true);
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((s) => s.isEmpty ? '' : s[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final visible = _groups.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeaderAction(
          icon: 'assets/icons/group-chat-icon.svg',
          title: 'My Groups',
          action: 'View all',
          onAction: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyGroupsScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        ...visible.map((g) {
          final group = g as Map;
          final name = (group['name'] ?? 'Group').toString();
          final imageUrl = group['image_url'] as String?;
          final unread = (group['unread_count'] ?? 0) as int;
          final memberCount = group['member_count'] ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventGroupWorkspaceScreen(
                      groupId: group['id'].toString(),
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withOpacity(0.1),
                        image: (imageUrl != null && imageUrl.isNotEmpty)
                            ? DecorationImage(
                                image: NetworkImage(imageUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: (imageUrl == null || imageUrl.isEmpty)
                          ? Center(
                              child: Text(
                                _initials(name),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$memberCount members',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (unread > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minWidth: 20),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 28),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// Quick Action Tile
// ═══════════════════════════════════════════════
class _QuickTile extends StatelessWidget {
  final String iconAsset;
  final String label;
  final VoidCallback onTap;
  const _QuickTile({
    required this.iconAsset,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderLight, width: 1),
          ),
          child: Column(
            children: [
              SvgPicture.asset(
                iconAsset,
                width: 22,
                height: 22,
                colorFilter: const ColorFilter.mode(
                  AppColors.primary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
