import 'dart:async';
import '../../../widgets/app_action_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/social_service.dart';
import '../../events/event_detail_screen.dart';
import '../../services/my_services_screen.dart';
import '../../removed/removed_content_screen.dart';
import '../../public_profile/public_profile_screen.dart';
import '../../events/event_public_view_screen.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/swipe_action_tile.dart';
import '../../../core/widgets/nuru_refresh.dart';
import '../../../core/utils/notification_center.dart';
import '../../../core/widgets/nuru_skeleton.dart';
import '../../../core/widgets/self_scrolling_pills.dart';

/// Notifications screen - premium redesign matching the reference mock.
class HomeNotificationsTab extends StatefulWidget {
  final List<dynamic> notifications;
  final int unreadCount;
  final bool isLoading;
  final VoidCallback onRefresh;
  final ValueChanged<int>? onTabChanged;
  final ValueChanged<String>? onSearch;

  const HomeNotificationsTab({
    super.key,
    required this.notifications,
    this.unreadCount = 0,
    this.isLoading = false,
    required this.onRefresh,
    this.onTabChanged,
    this.onSearch,
  });

  @override
  State<HomeNotificationsTab> createState() => _HomeNotificationsTabState();
}

class _HomeNotificationsTabState extends State<HomeNotificationsTab> {
  String _filter = 'All';
  Timer? _debounce;

  static const _filters = ['All', 'Events', 'Tickets', 'Contributions', 'System'];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool _matchesFilter(Map<String, dynamic> n) {
    if (_filter == 'All') return true;
    final t = (n['type'] ?? '').toString();
    switch (_filter) {
      case 'Events':
        return t.contains('event') || t.contains('rsvp') || t.contains('committee');
      case 'Tickets':
        return t.contains('ticket') || t.contains('booking');
      case 'Contributions':
        return t.contains('contribution') || t.contains('payment');
      case 'System':
        return t.contains('system') || t.contains('removed') || t.contains('password') ||
               t.contains('verified') || t.contains('kyc');
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.notifications
        .whereType<Map<String, dynamic>>()
        .where(_matchesFilter)
        .toList();

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          _topBar(context),
          _filterRow(),
          const SizedBox(height: 4),
          Expanded(
            child: NuruRefresh(
              onRefresh: () async => widget.onRefresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                children: [
                  if (widget.isLoading)
                    ...List.generate(6, (_) => _skeletonItem())
                  else if (filtered.isEmpty)
                    _emptyState()
                  else
                    ..._buildGrouped(filtered),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  widget.onTabChanged?.call(0);
                }
              },
              icon: const Icon(Icons.arrow_back_rounded,
                size: 24, color: AppColors.textPrimary),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Notifications',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz_rounded,
                  color: AppColors.textPrimary, size: 24),
              onPressed: () async {
                final value = await AppActionSheet.show<String>(
                  context: context,
                  title: 'Notifications',
                  actions: [
                    const MenuAction(value: 'mark_all_read', label: 'Mark all as read', icon: 'double-check'),
                    const MenuAction(value: 'refresh', label: 'Refresh', icon: 'time-fast'),
                    if (_filter != 'All')
                      const MenuAction(value: 'clear_filter', label: 'Clear filter', icon: 'close'),
                  ],
                );
                if (value == null) return;
                Haptics.medium();
                switch (value) {
                  case 'mark_all_read':
                    await SocialService.markAllNotificationsRead();
                    NotificationCenter.clear();
                    widget.onRefresh();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('All notifications marked as read'),
                      ));
                    }
                    break;
                  case 'clear_filter':
                    setState(() => _filter = 'All');
                    break;
                  case 'refresh':
                    widget.onRefresh();
                    break;
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SelfScrollingPills(
        activeIndex: _filters.indexOf(_filter).clamp(0, _filters.length - 1),
        height: 38,
        spacing: 10,
        children: [
          for (final f in _filters)
            GestureDetector(
              onTap: () => setState(() => _filter = f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: f == _filter ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: f == _filter ? AppColors.primary : const Color(0xFFE5E7EB),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    f,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: f == _filter ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildGrouped(List<Map<String, dynamic>> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final buckets = <String, List<Map<String, dynamic>>>{
      'Today': [],
      'Yesterday': [],
      'Earlier': [],
    };

    for (final n in items) {
      final ts = n['created_at']?.toString() ?? '';
      DateTime? d;
      try {
        final hasTz = ts.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(ts);
        d = DateTime.parse(hasTz ? ts : '${ts}Z').toLocal();
      } catch (_) {}
      String key = 'Earlier';
      if (d != null) {
        final day = DateTime(d.year, d.month, d.day);
        if (day == today) {
          key = 'Today';
        } else if (day == yesterday) {
          key = 'Yesterday';
        }
      }
      buckets[key]!.add(n);
    }

    final out = <Widget>[];
    buckets.forEach((label, list) {
      if (list.isEmpty) return;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ));
      for (final data in list) {
        final id = (data['id'] ?? data.hashCode).toString();
        out.add(SwipeActionTile(
          dismissKey: ValueKey('notif-$id'),
          leadingIcon: Icons.mark_email_read_outlined,
          leadingLabel: 'Mark read',
          onArchive: () async {
            if (data['is_read'] != true && data['read'] != true && data['id'] != null) {
              await SocialService.markNotificationRead(data['id'].toString());
              NotificationCenter.decrement();
              widget.onRefresh();
            }
            return false;
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _notificationItem(context, data),
          ),
        ));
      }
    });
    return out;
  }

  Widget _skeletonItem() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: NuruSkeletonGroup(
        child: Row(children: [
          NuruSkeleton(
            width: 44,
            height: 44,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NuruSkeleton(
                  width: 180,
                  height: 12,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
                SizedBox(height: 8),
                NuruSkeleton(
                  width: 120,
                  height: 10,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(36)),
          child: Center(
            child: SvgPicture.asset('assets/icons/bell-icon.svg', width: 32, height: 32,
              colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
          ),
        ),
        const SizedBox(height: 16),
        Text('No notifications yet',
          style: GoogleFonts.inter(
            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text("We'll let you know the moment something happens.",
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary, height: 1.4)),
      ]),
    );
  }

  Widget _notificationItem(BuildContext context, Map<String, dynamic> data) {
    final message = (data['message'] ?? data['text'] ?? '').toString();
    final title = (data['title'] ?? _titleForType(data['type']?.toString() ?? '')).toString();
    final isRead = data['is_read'] == true || data['read'] == true;
    final createdAt = data['created_at']?.toString() ?? '';
    final type = data['type']?.toString() ?? '';
    final actor = data['actor'] is Map<String, dynamic> ? data['actor'] as Map<String, dynamic> : null;
    final visual = _visualForType(type);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final id = data['id']?.toString();
        if (id != null && !isRead) {
          await SocialService.markNotificationRead(id);
          NotificationCenter.decrement();
        }
        widget.onRefresh();
        _navigateForNotification(context, data);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _leadingVisual(type, actor, visual),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.3,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _buildActorMessage(actor, message),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _timeAgo(createdAt),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                if (!isRead)
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Social/people-driven types: show the actor's avatar.
  // Everything else: show a colored SVG glyph (Nuru branded).
  static const _actorTypes = {
    'follow', 'circle_add', 'circle_request', 'circle_accepted',
    'glow', 'comment', 'echo', 'mention',
    'rsvp_received', 'ticket_purchased', 'contribution_received',
    'booking_request', 'booking_accepted', 'booking_rejected',
    'event_invite', 'committee_invite',
  };

  Widget _leadingVisual(String type, Map<String, dynamic>? actor, _Visual visual) {
    final actorAvatar = actor?['avatar']?.toString();
    final showActor = _actorTypes.contains(type) &&
        actorAvatar != null && actorAvatar.isNotEmpty;

    if (showActor) {
      return Stack(clipBehavior: Clip.none, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: CachedNetworkImage(
            imageUrl: actorAvatar,
            width: 44, height: 44, fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 44, height: 44, color: AppColors.surfaceVariant),
            errorWidget: (_, __, ___) => _glyphTile(visual),
          ),
        ),
        Positioned(
          right: -2, bottom: -2,
          child: Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              color: visual.fg, shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 2)),
            alignment: Alignment.center,
            child: SvgPicture.asset(visual.svg,
              width: 9, height: 9,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
          ),
        ),
      ]);
    }
    return _glyphTile(visual);
  }

  Widget _glyphTile(_Visual visual) {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: visual.bg, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: SvgPicture.asset(visual.svg,
        width: 22, height: 22,
        colorFilter: ColorFilter.mode(visual.fg, BlendMode.srcIn)),
    );
  }

  String _titleForType(String type) {
    switch (type) {
      case 'event_invite': return 'Event Invite';
      case 'committee_invite': return 'Committee Invite';
      case 'rsvp_received': return 'New RSVP';
      case 'event_update': return 'Event Update';
      case 'event_reminder': return 'Event Reminder';
      case 'ticket_sold': return 'New Ticket Sold';
      case 'ticket_purchased': return 'Ticket Purchased';
      case 'booking_request': return 'Booking Request';
      case 'booking_accepted': return 'Vendor Confirmed';
      case 'booking_rejected': return 'Booking Rejected';
      case 'contribution_received': return 'New Contribution';
      case 'payment_received': return 'Payment Received';
      case 'follow': return 'New Follower';
      case 'glow': return 'New Like';
      case 'comment': case 'echo': return 'New Comment';
      case 'identity_verified': case 'kyc_approved': return 'Identity Verified';
      case 'password_changed': return 'Password Changed';
      case 'system_update': return 'System Update';
      case 'content_removed': case 'post_removed': case 'moment_removed': return 'Content Removed';
      default: return 'Notification';
    }
  }

  _Visual _visualForType(String type) {
    if (type.contains('ticket')) {
      return const _Visual(
        bg: Color(0xFFFFF3D6), fg: Color(0xFFD97706),
        svg: 'assets/icons/ticket-icon.svg');
    }
    if (type.contains('contribution')) {
      return const _Visual(
        bg: Color(0xFFE5F8E8), fg: Color(0xFF22C55E),
        svg: 'assets/icons/card-icon.svg');
    }
    if (type == 'payment_received' || type.contains('payment')) {
      return const _Visual(
        bg: Color(0xFFFFE4E6), fg: Color(0xFFEF4444),
        svg: 'assets/icons/card-icon.svg');
    }
    if (type.contains('event') || type.contains('rsvp') || type.contains('reminder') || type.contains('committee')) {
      return const _Visual(
        bg: Color(0xFFE8E4FF), fg: Color(0xFF6D5BFF),
        svg: 'assets/icons/calendar-icon.svg');
    }
    if (type.contains('booking') || type.contains('vendor')) {
      return const _Visual(
        bg: Color(0xFFDDEBFF), fg: Color(0xFF2563EB),
        svg: 'assets/icons/package-icon.svg');
    }
    if (type == 'follow') {
      return const _Visual(
        bg: Color(0xFFDDEBFF), fg: Color(0xFF2563EB),
        svg: 'assets/icons/user-icon.svg');
    }
    if (type == 'glow') {
      return const _Visual(
        bg: Color(0xFFFFE4E6), fg: Color(0xFFEF4444),
        svg: 'assets/icons/heart-filled-icon.svg');
    }
    if (type.contains('comment') || type == 'echo') {
      return const _Visual(
        bg: Color(0xFFDDEBFF), fg: Color(0xFF2563EB),
        svg: 'assets/icons/chat-icon.svg');
    }
    if (type.contains('removed')) {
      return const _Visual(
        bg: Color(0xFFFFE4E6), fg: Color(0xFFEF4444),
        svg: 'assets/icons/info-icon.svg');
    }
    if (type.contains('verified') || type.contains('kyc')) {
      return const _Visual(
        bg: Color(0xFFE5F8E8), fg: Color(0xFF22C55E),
        svg: 'assets/icons/verified-icon.svg');
    }
    if (type.contains('password')) {
      return const _Visual(
        bg: Color(0xFFFFF3D6), fg: Color(0xFFD97706),
        svg: 'assets/icons/shield-icon.svg');
    }
    return const _Visual(
      bg: Color(0xFFEEEEF1), fg: AppColors.textSecondary,
      svg: 'assets/icons/bell-icon.svg');
  }

  void _navigateForNotification(BuildContext context, Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final refId = data['reference_id']?.toString() ?? data['event_id']?.toString() ?? data['post_id']?.toString() ?? '';
    final actorId = (data['actor'] is Map ? data['actor']['id'] : null)?.toString();
    final roleHintRaw = (data['role'] ?? data['viewer_role'] ?? data['my_role'])?.toString().toLowerCase();
    final knownRole = roleHintRaw == 'creator' || roleHintRaw == 'organizer' || roleHintRaw == 'owner'
        ? 'creator' : (roleHintRaw == 'committee' || roleHintRaw == 'member' ? 'committee' : null);
    if (refId.isEmpty && actorId == null) return;
    if (['event_invite'].contains(type) && refId.isNotEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => EventPublicViewScreen(eventId: refId)));
    } else if (['committee_invite', 'rsvp_received', 'event_update'].contains(type) && refId.isNotEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: refId, knownRole: knownRole)));
    } else if (['follow', 'circle_add', 'circle_request', 'circle_accepted'].contains(type) && actorId != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: actorId)));
    } else if (['glow', 'comment', 'echo', 'mention'].contains(type) && refId.isNotEmpty) {
      widget.onTabChanged?.call(0);
    } else if (['booking_request', 'booking_accepted', 'booking_rejected'].contains(type)) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyServicesScreen()));
    } else if (['content_removed', 'post_removed', 'moment_removed'].contains(type)) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const RemovedContentScreen()));
    } else if (actorId != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: actorId)));
    }
  }

  Widget _buildActorMessage(Map<String, dynamic>? actor, String message) {
    final firstName = (actor?['first_name'] ?? '').toString().trim();
    final lastName = (actor?['last_name'] ?? '').toString().trim();
    final fullName = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

    if (fullName.isEmpty) {
      return Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 12.5,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
      );
    }

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 12.5,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
        children: [
          TextSpan(
            text: fullName,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          TextSpan(text: ' $message'),
        ],
      ),
    );
  }

  String _timeAgo(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      // Server returns UTC without timezone suffix; normalize before parsing.
      final hasTz = dateStr.endsWith('Z') ||
          RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(dateStr);
      final normalized = hasTz ? dateStr : '${dateStr}Z';
      final d = DateTime.parse(normalized).toLocal();
      final diff = DateTime.now().difference(d);
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 2) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
      if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
      return '${(diff.inDays / 365).floor()}y ago';
    } catch (_) { return ''; }
  }
}

class _Visual {
  final Color bg;
  final Color fg;
  final String svg;
  const _Visual({required this.bg, required this.fg, required this.svg});
}
