import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/call_options_sheet.dart';
import '../../../core/widgets/self_scrolling_pills.dart';
import '../../../core/widgets/nuru_search_bar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/services/events_service.dart';
import '../../../core/services/report_generator.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/l10n/l10n_helper.dart';
import '../report_preview_screen.dart';

/// RSVP tab - full redesign.
/// Flat surfaces, project SVG icons only, no material icons, no gradients.
class EventRsvpTab extends StatefulWidget {
  final String eventId;
  const EventRsvpTab({super.key, required this.eventId});

  @override
  State<EventRsvpTab> createState() => _EventRsvpTabState();
}

class _EventRsvpTabState extends State<EventRsvpTab> with AutomaticKeepAliveClientMixin {
  /// Master list - fetched once. All filtering/search is client-side so the
  /// tabs respond instantly without hitting the backend on every tap.
  List<dynamic> _allGuests = [];
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  bool _generating = false;
  String _filter = 'all'; // all | confirmed | pending | declined | maybe
  final _searchCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load({bool background = false}) async {
    if (!background) setState(() => _loading = true);
    // Fetch every guest in one shot (paginate server-side) - filtering &
    // searching then happen instantly on the client.
    final List<dynamic> all = [];
    Map<String, dynamic> summary = {};
    int page = 1;
    while (true) {
      final res = await EventsService.getGuests(widget.eventId,
          page: page, limit: 200);
      if (res['success'] != true) break;
      final data = res['data'];
      final list = (data?['guests'] as List?) ?? const [];
      all.addAll(list);
      if (page == 1) {
        summary = (data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
      }
      final pagination = (data?['pagination'] as Map?) ?? const {};
      final totalPages = (pagination['total_pages'] ?? pagination['totalPages'] ?? 1) as int;
      if (list.isEmpty || page >= totalPages) break;
      page++;
      if (page > 200) break; // safety
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _allGuests = all;
      if (summary.isNotEmpty) _summary = summary;
    });
  }

  /// Client-side filter + search applied to [_allGuests].
  List<dynamic> get _guests {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allGuests.where((g) {
      if (g is! Map) return false;
      final status = (g['rsvp_status'] ?? 'pending').toString();
      if (_filter != 'all' && status != _filter) return false;
      if (q.isEmpty) return true;
      final hay = [
        g['name'], g['full_name'], g['phone'], g['phone_number'], g['email'],
      ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _guests.isEmpty) return _skeleton();

    return NuruRefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _responseCard(),
          const SizedBox(height: 14),
          _checkInRow(),
          const SizedBox(height: 14),
          _searchField(),
          const SizedBox(height: 12),
          _filterStrip(),
          const SizedBox(height: 14),
          if (_guests.isEmpty)
            _emptyState()
          else
            ..._guests.map((g) => _guestTile(g as Map<String, dynamic>)),
          const SizedBox(height: 14),
          _reportButton(),
        ],
      ),
    );
  }

  // ─── headline response card ───────────────────────────────────
  Widget _responseCard() {
    final confirmed = (_summary['confirmed'] ?? 0) as int;
    final pending = (_summary['pending'] ?? 0) as int;
    final declined = (_summary['declined'] ?? 0) as int;
    final maybe = (_summary['maybe'] ?? 0) as int;
    final total = (_summary['total'] ?? (confirmed + pending + declined + maybe)) as int;
    final responded = confirmed + declined + maybe;
    final responseRate = total > 0 ? responded / total : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Response rate', style: appText(size: 12, color: AppColors.textTertiary, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${(responseRate * 100).toStringAsFixed(0)}%',
                  style: appText(size: 34, weight: FontWeight.w800, height: 1.0)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('$responded of $total',
                    style: appText(size: 12, color: AppColors.textTertiary)),
              ),
            ]),
          ])),
          SizedBox(
            width: 64, height: 64,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 64, height: 64,
                child: CircularProgressIndicator(
                  value: responseRate,
                  strokeWidth: 6,
                  backgroundColor: const Color(0xFFF1F1F4),
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const AppIcon('users', size: 22, color: AppColors.primary),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _responseMetric('$confirmed', 'Confirmed', const Color(0xFF16A34A), 'verified')),
          const SizedBox(width: 8),
          Expanded(child: _responseMetric('$pending', 'Pending', const Color(0xFFCA8A04), 'clock')),
          const SizedBox(width: 8),
          Expanded(child: _responseMetric('$declined', 'Declined', const Color(0xFFDC2626), 'close-circle')),
          const SizedBox(width: 8),
          Expanded(child: _responseMetric('$maybe', 'Maybe', const Color(0xFF2563EB), 'info')),
        ]),
      ]),
    );
  }

  Widget _responseMetric(String value, String label, Color color, String icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(icon, size: 16, color: color),
        const SizedBox(height: 6),
        Text(value,
            style: appText(size: 16, weight: FontWeight.w800, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(label,
            style: appText(size: 10, weight: FontWeight.w600, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _checkInRow() {
    final checkedIn = (_summary['checked_in'] ?? 0) as int;
    final invitationsSent = (_summary['invitations_sent'] ?? 0) as int;
    return Row(children: [
      Expanded(child: _miniStat('check-in-reception', 'Checked in', '$checkedIn', tint: false)),
      const SizedBox(width: 10),
      Expanded(child: _miniStat('send', 'Invitations sent', '$invitationsSent')),
    ]);
  }

  Widget _miniStat(String icon, String label, String value, {bool tint = true}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
        child: Center(child: AppIcon(icon, size: 16, color: tint ? AppColors.textSecondary : null)),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: appText(size: 11, color: AppColors.textTertiary)),
        const SizedBox(height: 2),
        Text(value, style: appText(size: 15, weight: FontWeight.w800)),
      ])),
    ]),
  );

  // ─── search (matches conversations search style) ───────────────
      Widget _searchField() => NuruSearchBar(
        controller: _searchCtrl,
        hintText: 'Search by name or phone',
        debounce: const Duration(milliseconds: 300),
        onChanged: (_) => setState(() {}),
      );

  // ─── filter pills - self-scrolls active into view ─────────────
  Widget _filterStrip() {
    const opts = [
      ['all', 'All', null],
      ['confirmed', 'Confirmed', Color(0xFF16A34A)],
      ['pending', 'Pending', Color(0xFFCA8A04)],
      ['declined', 'Declined', Color(0xFFDC2626)],
      ['maybe', 'Maybe', Color(0xFF2563EB)],
    ];
    final activeIndex = opts.indexWhere((o) => o[0] == _filter);
    return SelfScrollingPills(
      activeIndex: activeIndex < 0 ? 0 : activeIndex,
      height: 36,
      children: opts
          .map((o) => _pill(o[1] as String, o[0] as String, o[2] as Color?))
          .toList(),
    );
  }

  Widget _pill(String label, String value, Color? dot) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? AppColors.primary.withOpacity(0.35) : AppColors.borderLight),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(label, style: appText(size: 12, weight: FontWeight.w700,
              color: active ? AppColors.primaryDark : AppColors.textSecondary)),
        ]),
      ),
    );
  }

  // ─── guest tile ────────────────────────────────────────────────
  Widget _guestTile(Map<String, dynamic> g) {
    final name = (g['name'] ?? g['full_name'] ?? 'Guest').toString();
    final rsvp = (g['rsvp_status'] ?? 'pending').toString();
    final phone = (g['phone'] ?? '').toString();
    final avatar = (g['avatar'] ?? g['avatar_url'] ?? '').toString();
    final checkedIn = g['checked_in'] == true;

    Color color; String icon; String label;
    switch (rsvp) {
      case 'confirmed':
        color = const Color(0xFF16A34A); icon = 'verified'; label = 'Confirmed'; break;
      case 'declined':
        color = const Color(0xFFDC2626); icon = 'close-circle'; label = 'Declined'; break;
      case 'maybe':
        color = const Color(0xFF2563EB); icon = 'info'; label = 'Maybe'; break;
      default:
        color = const Color(0xFFCA8A04); icon = 'clock'; label = 'Pending';
    }

    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(children: [
        ClipOval(
          child: SizedBox(
            width: 44, height: 44,
            child: avatar.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: avatar,
                    width: 44, height: 44, fit: BoxFit.cover,
                    imageBuilder: (_, p) => Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(image: p, fit: BoxFit.cover),
                      ),
                    ),
                    errorWidget: (_, __, ___) => _initialAvatar(initial, color),
                  )
                : _initialAvatar(initial, color),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, style: appText(size: 14, weight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (checkedIn) Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const AppIcon('event-calendar-check', size: 10, color: Color(0xFF1D4ED8)),
                const SizedBox(width: 4),
                Text('Checked in', style: appText(size: 9, weight: FontWeight.w700, color: const Color(0xFF1D4ED8))),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(icon, size: 10, color: color),
                const SizedBox(width: 4),
                Text(label, style: appText(size: 10, weight: FontWeight.w700, color: color)),
              ]),
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: InkWell(
                  onTap: () => showCallOptions(context,
                      name: name, phone: phone,
                      avatarUrl: avatar.isNotEmpty ? avatar : null),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const AppIcon('phone', size: 11, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          phone,
                          style: appText(
                              size: 11,
                              weight: FontWeight.w600,
                              color: AppColors.primary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
        ])),
      ]),
    );
  }

  Widget _initialAvatar(String initial, Color color) => Container(
    color: color.withOpacity(0.12),
    alignment: Alignment.center,
    child: Text(initial, style: appText(size: 17, weight: FontWeight.w800, color: color)),
  );

  // ─── empty + report ────────────────────────────────────────────
  Widget _emptyState() => Container(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Column(children: [
      Container(
        width: 60, height: 60,
        decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
        child: const Center(child: AppIcon('users', size: 26, color: AppColors.textTertiary)),
      ),
      const SizedBox(height: 14),
      Text('No responses yet', style: appText(size: 15, weight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Guest responses will appear here as they come in.',
          style: appText(size: 12, color: AppColors.textTertiary), textAlign: TextAlign.center),
    ]),
  );

  Widget _reportButton() => GestureDetector(
    onTap: _generating ? null : _showReportOptions,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
          child: const Center(child: AppIcon('document-text', size: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('RSVP report', style: appText(size: 13, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Download as PDF or Excel for sharing',
              style: appText(size: 11, color: AppColors.textTertiary)),
        ])),
        if (_generating)
          const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
        else
          const AppIcon('chevron-right', size: 16, color: AppColors.textTertiary),
      ]),
    ),
  );

  // ─── skeleton ──────────────────────────────────────────────────
  Widget _skeleton() {
    Widget bar(double w, double h, {double r = 8}) => Container(
      width: w, height: h,
      decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(r)),
    );
    Widget responseCard() => Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            bar(96, 12, r: 4),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              bar(58, 34, r: 6),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(bottom: 4), child: bar(58, 12, r: 4)),
            ]),
          ])),
          SizedBox(
            width: 64, height: 64,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFF1F1F4), width: 6)),
              ),
              bar(22, 22, r: 6),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Row(children: List.generate(4, (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 3 ? 0 : 8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(14)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                bar(16, 16, r: 5),
                const SizedBox(height: 6),
                bar(24, 16, r: 4),
                const SizedBox(height: 4),
                bar(46, 10, r: 4),
              ]),
            ),
          ),
        ))),
      ]),
    );
    Widget tile() => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderLight)),
      child: Row(children: [
        Container(width: 44, height: 44, decoration: const BoxDecoration(color: Color(0xFFF1F1F4), shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          bar(140, 13), const SizedBox(height: 8), bar(90, 18, r: 999),
        ])),
      ]),
    );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      responseCard(),
      const SizedBox(height: 14),
      Row(children: [Expanded(child: bar(double.infinity, 56, r: 14)), const SizedBox(width: 10), Expanded(child: bar(double.infinity, 56, r: 14))]),
      const SizedBox(height: 14),
      bar(double.infinity, 46, r: 14),
      const SizedBox(height: 12),
      SizedBox(
        height: 34,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(children: List.generate(5, (_) => Padding(padding: const EdgeInsets.only(right: 8), child: bar(80, 30, r: 999)))),
        ),
      ),
      const SizedBox(height: 14),
      ...List.generate(5, (_) => tile()),
    ]);
  }

  void _showReportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Download RSVP Report', style: appText(size: 18, weight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(ctx); _generateReport('pdf'); },
                icon: const AppIcon('pdf-file-type', size: 18),
                label: Text('PDF', style: appText(size: 13, weight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.borderLight),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(ctx); _generateReport('xlsx'); },
                icon: const AppIcon('excel-document', size: 18),
                label: Text('Excel', style: appText(size: 13, weight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.borderLight),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Future<void> _generateReport(String format) async {
    setState(() => _generating = true);
    AppSnackbar.success(context, 'Generating ${format == 'xlsx' ? 'Excel' : 'PDF'} report...');
    // We already hold every guest in memory - feed them straight to the report.
    final res = await ReportGenerator.generateRsvpReport(
      widget.eventId,
      format: format,
      guests: _allGuests.isNotEmpty ? _allGuests : _guests,
    );
    if (!mounted) return;
    setState(() => _generating = false);
    if (res['success'] == true) {
      if (format == 'pdf' && res['bytes'] != null) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(
            title: 'RSVP Report',
            pdfBytes: res['bytes'] as Uint8List,
            filePath: res['path'] as String?,
          ),
        ));
      } else if (res['path'] != null) {
        await OpenFilex.open(res['path'] as String);
        if (mounted) AppSnackbar.success(context, 'Report opened');
      }
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? "We couldn't generate the report");
    }
  }
}
