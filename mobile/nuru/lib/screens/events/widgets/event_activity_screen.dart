import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/nuru_search_bar.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/services/events_service.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/event_cover_image.dart';

/// Full-screen activity log for an event. Shows search, type filter pills
/// and items grouped into Today / This Week / Earlier - the same visual
/// system as the Recent Activity card on the overview tab.
class EventActivityScreen extends StatefulWidget {
  final String eventId;
  final String? eventTitle;
  final String? eventCover;
  final String? eventStatus;
  const EventActivityScreen({
    super.key,
    required this.eventId,
    this.eventTitle,
    this.eventCover,
    this.eventStatus,
  });

  @override
  State<EventActivityScreen> createState() => _EventActivityScreenState();
}

class _EventActivityScreenState extends State<EventActivityScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String _filter = 'all';
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      if (_query != _searchCtrl.text.trim().toLowerCase()) {
        setState(() => _query = _searchCtrl.text.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await EventsService.getRecentActivity(widget.eventId, limit: 100);
    if (!mounted) return;
    // Backend returns: { success, data: { items: [...], currency: 'TZS' } }.
    // Older clients expected `data` to be a list directly - handle both shapes
    // so the activity list always populates.
    final data = res['data'];
    List raw = const [];
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      final i = data['items'] ?? data['activities'] ?? data['results'];
      if (i is List) raw = i;
    }
    final items = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    return _items.where((a) {
      final type = (a['type'] ?? '').toString();
      if (_filter != 'all' && type != _filter) return false;
      if (_query.isEmpty) return true;
      final title = (a['title'] ?? '').toString().toLowerCase();
      final sub = (a['subtitle'] ?? '').toString().toLowerCase();
      return title.contains(_query) || sub.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: SvgPicture.asset('assets/icons/arrow-left-icon.svg',
              width: 22, height: 22,
              colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
        ),
        title: Text('Recent Activity',
            style: appText(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
        actions: const [SizedBox(width: 8)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (_loading) ...[
              _skeletonHeaderCard(),
              const SizedBox(height: 16),
              _skeletonSearch(),
              const SizedBox(height: 14),
              _skeletonFilters(),
              const SizedBox(height: 18),
              ..._buildSkeleton(),
            ] else ...[
              if (widget.eventTitle != null) _eventHeaderCard(),
              if (widget.eventTitle != null) const SizedBox(height: 16),
              _searchField(),
              const SizedBox(height: 14),
              _filters(),
              const SizedBox(height: 18),
              if (_filtered.isEmpty)
                _emptyState()
              else
                ..._buildGroupedTimeline(_filtered),
            ],
          ],
        ),
      ),
    );
  }

  Widget _eventHeaderCard() {
    final status = (widget.eventStatus ?? '').toLowerCase();
    final isConfirmed = status == 'published' || status == 'confirmed';
    final isCancelled = status == 'cancelled';
    final statusLabel = isConfirmed
        ? 'Confirmed'
        : isCancelled
            ? 'Cancelled'
            : status.isEmpty
                ? ''
                : (status[0].toUpperCase() + status.substring(1));
    final statusColor = isConfirmed
        ? const Color(0xFF16A34A)
        : isCancelled
            ? AppColors.error
            : AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: EventCoverImage(
              url: widget.eventCover,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.eventTitle ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText(size: 14.5, weight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                if (statusLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(statusLabel,
                          style: appText(size: 12, weight: FontWeight.w700, color: statusColor)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return NuruSearchBar(
      controller: _searchCtrl,
      hintText: 'Search activity',
      debounce: const Duration(milliseconds: 200),
      onChanged: (v) => setState(() {}),
    );
  }

  Widget _filters() {
    final tabs = const [
      ('all', 'All', Icons.apps_rounded, null),
      ('rsvp', 'RSVP', null, 'double-check'),
      ('ticket', 'Tickets', null, 'ticket'),
      ('expense', 'Expenses', null, 'report'),
      ('contribution', 'Contributions', null, 'donation'),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = tabs[i];
          final active = _filter == t.$1;
          return GestureDetector(
            onTap: () => setState(() => _filter = t.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    Icon(t.$3,
                        size: 15,
                        color: active ? AppColors.primary : AppColors.textSecondary)
                  else
                    AppIcon(t.$4!, size: 14,
                        color: active ? AppColors.primary : AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(t.$2,
                      style: appText(size: 12.5, weight: FontWeight.w700,
                          color: active ? AppColors.primary : AppColors.textPrimary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildGroupedTimeline(List<Map<String, dynamic>> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    final groups = <String, List<Map<String, dynamic>>>{
      'Today': [], 'This Week': [], 'Earlier': [],
    };
    for (final a in items) {
      final dt = _parse(a['time']?.toString());
      if (dt == null) { groups['Earlier']!.add(a); continue; }
      final d = DateTime(dt.year, dt.month, dt.day);
      if (d == today) groups['Today']!.add(a);
      else if (!d.isBefore(weekStart)) groups['This Week']!.add(a);
      else groups['Earlier']!.add(a);
    }

    final widgets = <Widget>[];
    for (final entry in groups.entries) {
      if (entry.value.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 0, 10),
        child: Text(entry.key,
            style: appText(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
      ));
      for (final a in entry.value) {
        widgets.add(_timelineRow(a));
      }
    }
    return widgets;
  }

  DateTime? _parse(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    var s = iso.trim();
    final hasTz = s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasTz) s = '${s}Z';
    return DateTime.tryParse(s)?.toLocal();
  }

  Widget _timelineRow(Map<String, dynamic> a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 18,
              child: Column(
                children: [
                  const SizedBox(height: 22),
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.borderLight,
                      border: Border.all(color: AppColors.borderLight),
                    ),
                  ),
                  Expanded(
                    child: Container(width: 1.2, color: AppColors.borderLight.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: _ActivityCard(activity: a)),
          ],
        ),
      ),
    );
  }

  Widget _skeletonRow() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(12))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 12, width: 180, decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 8),
          Container(height: 10, width: 120, decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(4))),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(height: 18, width: 56, decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 6),
          Container(height: 9, width: 34, decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(4))),
        ]),
      ]),
    );
  }

  List<Widget> _buildSkeleton() {
    Widget bar(double w, double h) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F1F4),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    Widget timelineRow() => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 18,
                child: Column(children: [
                  const SizedBox(height: 22),
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.borderLight,
                    ),
                  ),
                  Expanded(
                    child: Container(width: 1.2, color: AppColors.borderLight.withOpacity(0.7)),
                  ),
                ]),
              ),
              const SizedBox(width: 6),
              Expanded(child: _skeletonRow()),
            ],
          ),
        );
    return [
      Padding(padding: const EdgeInsets.fromLTRB(2, 0, 0, 10), child: bar(60, 14)),
      ...List.generate(3, (_) => timelineRow()),
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 0, 10), child: bar(78, 14)),
      ...List.generate(2, (_) => timelineRow()),
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 0, 10), child: bar(56, 14)),
      ...List.generate(2, (_) => timelineRow()),
    ];
  }

  Widget _skeletonHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(children: [
        Container(width: 52, height: 52,
            decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(10))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 12, width: 160, decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 8),
          Container(height: 10, width: 80, decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(4))),
        ])),
      ]),
    );
  }

  Widget _skeletonSearch() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1F4).withOpacity(0.6),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
      ),
    );
  }

  Widget _skeletonFilters() {
    final widths = [60.0, 76.0, 86.0, 92.0, 116.0];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Container(
          width: widths[i],
          decoration: BoxDecoration(
            color: const Color(0xFFF1F1F4),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.borderLight),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Center(child: AppIcon('thunder', size: 22, color: AppColors.primary)),
          ),
          const SizedBox(height: 14),
          Text('No activity yet',
              style: appText(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Updates from your event will show up here.',
              textAlign: TextAlign.center,
              style: appText(size: 12, color: AppColors.textTertiary, weight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> activity;
  const _ActivityCard({required this.activity});

  ({String icon, Color tint, Color bg, Color? badgeTint, Color? badgeBg, String? badgeText})
      _style() {
    final type = (activity['type'] ?? '').toString();
    final subtype = (activity['subtype'] ?? '').toString();
    String icon = 'thunder';
    Color tint = AppColors.primary;
    Color bg = AppColors.primary.withOpacity(0.10);
    Color? badgeTint;
    Color? badgeBg;
    String? badgeText;

    if (type == 'rsvp') {
      icon = 'double-check';
      tint = const Color(0xFF16A34A);
      bg = const Color(0xFFE7F8EE);
      badgeTint = const Color(0xFF16A34A);
      badgeBg = const Color(0xFFE7F8EE);
      badgeText = 'RSVP';
    } else if (type == 'ticket') {
      icon = 'ticket';
      tint = const Color(0xFFD97706);
      bg = const Color(0xFFFFF7E6);
    } else if (type == 'expense') {
      icon = 'report';
      tint = const Color(0xFFDC2626);
      bg = const Color(0xFFFEF2F2);
    } else if (type == 'contribution') {
      icon = subtype == 'payment' ? 'money' : 'donation';
      tint = const Color(0xFF7C3AED);
      bg = const Color(0xFFF3EBFF);
    }
    return (
      icon: icon, tint: tint, bg: bg,
      badgeTint: badgeTint, badgeBg: badgeBg, badgeText: badgeText,
    );
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '';
    final n = (amount is num) ? amount.toDouble() : double.tryParse(amount.toString()) ?? 0;
    final cur = getActiveCurrency();
    if (n >= 1000000) return '$cur ${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
    if (n >= 1000) return '$cur ${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 0)}K';
    return '$cur ${n.toStringAsFixed(0)}';
  }

  String _formatTime(String? iso) {
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month-1]} ${dt.day} • $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final s = _style();
    final amount = activity['amount'];
    final amountStr = _formatAmount(amount);
    final timeStr = _formatTime(activity['time']?.toString());

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
            decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(12)),
            child: Center(child: AppIcon(s.icon, size: 18, color: s.tint)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity['title']?.toString() ?? 'Activity',
                  style: appText(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  activity['subtitle']?.toString() ?? '',
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
              if (amountStr.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(99)),
                  child: Text(amountStr,
                      style: appText(size: 11, weight: FontWeight.w800, color: s.tint)),
                )
              else if (s.badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: s.badgeBg, borderRadius: BorderRadius.circular(99)),
                  child: Text(s.badgeText!,
                      style: appText(size: 11, weight: FontWeight.w800, color: s.badgeTint!)),
                ),
              const SizedBox(height: 6),
              Text(timeStr,
                  style: appText(size: 10.5, color: AppColors.textTertiary, weight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
