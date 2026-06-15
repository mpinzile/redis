import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/widgets/amount_input.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/services/events_service.dart';
import '../../../core/services/report_generator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/deleting_overlay.dart';
import '../../../core/l10n/l10n_helper.dart';
import '../report_preview_screen.dart';
import '../../../widgets/app_select.dart';

/// Full redesign - Budget tab.
/// Flat surfaces, project SVG icons, skeleton loader, header summary with
/// progress ring (actual vs estimated), status filter pills, modern item cards.
const _kCategories = [
  'Venue','Catering','Decorations','Entertainment','Photography','Transport',
  'Printing','Gifts & Favors','Equipment Rental','Marketing','Staffing',
  'Audio & Visual','Flowers','Invitations','Security','Miscellaneous',
];

const _kStatusOptions = [
  {'value': 'pending', 'label': 'Pending', 'color': Color(0xFFD97706)},
  {'value': 'deposit_paid', 'label': 'Deposit', 'color': Color(0xFF2471E7)},
  {'value': 'paid', 'label': 'Paid', 'color': Color(0xFF16A34A)},
];

class EventBudgetTab extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic>? permissions;
  final String? eventTitle;
  final double? eventBudget;
  const EventBudgetTab({
    super.key,
    required this.eventId,
    this.permissions,
    this.eventTitle,
    this.eventBudget,
  });

  @override
  State<EventBudgetTab> createState() => _EventBudgetTabState();
}

class _EventBudgetTabState extends State<EventBudgetTab>
    with AutomaticKeepAliveClientMixin {
  List<dynamic> _items = [];
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  bool _deleting = false;
  String _filter = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool background = false}) async {
    if (!background) setState(() => _loading = true);
    final res = await EventsService.getBudget(widget.eventId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _items = res['data']?['items'] ?? res['data']?['budget_items'] ?? [];
        _summary = res['data']?['summary'] ?? {};
      }
    });
  }

  List<dynamic> get _filtered {
    if (_filter == 'all') return _items;
    return _items
        .where((i) => (i['status'] ?? 'pending').toString() == _filter)
        .toList();
  }

  bool get _canManage =>
      widget.permissions?['can_manage_budget'] == true ||
      widget.permissions?['is_creator'] == true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return _skeleton();

    final estimated = _asNum(_summary['total_estimated']);
    final actual = _asNum(_summary['total_actual']);
    final variance =
        _summary['variance'] != null ? _asNum(_summary['variance']) : estimated - actual;
    final progress = estimated > 0 ? (actual / estimated).clamp(0.0, 1.0) : 0.0;

    final paidCount =
        _items.where((i) => (i['status'] ?? '') == 'paid').length;
    final pendingCount =
        _items.where((i) => (i['status'] ?? 'pending') == 'pending').length;
    final depositCount =
        _items.where((i) => (i['status'] ?? '') == 'deposit_paid').length;

    return Stack(children: [
      NuruRefreshIndicator(
        onRefresh: () => _load(background: true),
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (_summary.isNotEmpty || _items.isNotEmpty)
              _summaryHeader(estimated, actual, variance, progress),
            const SizedBox(height: 14),
            _exportRow(),
            const SizedBox(height: 18),
            _filterRow(_items.length, pendingCount, depositCount, paidCount),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              _emptyState()
            else if (_filtered.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36),
                alignment: Alignment.center,
                child: Text('No items in this view',
                    style: appText(size: 13, color: AppColors.textTertiary)),
              )
            else
              ..._filtered.map((i) => _itemCard(i as Map<String, dynamic>)),
            if (_canManage) ...[
              const SizedBox(height: 16),
              _addButton(),
            ],
          ],
        ),
      ),
      DeletingOverlay(visible: _deleting),
    ]);
  }

  // ---------- Skeleton ----------
  Widget _skeleton() {
    Widget summaryHeader() => Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.borderLight, width: 7),
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    _skel(height: 16, width: 34, radius: 4),
                    const SizedBox(height: 6),
                    _skel(height: 8, width: 28, radius: 4),
                  ]),
                ]),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _skel(height: 10, width: 70, radius: 4),
                  const SizedBox(height: 8),
                  _skel(height: 20, width: 150, radius: 5),
                  const SizedBox(height: 12),
                  Row(children: [
                    _skel(height: 12, width: 12, radius: 4),
                    const SizedBox(width: 6),
                    _skel(height: 12, width: 118, radius: 4),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Container(height: 1, color: AppColors.borderLight),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _metricSkeleton()),
              Container(width: 1, height: 34, color: AppColors.borderLight),
              Expanded(child: _metricSkeleton()),
            ]),
          ]),
        );

    Widget itemCard() => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _skel(height: 56, width: 56, radius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _skel(height: 11, width: 72, radius: 4),
                const SizedBox(height: 8),
                _skel(height: 14, width: 170, radius: 4),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _skel(height: 4, radius: 999)),
                  const SizedBox(width: 8),
                  _skel(height: 10, width: 48, radius: 4),
                ]),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _skel(height: 28, width: 92, radius: 10),
              const SizedBox(height: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _skel(height: 22, width: 74, radius: 999),
                const SizedBox(width: 4),
                _skel(height: 14, width: 14, radius: 4),
              ]),
            ]),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        summaryHeader(),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _skel(height: 46, radius: 14)),
          const SizedBox(width: 10),
          Expanded(child: _skel(height: 46, radius: 14)),
        ]),
        const SizedBox(height: 18),
        // Underline tabs skeleton
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
                _skel(height: 14, width: 56 + (i * 6).toDouble(), radius: 4),
                const SizedBox(width: 16),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 14),
        for (int i = 0; i < 4; i++) ...[
          itemCard(),
          const SizedBox(height: 10),
        ],
        _skel(height: 50, radius: 14),
      ],
    );
  }


  Widget _skel({double? width, required double height, double radius = 12}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
            color: AppColors.borderLight,
            borderRadius: BorderRadius.circular(radius)),
      );

  Widget _metricSkeleton() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _skel(height: 12, width: 12, radius: 4),
            const SizedBox(width: 5),
            _skel(height: 10, width: 58, radius: 4),
          ]),
          const SizedBox(height: 6),
          _skel(height: 14, width: 86, radius: 4),
        ]),
      );

  // ---------- Header summary ----------
  Widget _summaryHeader(double est, double act, double variance, double p) {
    final overBudget = act > est && est > 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 76,
                height: 76,
                child: CircularProgressIndicator(
                  value: p,
                  strokeWidth: 7,
                  backgroundColor: AppColors.borderLight,
                  valueColor: AlwaysStoppedAnimation(
                      overBudget ? AppColors.error : AppColors.primary),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(p * 100).round()}%',
                    style: appText(size: 16, weight: FontWeight.w800)),
                Text('spent',
                    style: appText(
                        size: 10,
                        color: AppColors.textTertiary,
                        weight: FontWeight.w600)),
              ]),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estimated',
                      style: appText(
                          size: 11,
                          color: AppColors.textTertiary,
                          weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_money(est),
                      style:
                          appText(size: 19, weight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Row(children: [
                    const AppIcon('wallet', size: 12, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('Actual ${_money(act)}',
                        style: appText(
                            size: 12,
                            color: AppColors.textSecondary,
                            weight: FontWeight.w600)),
                  ]),
                ]),
          ),
        ]),
        const SizedBox(height: 16),
        Container(height: 1, color: AppColors.borderLight),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _metric(
                  'Variance',
                  _money(variance.abs()),
                  variance >= 0 ? AppColors.success : AppColors.error,
                  variance >= 0 ? 'trending-up' : 'warning')),
          Container(width: 1, height: 34, color: AppColors.borderLight),
          Expanded(
              child: _metric('Items', '${_items.length}',
                  AppColors.textPrimary, 'package')),
        ]),
      ]),
    );
  }

  Widget _metric(String label, String value, Color color, String icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AppIcon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: appText(
                  size: 11,
                  color: AppColors.textTertiary,
                  weight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        Text(value,
            style: appText(size: 14, weight: FontWeight.w800, color: color)),
      ]),
    );
  }

  // ---------- Export row ----------
  Widget _exportRow() {
    return Row(children: [
      Expanded(
          child: _exportBtn(
              'PDF', 'pdf-file-type', () => _download('pdf'))),
      const SizedBox(width: 10),
      Expanded(
          child: _exportBtn(
              'Excel', 'excel-document', () => _download('xlsx'))),
    ]);
  }

  Widget _exportBtn(String label, String icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          AppIcon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: appText(size: 13, weight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ]),
      ),
    );
  }

  // ---------- Filter underline tabs ----------
  Widget _filterRow(int total, int pend, int dep, int paid) {
    final opts = [
      ['all', 'All', total],
      ['pending', 'Pending', pend],
      ['deposit_paid', 'Deposit', dep],
      ['paid', 'Paid', paid],
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
          child:
              const Center(child: AppIcon('wallet', size: 26, color: AppColors.primary)),
        ),
        const SizedBox(height: 14),
        Text('No budget yet', style: appText(size: 15, weight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Plan how every shilling will be spent for this event.',
            style: appText(size: 12, color: AppColors.textTertiary),
            textAlign: TextAlign.center),
      ]),
    );
  }

  // ---------- Item card (matches mockup) ----------
  Widget _itemCard(Map<String, dynamic> item) {
    final actualNum = _asNum(item['actual_cost']);
    final estNum = _asNum(item['estimated_cost']);
    final isEstimate = actualNum == 0;
    final effective = isEstimate ? estNum : actualNum;
    final status = (item['status'] ?? 'pending').toString();
    final s = _kStatusOptions.firstWhere(
        (x) => x['value'] == status,
        orElse: () => _kStatusOptions.first);
    final category = item['category']?.toString() ?? '';
    final name = item['description']?.toString() ??
        item['item_name']?.toString() ??
        'Item';
    final tone = _categoryTone(category);
    final usedPct = estNum > 0 ? (actualNum / estNum).clamp(0.0, 1.0) : 0.0;
    final statusIcon = status == 'paid'
        ? 'check'
        : status == 'deposit_paid'
            ? 'credit-card'
            : 'clock';

    return Dismissible(
      key: ValueKey('budget-${item['id']}'),
      direction: _canManage
          ? DismissDirection.endToStart
          : DismissDirection.none,
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
        onTap: () => _showItemDetail(item),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Tinted category thumbnail (list icon, colored per category)
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: tone.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: AppIcon('list', size: 24, color: tone.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (category.isNotEmpty)
                    Text(category.toUpperCase(),
                        style: appText(
                            size: 11,
                            weight: FontWeight.w700,
                            color: tone.fg,
                            height: 1.1)),
                  const SizedBox(height: 4),
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appText(
                          size: 13.5,
                          weight: FontWeight.w500,
                          height: 1.35,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  // % used bar
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: usedPct,
                          minHeight: 4,
                          backgroundColor: AppColors.borderLight,
                          valueColor: AlwaysStoppedAnimation(tone.fg),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${(usedPct * 100).round()}% used',
                        style: appText(
                            size: 10,
                            weight: FontWeight.w500,
                            color: AppColors.textTertiary)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Amount + status pill + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: tone.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_money(effective),
                      style: appText(
                          size: 12.5,
                          weight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (s['color'] as Color).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child:
                        Row(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon(statusIcon,
                          size: 10, color: s['color'] as Color),
                      const SizedBox(width: 4),
                      Text(s['label'] as String,
                          style: appText(
                              size: 10,
                              weight: FontWeight.w700,
                              color: s['color'] as Color)),
                    ]),
                  ),
                  const SizedBox(width: 4),
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

  // ---------- Item detail sheet ----------
  void _showItemDetail(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final category = item['category']?.toString() ?? '';
    final name = item['description']?.toString() ??
        item['item_name']?.toString() ??
        'Item';
    final vendor = item['vendor_name']?.toString() ?? '';
    final notes = item['notes']?.toString() ?? '';
    final est = _asNum(item['estimated_cost']);
    final act = _asNum(item['actual_cost']);
    final pct = est > 0 ? (act / est).clamp(0.0, 1.0) : 0.0;
    final variance = est - act;
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
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                          color: tone.bg,
                          borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: AppIcon('list', size: 26, color: tone.fg),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (category.isNotEmpty)
                            Text(category.toUpperCase(),
                                style: appText(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: tone.fg)),
                          const SizedBox(height: 4),
                          Text(name,
                              style: appText(
                                  size: 17,
                                  weight: FontWeight.w600,
                                  height: 1.3)),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  // Spend stats row
                  Row(children: [
                    Expanded(
                      child: _spendStat('Estimated', _money(est),
                          AppColors.textSecondary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _spendStat('Actual', _money(act), tone.fg),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _spendStat(
                          variance >= 0 ? 'Under' : 'Over',
                          _money(variance.abs()),
                          variance >= 0
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  // Progress
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor: AppColors.borderLight,
                          valueColor: AlwaysStoppedAnimation(tone.fg),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${(pct * 100).round()}% of estimate',
                        style: appText(
                            size: 11,
                            weight: FontWeight.w600,
                            color: AppColors.textTertiary)),
                  ]),
                  const SizedBox(height: 22),
                  Text('Payment status',
                      style: appText(
                          size: 12,
                          weight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                      'A manual tag for tracking. Update it as you pay this vendor.',
                      style: appText(
                          size: 11,
                          color: AppColors.textTertiary,
                          height: 1.4)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: _kStatusOptions.map((o) {
                        final v = o['value'] as String;
                        final label = o['label'] as String;
                        final active = status == v;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (id.isEmpty || active) return;
                              setSheetState(() => item['status'] = v);
                              final res =
                                  await EventsService.updateBudgetItem(
                                      widget.eventId, id, {'status': v});
                              if (!mounted) return;
                              if (res['success'] != true) {
                                setSheetState(() => item['status'] = status);
                                AppSnackbar.error(context,
                                    res['message'] ?? 'Failed to update');
                              } else {
                                _load(background: true);
                              }
                            },
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
                                      weight: active
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: active
                                          ? (o['color'] as Color)
                                          : AppColors.textTertiary)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (vendor.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _detailRow('user', 'Vendor / supplier', vendor),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('Notes',
                        style: appText(
                            size: 12,
                            weight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text(notes,
                        style: appText(
                            size: 14,
                            weight: FontWeight.w400,
                            height: 1.45,
                            color: AppColors.textPrimary)),
                  ],
                  const SizedBox(height: 24),
                  if (_canManage)
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteItem(id);
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

  Widget _spendStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: appText(
                size: 10.5,
                weight: FontWeight.w600,
                color: AppColors.textTertiary)),
        const SizedBox(height: 3),
        Text(value,
            style: appText(size: 13, weight: FontWeight.w700, color: color)),
      ]),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        ]),
      ),
    ]);
  }


  // Category color tones (mirrors checklist tab palette)
  _CategoryTone _categoryTone(String? category) {
    final c = (category ?? '').toLowerCase();
    if (c.contains('decor') || c.contains('flower')) {
      return const _CategoryTone(Color(0xFFEDE9FE), Color(0xFF7C3AED));
    }
    if (c.contains('transport')) {
      return const _CategoryTone(Color(0xFFDCFCE7), Color(0xFF16A34A));
    }
    if (c.contains('attire') || c.contains('dress')) {
      return const _CategoryTone(Color(0xFFFEF3C7), Color(0xFFD97706));
    }
    if (c.contains('contingency') || c.contains('misc')) {
      return const _CategoryTone(Color(0xFFD1FAE5), Color(0xFF059669));
    }
    if (c.contains('cater') || c.contains('food')) {
      return const _CategoryTone(Color(0xFFFEE2E2), Color(0xFFDC2626));
    }
    if (c.contains('photo') || c.contains('video') || c.contains('audio')) {
      return const _CategoryTone(Color(0xFFDBEAFE), Color(0xFF2563EB));
    }
    if (c.contains('music') || c.contains('entertain')) {
      return const _CategoryTone(Color(0xFFFCE7F3), Color(0xFFDB2777));
    }
    if (c.contains('venue')) {
      return const _CategoryTone(Color(0xFFCFFAFE), Color(0xFF0891B2));
    }
    if (c.contains('invit') || c.contains('print') || c.contains('market')) {
      return const _CategoryTone(Color(0xFFE0E7FF), Color(0xFF4F46E5));
    }
    if (c.contains('gift') || c.contains('favor')) {
      return const _CategoryTone(Color(0xFFFFE4E6), Color(0xFFE11D48));
    }
    if (c.contains('equipment') || c.contains('rental')) {
      return const _CategoryTone(Color(0xFFE0F2FE), Color(0xFF0369A1));
    }
    if (c.contains('staff') || c.contains('security')) {
      return const _CategoryTone(Color(0xFFFEF3C7), Color(0xFFCA8A04));
    }
    return _CategoryTone(AppColors.primarySoft, AppColors.primary);
  }


  Widget _addButton() {
    return GestureDetector(
      onTap: _showAddSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const AppIcon('plus', size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text('Add budget item',
              style: appText(
                  size: 14, weight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }

  // ---------- helpers ----------
  double _asNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _money(double v) {
    return '${getActiveCurrency()} ${v
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  Future<void> _download(String format) async {
    AppSnackbar.success(
        context, 'Generating ${format == 'xlsx' ? 'Excel' : 'PDF'} report...');
    try {
      final res = await ReportGenerator.generateBudgetReport(
        widget.eventId,
        format: format,
        budgetItems: _items,
        summary: _summary,
        eventTitle: widget.eventTitle,
        eventBudget: widget.eventBudget,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        if (format == 'pdf' && res['bytes'] != null) {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ReportPreviewScreen(
                        title: 'Budget Report',
                        pdfBytes: res['bytes'] as Uint8List,
                        filePath: res['path'] as String,
                      )));
        } else if (res['path'] != null) {
          await OpenFilex.open(res['path'] as String);
          if (mounted) AppSnackbar.success(context, 'Report opened');
        }
      } else {
        AppSnackbar.error(context, res['message'] ?? 'Failed');
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to generate report');
    }
  }

  Future<void> _deleteItem(String id) async {
    if (id.isEmpty) return;
    setState(() => _deleting = true);
    final res = await EventsService.deleteBudgetItem(widget.eventId, id);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (res['success'] == true) {
      AppSnackbar.success(context, 'Removed');
      _load(background: true);
    } else {
      AppSnackbar.error(context, res['message'] ?? 'Failed');
    }
  }

  void _showAddSheet() {
    final descCtrl = TextEditingController();
    final estCtrl = TextEditingController();
    final actCtrl = TextEditingController();
    final vendorCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final customCatCtrl = TextEditingController();
    String selectedCategory = _kCategories.first;
    String selectedStatus = 'pending';
    bool customMode = false;

    final existing = <String>{};
    for (final i in _items) {
      if (i['category'] != null) existing.add(i['category'].toString());
    }
    final cats = (<String>{..._kCategories, ...existing}).toList()..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
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
                  const SizedBox(height: 16),
                  Text('Add budget item',
                      style: appText(size: 18, weight: FontWeight.w800)),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _label('Category *'),
                          if (customMode)
                            Row(children: [
                              Expanded(child: _input(customCatCtrl, 'Custom')),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  if (customCatCtrl.text.trim().isNotEmpty) {
                                    setSheetState(() {
                                      selectedCategory =
                                          customCatCtrl.text.trim();
                                      customMode = false;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Text('Set',
                                      style: appText(
                                          size: 12,
                                          weight: FontWeight.w700,
                                          color: Colors.white)),
                                ),
                              ),
                            ])
                          else
                            _dropdown<String>(
                              value: cats.contains(selectedCategory)
                                  ? selectedCategory
                                  : null,
                              hint: 'Select',
                              items: [
                                ...cats.map((c) =>
                                    DropdownMenuItem(value: c, child: Text(c))),
                                DropdownMenuItem(
                                    value: '__custom__',
                                    child: Text('+ Add custom',
                                        style: appText(
                                            size: 13,
                                            weight: FontWeight.w700,
                                            color: AppColors.primary))),
                              ],
                              onChanged: (v) {
                                if (v == '__custom__') {
                                  setSheetState(() => customMode = true);
                                } else if (v != null) {
                                  setSheetState(() => selectedCategory = v);
                                }
                              },
                            ),
                        ])),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _label('Status'),
                          _dropdown<String>(
                            value: selectedStatus,
                            items: _kStatusOptions
                                .map((s) => DropdownMenuItem(
                                    value: s['value'] as String,
                                    child: Text(s['label'] as String)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setSheetState(() => selectedStatus = v);
                              }
                            },
                          ),
                        ])),
                  ]),
                  const SizedBox(height: 14),
                  _label('Item name *'),
                  _input(descCtrl, 'e.g. Main hall booking'),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _label('Estimated cost'),
                          _input(estCtrl, '${getActiveCurrency()} 0',
                              keyboard: TextInputType.number,
                              inputFormatters: amountFormatters),
                        ])),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _label('Actual cost'),
                          _input(actCtrl, '${getActiveCurrency()} 0',
                              keyboard: TextInputType.number,
                              inputFormatters: amountFormatters),
                        ])),
                  ]),
                  const SizedBox(height: 14),
                  _label('Vendor / supplier'),
                  _input(vendorCtrl, 'Search or type name'),
                  const SizedBox(height: 14),
                  _label('Notes'),
                  _input(notesCtrl, 'Optional notes...', maxLines: 2),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999)),
                      ),
                      onPressed: () async {
                        if (descCtrl.text.trim().isEmpty) return;
                        Navigator.pop(ctx);
                        final res = await EventsService.addBudgetItem(
                            widget.eventId, {
                          'category': selectedCategory,
                          'description': descCtrl.text.trim(),
                          'estimated_cost': parseAmount(estCtrl.text) ?? 0,
                          'actual_cost': parseAmount(actCtrl.text) ?? 0,
                          'vendor_name': vendorCtrl.text.trim().isEmpty
                              ? null
                              : vendorCtrl.text.trim(),
                          'notes': notesCtrl.text.trim().isEmpty
                              ? null
                              : notesCtrl.text.trim(),
                          'status': selectedStatus,
                        });
                        if (!mounted) return;
                        if (res['success'] == true) {
                          AppSnackbar.success(context, 'Added');
                          _load(background: true);
                        } else {
                          AppSnackbar.error(
                              context, res['message'] ?? 'Failed');
                        }
                      },
                      child: Text('Save',
                          style: appText(
                              size: 14,
                              weight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: appText(
                size: 12,
                weight: FontWeight.w700,
                color: AppColors.textSecondary)),
      );

  Widget _input(TextEditingController c, String hint,
      {TextInputType keyboard = TextInputType.text, int maxLines = 1,
      List<TextInputFormatter>? inputFormatters}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
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

