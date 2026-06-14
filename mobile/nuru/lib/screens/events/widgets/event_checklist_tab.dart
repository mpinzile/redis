import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../core/widgets/nuru_date_time_picker.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/services/events_service.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/l10n/l10n_helper.dart';
import '../../../widgets/app_select.dart';

/// Full redesign - Checklist tab.
/// Flat surfaces, project SVG icons, skeleton loaders, background refresh,
/// progress ring header, filter pills, modern task tile.
class EventChecklistTab extends StatefulWidget {
  final String eventId;
  final String? eventTypeId;
  const EventChecklistTab({super.key, required this.eventId, this.eventTypeId});

  @override
  State<EventChecklistTab> createState() => _EventChecklistTabState();
}

class _EventChecklistTabState extends State<EventChecklistTab>
    with AutomaticKeepAliveClientMixin {
  List<dynamic> _items = [];
  Map<String, dynamic> _summary = {};
  List<dynamic> _templates = [];
  bool _loading = true;
  bool _templatesLoading = false;
  bool _applying = false;
  String _filter = 'all'; // all | pending | in_progress | completed

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadTemplates();
  }

  Future<void> _load({bool background = false}) async {
    if (!background) setState(() => _loading = true);
    final res = await EventsService.getChecklist(widget.eventId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        _items = data?['items'] ?? [];
        _summary = data?['summary'] ?? {};
      }
    });
  }

  Future<void> _loadTemplates() async {
    setState(() => _templatesLoading = true);
    var res = await EventsService.getTemplates(eventTypeId: widget.eventTypeId);
    if (res['success'] == true &&
        (res['data'] is List) &&
        (res['data'] as List).isEmpty &&
        widget.eventTypeId != null) {
      res = await EventsService.getTemplates();
    }
    if (!mounted) return;
    setState(() {
      _templatesLoading = false;
      if (res['success'] == true && res['data'] is List) {
        _templates = res['data'] as List;
      }
    });
  }

  Future<void> _applyTemplate(Map<String, dynamic> template) async {
    setState(() => _applying = true);
    final id = template['id']?.toString() ?? '';
    final res = await EventsService.applyTemplate(widget.eventId, id,
        clearExisting: _items.isEmpty);
    if (!mounted) return;
    setState(() => _applying = false);
    if (res['success'] == true) {
      final added = res['data']?['added'] ?? 0;
      AppSnackbar.success(context, '$added tasks added from template');
      _load(background: true);
    } else {
      AppSnackbar.error(context, res['message'] ?? 'Failed to apply template');
    }
  }

  List<dynamic> get _filtered {
    if (_filter == 'all') return _items;
    return _items.where((i) => (i['status'] ?? 'pending').toString() == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return _skeleton();

    final total = (_summary['total'] ?? _items.length) as int;
    final completed = (_summary['completed'] ?? 0) as int;
    final inProgress = (_summary['in_progress'] ?? 0) as int;
    final pending = (_summary['pending'] ?? math.max(0, total - completed - inProgress)) as int;
    final progress = total == 0 ? 0.0 : completed / total;

    return NuruRefreshIndicator(
      onRefresh: () => _load(background: true),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (total > 0) _progressHeader(progress, completed, inProgress, pending, total),
          if (total > 0) const SizedBox(height: 14),
          if (total > 0) _filterRow(total, completed, inProgress, pending),
          if (total > 0) const SizedBox(height: 12),

          if (_items.isEmpty) ...[
            _emptyState(),
            const SizedBox(height: 16),
          ],

          ..._filtered.map(_taskTile),

          if (_items.isNotEmpty && _filtered.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36),
              alignment: Alignment.center,
              child: Text('No tasks in this view',
                  style: appText(size: 13, color: AppColors.textTertiary)),
            ),

          if (_templates.isNotEmpty) ...[
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 10),
              child: Text('Templates',
                  style: appText(
                      size: 15,
                      weight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
            ..._templates.map((t) => _templateCard(t as Map<String, dynamic>)),
          ],

          if (_templatesLoading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary)),
              ),
            ),

          const SizedBox(height: 16),
          _addButton(),
        ],
      ),
    );
  }

  // ---------- Skeleton ----------
  Widget _skeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // Progress header skeleton: ring + 4 stat tiles
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(children: [
            _skelCircle(96),
            const SizedBox(width: 14),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                    4,
                    (_) => Column(children: [
                          _skelBox(height: 32, width: 32, radius: 10),
                          const SizedBox(height: 6),
                          _skelBox(height: 11, width: 26, radius: 4),
                          const SizedBox(height: 4),
                          _skelBox(height: 9, width: 40, radius: 4),
                        ])),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        // Filter underline tabs skeleton
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderLight)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(children: [
              for (int i = 0; i < 4; i++) ...[
                _skelBox(height: 14, width: 56 + (i * 6).toDouble(), radius: 4),
                const SizedBox(width: 16),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 14),
        // Task tiles
        for (int i = 0; i < 4; i++) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              _skelBox(height: 52, width: 52, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skelBox(height: 12, width: 160, radius: 4),
                      const SizedBox(height: 6),
                      Row(children: [
                        _skelBox(height: 20, width: 70, radius: 999),
                        const SizedBox(width: 6),
                        _skelBox(height: 20, width: 58, radius: 999),
                      ]),
                    ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _skelBox(height: 11, width: 62, radius: 4),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _skelCircle(22),
                  const SizedBox(width: 6),
                  _skelBox(height: 16, width: 16, radius: 4),
                ]),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        // Templates section heading
        const SizedBox(height: 14),
        _skelBox(height: 14, width: 100, radius: 4),
        const SizedBox(height: 12),
        for (int i = 0; i < 2; i++) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(children: [
              _skelBox(height: 52, width: 52, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skelBox(height: 12, width: 140, radius: 4),
                      const SizedBox(height: 8),
                      _skelBox(height: 10, width: 200, radius: 4),
                    ]),
              ),
              const SizedBox(width: 8),
              _skelBox(height: 22, width: 56, radius: 999),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        _skelBox(height: 50, radius: 14),
      ],
    );
  }

  Widget _skelBox({double? width, required double height, double radius = 12}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _skelCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        shape: BoxShape.circle,
      ),
    );
  }

  // ---------- Progress header ----------
  Widget _progressHeader(double p, int done, int prog, int pend, int total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Progress ring
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CircularProgressIndicator(
                  value: p,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.primarySoft,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(p * 100).round()}%',
                    style: appText(
                        size: 20,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 1),
                Text('Planning',
                    style: appText(
                        size: 9.5,
                        weight: FontWeight.w600,
                        color: AppColors.textTertiary)),
                Text('progress',
                    style: appText(
                        size: 9.5,
                        weight: FontWeight.w600,
                        color: AppColors.textTertiary)),
              ]),
            ]),
          ),
          const SizedBox(width: 12),
          // 4 stat tiles row
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _statTile('checklist', total, 'Total tasks',
                    const Color(0xFFFFF1D6), const Color(0xFFD97706)),
                _statTile('double-check', done, 'Done',
                    const Color(0xFFE6F7EC), const Color(0xFF16A34A)),
                _statTileDashed(prog, 'In progress', const Color(0xFF2563EB)),
                _statTile('more-vertical', pend, 'Pending',
                    const Color(0xFFFFE8E0), const Color(0xFFEA580C)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String icon, int n, String label, Color bg, Color fg) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: AppIcon(icon, size: 18, color: fg),
      ),
      const SizedBox(height: 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('$n',
          style: appText(
              size: 16, weight: FontWeight.w800, color: AppColors.textPrimary)),
      ),
      const SizedBox(height: 1),
      Text(label,
          style:
              appText(size: 9.5, color: AppColors.textTertiary, weight: FontWeight.w600)),
    ]);
  }

  Widget _statTileDashed(int n, String label, Color fg) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: fg.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: const Size(18, 18),
          painter: _DashedCirclePainter(color: fg),
        ),
      ),
      const SizedBox(height: 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('$n',
          style: appText(
              size: 16, weight: FontWeight.w800, color: AppColors.textPrimary)),
      ),
      const SizedBox(height: 1),
      Text(label,
          style:
              appText(size: 9.5, color: AppColors.textTertiary, weight: FontWeight.w600)),
    ]);
  }


  // ---------- Filter underline tabs (matches event detail tabs) ----------
  Widget _filterRow(int total, int done, int prog, int pend) {
    final opts = [
      ['all', 'All', total],
      ['completed', 'Done', done],
      ['in_progress', 'In progress', prog],
      ['pending', 'Pending', pend],
    ];
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: opts.map((o) {
            final active = _filter == o[0];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _filter = o[0] as String),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(o[1] as String,
                            style: appText(
                                size: 13,
                                weight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: active
                                    ? AppColors.textPrimary
                                    : AppColors.textTertiary)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primarySoft
                                : AppColors.borderLight.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('${o[2]}',
                              style: appText(
                                  size: 10,
                                  weight: FontWeight.w800,
                                  color: active
                                      ? AppColors.primaryDark
                                      : AppColors.textTertiary)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }


  // ---------- Empty state ----------
  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const AppIcon('checklist', size: 26, color: AppColors.primary),
        ),
        const SizedBox(height: 14),
        Text('Start planning', style: appText(size: 15, weight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          _templates.isNotEmpty
              ? 'Pick a template below or add tasks manually.'
              : 'Add tasks to track every step of your event.',
          style: appText(size: 12, color: AppColors.textTertiary),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  // ---------- Task tile ----------
  Widget _taskTile(dynamic raw) {
    final item = raw as Map<String, dynamic>;
    final title = item['title']?.toString() ?? '';
    final status = (item['status'] ?? 'pending').toString();
    final isDone = status == 'completed';
    // status is also used to render status circle (in_progress shown for items already set server-side)
    final priority = item['priority']?.toString();
    final category = item['category']?.toString();
    final due = item['due_date']?.toString();
    final tone = _categoryTone(category);

    return Dismissible(
      key: ValueKey('task-${item['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const AppIcon('delete', size: 18, color: AppColors.error),
      ),
      onDismissed: (_) => _deleteItem(item['id']?.toString() ?? ''),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showTaskDetail(item),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Category-tinted thumbnail with list icon (matches update modal style)
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tone.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: AppIcon('list', size: 24, color: tone.fg),
            ),
            const SizedBox(width: 12),
            // Title + chips
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appText(
                        size: 14,
                        weight: FontWeight.w500,
                        height: 1.3,
                        color: isDone
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (category != null && category.isNotEmpty)
                        _chip(category, tone.fg, tone.bg),
                      if (priority != null && priority.isNotEmpty)
                        _priorityChip(priority),
                    ]),
                  ]),
            ),
            const SizedBox(width: 8),
            // Date + status circle (tap to quick-toggle) + chevron
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (due != null && due.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const AppIcon('calendar',
                        size: 10, color: AppColors.textTertiary),
                    const SizedBox(width: 3),
                    Text(_formatDateLong(due),
                        style: appText(
                            size: 10.5,
                            weight: FontWeight.w500,
                            color: AppColors.textTertiary)),
                  ]),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        _setStatus(item, isDone ? 'pending' : 'completed'),
                    child: _statusCircle(status),
                  ),
                  const SizedBox(width: 6),
                  const AppIcon('chevron-right',
                      size: 14, color: AppColors.textHint),
                ]),
              ],
            ),
          ]),
        ),
      ),
    );
  }


  Widget _statusCircle(String status) {
    if (status == 'completed') {
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
            color: Color(0xFF16A34A), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const AppIcon('double-check', size: 12, color: Colors.white),
      );
    }
    if (status == 'in_progress') {
      return SizedBox(
        width: 22,
        height: 22,
        child: CustomPaint(
          painter: _DashedCirclePainter(color: const Color(0xFF2563EB)),
        ),
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFEA580C), width: 2)),
    );
  }

  Widget _chip(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: appText(size: 10, weight: FontWeight.w700, color: fg)),
    );
  }

  Widget _priorityChip(String p) {
    final lower = p.toLowerCase();
    Color fg;
    Color bg;
    if (lower == 'high') {
      fg = const Color(0xFFDC2626);
      bg = const Color(0xFFFEE2E2);
    } else if (lower == 'low') {
      fg = const Color(0xFF16A34A);
      bg = const Color(0xFFDCFCE7);
    } else {
      fg = const Color(0xFFD97706);
      bg = const Color(0xFFFEF3C7);
    }
    return _chip(p[0].toUpperCase() + p.substring(1), fg, bg);
  }

  _CategoryTone _categoryTone(String? category) {
    final c = (category ?? '').toLowerCase();
    if (c.contains('decor') || c.contains('flower')) {
      return const _CategoryTone(Color(0xFFFFE8D6), Color(0xFFD97706));
    }
    if (c.contains('transport')) {
      return const _CategoryTone(Color(0xFFDCFCE7), Color(0xFF16A34A));
    }
    if (c.contains('attire') || c.contains('dress')) {
      return const _CategoryTone(Color(0xFFEDE9FE), Color(0xFF7C3AED));
    }
    if (c.contains('plan') || c.contains('coordinat')) {
      return const _CategoryTone(Color(0xFFFFEDD5), Color(0xFFEA580C));
    }
    if (c.contains('cater') || c.contains('food')) {
      return const _CategoryTone(Color(0xFFFCE7F3), Color(0xFFDB2777));
    }
    if (c.contains('photo') || c.contains('video')) {
      return const _CategoryTone(Color(0xFFDBEAFE), Color(0xFF2563EB));
    }
    if (c.contains('music') || c.contains('entertain')) {
      return const _CategoryTone(Color(0xFFFEF3C7), Color(0xFFD97706));
    }
    if (c.contains('venue')) {
      return const _CategoryTone(Color(0xFFCFFAFE), Color(0xFF0891B2));
    }
    if (c.contains('budget')) {
      return const _CategoryTone(Color(0xFFD1FAE5), Color(0xFF059669));
    }
    if (c.contains('invit')) {
      return const _CategoryTone(Color(0xFFE0E7FF), Color(0xFF4F46E5));
    }
    return _CategoryTone(AppColors.primarySoft, AppColors.primary);
  }


  // ---------- Templates ----------
  Widget _templateCard(Map<String, dynamic> t) {
    final name = t['name']?.toString() ?? 'Template';
    final desc = t['description']?.toString();
    final count = t['task_count'] ??
        (t['tasks'] is List ? (t['tasks'] as List).length : 0);
    return GestureDetector(
      onTap: _applying ? null : () => _showTemplatePreview(t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Colorful template thumbnail - inline SVG (original colors preserved)
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: const Color(0xFFFFF8EC),
                borderRadius: BorderRadius.circular(14)),
            alignment: Alignment.center,
            child: SvgPicture.string(
              _kTemplateDocSvg,
              width: 34,
              height: 34,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: appText(
                        size: 14,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(desc,
                      style: appText(
                          size: 11.5,
                          color: AppColors.textTertiary,
                          height: 1.35),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ])),
          const SizedBox(width: 8),
          Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text('$count tasks',
                      style: appText(
                          size: 10.5,
                          weight: FontWeight.w800,
                          color: AppColors.primary)),
                ),
                const SizedBox(height: 6),
                const AppIcon('chevron-right',
                    size: 14, color: AppColors.textHint),
              ]),
        ]),
      ),
    );
  }

  // ---------- Template preview sheet ----------
  void _showTemplatePreview(Map<String, dynamic> t) {
    final name = t['name']?.toString() ?? 'Template';
    final desc = t['description']?.toString();
    final tasks = (t['tasks'] is List) ? (t['tasks'] as List) : const [];
    final count = t['task_count'] ?? tasks.length;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(children: [
              // grab handle
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              // header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: Row(children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFF8EC),
                        borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: SvgPicture.string(_kTemplateDocSvg,
                        width: 36, height: 36),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: appText(
                                  size: 17,
                                  weight: FontWeight.w800,
                                  color: AppColors.textPrimary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(999)),
                              child: Text('$count tasks',
                                  style: appText(
                                      size: 10.5,
                                      weight: FontWeight.w800,
                                      color: AppColors.primary)),
                            ),
                            const SizedBox(width: 8),
                            Text('Preview',
                                style: appText(
                                    size: 11.5,
                                    weight: FontWeight.w600,
                                    color: AppColors.textTertiary)),
                          ]),
                        ]),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const AppIcon('close',
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                ]),
              ),
              if (desc != null && desc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(desc,
                      style: appText(
                          size: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.4)),
                ),
              const Divider(height: 1),
              // task list
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '$count tasks will be added to your checklist.',
                            textAlign: TextAlign.center,
                            style: appText(
                                size: 13,
                                color: AppColors.textTertiary,
                                height: 1.5),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding:
                            const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final task = tasks[i] as Map<String, dynamic>;
                          final title = task['title']?.toString() ??
                              task['name']?.toString() ??
                              'Task';
                          final cat = task['category']?.toString();
                          final tone = _categoryTone(cat);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppColors.borderLight),
                            ),
                            child: Row(children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: tone.bg,
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text('${i + 1}',
                                    style: appText(
                                        size: 11.5,
                                        weight: FontWeight.w800,
                                        color: tone.fg)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(title,
                                    style: appText(
                                        size: 13,
                                        weight: FontWeight.w600,
                                        color: AppColors.textPrimary),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (cat != null && cat.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: tone.bg,
                                      borderRadius:
                                          BorderRadius.circular(999)),
                                  child: Text(cat,
                                      style: appText(
                                          size: 10,
                                          weight: FontWeight.w700,
                                          color: tone.fg)),
                                ),
                              ],
                            ]),
                          );
                        },
                      ),
              ),
              // footer actions
              Container(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, 16 + MediaQuery.of(ctx).padding.bottom),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                      top: BorderSide(color: AppColors.borderLight)),
                ),
                child: Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.borderLight),
                        ),
                        alignment: Alignment.center,
                        child: Text('Cancel',
                            style: appText(
                                size: 14,
                                weight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _confirmApplyTemplate(t);
                      },
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.primary
                                    .withOpacity(0.25),
                                blurRadius: 14,
                                offset: const Offset(0, 6)),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppIcon('plus',
                                  size: 16, color: Colors.white),
                              const SizedBox(width: 8),
                              Text('Use this template',
                                  style: appText(
                                      size: 14,
                                      weight: FontWeight.w800,
                                      color: Colors.white)),
                            ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }



  void _confirmApplyTemplate(Map<String, dynamic> t) {
    if (_items.isEmpty) {
      _applyTemplate(t);
      return;
    }
    final name = t['name']?.toString() ?? 'Template';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Apply template',
            style: appText(size: 17, weight: FontWeight.w700)),
        content: Text('Add tasks from "$name" to your existing checklist?',
            style: appText(size: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: appText(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.textTertiary))),
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _applyTemplate(t);
              },
              child: Text('Apply',
                  style: appText(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.primary))),
        ],
      ),
    );
  }

  Widget _addButton() {
    return GestureDetector(
      onTap: _showAddSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const AppIcon('plus', size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Text('Add task',
              style: appText(
                  size: 15, weight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }

  // ---------- Helpers ----------
  String _formatDate(String s) {
    try {
      final d = DateTime.parse(s);
      const m = [
        'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
      ];
      return '${m[d.month - 1]} ${d.day}';
    } catch (_) {
      return s;
    }
  }

  Future<void> _setStatus(Map<String, dynamic> item, String newStatus) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final old = item['status'];
    setState(() => item['status'] = newStatus);
    final res = await EventsService.updateChecklistItem(
        widget.eventId, id, {'status': newStatus});
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() => item['status'] = old);
      AppSnackbar.error(context, res['message'] ?? 'Failed');
    } else {
      // refresh summary in background
      _load(background: true);
    }
  }

  Future<void> _deleteItem(String id) async {
    if (id.isEmpty) return;
    final idx = _items.indexWhere((i) => i['id']?.toString() == id);
    final removed = idx >= 0 ? _items[idx] : null;
    if (idx >= 0) setState(() => _items.removeAt(idx));
    final res = await EventsService.deleteChecklistItem(widget.eventId, id);
    if (!mounted) return;
    if (res['success'] == true) {
      AppSnackbar.success(context, 'Task removed');
      _load(background: true);
    } else {
      if (removed != null && idx >= 0) {
        setState(() => _items.insert(idx, removed));
      }
      AppSnackbar.error(context, res['message'] ?? 'Failed');
    }
  }

  // ---------- Task detail sheet ----------
  void _showTaskDetail(Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? '';
    final description = item['description']?.toString() ?? '';
    final category = item['category']?.toString() ?? '';
    final priority = item['priority']?.toString() ?? '';
    final due = item['due_date']?.toString() ?? '';
    final assignee = item['assignee_name']?.toString() ??
        item['assigned_to_name']?.toString() ??
        '';
    final tone = _categoryTone(category);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final status = (item['status'] ?? 'pending').toString();
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                          color: tone.bg,
                          borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: AppIcon('list', size: 24, color: tone.fg),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: appText(
                                  size: 17,
                                  weight: FontWeight.w600,
                                  height: 1.3)),
                          if (category.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _chip(category, tone.fg, tone.bg),
                          ],
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 22),
                  Text('Status',
                      style: appText(
                          size: 12,
                          weight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  // Segmented control
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _statusSeg('pending', 'Pending', status, (v) async {
                          setSheetState(() => item['status'] = v);
                          await _setStatus(item, v);
                        }),
                        _statusSeg('in_progress', 'In progress', status,
                            (v) async {
                          setSheetState(() => item['status'] = v);
                          await _setStatus(item, v);
                        }),
                        _statusSeg('completed', 'Done', status, (v) async {
                          setSheetState(() => item['status'] = v);
                          await _setStatus(item, v);
                        }),
                      ],
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text('Description',
                        style: appText(
                            size: 12,
                            weight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text(description,
                        style: appText(
                            size: 14,
                            weight: FontWeight.w400,
                            height: 1.45,
                            color: AppColors.textPrimary)),
                  ],
                  const SizedBox(height: 22),
                  _detailRow('calendar', 'Due date',
                      due.isEmpty ? 'Not set' : _formatDateLong(due)),
                  const SizedBox(height: 12),
                  _detailRow('star', 'Priority',
                      priority.isEmpty ? 'Normal' : (priority[0].toUpperCase() + priority.substring(1))),
                  const SizedBox(height: 12),
                  _detailRow('user', 'Assignee',
                      assignee.isEmpty ? 'Unassigned' : assignee),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteItem(item['id']?.toString() ?? '');
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                              color: AppColors.error.withOpacity(0.4)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999)),
                        ),
                        icon: const AppIcon('delete',
                            size: 16, color: AppColors.error),
                        label: Text('Delete',
                            style: appText(
                                size: 13,
                                weight: FontWeight.w700,
                                color: AppColors.error)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999)),
                        ),
                        child: Text('Done',
                            style: appText(
                                size: 13,
                                weight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusSeg(String value, String label, String current,
      ValueChanged<String> onPick) {
    final active = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onPick(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Text(label,
              style: appText(
                  size: 12.5,
                  weight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.textTertiary)),
        ),
      ),
    );
  }

  Widget _detailRow(String icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: AppIcon(icon, size: 16, color: AppColors.textSecondary),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: appText(
                    size: 11,
                    weight: FontWeight.w600,
                    color: AppColors.textTertiary)),
            const SizedBox(height: 2),
            Text(value,
                style: appText(
                    size: 14,
                    weight: FontWeight.w500,
                    color: AppColors.textPrimary)),
          ],
        ),
      ),
    ]);
  }


  static const List<String> _categories = [
    'Venue','Catering','Decorations','Photography','Music & Entertainment',
    'Invitations','Transport','Attire','Budget','Coordination','Other',
  ];

  void _showAddSheet() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String category = '';
    String priority = 'medium';
    DateTime? dueDate;
    String? assignedTo;
    String? assignedName;
    List<dynamic> members = [];
    bool membersLoaded = false;
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        if (!membersLoaded) {
          membersLoaded = true;
          EventsService.getAssignableMembers(widget.eventId).then((res) {
            if (ctx.mounted && res['success'] == true) {
              setSheetState(() =>
                  members = res['data'] is List ? res['data'] as List : []);
            }
          });
        }
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, scrollCtrl) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 10, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: ListView(controller: scrollCtrl, children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const AppIcon('checklist',
                      size: 22, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New task',
                            style: appText(
                                size: 18, weight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('Add a step to your event checklist',
                            style: appText(
                                size: 12, color: AppColors.textTertiary)),
                      ]),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const AppIcon('close',
                        size: 14, color: AppColors.textSecondary),
                  ),
                ),
              ]),
              const SizedBox(height: 22),
              _label('Title'),
              _input(titleCtrl, 'e.g. Book venue', autofocus: true),
              const SizedBox(height: 16),
              _label('Description'),
              _input(descCtrl, 'Optional details', maxLines: 2),
              const SizedBox(height: 18),
              _label('Category'),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final c = _categories[i];
                    final active = category == c;
                    final tone = _categoryTone(c);
                    return GestureDetector(
                      onTap: () => setSheetState(
                          () => category = active ? '' : c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? tone.bg : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: active
                                  ? tone.fg.withOpacity(0.4)
                                  : AppColors.borderLight),
                        ),
                        child: Text(c,
                            style: appText(
                                size: 12,
                                weight: FontWeight.w700,
                                color: active
                                    ? tone.fg
                                    : AppColors.textSecondary)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              _label('Priority'),
              Row(children: [
                for (final entry in const [
                  ['low', 'Low', Color(0xFF16A34A), Color(0xFFDCFCE7)],
                  ['medium', 'Medium', Color(0xFFD97706), Color(0xFFFEF3C7)],
                  ['high', 'High', Color(0xFFDC2626), Color(0xFFFEE2E2)],
                ]) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setSheetState(
                          () => priority = entry[0] as String),
                      child: Container(
                        margin: EdgeInsets.only(
                            right: entry[0] == 'high' ? 0 : 8),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: priority == entry[0]
                              ? entry[3] as Color
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: priority == entry[0]
                                  ? (entry[2] as Color).withOpacity(0.4)
                                  : AppColors.borderLight),
                        ),
                        child: Text(entry[1] as String,
                            style: appText(
                                size: 13,
                                weight: FontWeight.w800,
                                color: priority == entry[0]
                                    ? entry[2] as Color
                                    : AppColors.textSecondary)),
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 18),
              _label('Due date'),
              GestureDetector(
                onTap: () async {
                  final d = await showNuruDatePicker(
                    context: ctx,
                    initialDate:
                        dueDate ?? DateTime.now().add(const Duration(days: 7)),
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 30)),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365 * 2)),
                  );
                  if (d != null) setSheetState(() => dueDate = d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(children: [
                    AppIcon('calendar',
                        size: 16,
                        color: dueDate != null
                            ? AppColors.primary
                            : AppColors.textHint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        dueDate != null
                            ? _formatDateLong(dueDate!.toIso8601String())
                            : 'Pick a date',
                        style: appText(
                            size: 13,
                            weight: FontWeight.w600,
                            color: dueDate != null
                                ? AppColors.textPrimary
                                : AppColors.textHint),
                      ),
                    ),
                    if (dueDate != null)
                      GestureDetector(
                        onTap: () => setSheetState(() => dueDate = null),
                        child: const AppIcon('close',
                            size: 14, color: AppColors.textHint),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              _label('Assign to'),
              if (assignedTo != null && assignedName != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primary.withOpacity(0.2),
                        child: Text(assignedName![0].toUpperCase(),
                            style: appText(
                                size: 11,
                                weight: FontWeight.w700,
                                color: AppColors.primary))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(assignedName!,
                            style:
                                appText(size: 13, weight: FontWeight.w600))),
                    GestureDetector(
                      onTap: () => setSheetState(() {
                        assignedTo = null;
                        assignedName = null;
                      }),
                      child: const AppIcon('close',
                          size: 14, color: AppColors.textHint),
                    ),
                  ]),
                )
              else
                _dropdown<String>(
                  value: null,
                  hint: 'Select member',
                  items: members.map((m) {
                    final mm = m as Map<String, dynamic>;
                    final name = mm['full_name']?.toString() ??
                        '${mm['first_name'] ?? ''} ${mm['last_name'] ?? ''}'
                            .trim();
                    return DropdownMenuItem(
                        value: mm['id']?.toString(), child: Text(name));
                  }).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final m = members.firstWhere(
                        (e) => (e as Map)['id']?.toString() == v,
                        orElse: () => null);
                    if (m != null) {
                      final mm = m as Map<String, dynamic>;
                      setSheetState(() {
                        assignedTo = v;
                        assignedName = mm['full_name']?.toString() ??
                            '${mm['first_name'] ?? ''} ${mm['last_name'] ?? ''}'
                                .trim();
                      });
                    }
                  },
                ),
              const SizedBox(height: 18),
              _label('Notes'),
              _input(notesCtrl, 'Optional notes', maxLines: 2),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (titleCtrl.text.trim().isEmpty) return;
                          setSheetState(() => submitting = true);
                          final data = <String, dynamic>{
                            'title': titleCtrl.text.trim(),
                            if (descCtrl.text.trim().isNotEmpty)
                              'description': descCtrl.text.trim(),
                            if (category.isNotEmpty) 'category': category,
                            'priority': priority,
                            if (dueDate != null)
                              'due_date':
                                  '${dueDate!.year}-${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}',
                            if (assignedTo != null) 'assigned_to': assignedTo,
                            if (notesCtrl.text.trim().isNotEmpty)
                              'notes': notesCtrl.text.trim(),
                          };
                          Navigator.pop(ctx);
                          final res = await EventsService.addChecklistItem(
                              widget.eventId, data);
                          if (mounted) {
                            if (res['success'] == true) {
                              AppSnackbar.success(context, 'Task added');
                              _load(background: true);
                            } else {
                              AppSnackbar.error(
                                  context, res['message'] ?? 'Failed');
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: AppColors.primary.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const AppIcon('plus',
                                size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            Text('Add task',
                                style: appText(
                                    size: 15,
                                    weight: FontWeight.w800,
                                    color: Colors.white)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
            ]),
          ),
        );
      }),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: appText(
                size: 12,
                weight: FontWeight.w700,
                color: AppColors.textSecondary)),
      );

  Widget _input(TextEditingController c, String hint,
      {int maxLines = 1, bool autofocus = false}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      autofocus: autofocus,
      style: appText(size: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: appText(size: 13, color: AppColors.textHint),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.borderLight)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.borderLight)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _dropdown<T>({
    required T? value,
    String? hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return AppSelect.fromItems<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      hint: hint,
      title: hint,
      borderRadius: 14,
      fontSize: 13,
    );
  }
}

class _CategoryTone {
  final Color bg;
  final Color fg;
  const _CategoryTone(this.bg, this.fg);
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  _DashedCirclePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    const dashCount = 10;
    const sweep = (2 * math.pi) / dashCount;
    const dash = sweep * 0.55;
    for (int i = 0; i < dashCount; i++) {
      final start = i * sweep;
      canvas.drawArc(rect.deflate(1), start, dash, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _formatDateLong(String s) {
  try {
    final d = DateTime.parse(s);
    const m = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  } catch (_) {
    return s;
  }
}


// Inline colorful template document SVG (preserves original colors).
const String _kTemplateDocSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
    '<path d="M899.984 19.873h-3.452c-26.123 0-47.296 21.172-47.296 47.296v888.508c0 26.127 21.173 47.298 47.296 47.298h3.452c26.119 0 47.297-21.171 47.297-47.298V67.169c0-26.124-21.177-47.296-47.297-47.296z" fill="#4A5699"/>'
    '<path d="M132.643 19.873h-3.449c-26.12 0-47.296 21.172-47.296 47.296v888.508c0 26.127 21.177 47.298 47.296 47.298h3.449c26.123 0 47.299-21.171 47.299-47.298V67.169c0-26.124-21.176-47.296-47.299-47.296z" fill="#C45FA0"/>'
    '<path d="M899.463 19.873H129.194c-26.12 0-47.296 21.172-47.296 47.296v3.377c0 26.12 21.177 47.299 47.296 47.299h770.269c26.123 0 47.296-21.179 47.296-47.299v-3.377c0-26.124-21.173-47.296-47.296-47.296z" fill="#6277BA"/>'
    '<path d="M899.463 905.006H129.194c-26.12 0-47.296 21.17-47.296 47.29v3.381c0 26.127 21.177 47.298 47.296 47.298h770.269c26.123 0 47.296-21.171 47.296-47.298v-3.381c0-26.12-21.173-47.29-47.296-47.29z" fill="#C45FA0"/>'
    '<path d="M717.962 543.153H542.047c-26.121 0-47.298 21.175-47.298 47.297v3.724c0 26.123 21.177 47.293 47.298 47.293h175.915c26.121 0 47.297-21.17 47.297-47.293v-3.724c0-26.122-21.176-47.297-47.297-47.297z" fill="#E5594F"/>'
    '<path d="M689.268 198.849H513.355c-26.122 0-47.298 21.175-47.298 47.297v3.722c0 26.12 21.176 47.297 47.298 47.297h175.912c26.122 0 47.298-21.177 47.298-47.297v-3.722c0-26.122-21.175-47.297-47.297-47.297z" fill="#F0D043"/>'
    '<path d="M757.789 353.081H261.17c-26.121 0-47.297 21.172-47.297 47.296v3.377c0 26.121 21.177 47.299 47.297 47.299h496.619c26.121 0 47.296-21.178 47.296-47.299v-3.377c0-26.125-21.175-47.296-47.296-47.296z" fill="#E5594F"/>'
    '<path d="M762.638 726.225h-496.62c-26.12 0-47.294 21.18-47.294 47.301v3.377c0 26.12 21.174 47.3 47.294 47.3h496.62c26.122 0 47.296-21.18 47.296-47.3v-3.377c0-26.122-21.174-47.301-47.296-47.301z" fill="#6277BA"/>'
    '<path d="M355.734 543.328H281.41c-26.122 0-47.297 21.17-47.297 47.293v3.378c0 26.118 21.175 47.297 47.297 47.297h74.324c26.123 0 47.296-21.179 47.296-47.297v-3.378c0-26.123-21.174-47.293-47.296-47.293z" fill="#F39A2B"/>'
    '<circle cx="334.85" cy="248.006" r="48.986" fill="#F39A2B"/>'
    '</svg>';
