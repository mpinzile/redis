import '../../core/widgets/nuru_refresh_indicator.dart';
import '../../core/utils/money_format.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/event_cover_image.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/expanding_search_action.dart';
import '../../core/services/ticketing_service.dart';
import '../../core/l10n/l10n_helper.dart';
import '../home/home_tab_controller.dart';
import '../../core/widgets/empty_state_illustration.dart';
import '../wallet/make_payment_screen.dart';
import '../../core/widgets/app_snackbar.dart';
import 'select_tickets_screen.dart';

class BrowseTicketsScreen extends StatefulWidget {
  const BrowseTicketsScreen({super.key});

  @override
  State<BrowseTicketsScreen> createState() => _BrowseTicketsScreenState();
}

class _BrowseTicketsScreenState extends State<BrowseTicketsScreen> {
  List<dynamic> _events = [];
  bool _loading = true;
  String _search = '';
  int _page = 1;
  Map<String, dynamic>? _pagination;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await TicketingService.getTicketedEvents(page: _page, search: _search.isNotEmpty ? _search : null);
    if (mounted) {
      setState(() {
        _loading = false;
        if (res['success'] == true) {
          final data = res['data'];
          _events = data is Map ? (data['events'] ?? []) : (data is List ? data : []);
          if (data is Map && data['pagination'] != null) {
            _pagination = data['pagination'] is Map<String, dynamic> ? data['pagination'] : null;
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: NuruSubPageAppBar(
        title: context.tr('browse_tickets'),
        actions: [
          ExpandingSearchAction(
            value: _search,
            hintText: 'Search events…',
            onChanged: (v) {
              setState(() => _search = v);
              _page = 1;
              _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header row: icon + description + My Tickets button (matches web)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: SvgPicture.asset('assets/icons/ticket-icon.svg', width: 20, height: 20,
                      colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Find events and purchase tickets',
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary)),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => HomeTabController.openTickets(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.borderLight),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset('assets/icons/ticket-icon.svg', width: 14, height: 14,
                            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
                        const SizedBox(width: 6),
                        Text('My Tickets', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Events list
          Expanded(
            child: _loading
                ? _buildLoadingSkeleton()
                : NuruRefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    child: _events.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 40),
                              _buildEmptyState(),
                            ],
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              ..._events.map((e) => _eventCard(e)),
                              if (_pagination != null && (_pagination!['total_pages'] ?? 1) > 1)
                                _buildPagination(),
                              const SizedBox(height: 16),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 4,
      itemBuilder: (_, __) => _BrowseTicketCardSkeleton(),
    );
  }


  Widget _buildEmptyState() {
    return const EmptyStateIllustration(
      variant: 'tickets',
      title: 'No ticketed events found',
      subtitle: 'Check back soon · fresh events drop every week.',
    );
  }

  Widget _buildPagination() {
    final totalPages = _pagination!['total_pages'] ?? 1;
    final hasPrev = _pagination!['has_previous'] == true;
    final hasNext = _pagination!['has_next'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _paginationButton(Icons.chevron_left, hasPrev, () { _page--; _load(); }),
          const SizedBox(width: 12),
          Text('Page $_page of $totalPages', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
          const SizedBox(width: 12),
          _paginationButton(Icons.chevron_right, hasNext, () { _page++; _load(); }),
        ],
      ),
    );
  }

  Widget _paginationButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          border: Border.all(color: enabled ? AppColors.borderLight : AppColors.surfaceVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: enabled ? AppColors.textPrimary : AppColors.textHint),
      ),
    );
  }

  /// Event card matching the web BrowseTickets card exactly:
  /// Cover image with price badge + sold-out badge overlaid,
  /// then a row with date stub on left + event info on right
  Widget _eventCard(dynamic event) {
    final e = event is Map<String, dynamic> ? event : <String, dynamic>{};
    final name = e['name']?.toString() ?? e['title']?.toString() ?? 'Event';
    final cover = e['cover_image']?.toString() ?? '';
    final location = e['location']?.toString() ?? '';
    final startDate = e['start_date']?.toString() ?? '';
    final minPrice = e['min_price'];
    final available = e['total_available'] ?? 0;
    final ticketClassCount = e['ticket_class_count'] ?? 0;
    final isOwner = e['is_owner'] == true;
    final approvalStatus = e['ticket_approval_status']?.toString();
    final isPending = isOwner && approvalStatus != null && approvalStatus != 'approved';

    DateTime? d;
    try { d = DateTime.parse(startDate); } catch (_) {}
    final countdown = _getCountdown(startDate);

    return GestureDetector(
      onTap: () => _showTicketClasses(e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Cover image with price badge overlay (matches web)
            Stack(
              children: [
                EventCoverImage(
                  event: e,
                  width: double.infinity,
                  height: 150,
                  fit: BoxFit.cover,
                ),
                // Price badge bottom-left (matches web)
                if (minPrice != null)
                  Positioned(
                    bottom: 10, left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6)],
                      ),
                      child: Text('From ${getActiveCurrency()} ${_formatNumber(minPrice)}',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                // Sold out badge top-right (matches web)
                if (available <= 0)
                  Positioned(
                    top: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(6)),
                      child: Text('Sold Out', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                // Pending review badge top-left (owner only)
                if (isPending)
                  Positioned(
                    top: 10, right: available <= 0 ? null : 10, left: available <= 0 ? 10 : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade600,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6)],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.schedule, size: 11, color: Colors.white),
                        const SizedBox(width: 4),
                        Text('Pending review', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  ),
              ],
            ),
            // Bottom section: date stub + event info (matches web layout)
            IntrinsicHeight(
              child: Row(
                children: [
                  // Date stub on left (matches web)
                  if (d != null)
                    Container(
                      width: 56,
                      decoration: BoxDecoration(
                        color: countdown != null && countdown['isPast'] == true
                            ? AppColors.surfaceVariant.withOpacity(0.5)
                            : AppColors.primarySoft,
                        border: Border(right: BorderSide(color: AppColors.borderLight)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 8),
                          Text('${d.day}', style: GoogleFonts.inter(
                            fontSize: 20, fontWeight: FontWeight.w800, height: 1,
                            color: countdown != null && countdown['isPast'] == true ? AppColors.textTertiary : AppColors.primary,
                          )),
                          const SizedBox(height: 2),
                          Text(_monthAbbr(d.month), style: GoogleFonts.inter(
                            fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5,
                            color: countdown != null && countdown['isPast'] == true ? AppColors.textTertiary : AppColors.primary,
                          )),
                          const SizedBox(height: 2),
                          Text('${d.year}', style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiary)),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  // Event info on right (matches web)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.3)),
                          if (location.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              SvgPicture.asset('assets/icons/location-icon.svg', width: 11, height: 11,
                                  colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
                              const SizedBox(width: 4),
                              Expanded(child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary))),
                            ]),
                          ],
                          const SizedBox(height: 6),
                          // Countdown + ticket class count + available (matches web badges row)
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (countdown != null)
                                _countdownChip(countdown),
                              if (ticketClassCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.borderLight),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('$ticketClassCount class${ticketClassCount != 1 ? 'es' : ''}',
                                      style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiary)),
                                ),
                              if (available > 0)
                                Text('$available left', style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countdownChip(Map<String, dynamic> countdown) {
    final isPast = countdown['isPast'] == true;
    final text = countdown['text'] as String;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isPast ? AppColors.surfaceVariant : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: GoogleFonts.inter(
        fontSize: 9, fontWeight: FontWeight.w600,
        color: isPast ? AppColors.textTertiary : AppColors.primary,
      )),
    );
  }

  void _showTicketClasses(Map<String, dynamic> event) async {
    final eventId = event['id']?.toString() ?? '';
    if (eventId.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SelectTicketsScreen(
      eventId: eventId,
      eventName: event['name']?.toString() ?? event['title']?.toString() ?? 'Event',
      coverImage: event['cover_image']?.toString(),
      startDate: event['start_date']?.toString(),
      startTime: event['start_time']?.toString(),
      location: event['location']?.toString(),
      eventType: event['event_type']?.toString(),
    )));
  }

  Map<String, dynamic>? _getCountdown(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      final eventDate = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(eventDate.year, eventDate.month, eventDate.day);
      final diffDays = target.difference(today).inDays;

      if (diffDays == 0) return {'text': 'Today!', 'isPast': false};
      if (diffDays == 1) return {'text': 'Tomorrow', 'isPast': false};
      if (diffDays == -1) return {'text': 'Yesterday', 'isPast': true};
      if (diffDays < 0) return {'text': 'Event passed', 'isPast': true};
      if (diffDays <= 7) return {'text': '$diffDays day${diffDays != 1 ? 's' : ''} left', 'isPast': false};
      if (diffDays <= 30) {
        final weeks = (diffDays / 7).round();
        return {'text': '$weeks week${weeks != 1 ? 's' : ''} left', 'isPast': false};
      }
      final months = (diffDays / 30).round();
      return {'text': '$months month${months != 1 ? 's' : ''} left', 'isPast': false};
    } catch (_) {
      return null;
    }
  }

  String _monthAbbr(int month) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return m[month - 1];
  }

  String _formatNumber(dynamic num) {
    if (num == null) return '0';
    final n = num is int ? num : (num is double ? num.toInt() : int.tryParse(num.toString()) ?? 0);
    return n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
}

// ── Purchase Bottom Sheet (matches web Dialog) ──

class _TicketClassesSheet extends StatefulWidget {
  final String eventId;
  final String eventName;
  final String? coverImage;
  final String? startDate;
  final String? location;
  const _TicketClassesSheet({required this.eventId, required this.eventName, this.coverImage, this.startDate, this.location});

  @override
  State<_TicketClassesSheet> createState() => _TicketClassesSheetState();
}

class _TicketClassesSheetState extends State<_TicketClassesSheet> {
  List<dynamic> _classes = [];
  bool _loading = true;
  bool _purchasing = false;
  String? _selectedId;
  int _quantity = 1;
  Map<String, dynamic>? _purchaseResult;
  bool _isOwner = false;
  String? _approvalStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await TicketingService.getTicketClasses(widget.eventId);
    if (mounted) {
      setState(() {
        _loading = false;
        if (res['success'] == true) {
          final data = res['data'];
          _classes = data is Map ? (data['ticket_classes'] ?? []) : (data is List ? data : []);
          if (data is Map) {
            _isOwner = data['is_owner'] == true;
            _approvalStatus = data['ticket_approval_status']?.toString();
          }
        }
      });
    }
  }

  Future<void> _purchase() async {
    if (_selectedId == null) return;
    setState(() => _purchasing = true);
    final res = await TicketingService.purchaseTicket(ticketClassId: _selectedId!, quantity: _quantity);
    if (!mounted) return;
    setState(() => _purchasing = false);
    if (res['success'] == true) {
      final data = res['data'];
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final pendingTicketId = map['ticket_id']?.toString() ?? map['id']?.toString() ?? _selectedId!;
      final totalAmount = map['total_amount'] is num
          ? map['total_amount'] as num
          : num.tryParse(map['total_amount']?.toString() ?? '') ?? 0;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MakePaymentScreen(
            targetType: 'event_ticket',
            targetId: pendingTicketId,
            amount: totalAmount,
            allowBank: false,
            title: 'Buy $_quantity ${_selectedClassName()} ticket${_quantity > 1 ? 's' : ''}',
            description: 'Ticket for ${widget.eventName} · ${_selectedClassName()} × $_quantity',
            summaryImageUrl: widget.coverImage,
            summarySubtitle: '${_selectedClassName()} × $_quantity',
            summaryMeta: widget.eventName,
            showFee: true,
            onReserve: () async {
              final r = await TicketingService.reserveTicket(
                ticketClassId: _selectedId!,
                quantity: _quantity,
              );
              if (!mounted) return;
              if (r['success'] == true) {
                Navigator.pop(context); // close MakePayment
                Navigator.pop(context); // close sheet
                AppSnackbar.show(context,
                  type: AppSnackbarType.success,
                  title: 'Ticket reserved',
                  message:
                      'Find it in My Tickets and pay before the hold expires.');
              } else {
                AppSnackbar.show(context,
                  type: AppSnackbarType.error,
                  title: 'Unable to reserve',
                  message: r['message']?.toString() ?? 'Please try again in a moment.');
              }
            },
            onSuccess: (_) {
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Payment confirmed · your ticket is now issued.'),
                ));
              }
            },
          ),
        ),
      );

    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Purchase failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            // Cover image (matches web dialog)
            if (widget.coverImage != null && widget.coverImage!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                child: ClipRRect(
                  child: CachedNetworkImage(
                    imageUrl: widget.coverImage!, width: double.infinity, height: 140, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            // Event info (matches web dialog header)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.eventName, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  if (widget.startDate != null && widget.startDate!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      SvgPicture.asset('assets/icons/ticket-icon.svg', width: 12, height: 12,
                          colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
                      const SizedBox(width: 6),
                      Text(_formatFullDate(widget.startDate!),
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
                    ]),
                  ],
                  if (widget.location != null && widget.location!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      SvgPicture.asset('assets/icons/location-icon.svg', width: 12, height: 12,
                          colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(widget.location!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary))),
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Owner pending banner (matches web)
            if (_isOwner && _approvalStatus != null && _approvalStatus != 'approved')
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, size: 18, color: Colors.amber.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pending review',
                              style: GoogleFonts.inter(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.amber.shade900)),
                          const SizedBox(height: 2),
                          Text(
                            'Your ticketed event is awaiting admin approval. Buyers will be able to purchase tickets once approved.',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.amber.shade900, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Purchase result (matches web success state)
            if (_purchaseResult != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(28)),
                      child: Center(child: SvgPicture.asset('assets/icons/ticket-icon.svg', width: 28, height: 28,
                          colorFilter: const ColorFilter.mode(AppColors.success, BlendMode.srcIn))),
                    ),
                    const SizedBox(height: 14),
                    Text('Ticket Request Sent!', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Awaiting organizer approval', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Column(
                        children: [
                          Text('Ticket Code', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
                          const SizedBox(height: 4),
                          Text('${_purchaseResult!['ticket_code']}',
                              style: GoogleFonts.sourceCodePro(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 2)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Total: ${getActiveCurrency()} ${_formatAmount(_purchaseResult!['total_amount'])}',
                        style: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity, height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text('Done', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              )
            // Loading
            else if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.primary))
            // Empty
            else if (_classes.isEmpty)
              Padding(padding: const EdgeInsets.all(40), child: Text('No ticket classes available',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary)))
            // Ticket classes list (matches web dialog)
            else ...[
              ..._classes.map((tc) {
                final t = tc is Map<String, dynamic> ? tc : <String, dynamic>{};
                final id = t['id']?.toString() ?? '';
                final name = t['name']?.toString() ?? 'Ticket';
                final description = t['description']?.toString() ?? '';
                final price = t['price'] ?? 0;
                final available = t['available'] ?? 0;
                final quantity = t['quantity'] ?? 0;
                final isSelected = _selectedId == id;
                final isSoldOut = (available is int ? available : 0) <= 0;

                return GestureDetector(
                  onTap: isSoldOut ? null : () => setState(() { _selectedId = id; _quantity = 1; }),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isSoldOut
                          ? AppColors.surfaceVariant.withOpacity(0.3)
                          : isSelected ? AppColors.primarySoft : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSoldOut ? AppColors.borderLight : (isSelected ? AppColors.primary : AppColors.borderLight),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Opacity(
                      opacity: isSoldOut ? 0.6 : 1.0,
                      child: Stack(
                        children: [
                          // Left accent bar when selected (matches web)
                          if (isSelected)
                            Positioned(
                              left: 0, top: 4, bottom: 4,
                              child: Container(width: 3, decoration: BoxDecoration(
                                color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
                            ),
                          Padding(
                            padding: EdgeInsets.only(left: isSelected ? 10 : 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(child: Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                                          if (isSoldOut) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(4)),
                                              child: Text('Sold Out', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (description.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(description, maxLines: 2, overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
                                        ),
                                      const SizedBox(height: 3),
                                      Text('$available of $quantity available',
                                          style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('${getActiveCurrency()} ${_formatAmount(price)}',
                                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                    Text('per ticket', style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiary)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              // Quantity + purchase (matches web)
              if (_selectedId != null) ...[
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.borderLight)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Quantity', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                          Row(
                            children: [
                              _quantityButton(Icons.remove, _quantity > 1, () => setState(() => _quantity--)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('$_quantity', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600)),
                              ),
                              _quantityButton(Icons.add, true, () => setState(() => _quantity++)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Total line (matches web)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_selectedClassName() + ' × $_quantity',
                              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
                          Text('${getActiveCurrency()} ${_formatAmount(_selectedPrice() * _quantity)}',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity, height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _purchasing ? null : _purchase,
                          child: _purchasing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SvgPicture.asset('assets/icons/ticket-icon.svg', width: 16, height: 16,
                                        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                                    const SizedBox(width: 8),
                                    Text('Purchase Ticket${_quantity > 1 ? 's' : ''}',
                                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _quantityButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          border: Border.all(color: enabled ? AppColors.borderLight : AppColors.surfaceVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: enabled ? AppColors.textPrimary : AppColors.textHint),
      ),
    );
  }

  String _selectedClassName() {
    for (final tc in _classes) {
      final t = tc is Map<String, dynamic> ? tc : <String, dynamic>{};
      if (t['id']?.toString() == _selectedId) return t['name']?.toString() ?? 'Ticket';
    }
    return 'Ticket';
  }

  num _selectedPrice() {
    for (final tc in _classes) {
      final t = tc is Map<String, dynamic> ? tc : <String, dynamic>{};
      if (t['id']?.toString() == _selectedId) return t['price'] ?? 0;
    }
    return 0;
  }

  String _formatFullDate(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      const weekdays = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
      const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
      return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '0';
    final n = amount is int ? amount : (amount is double ? amount : num.tryParse(amount.toString()) ?? 0);
    return n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
}

// ─── Skeleton shaped like the real ticket card ───────────────────────
class _BrowseTicketCardSkeleton extends StatefulWidget {
  @override
  State<_BrowseTicketCardSkeleton> createState() => _BrowseTicketCardSkeletonState();
}

class _BrowseTicketCardSkeletonState extends State<_BrowseTicketCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _box(double w, double h, {double r = 6}) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Color.lerp(
              const Color(0xFFEDEEF1), const Color(0xFFF6F7F9), _ctrl.value)!,
          borderRadius: BorderRadius.circular(r),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover area with floating "price" pill
          Stack(
            children: [
              _box(double.infinity, 150, r: 0),
              Positioned(bottom: 10, left: 10, child: _box(86, 22, r: 6)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date stub
                _box(48, 56, r: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(double.infinity, 14),
                      const SizedBox(height: 8),
                      _box(160, 11),
                      const SizedBox(height: 6),
                      _box(110, 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
