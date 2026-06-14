import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/events_service.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/theme/text_styles.dart';
import 'log_offline_payment_sheet.dart';

/// Event Services tab - refined redesign.
/// • No gradients, no heavy shadows, no oversized hero icon.
/// • Removed "you're building something beautiful" tagline.
/// • Project SVG icons only via AppIcon.
class EventServicesTab extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic>? permissions;
  final String? eventTypeId;
  final String? eventCoverImage;

  const EventServicesTab({
    super.key,
    required this.eventId,
    this.permissions,
    this.eventTypeId,
    this.eventCoverImage,
  });

  @override
  State<EventServicesTab> createState() => _EventServicesTabState();
}

class _EventServicesTabState extends State<EventServicesTab> with AutomaticKeepAliveClientMixin {
  List<dynamic> _assignedServices = [];
  List<dynamic> _searchResults = [];
  bool _loading = true;
  bool _searching = false;
  bool _showSearch = false;
  String _searchQuery = '';
  Timer? _debounce;
  final Set<String> _addingIds = {};
  final Set<String> _removingIds = {};
  final TextEditingController _searchCtrl = TextEditingController();

  bool get _canManage =>
      widget.permissions?['can_manage_vendors'] == true ||
      widget.permissions?['is_creator'] == true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAssigned();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAssigned({bool background = false}) async {
    if (!background) setState(() => _loading = true);
    final res = await EventsService.getEventServices(widget.eventId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        _assignedServices = data is List
            ? data
            : (data is Map ? (data['services'] ?? data['items'] ?? []) : []);
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchCtrl.clear();
        _searchQuery = '';
        _searchResults = [];
        _searching = false;
        _debounce?.cancel();
      }
    });
  }

  void _searchServices(String q) {
    _debounce?.cancel();
    setState(() => _searchQuery = q);
    if (q.trim().length < 2) {
      setState(() { _searchResults = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final res = await EventsService.searchServicesPublic(q.trim(), eventTypeId: widget.eventTypeId);
      if (!mounted) return;
      setState(() {
        _searching = false;
        if (res['success'] == true) {
          final data = res['data'];
          _searchResults = data is List ? data : (data is Map ? (data['services'] ?? []) : []);
        }
      });
    });
  }

  Future<void> _addServiceToEvent(Map<String, dynamic> service) async {
    final id = service['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _addingIds.add(id));
    final providerUserId = service['provider']?['id']?.toString()
        ?? service['provider_user_id']?.toString()
        ?? service['user_id']?.toString();
    final payload = <String, dynamic>{
      'provider_service_id': id,
      if (providerUserId != null) 'provider_user_id': providerUserId,
      if (service['min_price'] != null) 'quoted_price': service['min_price'],
    };
    final res = await EventsService.addEventService(widget.eventId, payload);
    if (!mounted) return;
    setState(() => _addingIds.remove(id));
    if (res['success'] == true) {
      AppSnackbar.success(context, 'Service added to event');
      _loadAssigned(background: true);
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? "We couldn't add this service");
    }
  }

  Future<void> _confirmRemoveService(Map<String, dynamic> service) async {
    final name = (service['service_name'] ?? service['title'] ?? service['provider_name'] ?? 'Service').toString();
    final id = service['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove service', style: appText(size: 16, weight: FontWeight.w700)),
        content: Text('Remove "$name" from this event?',
            style: appText(size: 14, color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: appText(size: 14, color: AppColors.textTertiary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Remove', style: appText(size: 14, weight: FontWeight.w700, color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _removingIds.add(id));
    final res = await EventsService.removeEventService(widget.eventId, id);
    if (!mounted) return;
    setState(() => _removingIds.remove(id));
    if (res['success'] == true) {
      AppSnackbar.success(context, 'Service removed');
      _loadAssigned(background: true);
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? "We couldn't remove this service");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _assignedServices.isEmpty) return _skeleton();

    final total = _assignedServices.length;
    int countStatus(List<String> ss) => _assignedServices.where((s) {
      final st = ((s as Map)['service_status'] ?? s['status'] ?? '').toString();
      return ss.contains(st);
    }).length;
    final confirmed = countStatus(['confirmed', 'assigned', 'in_progress', 'completed']);
    final pending = countStatus(['pending', '']);
    final progress = total > 0 ? confirmed / total : 0.0;

    return NuruRefreshIndicator(
      onRefresh: _loadAssigned,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _summaryCard(total: total, confirmed: confirmed, pending: pending, progress: progress),
          const SizedBox(height: 14),
          if (_canManage) _searchToggle(),
          if (_canManage) const SizedBox(height: 14),
          if (_showSearch) ...[
            _searchPanel(),
            const SizedBox(height: 16),
          ],
          if (_assignedServices.isNotEmpty) ...[
            Row(children: [
              Text('Assigned vendors',
                  style: appText(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.3)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(999)),
                child: Text('${_assignedServices.length}',
                    style: appText(size: 10, weight: FontWeight.w700, color: AppColors.primary)),
              ),
            ]),
            const SizedBox(height: 10),
            ..._assignedServices.map((s) => _assignedServiceCard(s as Map<String, dynamic>)),
          ] else
            _emptyState(),
        ],
      ),
    );
  }

  // ─── summary ───────────────────────────────────────────────────
  Widget _summaryCard({
    required int total,
    required int confirmed,
    required int pending,
    required double progress,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
          child: const Center(child: AppIcon('bag', size: 16, color: AppColors.primary)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Assigned services',
              style: appText(size: 12, color: AppColors.textTertiary, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$confirmed', style: appText(size: 28, weight: FontWeight.w800, height: 1.0)),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('/ $total', style: appText(size: 13, color: AppColors.textTertiary)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('$pending pending', style: appText(size: 11, color: AppColors.textTertiary)),
        ])),
        SizedBox(
          width: 60, height: 60,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 60, height: 60,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 5,
                backgroundColor: const Color(0xFFF1F1F4),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            Text('${(progress * 100).toStringAsFixed(0)}%',
                style: appText(size: 12, weight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }

  // ─── search toggle ────────────────────────────────────────────
  Widget _searchToggle() => GestureDetector(
    onTap: _toggleSearch,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _showSearch ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _showSearch ? AppColors.primary : AppColors.borderLight),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: _showSearch ? Colors.white.withOpacity(0.18) : AppColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: AppIcon(_showSearch ? 'close' : 'search', size: 14,
              color: _showSearch ? Colors.white : AppColors.primary)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(_showSearch ? 'Close search' : 'Find service providers',
              style: appText(size: 13, weight: FontWeight.w700,
                  color: _showSearch ? Colors.white : AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(_showSearch ? 'Hide the search panel' : 'Browse and add vendors to this event',
              style: appText(size: 11,
                  color: _showSearch ? Colors.white.withOpacity(0.85) : AppColors.textTertiary)),
        ])),
        AppIcon(_showSearch ? 'chevron-down' : 'chevron-right', size: 16,
            color: _showSearch ? Colors.white : AppColors.textTertiary),
      ]),
    ),
  );

  // ─── search panel ──────────────────────────────────────────────
  Widget _searchPanel() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _searchCtrl,
        onChanged: _searchServices,
        autocorrect: false,
        style: appText(size: 14),
        decoration: InputDecoration(
          hintText: 'Search services by name or category',
          hintStyle: appText(size: 13, color: AppColors.textHint),
          prefixIcon: const Padding(padding: EdgeInsets.all(12),
              child: AppIcon('search', size: 16, color: AppColors.textHint)),
          suffixIcon: _searching
              ? const Padding(padding: EdgeInsets.all(12),
                  child: SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
              : null,
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.borderLight)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.borderLight)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary.withOpacity(0.5))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      if (_searchResults.isNotEmpty) ...[
        const SizedBox(height: 12),
        ..._searchResults.map((s) => _searchResultCard(s as Map<String, dynamic>)),
      ],
      if (!_searching && _searchQuery.length >= 2 && _searchResults.isEmpty)
        Padding(padding: const EdgeInsets.only(top: 14),
            child: Text('No services found. Try different search terms.',
                style: appText(size: 12, color: AppColors.textTertiary), textAlign: TextAlign.center)),
    ]),
  );

  // ─── search result row ────────────────────────────────────────
  Widget _searchResultCard(Map<String, dynamic> service) {
    final title = (service['title'] ?? service['name'] ?? 'Service').toString();
    final category = (service['service_category']?['name'] ?? service['category'] ?? '').toString();
    final location = (service['location'] ?? '').toString();
    final rating = service['rating'];
    final imgUrl = _getServiceImage(service);
    final id = service['id']?.toString() ?? '';
    final isAdding = _addingIds.contains(id);
    final alreadyAdded = _assignedServices.any((s) =>
        s['service_id']?.toString() == id ||
        s['provider_service_id']?.toString() == id ||
        s['provider_user_service_id']?.toString() == id);
    final price = service['price_display']
        ?? (service['min_price'] != null ? '${getActiveCurrency()} ${_fmt(service['min_price'])}' : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: alreadyAdded ? AppColors.primary.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: alreadyAdded ? AppColors.primary.withOpacity(0.3) : AppColors.borderLight),
      ),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64, height: 64,
              child: imgUrl != null
                  ? CachedNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _imgPlaceholder())
                  : _imgPlaceholder(),
            ),
          ),
        ),
        Expanded(child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: appText(size: 13, weight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (category.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(category, style: appText(size: 10, color: AppColors.textTertiary)),
            ],
            const SizedBox(height: 4),
            Row(children: [
              if (rating != null) ...[
                const AppIcon('star', size: 11, color: Color(0xFFD4AF37)),
                const SizedBox(width: 3),
                Text(double.tryParse(rating.toString())?.toStringAsFixed(1) ?? '$rating',
                    style: appText(size: 10, weight: FontWeight.w700)),
                const SizedBox(width: 8),
              ],
              if (location.isNotEmpty) ...[
                const AppIcon('location', size: 10, color: AppColors.textHint),
                const SizedBox(width: 3),
                Flexible(child: Text(location, style: appText(size: 10, color: AppColors.textTertiary),
                    overflow: TextOverflow.ellipsis)),
              ],
            ]),
            if (price != null) ...[
              const SizedBox(height: 4),
              Text(price.toString(), style: appText(size: 12, weight: FontWeight.w800, color: AppColors.primary)),
            ],
          ]),
        )),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: alreadyAdded
              ? Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Center(child: AppIcon('double-check', size: 12, color: Colors.white)),
                )
              : GestureDetector(
                  onTap: isAdding ? null : () => _addServiceToEvent(service),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                    child: isAdding
                        ? const Padding(padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                        : const Center(child: AppIcon('plus', size: 14, color: AppColors.primary)),
                  ),
                ),
        ),
      ]),
    );
  }

  // ─── assigned vendor card ─────────────────────────────────────
  Widget _assignedServiceCard(Map<String, dynamic> service) {
    final nested = service['service'] as Map<String, dynamic>? ?? {};
    final name = (service['service_name']
        ?? nested['title']
        ?? service['title']
        ?? service['provider_name']
        ?? 'Service').toString();
    final providerName = (service['provider_name']
        ?? service['provider']?['name']
        ?? nested['provider_name'] ?? '').toString();
    final category = (nested['category']
        ?? nested['service_type_name']
        ?? service['service_category']?['name']
        ?? service['category'] ?? '').toString();
    final status = (service['service_status'] ?? service['status'] ?? 'pending').toString();
    final price = service['agreed_price'] ?? service['quoted_price'];
    final id = service['id']?.toString() ?? '';
    final isRemoving = _removingIds.contains(id);
    final imgUrl = _getAssignedServiceImage(service);

    final isAssignedLike = ['confirmed', 'assigned', 'in_progress'].contains(status);
    Color sBg; Color sFg; String sIcon;
    if (status == 'completed' || isAssignedLike) {
      sBg = const Color(0xFFDCFCE7); sFg = const Color(0xFF16A34A); sIcon = 'verified';
    } else if (status == 'cancelled') {
      sBg = const Color(0xFFFEE2E2); sFg = const Color(0xFFDC2626); sIcon = 'close-circle';
    } else {
      sBg = const Color(0xFFFEF3C7); sFg = const Color(0xFFCA8A04); sIcon = 'clock';
    }
    final statusLabel = status.isEmpty
        ? 'Pending'
        : status.replaceAll('_', ' ').split(' ')
            .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64, height: 64,
                child: imgUrl != null
                    ? CachedNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _imgPlaceholder())
                    : _imgPlaceholder(),
              ),
            ),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(name, style: appText(size: 14, weight: FontWeight.w800),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (_canManage && !['assigned', 'in_progress', 'completed'].contains(status))
                  GestureDetector(
                    onTap: isRemoving ? null : () => _confirmRemoveService(service),
                    child: isRemoving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error))
                        : const AppIcon('more-vertical', size: 16, color: AppColors.textHint),
                  ),
              ]),
              if (providerName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(providerName, style: appText(size: 12, color: AppColors.textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              if (category.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(category, style: appText(size: 11, color: AppColors.textTertiary),
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
                    Text(statusLabel, style: appText(size: 10, weight: FontWeight.w700, color: sFg)),
                  ]),
                ),
                const Spacer(),
                if (price != null)
                  Text('${getActiveCurrency()} ${_fmt(price)}',
                      style: appText(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
              ]),
            ]),
          )),
        ]),
        if (_canManage && status == 'assigned' && id.isNotEmpty) ...[
          Container(height: 1, color: AppColors.borderLight),
          InkWell(
            onTap: () => _openLogPayment(service),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                const AppIcon('card', size: 14, color: Color(0xFF16A34A)),
                const SizedBox(width: 8),
                Expanded(child: Text('Log offline payment',
                    style: appText(size: 12, weight: FontWeight.w700, color: const Color(0xFF16A34A)))),
                const AppIcon('chevron-right', size: 14, color: Color(0xFF16A34A)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  void _openLogPayment(Map<String, dynamic> service) {
    final nested = service['service'] as Map<String, dynamic>? ?? {};
    final vendor = (service['provider_name']
        ?? service['provider']?['name']
        ?? nested['provider_name']
        ?? nested['title'] ?? 'Vendor').toString();
    final title = (service['service_name']
        ?? nested['title']
        ?? service['title'] ?? 'Service').toString();
    final agreed = service['agreed_price'] ?? service['quoted_price'];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => LogOfflinePaymentSheet(
        eventId: widget.eventId,
        eventServiceId: service['id'].toString(),
        vendorName: vendor,
        serviceTitle: title,
        agreedPrice: agreed is num ? agreed : num.tryParse(agreed?.toString() ?? ''),
        onLogged: () => _loadAssigned(background: true),
      ),
    );
  }

  // ─── empty / skeleton / fallbacks ─────────────────────────────
  Widget _emptyState() => Container(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Column(children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(18)),
        child: const Center(child: AppIcon('bag', size: 22, color: AppColors.primary)),
      ),
      const SizedBox(height: 14),
      Text('No services assigned', style: appText(size: 15, weight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        _canManage
            ? 'Find vendors above and add them to this event.'
            : 'No service providers assigned yet.',
        style: appText(size: 12, color: AppColors.textTertiary),
        textAlign: TextAlign.center,
      ),
    ]),
  );

  Widget _imgPlaceholder() => Container(
    color: const Color(0xFFF3F4F6),
    child: const Center(child: AppIcon('image', size: 20, color: AppColors.textHint)),
  );

  Widget _skeleton() {
    Widget bar(double w, double h, {double r = 8}) => Container(
      width: w, height: h,
      decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(r)),
    );
    Widget summaryCard() => Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.borderLight)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        bar(36, 36, r: 10),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          bar(108, 12, r: 4),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            bar(32, 28, r: 5),
            const SizedBox(width: 6),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: bar(34, 13, r: 4)),
          ]),
          const SizedBox(height: 6),
          bar(72, 11, r: 4),
        ])),
        SizedBox(
          width: 60, height: 60,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFF1F1F4), width: 5)),
            ),
            bar(28, 12, r: 4),
          ]),
        ),
      ]),
    );
    Widget searchToggle() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.borderLight)),
      child: Row(children: [
        bar(32, 32, r: 10),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          bar(136, 13, r: 4),
          const SizedBox(height: 6),
          bar(190, 11, r: 4),
        ])),
        bar(16, 16, r: 4),
      ]),
    );
    Widget row() => Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderLight)),
      clipBehavior: Clip.antiAlias,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: bar(64, 64, r: 12),
        ),
        Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(2, 12, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: bar(160, 14, r: 4)),
                bar(16, 16, r: 4),
              ]),
              const SizedBox(height: 7),
              bar(116, 12, r: 4),
              const SizedBox(height: 6),
              bar(92, 11, r: 4),
              const SizedBox(height: 8),
              Row(children: [
                bar(86, 20, r: 999),
                const Spacer(),
                bar(82, 14, r: 4),
              ]),
            ]))),
      ]),
    );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
      summaryCard(),
      const SizedBox(height: 14),
      searchToggle(),
      const SizedBox(height: 14),
      Row(children: [
        bar(116, 13, r: 4),
        const SizedBox(width: 6),
        bar(22, 16, r: 999),
      ]),
      const SizedBox(height: 10),
      ...List.generate(4, (_) => row()),
    ]);
  }

  // ─── image extraction helpers (unchanged business logic) ──────
  String? _getAssignedServiceImage(Map<String, dynamic> s) {
    final nested = s['service'];
    if (nested is Map<String, dynamic>) {
      final v = _extractImageFromMap(nested);
      if (v != null) return v;
    }
    final provSvc = s['provider_service'];
    if (provSvc is Map<String, dynamic>) {
      final v = _extractImageFromMap(provSvc);
      if (v != null) return v;
    }
    return _extractImageFromMap(s);
  }

  String? _extractImageFromMap(Map<String, dynamic> m) {
    for (final key in ['image', 'primary_image', 'cover_image', 'image_url']) {
      final val = m[key];
      if (val is String && val.isNotEmpty) return val;
      if (val is Map) {
        final url = val['thumbnail_url'] ?? val['url'];
        if (url is String && url.isNotEmpty) return url;
      }
    }
    for (final key in ['images', 'gallery_images']) {
      if (m[key] is List && (m[key] as List).isNotEmpty) {
        final first = (m[key] as List)[0];
        if (first is String && first.isNotEmpty) return first;
        if (first is Map) {
          final url = first['url'] ?? first['image_url'] ?? first['file_url'] ?? first['thumbnail_url'];
          if (url is String && url.isNotEmpty) return url;
        }
      }
    }
    return null;
  }

  String? _getServiceImage(Map<String, dynamic> s) => _extractImageFromMap(s);

  String _fmt(dynamic n) {
    final num val = n is num ? n : (num.tryParse(n.toString()) ?? 0);
    return val.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
}
