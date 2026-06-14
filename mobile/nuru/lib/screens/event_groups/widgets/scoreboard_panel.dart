import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../core/widgets/nuru_search_bar.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/event_groups_service.dart';
import '../../../core/widgets/nuru_skeleton.dart';

/// Contributors tab - stat grid + searchable, filterable contributor list.
///
/// Reuses the `EventGroupsService.scoreboard` endpoint and the existing
/// 8-second poll so live progress keeps refreshing.
class ScoreboardPanel extends StatefulWidget {
  final String groupId;
  const ScoreboardPanel({super.key, required this.groupId});

  @override
  State<ScoreboardPanel> createState() => _ScoreboardPanelState();
}

enum _ContribFilter { all, complete, pending }

// Module-level cache so flipping tabs doesn't flash a skeleton.
class _ScoreCache {
  final List<dynamic> rows;
  final Map<String, dynamic>? summary;
  _ScoreCache(this.rows, this.summary);
}
final Map<String, _ScoreCache> _scoreCache = {};

class _ScoreboardPanelState extends State<ScoreboardPanel> {
  List<dynamic> _rows = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  Timer? _poll;
  String _search = '';
  _ContribFilter _filter = _ContribFilter.all;

  @override
  void initState() {
    super.initState();
    final cached = _scoreCache[widget.groupId];
    if (cached != null) {
      _rows = cached.rows;
      _summary = cached.summary;
      _loading = false;
    }
    _load(silent: cached != null);
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
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
    setState(() {
      _loading = false;
      if (res['success'] == true && res['data'] is Map) {
        _rows = List.from(res['data']['rows'] ?? []);
        _summary = Map<String, dynamic>.from(res['data']['summary'] ?? {});
        _scoreCache[widget.groupId] = _ScoreCache(_rows, _summary);
      }
    });
  }

  String _money(num? v) =>
      NumberFormat('#,##0', 'en_US').format((v ?? 0).round());

  String _initials(String n) =>
      n.trim().split(RegExp(r'\s+')).take(2).map((s) => s.isEmpty ? '' : s[0].toUpperCase()).join();

  String _currency() {
    // Pull currency off summary or first row when available.
    final c = _summary?['currency'] ?? _summary?['currency_code'];
    if (c is String && c.isNotEmpty) return c;
    if (_rows.isNotEmpty && _rows.first is Map) {
      final r = _rows.first as Map;
      final rc = r['currency'] ?? r['currency_code'];
      if (rc is String && rc.isNotEmpty) return rc;
    }
    return 'TZS';
  }

  bool _isComplete(Map r) {
    final pledged = (r['pledged'] as num?)?.toDouble() ?? 0;
    final paid = (r['paid'] as num?)?.toDouble() ?? 0;
    return pledged > 0 && paid >= pledged;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty) {
      return const NuruSkeletonList(itemCount: 6, showTrailing: true);
    }
    final cur = _currency();
    final pledged = (_summary?['total_pledged'] as num?) ?? 0;
    final paid = (_summary?['total_paid'] as num?) ?? 0;
    final outstanding = (_summary?['outstanding'] as num?) ?? (pledged - paid);
    final rate = (_summary?['collection_rate'] as num?)?.toDouble() ?? 0.0;
    final budget = (_summary?['budget'] as num?)?.toDouble() ?? 0.0;
    final goalPct = (_summary?['goal_progress'] as num?)?.toDouble()
        ?? (budget > 0 ? ((pledged / budget) * 100).clamp(0, 100).toDouble() : 0.0);
    final paidPct = pledged > 0 ? ((paid / pledged) * 100).clamp(0, 100).round() : 0;
    final outstandingPct = pledged > 0 ? ((outstanding / pledged) * 100).clamp(0, 100).round() : 0;

    // Apply search + filter (client-side only - no endpoint changes)
    final q = _search.trim().toLowerCase();
    final filtered = _rows.where((r) {
      if (r is! Map) return false;
      final name = (r['display_name'] ?? r['name'] ?? '').toString().toLowerCase();
      if (q.isNotEmpty && !name.contains(q)) return false;
      switch (_filter) {
        case _ContribFilter.all:
          return true;
        case _ContribFilter.complete:
          return _isComplete(r);
        case _ContribFilter.pending:
          return !_isComplete(r);
      }
    }).toList();

    return NuruRefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          // ─── Stat grid card (4 stats) ───
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppColors.subtleShadow,
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _statBlock(
                  iconWidget: Icon(Icons.description_outlined, size: 18, color: AppColors.primary),
                  label: 'Total Pledged',
                  value: '$cur ${_money(pledged)}',
                  sub: '${goalPct.round()}% of goal',
                  subColor: AppColors.textTertiary,
                )),
                _vDivider(),
                Expanded(child: _statBlock(
                  iconWidget: Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
                  label: 'Total Paid',
                  value: '$cur ${_money(paid)}',
                  sub: '$paidPct% of goal',
                  subColor: AppColors.success,
                )),
                _vDivider(),
                Expanded(child: _statBlock(
                  iconWidget: SvgPicture.asset('assets/icons/wallet-icon.svg',
                      width: 18, height: 18,
                      colorFilter: ColorFilter.mode(AppColors.warning, BlendMode.srcIn)),
                  label: 'Balance',
                  value: '$cur ${_money(outstanding)}',
                  sub: '$outstandingPct% remaining',
                  subColor: AppColors.warning,
                )),
                _vDivider(),
                Expanded(child: _statBlock(
                  iconWidget: Icon(Icons.pie_chart_outline_rounded, size: 18, color: AppColors.blue),
                  label: 'Completion Rate',
                  value: '${rate.round()}%',
                  customSub: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (rate / 100).clamp(0.0, 1.0),
                      minHeight: 4,
                      color: AppColors.primary,
                      backgroundColor: AppColors.borderLight,
                    ),
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ─── Search + filter pills (one row, events-style search) ───
          Row(children: [
            Expanded(
              child: NuruSearchBar(
                hintText: 'Search contributors...',
                debounce: const Duration(milliseconds: 200),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(width: 6),
            _filterPill('All', _ContribFilter.all),
            const SizedBox(width: 4),
            _filterPill('Complete', _ContribFilter.complete),
            const SizedBox(width: 4),
            _filterPill('Pending', _ContribFilter.pending),
          ]),
          const SizedBox(height: 12),

          // ─── Contributors list (single container, inset bottom borders) ───
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              alignment: Alignment.center,
              child: Text(_rows.isEmpty ? 'No contributors yet' : 'No matches',
                  style: GoogleFonts.inter(color: AppColors.textTertiary, fontSize: 13)),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.borderLight),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (int i = 0; i < filtered.length; i++) ...[
                    _contributorRow(filtered[i] as Map),
                    if (i != filtered.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Divider(height: 1, thickness: 1, color: AppColors.borderLight),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _contributorRow(Map r) {
    final name = (r['display_name'] ?? r['name'] ?? '?').toString();
    final pledged = (r['pledged'] as num?)?.toDouble() ?? 0;
    final paid = (r['paid'] as num?)?.toDouble() ?? 0;
    final balance = (pledged - paid).clamp(0, double.infinity);
    final pct = pledged > 0 ? ((paid / pledged) * 100).clamp(0, 100).round() : (paid > 0 ? 100 : 0);
    final avatar = r['avatar_url'] as String?;
    final complete = pct >= 100;

    final labelStyle = GoogleFonts.inter(
        fontSize: 9.5, color: AppColors.textTertiary, fontWeight: FontWeight.w500);
    final valueStyle = GoogleFonts.inter(
        fontSize: 11, color: AppColors.textPrimary, fontWeight: FontWeight.w600);

    Widget col(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: valueStyle, maxLines: 1, softWrap: false),
            ),
          ],
        );

    String fmt(double v) => 'TZS ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primarySoft,
          backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
          child: (avatar == null || avatar.isEmpty)
              ? Text(_initials(name),
                  style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 11.5))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            // Horizontal scroll so large amounts (e.g. TZS 2,000,000) never
            // visually collide with adjacent columns - tap+drag to reveal.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                SizedBox(width: 110, child: col('Pledged', fmt(pledged))),
                const SizedBox(width: 18),
                SizedBox(width: 110, child: col('Paid', fmt(paid))),
                const SizedBox(width: 18),
                SizedBox(width: 110, child: col('Balance', fmt(balance.toDouble()))),
              ]),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 4,
                backgroundColor: AppColors.borderLight,
                valueColor: AlwaysStoppedAnimation<Color>(
                  complete ? const Color(0xFF059669) : AppColors.primary,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$pct%',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700, fontSize: 12,
                  color: const Color(0xFF0F7A4A))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: complete
                  ? const Color(0xFFD6EFE0)
                  : const Color(0xFFFFE9B0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(complete ? 'Complete' : 'Pending',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: complete ? const Color(0xFF0F7A4A) : const Color(0xFFB07A12))),
          ),
        ]),
      ]),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: AppColors.borderLight,
      );

  Widget _statBlock({
    required Widget iconWidget,
    required String label,
    required String value,
    String? sub,
    Color? subColor,
    Widget? customSub,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        iconWidget,
        const SizedBox(height: 6),
        Text(label,
            textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(value,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: GoogleFonts.inter(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.2)),
        ),
        const SizedBox(height: 6),
        if (customSub != null)
          customSub
        else if (sub != null)
          Text(sub,
              textAlign: TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 9, color: subColor ?? AppColors.textTertiary, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _filterPill(String label, _ContribFilter value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: active ? AppColors.primary : AppColors.primary.withOpacity(0.55)),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
                color: active ? Colors.white : AppColors.primary)),
      ),
    );
  }

}
