import 'package:nuru/core/utils/money_format.dart' show getActiveCurrency, formatMoney;
import '../../../widgets/app_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/event_image.dart';
import '../../../core/widgets/event_cover_image.dart';
import '../../events/invitation_qr_screen.dart';
import '../../events/event_checkin_screen.dart';

/// Horizontal "list-row" event card (image left, details right) with a
/// trailing 3-dot menu. Matches the My Events visual reference.
class EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final String? role;
  final VoidCallback? onTap;
  final VoidCallback? onView;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onStatusChange;

  const EventCard({
    super.key,
    required this.event,
    this.role,
    this.onTap,
    this.onView,
    this.onEdit,
    this.onShare,
    this.onDelete,
    this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final title = (event['title'] ?? event['name'] ?? 'Untitled Event').toString();
    final status = (event['status'] ?? 'draft').toString();
    final startDate = (event['start_date'] ?? '').toString();
    final startTime = (event['start_time'] ?? '').toString();
    final location = (event['location'] ?? event['venue'] ?? '').toString();
    final eventType = (event['event_type'] is Map
            ? event['event_type']['name']
            : event['eventType'] ?? '')
        .toString();
    final currency = (event['currency'] ?? getActiveCurrency()).toString();
    final budget = event['budget'];
    final sellsTickets = event['sells_tickets'] == true;

    final ticketsSold = _toInt(event['tickets_sold']);
    final ticketsCapacity = _toInt(event['tickets_capacity']);
    final invitationsSent = _toInt(event['invitations_sent']);
    final invitationsTotal = _toInt(event['invitations_total']);
    final expectedGuests = _toInt(event['expected_guests']);
    final guestCount = _toInt(event['guest_count']);

    // Pick the most meaningful "progress" line to show.
    String? progressLabel;
    if (sellsTickets && ticketsCapacity > 0) {
      progressLabel = '$ticketsSold/$ticketsCapacity Tickets Sold';
    } else if (invitationsSent > 0 || invitationsTotal > 0) {
      // Match the RSVP tab metric exactly: show the number of invitations
      // actually dispatched. The previous "sent / total-created" denominator
      // was confusing because it never matched the RSVP screen's count.
      progressLabel = '$invitationsSent Invitation${invitationsSent == 1 ? '' : 's'} Sent';
    } else if (expectedGuests > 0) {
      progressLabel = '$guestCount/$expectedGuests Guests';
    } else if (budget != null && _toNum(budget) > 0) {
      progressLabel = 'Event Budget';
    }

    final rightAmount = _formatRightAmount(
      sellsTickets: sellsTickets,
      ticketsSold: ticketsSold,
      ticketsCapacity: ticketsCapacity,
      budget: budget,
      currency: currency,
      ticketRevenue: _toNum(event['ticket_revenue']),
    );

    final images = _getImages(event);
    final statusCfg = _statusConfig(status);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight, width: 1),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
              // ── Left cover image (square, rounded) ──
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: EventCoverImage(
                        url: images.isNotEmpty ? images[0] : null,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (role == 'guest')
                      Positioned(
                        bottom: 6,
                        left: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () {
                            final eventId = event['id']?.toString() ?? '';
                            if (eventId.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      InvitationQRScreen(eventId: eventId),
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/qr-icon.svg',
                                  width: 12,
                                  height: 12,
                                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'QR',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Right details ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.2,
                                height: 1.25,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _menuButton(context, status),
                        ],
                      ),

                      const SizedBox(height: 4),

                      if (eventType.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: (statusCfg['color'] as Color).withOpacity(0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            eventType,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: statusCfg['color'] as Color,
                              height: 1.1,
                            ),
                          ),
                        ),

                      // ── "Happening today" indicator + quick check-in ──
                      // Surfaces only on event day for organizers and any
                      // committee member that has the check-in permission.
                      if (_isHappeningToday(startDate) && _canCheckIn(role, event)) ...[
                        const SizedBox(height: 6),
                        _happeningTodayPill(context),
                      ],

                      const SizedBox(height: 6),

                      _metaItem(
                        'assets/icons/calendar-icon.svg',
                        _formatDateTime(startDate, startTime),
                      ),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        _metaItem(
                          'assets/icons/location-icon.svg',
                          location,
                        ),
                      ],

                      if (progressLabel != null || rightAmount != null) ...[
                        const SizedBox(height: 8),
                        if (progressLabel != null)
                          Text(
                            progressLabel,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (rightAmount != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            rightAmount,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.success,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
        ),
      ),
    );
  }

  // ── Event-day helpers ──────────────────────────────────────────────────
  static bool _isHappeningToday(String startDate) {
    if (startDate.isEmpty) return false;
    try {
      final d = DateTime.parse(startDate).toLocal();
      final now = DateTime.now();
      return d.year == now.year && d.month == now.month && d.day == now.day;
    } catch (_) {
      return false;
    }
  }

  static bool _canCheckIn(String? role, Map<String, dynamic> event) {
    if (role == 'creator') return true;
    if (role == 'committee') {
      final perms = event['committee_permissions'] ?? event['permissions'];
      if (perms is Map) {
        return perms['can_check_in_guests'] == true ||
            perms['can_check_in'] == true ||
            perms['is_organizer'] == true;
      }
      return true;
    }
    return false;
  }

  Widget _happeningTodayPill(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => EventCheckinScreen(
              eventId: (event['id'] ?? '').toString(),
              eventTitle: (event['title'] ?? event['name'] ?? '').toString(),
              eventDate: (event['start_date'] ?? '').toString(),
              eventLocation: (event['location'] ?? event['venue'] ?? '').toString(),
              permissions: event['committee_permissions'] is Map
                  ? Map<String, dynamic>.from(event['committee_permissions'] as Map)
                  : (event['permissions'] is Map
                      ? Map<String, dynamic>.from(event['permissions'] as Map)
                      : null),
            ),
          ));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.success.withOpacity(0.35), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('Happening today',
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success)),
              const SizedBox(width: 8),
              Container(width: 1, height: 10, color: AppColors.success.withOpacity(0.35)),
              const SizedBox(width: 8),
              Icon(Icons.qr_code_scanner_rounded, size: 13, color: AppColors.success),
              const SizedBox(width: 4),
              Text('Check in',
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuButton(BuildContext context, String status) {
    final isCreator = role == null || role == 'creator';
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: 'More',
        padding: EdgeInsets.zero,
        icon: const Icon(
          Icons.more_horiz_rounded,
          size: 20,
          color: AppColors.textTertiary,
        ),
        onPressed: () async {
          final v = await AppActionSheet.show<String>(
            context: context,
            title: 'Event actions',
            actions: [
              const MenuAction(value: 'view', label: 'View', icon: 'view'),
              if (isCreator)
                const MenuAction(value: 'edit', label: 'Edit', icon: 'pen'),
              const MenuAction(value: 'share', label: 'Share', icon: 'share'),
              if (isCreator && status == 'draft')
                const MenuAction(value: 'publish', label: 'Publish', icon: 'earth'),
              if (isCreator && status == 'published')
                const MenuAction(value: 'complete', label: 'Mark Completed', icon: 'double-check'),
              if (isCreator && status != 'cancelled')
                const MenuAction(value: 'cancel', label: 'Cancel Event', icon: 'block'),
              if (isCreator)
                const MenuAction(value: 'delete', label: 'Delete', icon: 'delete', destructive: true),
            ],
          );
          if (v == null) return;
          switch (v) {
            case 'view':
              (onView ?? onTap)?.call();
              break;
            case 'edit':
              onEdit?.call();
              break;
            case 'share':
              onShare?.call();
              break;
            case 'delete':
              _confirmDelete(context);
              break;
            case 'publish':
            case 'cancel':
            case 'complete':
              onStatusChange?.call(v == 'publish'
                  ? 'published'
                  : v == 'cancel'
                      ? 'cancelled'
                      : 'completed');
              break;
          }
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete event?', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(
          'This will remove the event and its data. This cannot be undone.',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete?.call();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _metaItem(String svgAsset, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          svgAsset,
          width: 12,
          height: 12,
          colorFilter: const ColorFilter.mode(
            AppColors.textTertiary,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textTertiary,
              height: 1.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
  }

  static String? _formatRightAmount({
    required bool sellsTickets,
    required int ticketsSold,
    required int ticketsCapacity,
    required dynamic budget,
    required String currency,
    required num ticketRevenue,
  }) {
    if (sellsTickets && ticketsCapacity > 0) {
      // For ticketed events show revenue if known, otherwise per-ticket avg via budget.
      if (ticketRevenue > 0) {
        return formatMoney(ticketRevenue, currency: currency, bare: false);
      }
      if (budget != null && _toNum(budget) > 0) {
        return formatMoney(_toNum(budget), currency: currency, bare: false);
      }
      return null;
    }
    final b = _toNum(budget);
    if (b > 0) return formatMoney(b, currency: currency, bare: false);
    return null;
  }

  static List<String> _getImages(Map<String, dynamic> e) {
    final gallery = e['gallery_images'] as List?;
    if (gallery != null && gallery.isNotEmpty) {
      return gallery.cast<String>().take(4).toList();
    }
    final images = e['images'] as List?;
    if (images != null && images.isNotEmpty) {
      final featured = images.firstWhere(
        (i) => i['is_featured'] == true,
        orElse: () => images.first,
      );
      final url = (featured['image_url'] ?? featured['url'] ?? '') as String;
      if (url.isNotEmpty) return [url];
    }
    final resolved = resolveEventImageUrl(e);
    return resolved != null ? [resolved] : [];
  }

  static Map<String, dynamic> _statusConfig(String status) {
    switch (status) {
      case 'published':
        return {'color': AppColors.primary, 'label': 'Published'};
      case 'confirmed':
        return {'color': AppColors.accent, 'label': 'Confirmed'};
      case 'cancelled':
        return {'color': AppColors.error, 'label': 'Cancelled'};
      case 'completed':
        return {'color': AppColors.info, 'label': 'Completed'};
      default:
        return {'color': AppColors.warning, 'label': 'Draft'};
    }
  }

  static String _formatDateTime(String dateStr, String timeStr) {
    final date = _formatDate(dateStr);
    if (date.isEmpty) return timeStr;
    if (timeStr.isEmpty) return date;
    return '$date • ${_formatTime(timeStr)}';
  }

  static String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dateStr);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return dateStr;
    }
  }

  static String _formatTime(String t) {
    // Accepts "HH:mm" or "HH:mm:ss"
    try {
      final parts = t.split(':');
      var h = int.parse(parts[0]);
      final m = parts.length > 1 ? parts[1] : '00';
      final period = h >= 12 ? 'PM' : 'AM';
      h = h % 12;
      if (h == 0) h = 12;
      return '$h:$m $period';
    } catch (_) {
      return t;
    }
  }
}

