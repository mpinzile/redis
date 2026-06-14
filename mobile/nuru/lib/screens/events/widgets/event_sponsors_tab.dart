import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/services/events_service.dart';
import '../../../core/services/event_extras_service.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../core/widgets/app_snackbar.dart';

/// Event Sponsors tab - full redesign.
/// Flat surfaces, project SVG icons only, no gradients, no material icons.
class EventSponsorsTab extends StatefulWidget {
  final String eventId;
  final bool isCreator;
  const EventSponsorsTab({super.key, required this.eventId, required this.isCreator});

  @override
  State<EventSponsorsTab> createState() => _EventSponsorsTabState();
}

class _EventSponsorsTabState extends State<EventSponsorsTab> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _summary = const {};
  String _filter = 'all'; // all | accepted | pending | declined

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool background = false}) async {
    if (!background) setState(() => _loading = true);
    final res = await EventsService.getSponsors(widget.eventId);
    if (!mounted) return;
    final data = res['data'];
    setState(() {
      _loading = false;
      if (res['success'] == true && data is Map) {
        _items = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();
        _summary = (data['summary'] is Map)
            ? (data['summary'] as Map).cast<String, dynamic>()
            : const {};
      }
    });
  }

  Future<void> _cancel(String id) async {
    final res = await EventsService.cancelSponsor(widget.eventId, id);
    if (!mounted) return;
    if (res['success'] == true) {
      AppSnackbar.success(context, 'Sponsor invitation removed');
      _load(background: true);
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not remove');
    }
  }

  void _openInvite() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _InviteSheet(eventId: widget.eventId, onInvited: () => _load(background: true)),
    );
  }

  List<Map<String, dynamic>> get _visible {
    if (_filter == 'all') return _items;
    return _items.where((s) => (s['status'] ?? 'pending').toString() == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _items.isEmpty) return _skeleton();

    return NuruRefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _summaryCard(),
          const SizedBox(height: 16),
          if (widget.isCreator) _inviteCta(),
          if (widget.isCreator) const SizedBox(height: 16),
          if (_items.isNotEmpty) ...[
            _filterRow(),
            const SizedBox(height: 12),
          ],
          if (_visible.isEmpty)
            _emptyState()
          else
            ..._visible.map(_sponsorRow),
        ],
      ),
    );
  }

  // ─── header summary ────────────────────────────────────────────
  Widget _summaryCard() {
    final total = (_summary['total'] ?? _items.length) as int;
    final accepted = (_summary['accepted'] ?? 0) as int;
    final pending = (_summary['pending'] ?? 0) as int;
    final pledged = (_summary['contribution_total'] is num)
        ? (_summary['contribution_total'] as num).toDouble()
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(color: Color(0xFFFEF3C7), shape: BoxShape.circle),
            child: const Center(child: AppIcon('heart', size: 20, color: Color(0xFFB45309))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sponsors', style: appText(size: 15, weight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('Vendors backing your event', style: appText(size: 12, color: AppColors.textTertiary)),
          ])),
        ]),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _metric('$accepted', 'Accepted', const Color(0xFF16A34A))),
          _vDivider(),
          Expanded(child: _metric('$pending', 'Pending', const Color(0xFFCA8A04))),
          _vDivider(),
          Expanded(child: _metric('$total', 'Total', AppColors.textPrimary)),
        ]),
        const SizedBox(height: 16),
        Container(height: 1, color: AppColors.borderLight),
        const SizedBox(height: 14),
        Row(children: [
          const AppIcon('money', size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Text('Pledged total', style: appText(size: 12, color: AppColors.textTertiary)),
          const Spacer(),
          Text('${getActiveCurrency()} ${_fmt(pledged)}',
              style: appText(size: 15, weight: FontWeight.w800)),
        ]),
      ]),
    );
  }

  Widget _metric(String value, String label, Color color) => Column(children: [
    Text(value, style: appText(size: 22, weight: FontWeight.w800, color: color)),
    const SizedBox(height: 2),
    Text(label, style: appText(size: 11, color: AppColors.textTertiary, weight: FontWeight.w600)),
  ]);

  Widget _vDivider() => Container(width: 1, height: 32, color: AppColors.borderLight);

  // ─── invite CTA ────────────────────────────────────────────────
  Widget _inviteCta() => GestureDetector(
    onTap: _openInvite,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const AppIcon('user-add', size: 18, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Invite a sponsor', style: appText(size: 14, weight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 2),
          Text('Search vendor services and send an invitation',
              style: appText(size: 11, color: Colors.white.withOpacity(0.85))),
        ])),
        const AppIcon('chevron-right', size: 18, color: Colors.white),
      ]),
    ),
  );

  // ─── filter pills ──────────────────────────────────────────────
  Widget _filterRow() {
    final counts = {
      'all': _items.length,
      'accepted': _items.where((s) => s['status'] == 'accepted').length,
      'pending': _items.where((s) => (s['status'] ?? 'pending') == 'pending').length,
      'declined': _items.where((s) => s['status'] == 'declined').length,
    };
    return SizedBox(
      height: 34,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        _pill('All', 'all', counts['all']!),
        _pill('Accepted', 'accepted', counts['accepted']!),
        _pill('Pending', 'pending', counts['pending']!),
        _pill('Declined', 'declined', counts['declined']!),
      ]),
    );
  }

  Widget _pill(String label, String value, int count) {
    final active = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? AppColors.primary.withOpacity(0.35) : AppColors.borderLight),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: appText(size: 12, weight: FontWeight.w700,
                color: active ? AppColors.primaryDark : AppColors.textSecondary)),
            const SizedBox(width: 6),
            Text('$count', style: appText(size: 11, weight: FontWeight.w700,
                color: active ? AppColors.primary : AppColors.textTertiary)),
          ]),
        ),
      ),
    );
  }

  // ─── sponsor row ───────────────────────────────────────────────
  Widget _sponsorRow(Map<String, dynamic> s) {
    final svc = (s['service'] is Map) ? (s['service'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final vendor = (s['vendor'] is Map) ? (s['vendor'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final status = (s['status'] ?? 'pending').toString();
    final amount = s['contribution_amount'];
    final img = (svc['image'] ?? svc['primary_image'] ?? '').toString();
    final title = (svc['title'] ?? 'Service').toString();
    final vendorName = (vendor['name'] ?? '').toString();

    Color sBg; Color sFg; String sLabel; String sIcon;
    switch (status) {
      case 'accepted':
        sBg = const Color(0xFFDCFCE7); sFg = const Color(0xFF16A34A); sLabel = 'Accepted'; sIcon = 'verified'; break;
      case 'declined':
        sBg = const Color(0xFFFEE2E2); sFg = const Color(0xFFDC2626); sLabel = 'Declined'; sIcon = 'close-circle'; break;
      case 'cancelled':
        sBg = const Color(0xFFF3F4F6); sFg = AppColors.textTertiary; sLabel = 'Cancelled'; sIcon = 'close'; break;
      default:
        sBg = const Color(0xFFFEF3C7); sFg = const Color(0xFFCA8A04); sLabel = 'Pending'; sIcon = 'clock';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 56, height: 56,
            child: img.isNotEmpty
                ? CachedNetworkImage(imageUrl: img, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _imgFallback())
                : _imgFallback(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: appText(size: 14, weight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (vendorName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(vendorName, style: appText(size: 12, color: AppColors.textTertiary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: sBg, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(sIcon, size: 10, color: sFg),
                const SizedBox(width: 4),
                Text(sLabel, style: appText(size: 10, weight: FontWeight.w700, color: sFg)),
              ]),
            ),
            if (amount is num) ...[
              const SizedBox(width: 8),
              Text('${getActiveCurrency()} ${_fmt(amount.toDouble())}',
                  style: appText(size: 12, weight: FontWeight.w700)),
            ],
          ]),
        ])),
        if (widget.isCreator && status != 'accepted')
          GestureDetector(
            onTap: () => _cancel(s['id'].toString()),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderLight),
              ),
              child: const Center(child: AppIcon('close', size: 14, color: AppColors.textTertiary)),
            ),
          ),
      ]),
    );
  }

  Widget _imgFallback() => Container(
    color: const Color(0xFFF3F4F6),
    child: const Center(child: AppIcon('image', size: 20, color: AppColors.textHint)),
  );

  // ─── empty state ───────────────────────────────────────────────
  Widget _emptyState() => Container(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Column(children: [
      Container(
        width: 60, height: 60,
        decoration: const BoxDecoration(color: Color(0xFFFEF3C7), shape: BoxShape.circle),
        child: const Center(child: AppIcon('heart', size: 26, color: Color(0xFFB45309))),
      ),
      const SizedBox(height: 14),
      Text(_filter == 'all' ? 'No sponsors yet' : 'No $_filter sponsors',
          style: appText(size: 15, weight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        widget.isCreator
            ? 'Invite vendor services to back your event.'
            : 'Sponsors will appear here once the organiser invites them.',
        style: appText(size: 12, color: AppColors.textTertiary), textAlign: TextAlign.center,
      ),
    ]),
  );

  // ─── skeleton ──────────────────────────────────────────────────
  Widget _skeleton() {
    Widget bar(double w, double h, {double r = 8}) => Container(
      width: w, height: h,
      decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(r)),
    );
    // ── Summary card placeholder: mirrors _summaryCard layout exactly ──
    Widget summary() => Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, decoration: const BoxDecoration(color: Color(0xFFF1F1F4), shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            bar(90, 14), const SizedBox(height: 6), bar(150, 11),
          ])),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Column(children: [bar(30, 22, r: 5), const SizedBox(height: 4), bar(54, 10)])),
          Container(width: 1, height: 32, color: AppColors.borderLight),
          Expanded(child: Column(children: [bar(30, 22, r: 5), const SizedBox(height: 4), bar(50, 10)])),
          Container(width: 1, height: 32, color: AppColors.borderLight),
          Expanded(child: Column(children: [bar(30, 22, r: 5), const SizedBox(height: 4), bar(40, 10)])),
        ]),
        const SizedBox(height: 16),
        Container(height: 1, color: AppColors.borderLight),
        const SizedBox(height: 14),
        Row(children: [
          bar(16, 16, r: 4), const SizedBox(width: 8), bar(90, 12),
          const Spacer(),
          bar(120, 16, r: 4),
        ]),
      ]),
    );
    // ── Invite CTA placeholder ──
    Widget invite() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Container(width: 18, height: 18, decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Container(height: 14, width: 100, decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          Container(height: 11, width: 180, decoration: BoxDecoration(color: Colors.white.withOpacity(0.4), borderRadius: BorderRadius.circular(4))),
        ])),
      ]),
    );
    // ── Sponsor row placeholder: mirrors _sponsorRow exactly ──
    Widget row() => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 56, height: 56, decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(12))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          bar(140, 14),
          const SizedBox(height: 4),
          bar(80, 12),
          const SizedBox(height: 10),
          Row(children: [
            bar(70, 20, r: 999),
            const SizedBox(width: 8),
            bar(80, 12),
          ]),
        ])),
        const SizedBox(width: 8),
        Container(width: 32, height: 32, decoration: const BoxDecoration(color: Color(0xFFF1F1F4), shape: BoxShape.circle)),
      ]),
    );
    // ── Filter pill placeholder ──
    Widget pill() => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [bar(40, 12), const SizedBox(width: 6), bar(14, 12)]),
      ),
    );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      summary(),
      const SizedBox(height: 16),
      invite(),
      const SizedBox(height: 16),
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(4, (_) => pill()),
        ),
      ),
      const SizedBox(height: 12),
      ...List.generate(4, (_) => row()),
    ]);
  }

  String _fmt(double v) => v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

// ────────────────────────────────────────────────────────────────
// Invite sheet
// ────────────────────────────────────────────────────────────────
class _InviteSheet extends StatefulWidget {
  final String eventId;
  final VoidCallback onInvited;
  const _InviteSheet({required this.eventId, required this.onInvited});
  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  String? _sendingId;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) { setState(() => _results = const []); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      final res = await EventExtrasService.searchServicesPublic(q.trim());
      if (!mounted) return;
      final data = res['data'];
      List<Map<String, dynamic>> list = const [];
      if (data is Map && data['services'] is List) {
        list = (data['services'] as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
      } else if (data is List) {
        list = data.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
      }
      setState(() { _results = list; _searching = false; });
    });
  }

  Future<void> _invite(Map<String, dynamic> svc) async {
    final id = svc['id'].toString();
    setState(() => _sendingId = id);
    final amt = double.tryParse(_amountCtrl.text.trim());
    final res = await EventsService.inviteSponsor(widget.eventId, {
      'user_service_id': svc['id'],
      if (amt != null) 'contribution_amount': amt,
    });
    if (!mounted) return;
    setState(() => _sendingId = null);
    if (res['success'] == true) {
      Navigator.pop(context);
      AppSnackbar.success(context, 'Sponsor invitation sent');
      widget.onInvited();
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not invite');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Invite Sponsor', style: appText(size: 18, weight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Search vendor services and send the invitation',
                      style: appText(size: 12, color: AppColors.textTertiary)),
                ])),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const AppIcon('close', size: 18, color: AppColors.textSecondary),
                ),
              ]),
              const SizedBox(height: 14),
              _input(
                controller: _searchCtrl,
                hint: 'Search vendor services',
                icon: 'search',
                onChanged: _onSearch,
              ),
              const SizedBox(height: 10),
              _input(
                controller: _amountCtrl,
                hint: 'Suggested amount (optional)',
                icon: 'money',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 14),
              Flexible(child: _resultsArea()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required String icon,
    void Function(String)? onChanged,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      autocorrect: false,
      style: appText(size: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: appText(size: 13, color: AppColors.textHint),
        prefixIcon: Padding(padding: const EdgeInsets.all(12), child: AppIcon(icon, size: 16, color: AppColors.textTertiary)),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.borderLight)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.borderLight)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.primary.withOpacity(0.5))),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      ),
    );
  }

  Widget _resultsArea() {
    if (_searching) {
      return const Padding(padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)));
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(children: [
          Container(
            width: 48, height: 48,
            decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
            child: const Center(child: AppIcon('search', size: 20, color: AppColors.textTertiary)),
          ),
          const SizedBox(height: 10),
          Text(
            _searchCtrl.text.isEmpty
                ? 'Start typing to search vendor services'
                : 'No services found. Try a different name.',
            style: appText(size: 12, color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = _results[i];
        final img = (s['primary_image'] ?? s['image_url'] ?? s['image'] ?? '').toString();
        final id = s['id'].toString();
        final sending = _sendingId == id;
        return InkWell(
          onTap: sending ? null : () => _invite(s),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 44, height: 44,
                  child: img.isNotEmpty
                      ? CachedNetworkImage(imageUrl: img, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: const Color(0xFFF3F4F6)))
                      : Container(color: const Color(0xFFF3F4F6),
                          child: const Center(child: AppIcon('image', size: 18, color: AppColors.textHint))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text((s['title'] ?? '').toString(), style: appText(size: 13, weight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text((s['category'] ?? s['service_type_name'] ?? '').toString(),
                    style: appText(size: 11, color: AppColors.textTertiary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                child: sending
                    ? const Padding(padding: EdgeInsets.all(7),
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : const Center(child: AppIcon('plus', size: 14, color: AppColors.primary)),
              ),
            ]),
          ),
        );
      },
    );
  }
}
