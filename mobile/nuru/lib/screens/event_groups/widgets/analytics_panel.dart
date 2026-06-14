import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../widgets/app_action_sheet.dart';
import '../../../core/utils/money_format.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/event_groups_service.dart';
import '../../../core/widgets/nuru_skeleton.dart';

/// AnalyticsPanel - Contribution Progress, AI Insight, time-series bar chart,
/// Method/Status donuts and Engagement & Chat insights.
///
/// Same data source as before (`/scoreboard`), with optional richer fields
/// surfaced when the backend provides them (`by_method`, `engagement`,
/// `daily`, `top_topics`). Falls back gracefully when they're missing.
class AnalyticsPanel extends StatefulWidget {
  final String groupId;
  const AnalyticsPanel({super.key, required this.groupId});

  @override
  State<AnalyticsPanel> createState() => _AnalyticsPanelState();
}

// Module-level cache so flipping tabs doesn't flash a skeleton.
final Map<String, _AnalyticsCache> _analyticsCache = {};

class _AnalyticsCache {
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? summary;
  _AnalyticsCache(this.rows, this.summary);
}

class _AnalyticsPanelState extends State<AnalyticsPanel> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  Timer? _poll;
  int _rangeDays = 7;

  @override
  void initState() {
    super.initState();
    final cached = _analyticsCache[widget.groupId];
    if (cached != null) {
      _rows = cached.rows;
      _summary = cached.summary;
      _loading = false;
    }
    _load(silent: cached != null);
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await EventGroupsService.scoreboard(widget.groupId);
    if (!mounted) return;
    if (res['success'] == true && res['data'] is Map) {
      final data = res['data'] as Map;
      final rows = (data['rows'] as List? ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final summary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary']) : null;
      _analyticsCache[widget.groupId] = _AnalyticsCache(rows, summary);
      setState(() {
        _rows = rows;
        _summary = summary;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  String _money(num v) => NumberFormat('#,##0', 'en_US').format(v.round());

  /// Bucket a row into one of: completed / in_progress / pending / no_pledge.
  String _classify(Map<String, dynamic> r) {
    final pledged = (r['pledged'] as num?)?.toDouble() ?? 0;
    final paid = (r['paid'] as num?)?.toDouble() ?? 0;
    if (pledged <= 0) return 'no_pledge';
    if (paid >= pledged) return 'completed';
    if (paid > 0) return 'in_progress';
    return 'pending';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty) {
      return const NuruSkeletonList(itemCount: 5, showTrailing: true);
    }
    if (_rows.isEmpty) {
      return _empty();
    }

    final pledgeSum = _rows.fold<double>(0, (a, r) => a + ((r['pledged'] as num?)?.toDouble() ?? 0));
    final paidSum = _rows.fold<double>(0, (a, r) => a + ((r['paid'] as num?)?.toDouble() ?? 0));
    final outstanding = math.max(0.0, pledgeSum - paidSum);
    final summaryPledged = (_summary?['total_pledged'] as num?)?.toDouble() ?? pledgeSum;
    final summaryPaid = (_summary?['total_paid'] as num?)?.toDouble() ?? paidSum;
    final summaryOutstanding = (_summary?['outstanding'] as num?)?.toDouble() ?? outstanding;
    final summaryRate = (_summary?['collection_rate'] as num?)?.toDouble() ??
        (pledgeSum > 0 ? paidSum / pledgeSum * 100 : 0.0);

    // Status buckets for the contributor donut
    final buckets = {'completed': 0, 'in_progress': 0, 'pending': 0, 'no_pledge': 0};
    for (final r in _rows) {
      buckets[_classify(r)] = (buckets[_classify(r)] ?? 0) + 1;
    }

    final cur = getActiveCurrency();
    final daysLeft = _daysLeft();
    final targetLabel = _targetLabel();
    final byMethod = (_summary?['by_method'] is List)
        ? List<Map<String, dynamic>>.from(
            (_summary!['by_method'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)))
        : <Map<String, dynamic>>[];
    final daily = (_summary?['daily'] is List)
        ? List<Map<String, dynamic>>.from(
            (_summary!['daily'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)))
        : <Map<String, dynamic>>[];
    final engagement = _summary?['engagement'] is Map ? Map<String, dynamic>.from(_summary!['engagement']) : null;
    final topTopics = (_summary?['top_topics'] is List)
        ? List<Map<String, dynamic>>.from(
            (_summary!['top_topics'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)))
        : <Map<String, dynamic>>[];

    return NuruRefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          // ─── Row 1: Contribution Progress + AI Insight ───
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _progressCard(
                  cur: cur,
                  goal: summaryPledged,
                  contributed: summaryPaid,
                  remaining: summaryOutstanding,
                  rate: summaryRate,
                  daysLeft: daysLeft,
                  targetLabel: targetLabel),
            ),
            const SizedBox(width: 10),
            Expanded(child: _aiInsightCard(rate: summaryRate)),
          ])),
          const SizedBox(height: 14),

          // ─── Contributions Over Time ───
          _sectionCard(
            title: 'Contributions Over Time',
            trailing: _rangePill(),
            child: _barChart(daily, cur),
          ),
          const SizedBox(height: 14),

          // ─── Row 3: Method donut + Status donut ───
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _sectionCard(
                title: 'Contributions by Method',
                child: _methodDonut(byMethod, summaryPaid, cur),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _sectionCard(
                title: 'Contributor Status',
                child: _statusDonut(buckets),
              ),
            ),
          ])),
          const SizedBox(height: 14),

          // ─── Engagement & Chat Insights ───
          _sectionCard(
            title: 'Engagement & Chat Insights',
            child: _engagementBlock(engagement, topTopics),
          ),
        ],
      ),
    );
  }

  // ──────────── Helpers / Cards ────────────

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Analytics will appear once contributions start coming in.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppColors.textTertiary, fontSize: 13)),
        ),
      );

  int? _daysLeft() {
    final iso = _summary?['target_date'] ?? _summary?['event_start_date'] ?? _summary?['event_end_date'];
    if (iso is! String || iso.isEmpty) return null;
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return null;
    final diff = d.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  String _targetLabel() {
    final iso = _summary?['target_date'] ?? _summary?['event_start_date'] ?? _summary?['event_end_date'];
    if (iso is! String || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _sectionCard({required String title, Widget? trailing, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.textPrimary)),
          ),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  Widget _rangePill() {
    final label = _rangeDays == 7
        ? 'Last 7 days'
        : _rangeDays == 14
            ? 'Last 14 days'
            : 'Last 30 days';
    return GestureDetector(
      onTap: () async {
        final v = await AppActionSheet.show<int>(
          context: context,
          title: 'Time range',
          actions: [
            MenuAction(value: 7, label: 'Last 7 days', icon: 'time-fast', selected: _rangeDays == 7),
            MenuAction(value: 14, label: 'Last 14 days', icon: 'time-fast', selected: _rangeDays == 14),
            MenuAction(value: 30, label: 'Last 30 days', icon: 'time-fast', selected: _rangeDays == 30),
          ],
        );
        if (v != null) setState(() => _rangeDays = v);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: GoogleFonts.inter(fontSize: 9.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AppColors.textSecondary),
        ]),
      ),
    );
  }

  Widget _progressCard({
    required String cur,
    required double goal,
    required double contributed,
    required double remaining,
    required double rate,
    required int? daysLeft,
    required String targetLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Contribution Progress',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
            width: 72, height: 72,
            child: CustomPaint(
              painter: _RingPainter(rate.clamp(0, 100) / 100, AppColors.primary, AppColors.primarySoft),
              child: Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${rate.round()}%',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primary)),
                  Text('of goal',
                      style: GoogleFonts.inter(fontSize: 7.5, color: AppColors.textTertiary)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              _moneyLine('Goal', '$cur ${_money(goal)}', AppColors.textPrimary),
              const SizedBox(height: 2),
              _moneyLine('Contributed', '$cur ${_money(contributed)}', AppColors.primary),
              const SizedBox(height: 2),
              _moneyLine('Remaining', '$cur ${_money(remaining)}', AppColors.textSecondary),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (rate / 100).clamp(0.0, 1.0),
            minHeight: 4,
            color: AppColors.primary,
            backgroundColor: AppColors.borderLight,
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          SvgPicture.asset('assets/icons/clock-icon.svg', width: 10, height: 10, colorFilter: ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
          const SizedBox(width: 3),
          Flexible(child: Text(daysLeft != null ? '${daysLeft}d left' : '-',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiary, fontWeight: FontWeight.w600))),
          const Spacer(),
          if (targetLabel.isNotEmpty)
            Flexible(child: Text(targetLabel,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiary, fontWeight: FontWeight.w600))),
        ]),
      ]),
    );
  }

  Widget _moneyLine(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
      Text(label, style: GoogleFonts.inter(fontSize: 8.5, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _aiInsightCard({required double rate}) {
    final momentum = rate >= 60 ? 'Strong momentum' : (rate >= 30 ? 'Steady progress' : 'Needs a push');
    final headline = rate >= 60
        ? "Great progress. You're at ${rate.round()}% of your goal."
        : (rate >= 30
            ? "You're at ${rate.round()}% of your goal. Keep going."
            : "Only ${rate.round()}% so far. Share the link to boost.");
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SvgPicture.asset('assets/icons/thunder-icon.svg', width: 12, height: 12, colorFilter: ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
          const SizedBox(width: 5),
          Text('Nuru Insight',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 10.5, color: AppColors.primary)),
        ]),
        const SizedBox(height: 8),
        Text(headline,
            style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textPrimary, height: 1.35, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: CustomPaint(
            painter: _SparkPainter(rate),
            size: const Size.fromHeight(32),
          ),
        ),
        const Spacer(),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.trending_up_rounded, size: 12, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(momentum,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _barChart(List<Map<String, dynamic>> daily, String cur) {
    // Build last N days worth of bars from the backend payload, or synthesise
    // a placeholder ladder when there's nothing yet - never show fake totals.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final byDay = <String, double>{};
    for (final d in daily) {
      final iso = (d['date'] ?? d['day'] ?? '').toString();
      final dt = DateTime.tryParse(iso);
      if (dt == null) continue;
      final key = DateTime(dt.year, dt.month, dt.day).toIso8601String();
      final v = (d['total'] as num?)?.toDouble() ?? (d['amount'] as num?)?.toDouble() ?? 0.0;
      byDay[key] = (byDay[key] ?? 0) + v;
    }
    final bars = <_Bar>[];
    for (var i = _rangeDays - 1; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final key = d.toIso8601String();
      bars.add(_Bar(_shortDay(d), byDay[key] ?? 0, _axisDay(d)));
    }
    final maxVal = bars.fold<double>(0, (a, b) => math.max(a, b.value));
    final tallestIdx = maxVal == 0 ? -1 : bars.indexWhere((b) => b.value == maxVal);

    return SizedBox(
      height: 160,
      child: LayoutBuilder(builder: (_, c) {
        return Stack(children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 22),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < bars.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(
                          height: maxVal == 0 ? 4 : (bars[i].value / maxVal * 110).clamp(2, 110),
                          decoration: BoxDecoration(
                            color: i == tallestIdx ? AppColors.primary : AppColors.primary.withOpacity(0.35),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Row(children: [
              for (var i = 0; i < bars.length; i++)
                Expanded(
                  child: Text(
                    bars.length <= 7 ||
                            (bars.length <= 14 && (i.isEven || i == bars.length - 1)) ||
                            (bars.length > 14 && (i % 5 == 0 || i == bars.length - 1))
                        ? bars[i].axisLabel
                        : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: GoogleFonts.inter(
                        fontSize: bars.length > 14 ? 7 : 9,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ]),
          ),
          if (tallestIdx >= 0)
            Positioned(
              top: 0,
              left: (c.maxWidth / bars.length) * tallestIdx,
              width: c.maxWidth / bars.length,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderLight),
                    boxShadow: AppColors.subtleShadow,
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('$cur ${_money(maxVal)}',
                          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    ),
                    Text(bars[tallestIdx].label,
                        style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiary)),
                  ]),
                ),
              ),
            ),
        ]);
      }),
    );
  }

  String _shortDay(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _axisDay(DateTime d) {
    final label = d.day.toString();
    if (d.day == 1 || d.day == DateTime.now().day) {
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[d.month - 1]} $label';
    }
    return label;
  }

  Widget _methodDonut(List<Map<String, dynamic>> byMethod, double totalPaid, String cur) {
    if (byMethod.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Method breakdown will appear once contributions arrive.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textTertiary)),
        ),
      );
    }
    final colors = [
      AppColors.primary,
      AppColors.success,
      AppColors.blue,
      AppColors.warning,
      AppColors.textTertiary,
    ];
    final slices = <_Slice>[];
    for (var i = 0; i < byMethod.length; i++) {
      final m = byMethod[i];
      final label = (m['label'] ?? m['method'] ?? 'Other').toString();
      final v = (m['amount'] as num?)?.toDouble() ?? (m['total'] as num?)?.toDouble() ?? 0.0;
      slices.add(_Slice(label, v.round(), colors[i % colors.length]));
    }
    final total = slices.fold<int>(0, (a, b) => a + b.value);
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(
        width: 70, height: 70,
        child: CustomPaint(
          painter: _DonutPainter(slices, total),
          child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(cur, style: GoogleFonts.inter(fontSize: 8, color: AppColors.textTertiary, fontWeight: FontWeight.w700)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_money(totalPaid),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 9.5, color: AppColors.textPrimary)),
                ),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in slices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(s.label,
                      maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 8.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 4),
                Text('${total == 0 ? 0 : (s.value / total * 100).round()}%',
                    style: GoogleFonts.inter(fontSize: 8.5, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _statusDonut(Map<String, int> buckets) {
    final total = buckets.values.fold<int>(0, (a, b) => a + b);
    final entries = [
      _Slice('Contributed', buckets['completed'] ?? 0, AppColors.primary),
      _Slice('Pending', buckets['in_progress'] ?? 0, AppColors.warning),
      _Slice('Not Yet', (buckets['pending'] ?? 0) + (buckets['no_pledge'] ?? 0), AppColors.textTertiary),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(
        width: 70, height: 70,
        child: CustomPaint(
          painter: _DonutPainter(entries, total),
          child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$total',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11, color: AppColors.textPrimary)),
              Text('Members',
                  style: GoogleFonts.inter(fontSize: 7.5, color: AppColors.textTertiary)),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(s.label,
                      maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 8.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 4),
                Text('${s.value}',
                    style: GoogleFonts.inter(fontSize: 8.5, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _engagementBlock(Map<String, dynamic>? engagement, List<Map<String, dynamic>> topics) {
    final messages = (engagement?['messages_today'] as num?)?.toInt();
    final messagesDelta = (engagement?['messages_change_pct'] as num?)?.toDouble()
        ?? (engagement?['messages_delta'] as num?)?.toDouble();
    final active = (engagement?['active_members_today'] as num?)?.toInt()
        ?? (engagement?['active_members'] as num?)?.toInt();
    final activeDelta = (engagement?['active_members_change_pct'] as num?)?.toDouble()
        ?? (engagement?['active_delta'] as num?)?.toDouble();
    final contributors = (engagement?['contributors_week'] as num?)?.toInt()
        ?? (_summary?['contributors'] as num?)?.toInt() ?? _rows.length;
    final contributorsDelta = (engagement?['contributors_change_pct'] as num?)?.toDouble()
        ?? (engagement?['contributors_delta'] as num?)?.toDouble();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _engStat('assets/icons/chat-icon.svg', messages, 'Messages today', messagesDelta)),
        Expanded(child: _engStat('assets/icons/users-icon.svg', active, 'Active members', activeDelta)),
        Expanded(child: _engStat('assets/icons/donation-icon.svg', contributors, 'Contributors', contributorsDelta)),
      ]),
      if (topics.isNotEmpty) ...[
        const SizedBox(height: 14),
        Divider(height: 1, color: AppColors.borderLight),
        const SizedBox(height: 10),
        Text('Top Discussion Topics',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        for (var i = 0; i < topics.length && i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                width: 18,
                child: Text('${i + 1}',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textTertiary)),
              ),
              Expanded(
                child: Text((topics[i]['label'] ?? topics[i]['topic'] ?? '').toString(),
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              ),
              Text('${(topics[i]['count'] as num?)?.toInt() ?? 0}',
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ]),
          ),
      ],
    ]);
  }

  Widget _engStat(String iconAsset, int? value, String label, double? deltaPct) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.center,
            child: SvgPicture.asset(iconAsset, width: 12, height: 12, colorFilter: ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text((value ?? 0).toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11, color: AppColors.textPrimary)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 8.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        if (deltaPct != null) Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(children: [
            Icon(deltaPct >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 9, color: deltaPct >= 0 ? AppColors.success : AppColors.error),
            const SizedBox(width: 2),
            Flexible(
              child: Text('${deltaPct.abs().toStringAsFixed(0)}%',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 8.5,
                      color: deltaPct >= 0 ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ──────────────── Painters / data ────────────────

class _Bar {
  final String label;
  final double value;
  final String axisLabel;
  _Bar(this.label, this.value, this.axisLabel);
}

class _Slice {
  final String label;
  final int value;
  final Color color;
  _Slice(this.label, this.value, this.color);
}

class _RingPainter extends CustomPainter {
  final double progress; // 0–1
  final Color color;
  final Color trackColor;
  _RingPainter(this.progress, this.color, this.trackColor);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 10.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

class _DonutPainter extends CustomPainter {
  final List<_Slice> slices;
  final int total;
  _DonutPainter(this.slices, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final stroke = 16.0;
    if (total == 0) {
      canvas.drawArc(
          rect,
          0,
          2 * math.pi,
          false,
          Paint()
            ..color = AppColors.borderLight
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke);
      return;
    }
    var start = -math.pi / 2;
    for (final s in slices) {
      if (s.value == 0) continue;
      final sweep = (s.value / total) * 2 * math.pi;
      canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.butt);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.total != total;
}

class _SparkPainter extends CustomPainter {
  final double rate;
  _SparkPainter(this.rate);
  @override
  void paint(Canvas canvas, Size size) {
    final r = (rate.clamp(0, 100)) / 100;
    final pts = <Offset>[];
    final n = 12;
    for (var i = 0; i < n; i++) {
      final t = i / (n - 1);
      // Gentle climbing curve weighted by current rate.
      final y = size.height - (size.height * (0.15 + 0.6 * r * t + 0.15 * math.sin(t * math.pi * 1.4)));
      final x = size.width * t;
      pts.add(Offset(x, y));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.rate != rate;
}
