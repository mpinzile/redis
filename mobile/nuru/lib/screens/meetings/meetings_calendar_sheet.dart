import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:nuru/core/services/meetings_service.dart';
import 'package:nuru/screens/meetings/meeting_details_screen.dart';

/// Full month-view calendar that lists meetings per day, opened from
/// the calendar icon in the Event Meetings app bar.
class MeetingsCalendarSheet extends StatefulWidget {
  final String eventId;
  final String? eventName;
  final bool isCreator;

  const MeetingsCalendarSheet({
    super.key,
    required this.eventId,
    this.eventName,
    this.isCreator = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String eventId,
    String? eventName,
    bool isCreator = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => MeetingsCalendarSheet(
        eventId: eventId,
        eventName: eventName,
        isCreator: isCreator,
      ),
    );
  }

  @override
  State<MeetingsCalendarSheet> createState() => _MeetingsCalendarSheetState();
}

class _MeetingsCalendarSheetState extends State<MeetingsCalendarSheet> {
  final _service = MeetingsService();
  bool _loading = true;
  List<Map<String, dynamic>> _meetings = [];
  late DateTime _focused;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focused = DateTime(now.year, now.month, 1);
    _selected = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _service.listMeetings(widget.eventId);
      if (!mounted) return;
      if (res['success'] == true && res['data'] != null) {
        setState(() {
          _meetings = List<Map<String, dynamic>>.from(res['data']);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime? _parseServerDate(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s.isEmpty) return null;
    var d = DateTime.tryParse(s);
    if (d == null) return null;
    final hasTz = s.endsWith('Z') || RegExp(r'[+\-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasTz) {
      d = DateTime.utc(
          d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond);
    }
    return d.toLocal();
  }

  Map<DateTime, List<Map<String, dynamic>>> _groupedByDay() {
    final map = <DateTime, List<Map<String, dynamic>>>{};
    for (final m in _meetings) {
      final d = _parseServerDate(m['scheduled_at']);
      if (d == null) continue;
      final key = DateTime(d.year, d.month, d.day);
      map.putIfAbsent(key, () => []).add(m);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedByDay();
    final selectedKey =
        DateTime(_selected.year, _selected.month, _selected.day);
    final dayMeetings = grouped[selectedKey] ?? const [];

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              const Text('Meetings Calendar',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),
          if (_loading)
            Expanded(
              child: SkeletonList(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                count: 6,
                spacing: 10,
                builder: (_, __) => const SkeletonListTile(padding: EdgeInsets.zero),
              ),
            )
          else
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _monthHeader(),
                  const SizedBox(height: 8),
                  _weekdayRow(),
                  const SizedBox(height: 4),
                  _monthGrid(grouped),
                  const SizedBox(height: 18),
                  Row(children: [
                    SvgPicture.asset('assets/icons/calendar-icon.svg',
                        width: 16,
                        height: 16,
                        colorFilter: ColorFilter.mode(
                            Colors.grey[700]!, BlendMode.srcIn)),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('EEEE, MMM d').format(_selected),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      '${dayMeetings.length} meeting${dayMeetings.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[600]),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  if (dayMeetings.isEmpty)
                    _emptyDay()
                  else
                    ...dayMeetings.map(_meetingTile),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _monthHeader() {
    return Row(children: [
      IconButton(
        onPressed: () => setState(() {
          _focused = DateTime(_focused.year, _focused.month - 1, 1);
        }),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Expanded(
        child: Center(
          child: Text(
            DateFormat('MMMM yyyy').format(_focused),
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      IconButton(
        onPressed: () => setState(() {
          _focused = DateTime(_focused.year, _focused.month + 1, 1);
        }),
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ]);
  }

  Widget _weekdayRow() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: labels
          .map((l) => Expanded(
                child: Center(
                  child: Text(l,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[500])),
                ),
              ))
          .toList(),
    );
  }

  Widget _monthGrid(Map<DateTime, List<Map<String, dynamic>>> grouped) {
    final firstOfMonth = DateTime(_focused.year, _focused.month, 1);
    final daysInMonth =
        DateTime(_focused.year, _focused.month + 1, 0).day;
    // Monday-first: Monday=0 .. Sunday=6
    final leading = (firstOfMonth.weekday + 6) % 7;
    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    final today = DateTime.now();
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_focused.year, _focused.month, d);
      final hasMeetings = (grouped[date] ?? const []).isNotEmpty;
      final isSelected = date.year == _selected.year &&
          date.month == _selected.month &&
          date.day == _selected.day;
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      cells.add(GestureDetector(
        onTap: () => setState(() => _selected = date),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF7B500)
                : (isToday ? const Color(0xFFFFF4D6) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$d',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected || isToday
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color:
                      isSelected ? Colors.black : Colors.grey[800],
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 5, height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasMeetings
                      ? (isSelected
                          ? Colors.black
                          : const Color(0xFF7C5CFC))
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ));
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.85,
      children: cells,
    );
  }

  Widget _emptyDay() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Text(
        'No meetings on this day',
        style: TextStyle(color: Colors.grey[500], fontSize: 13),
      ),
    );
  }

  Widget _meetingTile(Map<String, dynamic> m) {
    final at = _parseServerDate(m['scheduled_at']);
    final time = at != null ? DateFormat('h:mm a').format(at) : '--';
    final status = (m['status'] ?? 'scheduled').toString();
    Color sBg;
    Color sFg;
    String sLabel;
    if (status == 'in_progress') {
      sBg = const Color(0xFFFEE2E2);
      sFg = const Color(0xFFB91C1C);
      sLabel = 'Live';
    } else if (status == 'ended') {
      sBg = const Color(0xFFF1F1F4);
      sFg = const Color(0xFF6B7280);
      sLabel = 'Ended';
    } else {
      sBg = const Color(0xFFEDE9FE);
      sFg = const Color(0xFF6D28D9);
      sLabel = 'Scheduled';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEDF3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MeetingDetailsScreen(
                  eventId: widget.eventId,
                  meetingId: m['id'].toString(),
                  initialMeeting: m,
                  eventName: widget.eventName,
                  isCreator: widget.isCreator,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/people-in-meeting.svg',
                    width: 20, height: 20,
                    colorFilter: const ColorFilter.mode(
                        Color(0xFF6D28D9), BlendMode.srcIn),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(m['title'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(time,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: sBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(sLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: sFg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
