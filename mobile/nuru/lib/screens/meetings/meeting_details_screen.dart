import 'dart:io';
import '../../widgets/app_action_sheet.dart';
import '../../widgets/app_checkbox.dart';
import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:nuru/core/services/meetings_service.dart';
import 'package:nuru/screens/meetings/meeting_room_screen.dart';
import 'package:nuru/screens/meetings/meeting_documents_screen.dart';

/// Full-screen Meeting Details page matching the design mockup.
///
/// Reachable from:
///   1. Tapping a meeting row in [EventMeetingsTab].
///   2. The 3-dot menu on each meeting row.
///   3. The info button in the meeting room top bar.
///   4. Tapping a meeting push notification / calendar entry.
class MeetingDetailsScreen extends StatefulWidget {
  final String eventId;
  final String meetingId;
  final Map<String, dynamic>? initialMeeting;
  final String? eventName;
  final bool isCreator;

  const MeetingDetailsScreen({
    super.key,
    required this.eventId,
    required this.meetingId,
    this.initialMeeting,
    this.eventName,
    this.isCreator = false,
  });

  @override
  State<MeetingDetailsScreen> createState() => _MeetingDetailsScreenState();
}

class _MeetingDetailsScreenState extends State<MeetingDetailsScreen> {
  final MeetingsService _service = MeetingsService();
  Map<String, dynamic>? _meeting;
  bool _loading = true;
  bool _joining = false;
  bool _descExpanded = false;
  String? _error;

  static const _purple = Color(0xFF7C5CFC);
  static const _amber = Color(0xFFF7B500);

  @override
  void initState() {
    super.initState();
    _meeting = widget.initialMeeting;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final res = await _service.getMeeting(widget.eventId, widget.meetingId);
      if (!mounted) return;
      if (res['success'] == true && res['data'] != null) {
        setState(() {
          _meeting = Map<String, dynamic>.from(res['data']);
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          if (_meeting == null) _error = 'Meeting not found';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_meeting == null) _error = 'Failed to load meeting';
      });
    }
  }

  Future<void> _join() async {
    final m = _meeting;
    if (m == null || _joining) return;
    setState(() => _joining = true);
    try {
      final res = await _service.joinMeeting(widget.eventId, widget.meetingId);
      if (!mounted) return;
      if (res['success'] == true) {
        final roomId = res['data']?['room_id'] ?? m['room_id'] ?? '';
        if (roomId.toString().isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MeetingRoomScreen(
                eventId: widget.eventId,
                meetingId: widget.meetingId,
                roomId: roomId.toString(),
                eventName: widget.eventName,
              ),
            ),
          );
        }
      } else {
        _snack('Could not join meeting');
      }
    } catch (_) {
      _snack('Could not join meeting');
    }
    if (mounted) setState(() => _joining = false);
  }

  void _shareInvite() {
    final m = _meeting;
    if (m == null) return;
    final url = m['meeting_url'] ?? 'https://nuru.tz/meet/${m['room_id'] ?? ''}';
    final title = m['title'] ?? 'Meeting';
    Share.share('$title\n$url', sharePositionOrigin: sharePositionOrigin(context));
  }

  Future<void> _addToCalendar() async {
    final m = _meeting;
    if (m == null) return;
    final title = (m['title'] ?? 'Meeting').toString();
    final desc = (m['description'] ?? '').toString();
    final scheduledAt = _parseServerDate(m['scheduled_at']);
    final dur = int.tryParse(m['duration_minutes']?.toString() ?? '60') ?? 60;
    if (scheduledAt == null) {
      _snack('No scheduled time available');
      return;
    }
    // Ask the user which reminders they want (Google-Calendar style).
    final reminderMins = await _pickReminders();
    if (reminderMins == null) return; // cancelled

    final url =
        (m['meeting_url'] ?? 'https://nuru.tz/meet/${m['room_id'] ?? ''}')
            .toString();
    final start = scheduledAt.toUtc();
    final end = start.add(Duration(minutes: dur));
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'
        'T${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}${d.second.toString().padLeft(2, '0')}Z';
    final uid =
        '${m['id'] ?? m['room_id'] ?? DateTime.now().millisecondsSinceEpoch}@nuru.tz';

    final alarms = StringBuffer();
    for (final mins in reminderMins) {
      alarms.writeln('BEGIN:VALARM');
      alarms.writeln('ACTION:DISPLAY');
      alarms.writeln('DESCRIPTION:$title');
      alarms.writeln('TRIGGER:-PT${mins}M');
      alarms.writeln('END:VALARM');
    }

    final ics = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Nuru//Meetings//EN
BEGIN:VEVENT
UID:$uid
DTSTAMP:${fmt(DateTime.now().toUtc())}
DTSTART:${fmt(start)}
DTEND:${fmt(end)}
SUMMARY:${title.replaceAll('\n', ' ')}
DESCRIPTION:${desc.replaceAll('\n', ' ')}\\nJoin: $url
URL:$url
${alarms.toString().trimRight()}
END:VEVENT
END:VCALENDAR''';
    try {
      final dir = await getTemporaryDirectory();
      final safe = title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
      final file = File('${dir.path}/$safe.ics');
      await file.writeAsString(ics);
      // Always use the system share sheet so the user can pick Google
      // Calendar / Apple Calendar / etc. OpenFilex was unreliable on many
      // Android devices and silently fell back to a clipboard copy.
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/calendar', name: '$safe.ics')],
        subject: 'Add "$title" to your calendar',
        text: '$title\n$url',
        sharePositionOrigin: sharePositionOrigin(context),
      );
    } catch (_) {
      // Last-resort fallback
      try {
        await OpenFilex.open(
          (await getTemporaryDirectory()).path,
          type: 'text/calendar',
        );
      } catch (_) {}
      _snack('Could not open calendar');
    }
  }

  /// Multi-select dialog returning a list of "minutes before start" reminders.
  /// Returns null if the user cancels.
  Future<List<int>?> _pickReminders() async {
    final options = <int, String>{
      0: 'At time of meeting',
      5: '5 minutes before',
      10: '10 minutes before',
      15: '15 minutes before',
      30: '30 minutes before',
      60: '1 hour before',
      1440: '1 day before',
    };
    final selected = <int>{15};
    return showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            SvgPicture.asset('assets/icons/bell-icon.svg',
                width: 18,
                height: 18,
                colorFilter: const ColorFilter.mode(
                    Colors.black87, BlendMode.srcIn)),
            const SizedBox(width: 10),
            const Text('Set reminders',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: options.entries
                    .map((e) => AppCheckbox(
                          dense: true,
                          label: e.value,
                          value: selected.contains(e.key),
                          onChanged: (v) => setStateDialog(() {
                            if (v) {
                              selected.add(e.key);
                            } else {
                              selected.remove(e.key);
                            }
                          }),
                        ))
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF7B500),
                  foregroundColor: Colors.black),
              onPressed: () =>
                  Navigator.pop(ctx, selected.toList()..sort()),
              child: const Text('Add to calendar'),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat() {
    final m = _meeting;
    if (m == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MeetingDocumentsScreen(
        eventId: widget.eventId,
        meetingId: widget.meetingId,
        meetingTitle: m['title'] ?? '',
        meetingDescription: m['description'],
        meetingDate: m['scheduled_at'] ?? '',
        isCreator: widget.isCreator,
        eventName: widget.eventName,
      ),
    ));
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    _snack('$label copied');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0E0E10) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: SvgPicture.asset(
            'assets/icons/arrow-left-icon.svg',
            width: 22, height: 22,
            colorFilter: ColorFilter.mode(
              isDark ? Colors.white : Colors.black87, BlendMode.srcIn,
            ),
          ),
        ),
        title: const Text('Meeting Details',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.more_horiz_rounded,
                color: isDark ? Colors.white : Colors.black87),
            onPressed: () async {
              final v = await AppActionSheet.show<String>(
                context: context,
                title: 'Meeting actions',
                actions: [
                  const MenuAction(value: 'share', label: 'Share invite', icon: 'share'),
                  const MenuAction(value: 'copy', label: 'Copy meeting link', icon: 'share-upload'),
                  const MenuAction(value: 'calendar', label: 'Add to calendar', icon: 'calendar'),
                  const MenuAction(value: 'agenda', label: 'Agenda & Minutes', icon: 'chat'),
                  if (widget.isCreator)
                    const MenuAction(value: 'cancel', label: 'Cancel meeting', icon: 'close-circle', destructive: true),
                ],
              );
              if (v != null) _onMenuAction(v);
            },
          ),
        ],
      ),
      body: _loading && _meeting == null
          ? SkeletonList(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              count: 6,
              spacing: 12,
              builder: (_, i) => i == 0
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                      SkeletonBox(height: 160, radius: 16),
                      SizedBox(height: 14),
                      SkeletonLine(widthFactor: 0.6, height: 16),
                      SizedBox(height: 8),
                      SkeletonLine(widthFactor: 0.4, height: 12),
                    ])
                  : const SkeletonListTile(trailing: true, padding: EdgeInsets.zero),
            )
          : _meeting == null
              ? Center(child: Text(_error ?? 'No data'))
              : RefreshIndicator(
                  onRefresh: _loadDetails,
                  child: _buildBody(theme, isDark),
                ),
    );
  }

  void _onMenuAction(String action) {
    final m = _meeting;
    if (m == null) return;
    switch (action) {
      case 'share':
        _shareInvite();
        break;
      case 'copy':
        final url = m['meeting_url'] ?? 'https://nuru.tz/meet/${m['room_id'] ?? ''}';
        Clipboard.setData(ClipboardData(text: url.toString()));
        _snack('Meeting link copied');
        break;
      case 'calendar':
        _addToCalendar();
        break;
      case 'agenda':
        _openChat();
        break;
      case 'cancel':
        _confirmCancel();
        break;
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Cancel meeting?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Participants will no longer be able to join.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel meeting'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteMeeting(widget.eventId, widget.meetingId);
      if (mounted) {
        _snack('Meeting cancelled');
        Navigator.pop(context, true);
      }
    } catch (_) {
      _snack('Could not cancel meeting');
    }
  }

  /// Parse a server-provided ISO date safely. If the string lacks any TZ
  /// marker (Z or +HH:MM), assume UTC (matches backend convention) and then
  /// convert to the user's local time. This guarantees the meeting time is
  /// always shown in the viewer's own timezone.
  DateTime? _parseServerDate(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s.isEmpty) return null;
    var d = DateTime.tryParse(s);
    if (d == null) return null;
    final hasTz = s.endsWith('Z') ||
        RegExp(r'[+\-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasTz) {
      d = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second,
          d.millisecond);
    }
    return d.toLocal();
  }

  Widget _buildBody(ThemeData theme, bool isDark) {
    final m = _meeting!;
    final status = (m['status'] ?? 'scheduled').toString();
    final scheduledAt = _parseServerDate(m['scheduled_at']);
    final dur = int.tryParse(m['duration_minutes']?.toString() ?? '60') ?? 60;
    final endAt = scheduledAt?.add(Duration(minutes: dur));
    final participants = List<Map<String, dynamic>>.from(m['participants'] ?? const []);
    final createdBy = m['created_by'] is Map ? m['created_by'] as Map : null;
    final isLive = status == 'in_progress';
    final isEnded = status == 'ended';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const SizedBox(height: 8),
        _hero(theme, isDark, m, scheduledAt, endAt, isLive, isEnded),
        const SizedBox(height: 22),
        _actionGrid(theme, isDark, isLive, isEnded),
        const SizedBox(height: 18),
        _infoCard(theme, isDark, m, createdBy),
        const SizedBox(height: 16),
        _participantsCard(theme, isDark, participants),
      ],
    );
  }

  // ── Centered hero ──────────────────────────────────────────────────────
  Widget _hero(ThemeData theme, bool isDark, Map<String, dynamic> m,
      DateTime? scheduledAt, DateTime? endAt, bool isLive, bool isEnded) {
    final tz = scheduledAt?.timeZoneName ?? '';
    final timeRange = (scheduledAt != null && endAt != null)
        ? '${DateFormat('h:mm a').format(scheduledAt)} – ${DateFormat('h:mm a').format(endAt)}${tz.isNotEmpty ? ' ($tz)' : ''}'
        : '';
    final dateLabel = scheduledAt != null
        ? DateFormat('MMM d, yyyy').format(scheduledAt)
        : '-';
    return Column(
      children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_purple, _purple.withOpacity(0.78)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: _purple.withOpacity(0.35),
                  blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: Center(
            child: SvgPicture.asset(
              'assets/icons/people-in-meeting.svg',
              width: 44, height: 44,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          m['title']?.toString() ?? 'Untitled meeting',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800, letterSpacing: -0.6, fontSize: 22,
          ),
        ),
        if (widget.eventName != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.eventName!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14, color: isDark ? Colors.white60 : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SvgPicture.asset('assets/icons/calendar-icon.svg',
              width: 14, height: 14,
              colorFilter: ColorFilter.mode(Colors.grey[500]!, BlendMode.srcIn)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              timeRange.isEmpty
                  ? dateLabel
                  : '$dateLabel  •  $timeRange',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _statusPill(isLive: isLive, isEnded: isEnded),
          const SizedBox(width: 8),
          Text(
            isLive
                ? (scheduledAt != null
                    ? 'Started ${DateFormat('h:mm a').format(scheduledAt)}'
                    : 'Live')
                : isEnded
                    ? 'Ended'
                    : (scheduledAt != null
                        ? 'Starts ${DateFormat('h:mm a').format(scheduledAt)}'
                        : ''),
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ]),
      ],
    );
  }

  Widget _statusPill({required bool isLive, required bool isEnded}) {
    final color = isLive
        ? const Color(0xFF10B981)
        : isEnded ? Colors.grey : const Color(0xFF3B82F6);
    final label = isLive ? 'Ongoing' : isEnded ? 'Ended' : 'Scheduled';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }

  // ── Action grid ────────────────────────────────────────────────────────
  Widget _actionGrid(ThemeData theme, bool isDark, bool isLive, bool isEnded) {
    final actions = <_GridAction>[
      _GridAction(
        svg: 'assets/icons/video_chat_icon.svg',
        label: 'Join',
        primary: true,
        onTap: isEnded ? null : _join,
      ),
      _GridAction(
        svg: 'assets/icons/share-icon.svg',
        label: 'Share',
        onTap: _shareInvite,
      ),
      _GridAction(
        svg: 'assets/icons/calendar-icon.svg',
        label: 'Calendar',
        onTap: _addToCalendar,
      ),
      _GridAction(
        svg: 'assets/icons/chat-icon.svg',
        label: 'Agenda',
        onTap: _openChat,
      ),
    ];
    return Row(
      children: actions
          .map((a) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _gridTile(a, isDark),
                ),
              ))
          .toList(),
    );
  }

  Widget _gridTile(_GridAction a, bool isDark) {
    final disabled = a.onTap == null;
    final bg = a.primary
        ? _amber
        : (isDark ? const Color(0xFF1A1A22) : Colors.white);
    final border = a.primary
        ? null
        : Border.all(color: isDark ? Colors.white10 : const Color(0xFFE7E7EE));
    final fg = a.primary
        ? Colors.black
        : (isDark ? Colors.white : Colors.black87);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: a.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: disabled ? bg.withOpacity(0.5) : bg,
            borderRadius: BorderRadius.circular(18),
            border: border,
            boxShadow: a.primary
                ? [BoxShadow(color: _amber.withOpacity(0.35),
                    blurRadius: 14, offset: const Offset(0, 6))]
                : null,
          ),
          child: Column(children: [
            SvgPicture.asset(a.svg,
                width: 20, height: 20,
                colorFilter: ColorFilter.mode(fg, BlendMode.srcIn)),
            const SizedBox(height: 6),
            Text(a.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                )),
          ]),
        ),
      ),
    );
  }

  // ── Meeting info card ──────────────────────────────────────────────────
  Widget _infoCard(ThemeData theme, bool isDark, Map<String, dynamic> m,
      Map? createdBy) {
    final desc = (m['description'] ?? '').toString();
    final meetingId = (m['meeting_id'] ?? m['room_id'] ?? widget.meetingId).toString();
    final passcode = (m['passcode'] ?? '').toString();
    final allowBeforeHost = m['allow_join_before_host'] == true;
    final recording = m['recording_enabled'] == true ||
        (m['recording'] != null && m['recording'].toString().toLowerCase() != 'off');
    final hostName = createdBy?['name']?.toString() ?? '-';

    return _sectionCard(
      isDark: isDark,
      title: 'Meeting Info',
      trailing: desc.length > 80
          ? GestureDetector(
              onTap: () => setState(() => _descExpanded = !_descExpanded),
              child: Text(_descExpanded ? 'See less' : 'See more',
                  style: const TextStyle(
                      color: _amber,
                      fontSize: 12, fontWeight: FontWeight.w700)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (desc.isNotEmpty) ...[
            Text(
              desc,
              maxLines: _descExpanded ? null : 2,
              overflow: _descExpanded ? null : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13, height: 1.45,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _row('assets/icons/info-icon.svg', 'Meeting ID',
              trailing: _copyTrailing(meetingId, () => _copy('Meeting ID', meetingId))),
          _divider(isDark),
          _row('assets/icons/secure-shield-icon.svg', 'Passcode',
              trailing: _copyTrailing(passcode.isEmpty ? '-' : passcode,
                  passcode.isEmpty ? null : () => _copy('Passcode', passcode))),
          _divider(isDark),
          _row('assets/icons/user-icon.svg', 'Host',
              trailing: _valueText(hostName)),
          _divider(isDark),
          _row('assets/icons/user-profile-icon.svg', 'Allow Join Before Host',
              trailing: _valueText(allowBeforeHost ? 'Yes' : 'No')),
          _divider(isDark),
          _row('assets/icons/video-icon.svg', 'Recording',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                _valueText(recording ? 'On (Cloud)' : 'Off'),
                if (recording) ...[
                  const SizedBox(width: 6),
                  SvgPicture.asset('assets/icons/echo-icon.svg',
                      width: 14, height: 14,
                      colorFilter: const ColorFilter.mode(
                          Color(0xFF60A5FA), BlendMode.srcIn)),
                ],
              ])),
        ],
      ),
    );
  }

  Widget _row(String svg, String label, {required Widget trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(svg,
              width: 16, height: 16,
              colorFilter:
                  ColorFilter.mode(Colors.grey[500]!, BlendMode.srcIn)),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const Spacer(),
          // Hard-pin the value column to the right edge so all values align.
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: trailing,
            ),
          ),
        ],
      ),
    );
  }

  Widget _valueText(String v) => Text(v,
      textAlign: TextAlign.right,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700));

  Widget _copyTrailing(String value, VoidCallback? onTap) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: _valueText(value)),
      if (onTap != null) ...[
        const SizedBox(width: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
          ),
        ),
      ],
    ]);
  }

  // ── Participants ───────────────────────────────────────────────────────
  Widget _participantsCard(
      ThemeData theme, bool isDark, List<Map<String, dynamic>> participants) {
    return _sectionCard(
      isDark: isDark,
      title: 'Participants (${participants.length})',
      trailing: participants.isEmpty
          ? null
          : GestureDetector(
              onTap: () => _showAllParticipants(participants),
              child: const Text('See all',
                  style: TextStyle(
                      color: _amber,
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
      child: participants.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No participants yet',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            )
          : SizedBox(
              height: 44,
              child: _avatarRow(theme, isDark, participants),
            ),
    );
  }

  void _showAllParticipants(List<Map<String, dynamic>> participants) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scroll) => Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(children: [
                  Text('Participants (${participants.length})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: participants.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1, indent: 70,
                      color: Colors.grey[100]),
                  itemBuilder: (_, i) {
                    final p = participants[i];
                    final name = (p['name'] ?? 'Unknown').toString();
                    final role = (p['role'] ?? '').toString();
                    final joinedAt = _parseServerDate(p['joined_at']);
                    final attended = joinedAt != null;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: Row(children: [
                        _avatar(Theme.of(ctx), p),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                attended
                                    ? 'Joined ${DateFormat('MMM d, h:mm a').format(joinedAt)}'
                                    : 'Did not attend',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: attended
                                        ? Colors.green[700]
                                        : Colors.grey[500]),
                              ),
                            ],
                          ),
                        ),
                        if (role == 'creator' || role == 'co_host')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              role == 'creator' ? 'Host' : 'Co-host',
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF8A6A00)),
                            ),
                          ),
                      ]),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _avatarRow(ThemeData theme, bool isDark,
      List<Map<String, dynamic>> participants) {
    const max = 6;
    final shown = participants.take(max).toList();
    final remaining = participants.length - shown.length;
    return Stack(
      children: [
        for (int i = 0; i < shown.length; i++)
          Positioned(
            left: i * 30.0,
            child: _avatar(theme, shown[i]),
          ),
        if (remaining > 0)
          Positioned(
            left: shown.length * 30.0,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? const Color(0xFF1F1F26) : Colors.grey[200],
                border: Border.all(
                    color: isDark ? const Color(0xFF14141A) : Colors.white,
                    width: 2),
              ),
              alignment: Alignment.center,
              child: Text('+$remaining',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  Widget _avatar(ThemeData theme, Map<String, dynamic> p) {
    final name = (p['name'] ?? '?').toString();
    final avatar = p['avatar_url']?.toString();
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: isDark ? const Color(0xFF14141A) : Colors.white, width: 2),
      ),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
        backgroundImage: (avatar != null && avatar.isNotEmpty)
            ? NetworkImage(avatar)
            : null,
        child: (avatar == null || avatar.isEmpty)
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 13, fontWeight: FontWeight.w700))
            : null,
      ),
    );
  }

  // ── Section card shell ─────────────────────────────────────────────────
  Widget _sectionCard({
    required bool isDark,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF17171C) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFEDEDF3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2)),
          ),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  Widget _divider(bool isDark) => Divider(
      height: 1,
      color: isDark ? Colors.white10 : const Color(0xFFF0F0F4));

}

class _GridAction {
  final String svg;
  final String label;
  final bool primary;
  final VoidCallback? onTap;
  _GridAction({
    required this.svg,
    required this.label,
    this.primary = false,
    this.onTap,
  });
}
