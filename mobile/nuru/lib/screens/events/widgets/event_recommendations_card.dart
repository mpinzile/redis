import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/events_service.dart';

/// Mobile mirror of the web `<EventRecommendations />` component shown on
/// `/create-event`: surfaces matching service providers based on event type
/// (and optional location / max budget) so organisers can compare options
/// without leaving the create flow.
///
/// Pure presentation - does not mutate the parent form. The parent is free
/// to wire the [onToggleService] callback to track suggested-service IDs if
/// it later wants to attach them to the new event.
class EventRecommendationsCard extends StatefulWidget {
  final String? eventTypeId;
  final String? eventTypeName;
  final String? location;
  final num? maxBudget;
  final List<String> selectedServiceIds;
  final void Function(String serviceId, Map<String, dynamic> service)? onToggleService;

  const EventRecommendationsCard({
    super.key,
    required this.eventTypeId,
    this.eventTypeName,
    this.location,
    this.maxBudget,
    this.selectedServiceIds = const [],
    this.onToggleService,
  });

  @override
  State<EventRecommendationsCard> createState() => _EventRecommendationsCardState();
}

class _EventRecommendationsCardState extends State<EventRecommendationsCard> {
  List<Map<String, dynamic>> _services = [];
  bool _loading = false;
  bool _fetched = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if ((widget.eventTypeId ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
    }
  }

  @override
  void didUpdateWidget(covariant EventRecommendationsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventTypeId != widget.eventTypeId ||
        oldWidget.location != widget.location ||
        oldWidget.maxBudget != widget.maxBudget) {
      _scheduleFetch();
    }
  }

  void _scheduleFetch() {
    _debounce?.cancel();
    if ((widget.eventTypeId ?? '').isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 800), _fetch);
  }

  Future<void> _fetch() async {
    final typeId = widget.eventTypeId;
    if (typeId == null || typeId.isEmpty) return;
    setState(() => _loading = true);

    Future<List<Map<String, dynamic>>> doSearch({String? location, num? maxBudget}) async {
      final res = await EventsService.getServices(
        limit: 6,
        // EventsService.getServices accepts a free-text search string + a
        // category id; we pass the event-type id through `category` because
        // backend matches both ids and slugs, mirroring the web call.
        category: typeId,
        search: location,
      );
      if (res['success'] == true) {
        final data = res['data'];
        final list = data is List
            ? data
            : (data is Map ? (data['services'] ?? data['items'] ?? []) : []);
        return (list as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .where((s) => maxBudget == null || _withinBudget(s, maxBudget))
            .toList();
      }
      return [];
    }

    var results = await doSearch(location: widget.location, maxBudget: widget.maxBudget);
    // Fallback chain mirroring web: drop location, then drop budget.
    if (results.isEmpty && widget.location != null) {
      results = await doSearch(maxBudget: widget.maxBudget);
    }
    if (results.isEmpty && widget.maxBudget != null) {
      results = await doSearch();
    }

    if (!mounted) return;
    setState(() {
      _services = results;
      _loading = false;
      _fetched = true;
    });
  }

  bool _withinBudget(Map<String, dynamic> s, num maxBudget) {
    final min = (s['min_price'] as num?) ?? 0;
    return min <= maxBudget;
  }

  String? _serviceImage(Map<String, dynamic> s) {
    final primary = s['primary_image'];
    if (primary is String) return primary;
    if (primary is Map) return (primary['thumbnail_url'] ?? primary['url'])?.toString();
    final imgs = s['images'];
    if (imgs is List && imgs.isNotEmpty) {
      final first = imgs.first;
      if (first is Map) return (first['thumbnail_url'] ?? first['url'])?.toString();
    }
    return (s['image_url'] ?? s['cover_image'])?.toString();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Service providers',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
          ),
          TextButton.icon(
            onPressed: (widget.eventTypeId ?? '').isEmpty || _loading ? null : _fetch,
            icon: _loading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 16, color: AppColors.primary),
            label: Text(_loading ? 'Finding...' : (_fetched ? 'Refresh' : 'Find providers'),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          widget.eventTypeName != null && widget.eventTypeName!.isNotEmpty
              ? 'Recommended for ${widget.eventTypeName!.toLowerCase()}'
              : 'Pick an event type to see recommendations',
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 12),

        if (!_fetched && !_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text('Tap "Find providers" to discover service providers for your event.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
            ),
          )
        else if (_loading && _services.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_services.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Column(children: [
                Text('No service providers found.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
                const SizedBox(height: 4),
                Text('Try adjusting event type, location or budget.',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textHint)),
              ]),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _services.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.75,
            ),
            itemBuilder: (_, i) => _serviceTile(_services[i]),
          ),
      ]),
    );
  }

  Widget _serviceTile(Map<String, dynamic> s) {
    final id = s['id']?.toString() ?? '';
    final selected = widget.selectedServiceIds.contains(id);
    final title = (s['title'] ?? s['name'] ?? 'Service').toString();
    final category = (s['service_category'] is Map ? s['service_category']['name'] : null)?.toString();
    final price = s['price_display']?.toString();
    final rating = s['rating'];
    final reviews = s['review_count'];
    final location = s['location']?.toString();
    final image = _serviceImage(s);

    return GestureDetector(
      onTap: () {
        if (id.isNotEmpty) widget.onToggleService?.call(id, s);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1.4,
            child: Stack(children: [
              Positioned.fill(
                child: image != null
                    ? CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                      )
                    : Container(color: AppColors.surfaceVariant),
              ),
              if (selected)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    width: 22, height: 22,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.25)),
              if (category != null && category.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(category, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary)),
              ],
              const SizedBox(height: 6),
              Row(children: [
                if (rating != null) ...[
                  const Icon(Icons.star_rounded, size: 11, color: Color(0xFFE8A33D)),
                  const SizedBox(width: 2),
                  Text('${(rating as num).toStringAsFixed(1)}',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  if (reviews != null) Text(' ($reviews)',
                      style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiary)),
                  const SizedBox(width: 8),
                ],
                if (location != null && location.isNotEmpty)
                  Expanded(
                    child: Row(children: [
                      SvgPicture.asset('assets/icons/location-icon.svg',
                          width: 9, height: 9,
                          colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiary)),
                      ),
                    ]),
                  ),
              ]),
              if (price != null && price.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(price,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
