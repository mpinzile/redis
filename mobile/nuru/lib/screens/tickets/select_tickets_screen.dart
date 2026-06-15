import '../../core/utils/money_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/ticketing_service.dart';
import '../../core/services/wallet_service.dart';
import '../../core/widgets/nuru_loader.dart';
import '../wallet/make_payment_screen.dart';
import '../../core/widgets/app_snackbar.dart';

/// Full-screen ticket selection page (replaces the old bottom sheet).
/// Mirrors the "Select Tickets" mockup: header with back + Secure Checkout,
/// event card, list of ticket classes with +/- counters, order summary,
/// and a primary "Proceed to Checkout" CTA.
class SelectTicketsScreen extends StatefulWidget {
  final String eventId;
  final String eventName;
  final String? coverImage;
  final String? startDate;
  final String? startTime;
  final String? location;
  final String? eventType;

  const SelectTicketsScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    this.coverImage,
    this.startDate,
    this.startTime,
    this.location,
    this.eventType,
  });

  @override
  State<SelectTicketsScreen> createState() => _SelectTicketsScreenState();
}

class _SelectTicketsScreenState extends State<SelectTicketsScreen> {
  List<dynamic> _classes = [];
  bool _loading = true;
  bool _purchasing = false;
  bool _isOwner = false;
  String? _approvalStatus;
  // Map<classId, quantity>
  final Map<String, int> _quantities = {};
  // Service fee resolved from backend `/payments/fee-preview` (per-country
  // CommissionSetting). Falls back to 0 until loaded.
  double _serviceFee = 0;
  bool _feeLoading = false;
  String _feeCurrency = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await TicketingService.getTicketClasses(widget.eventId);
    if (!mounted) return;
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
    _loadFee();
  }

  Future<void> _loadFee() async {
    if (_feeLoading) return;
    setState(() => _feeLoading = true);
    final currency = getActiveCurrency();
    final country = currency == 'KES' ? 'KE' : 'TZ';
    // Use a nominal gross of 1 - backend fee is currently a flat per-tx
    // CommissionSetting; the amount only matters for percentage models.
    final res = await WalletService.feePreview(
      countryCode: country,
      currencyCode: currency,
      targetType: 'event_ticket',
      grossAmount: 1,
    );
    if (!mounted) return;
    setState(() {
      _feeLoading = false;
      if (res['success'] == true && res['data'] is Map) {
        final d = res['data'] as Map;
        _serviceFee = (d['commission_amount'] as num?)?.toDouble() ?? 0;
        _feeCurrency = (d['currency_code'] ?? currency).toString();
      } else {
        _feeCurrency = currency;
      }
    });
  }

  num _priceOf(Map t) => (t['price'] is num) ? t['price'] as num : num.tryParse(t['price']?.toString() ?? '') ?? 0;
  int _availOf(Map t) => (t['available'] is int) ? t['available'] as int : int.tryParse(t['available']?.toString() ?? '0') ?? 0;

  double get _subtotal {
    double total = 0;
    for (final tc in _classes) {
      if (tc is! Map) continue;
      final id = tc['id']?.toString() ?? '';
      final qty = _quantities[id] ?? 0;
      if (qty > 0) total += _priceOf(tc).toDouble() * qty;
    }
    return total;
  }

  int get _totalQty => _quantities.values.fold(0, (a, b) => a + b);
  double get _feeTotal => _subtotal == 0 ? 0 : _serviceFee;
  double get _grandTotal => _subtotal == 0 ? 0 : _subtotal + _feeTotal;

  Future<void> _proceed() async {
    if (_totalQty == 0 || _purchasing) return;
    // Build the full multi-class cart - backend is the source of truth for
    // pricing and the grand total, so we send every selected line.
    final items = <Map<String, dynamic>>[];
    _quantities.forEach((id, qty) {
      if (qty > 0) items.add({'ticket_class_id': id, 'quantity': qty});
    });
    if (items.isEmpty) return;

    setState(() => _purchasing = true);
    final res = items.length == 1
        ? await TicketingService.purchaseTicket(
            ticketClassId: items.first['ticket_class_id'] as String,
            quantity: items.first['quantity'] as int,
          )
        : await TicketingService.purchaseTicketsBulk(items);
    if (!mounted) return;
    setState(() => _purchasing = false);
    if (res['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Purchase failed')));
      return;
    }
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data']) : <String, dynamic>{};
    final pendingTicketId = (data['primary_ticket_id'] ?? data['ticket_id'] ?? data['id'])?.toString() ?? '';
    // Always trust the backend-computed amount (grand_total for bulk,
    // total_amount for single). Falls back to the client subtotal only if
    // the response is malformed.
    final num? backendAmount = data['grand_total'] is num
        ? data['grand_total'] as num
        : (data['total_amount'] is num
            ? data['total_amount'] as num
            : num.tryParse((data['grand_total'] ?? data['total_amount'])?.toString() ?? ''));
    final totalAmount = backendAmount ?? _grandTotal;
    final lineItems = (data['items'] is List) ? List<Map>.from((data['items'] as List).whereType<Map>()) : const <Map>[];
    final description = lineItems.isNotEmpty
        ? lineItems
            .map((it) => '${it['ticket_class'] ?? 'Ticket'} × ${it['quantity'] ?? 0}')
            .join(' · ')
        : '$_totalQty ticket${_totalQty > 1 ? "s" : ""} • ${widget.eventName}';

    // Reserve flow - supported only for single-class single-line carts
    // (mirrors what the backend's /ticketing/reserve route accepts).
    final canReserve = items.length == 1;
    final reserveClassId = canReserve ? items.first['ticket_class_id'] as String : null;
    final reserveQty = canReserve ? items.first['quantity'] as int : 0;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MakePaymentScreen(
          targetType: 'event_ticket',
          targetId: pendingTicketId,
          amount: totalAmount,
          allowBank: false,
          title: 'Tickets for ${widget.eventName}',
          description: description,
          summaryImageUrl: widget.coverImage,
          summarySubtitle: '$_totalQty ticket${_totalQty > 1 ? "s" : ""}',
          summaryMeta: [widget.startDate, widget.startTime]
              .where((s) => s != null && s.toString().trim().isNotEmpty)
              .join(' • '),
          showFee: true,
          onReserve: canReserve
              ? () async {
                  final r = await TicketingService.reserveTicket(
                    ticketClassId: reserveClassId!,
                    quantity: reserveQty,
                  );
                  if (!mounted) return;
                  if (r['success'] == true) {
                    Navigator.pop(context); // close MakePayment
                    Navigator.pop(context); // close SelectTickets
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
                }
              : null,
          onSuccess: (_) {
            if (mounted) {
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Payment confirmed · your tickets are now issued.'),
              ));
            }
          },
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.surface,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBar(),
        body: _loading
            ? const _SelectTicketsSkeleton()
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        _eventCard(),
                        const SizedBox(height: 18),
                        Text('Choose Ticket Type', style: appText(size: 14, weight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        if (_isOwner && _approvalStatus != null && _approvalStatus != 'approved')
                          _pendingBanner(),
                        if (_classes.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(child: Text('No ticket classes available',
                                style: appText(size: 13, color: AppColors.textTertiary))),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              border: Border.all(color: AppColors.borderLight),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: AppColors.cardShadow,
                            ),
                            child: Column(
                              children: [
                                for (int i = 0; i < _classes.length; i++) ...[
                                  if (i > 0) Divider(height: 1, color: AppColors.borderLight),
                                  _ticketRow(_classes[i] as Map),
                                ],
                              ],
                            ),
                          ),
                        const SizedBox(height: 18),
                        _orderSummary(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  _bottomBar(),
                ],
              ),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Container(
        color: const Color(0xFFFAFAFA),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: SvgPicture.asset('assets/icons/arrow-left-icon.svg', width: 22, height: 22,
                        colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
                  ),
                  Expanded(
                    child: Center(
                      child: Text('Select Tickets', style: appText(size: 16, weight: FontWeight.w700)),
                    ),
                  ),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    SvgPicture.asset('assets/icons/secure-shield-icon.svg', width: 16, height: 16,
                        colorFilter: const ColorFilter.mode(Color(0xFF15803D), BlendMode.srcIn)),
                    const SizedBox(width: 5),
                    Text('Secure Checkout', style: appText(size: 12, weight: FontWeight.w700, color: const Color(0xFF15803D))),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _eventCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 70, height: 80,
            child: (widget.coverImage != null && widget.coverImage!.isNotEmpty)
                ? CachedNetworkImage(imageUrl: widget.coverImage!, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant))
                : Container(color: AppColors.primarySoft, child: Center(child: SvgPicture.asset(
                    'assets/icons/ticket-icon.svg', width: 24, height: 24,
                    colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)))),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.eventName, style: appText(size: 15, weight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
          if ((widget.eventType ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
                child: Text(widget.eventType!, style: appText(size: 10, weight: FontWeight.w700, color: AppColors.primaryDark)),
            ),
          ],
          const SizedBox(height: 6),
          if ((widget.startDate ?? '').isNotEmpty)
            Row(children: [
              SvgPicture.asset('assets/icons/calendar-icon.svg', width: 11, height: 11,
                  colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
              const SizedBox(width: 4),
              Flexible(child: Text(_formatDate(widget.startDate!) + ((widget.startTime ?? '').isNotEmpty ? '  •  ${widget.startTime}' : ''),
                  style: appText(size: 11, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          if ((widget.location ?? '').isNotEmpty) ...[
            const SizedBox(height: 3),
            Row(children: [
              SvgPicture.asset('assets/icons/location-icon.svg', width: 11, height: 11,
                  colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
              const SizedBox(width: 4),
              Expanded(child: Text(widget.location!,
                  style: appText(size: 11, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ],
        ])),
      ]),
    );
  }

  Widget _pendingBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.schedule, size: 18, color: AppColors.warning),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pending review', style: appText(size: 13, weight: FontWeight.w700, color: AppColors.warning)),
          const SizedBox(height: 2),
          Text('Your ticketed event is awaiting admin approval.',
              style: appText(size: 11, color: AppColors.textSecondary, height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _ticketRow(Map t) {
    final id = t['id']?.toString() ?? '';
    final name = t['name']?.toString() ?? 'Ticket';
    final description = t['description']?.toString() ?? '';
    final price = _priceOf(t);
    final available = _availOf(t);
    final qty = _quantities[id] ?? 0;
    // Prefer backend-computed flags; fall back to local check for older payloads.
    final isSoldOut = (t['is_sold_out'] == true) || available <= 0;
    final statusLabel = (t['status_label'] ?? '').toString();
    final isLimited = !isSoldOut && (statusLabel == 'few_left' || statusLabel == 'almost_sold_out' || available <= 20);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(name, style: appText(size: 14, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (isLimited) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(20)),
                child: Text('Limited', style: appText(size: 9, weight: FontWeight.w700, color: const Color(0xFFB45309))),
              ),
            ],
            if (isSoldOut) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(20)),
                child: Text('Sold Out', style: appText(size: 9, weight: FontWeight.w700, color: AppColors.error)),
              ),
            ],
          ]),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(description, style: appText(size: 11, color: AppColors.textTertiary), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 4),
          Text('${getActiveCurrency()} ${_fmt(price)}', style: appText(size: 13, weight: FontWeight.w800, color: AppColors.textPrimary)),
        ])),
        const SizedBox(width: 10),
        _stepper(id, qty, available, isSoldOut),
      ]),
    );
  }

  Widget _stepper(String id, int qty, int available, bool isSoldOut) {
    final active = qty > 0;
    return Container(
      decoration: BoxDecoration(
        color: active ? AppColors.warningSoft : Colors.transparent,
        border: Border.all(color: active ? AppColors.primary : AppColors.borderLight, width: active ? 1.5 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _stepBtn('assets/icons/minus-icon.svg', '-', enabled: !isSoldOut && qty > 0, onTap: () => setState(() {
          if (qty > 0) _quantities[id] = qty - 1;
          if (_quantities[id] == 0) _quantities.remove(id);
        })),
        SizedBox(width: 28, child: Text('$qty', textAlign: TextAlign.center,
            style: appText(size: 14, weight: FontWeight.w700, color: active ? AppColors.primary : AppColors.textPrimary))),
        _stepBtn('assets/icons/plus-icon.svg', '+', enabled: !isSoldOut && qty < available, onTap: () => setState(() {
          _quantities[id] = qty + 1;
        })),
      ]),
    );
  }

  Widget _stepBtn(String iconAsset, String fallback, {required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28, height: 28,
        alignment: Alignment.center,
        child: iconAsset.endsWith('minus-icon.svg')
            ? Text(fallback, style: appText(size: 18, weight: FontWeight.w700, color: enabled ? AppColors.primary : AppColors.textHint))
            : SvgPicture.asset(iconAsset, width: 15, height: 15,
                colorFilter: ColorFilter.mode(enabled ? AppColors.primary : AppColors.textHint, BlendMode.srcIn)),
      ),
    );
  }

  Widget _orderSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Order Summary', style: appText(size: 14, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        for (final tc in _classes) ...[
          if (tc is Map && (_quantities[tc['id']?.toString() ?? ''] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Text(
                  '${tc['name'] ?? 'Ticket'} (${_quantities[tc['id']?.toString() ?? ''] ?? 0})',
                  style: appText(size: 12, color: AppColors.textSecondary),
                )),
                Text('${getActiveCurrency()} ${_fmt(_priceOf(tc) * (_quantities[tc['id']?.toString() ?? ''] ?? 0))}',
                    style: appText(size: 12, weight: FontWeight.w600)),
              ]),
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: Text('Service Fee', style: appText(size: 12, color: AppColors.textSecondary))),
            Text('${getActiveCurrency()} ${_fmt(_feeTotal)}', style: appText(size: 12, weight: FontWeight.w600)),
          ]),
        ),
        Divider(color: AppColors.borderLight, height: 14),
        Row(children: [
          Expanded(child: Text('Total Amount', style: appText(size: 14, weight: FontWeight.w800))),
          Text('${getActiveCurrency()} ${_fmt(_grandTotal)}', style: appText(size: 16, weight: FontWeight.w800, color: AppColors.textPrimary)),
        ]),
      ]),
    );
  }

  Widget _bottomBar() {
    final canProceed = _totalQty > 0 && !_purchasing && !(_isOwner && _approvalStatus != null && _approvalStatus != 'approved');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton(
              onPressed: canProceed ? _proceed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _purchasing
                  ? NuruLoader(size: 34, color: AppColors.textPrimary, inline: true)
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('Proceed to Checkout', style: appText(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(width: 8),
                      SvgPicture.asset('assets/icons/arrow-right-icon.svg', width: 18, height: 18,
                          colorFilter: ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
                    ]),
            ),
          ),
          const SizedBox(height: 14),
          _trustRow(),
        ]),
      ),
    );
  }

  Widget _trustRow() => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _trustChip('assets/icons/secure-shield-icon.svg', 'Secure Payment'),
        _trustChip('assets/icons/thunder-icon.svg', 'Instant Confirmation'),
        _trustChip('assets/icons/support-icon.svg', '24/7 Support'),
      ]);

  Widget _trustChip(String icon, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        SvgPicture.asset(icon, width: 16, height: 16,
            colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn)),
        const SizedBox(width: 6),
        Text(label, style: appText(size: 11, color: AppColors.textSecondary, weight: FontWeight.w600)),
      ]);

  String _formatDate(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
      return '${_weekday(d.weekday).substring(0,3)}, ${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) { return dateStr; }
  }

  String _weekday(int wd) => const ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][wd - 1];

  String _fmt(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

// ─── Skeleton mirroring the real Select Tickets layout ───────────────
class _SelectTicketsSkeleton extends StatefulWidget {
  const _SelectTicketsSkeleton();

  @override
  State<_SelectTicketsSkeleton> createState() => _SelectTicketsSkeletonState();
}

class _SelectTicketsSkeletonState extends State<_SelectTicketsSkeleton>
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

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.borderLight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppColors.cardShadow,
        ),
        child: child,
      );

  Widget _ticketRow() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _box(120, 14),
                  const SizedBox(height: 8),
                  _box(double.infinity, 11),
                  const SizedBox(height: 6),
                  _box(80, 14),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _box(96, 34, r: 10),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              // Event card
              _card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(70, 80, r: 12),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _box(double.infinity, 15),
                            const SizedBox(height: 8),
                            _box(60, 16, r: 20),
                            const SizedBox(height: 10),
                            _box(140, 11),
                            const SizedBox(height: 6),
                            _box(120, 11),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _box(140, 14),
              const SizedBox(height: 10),
              _card(
                child: Column(
                  children: [
                    _ticketRow(),
                    Divider(height: 1, color: AppColors.borderLight),
                    _ticketRow(),
                    Divider(height: 1, color: AppColors.borderLight),
                    _ticketRow(),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Order summary
              _card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(120, 14),
                      const SizedBox(height: 12),
                      _box(double.infinity, 11),
                      const SizedBox(height: 8),
                      _box(double.infinity, 11),
                      const SizedBox(height: 12),
                      Divider(color: AppColors.borderLight, height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [_box(100, 14), _box(110, 18)],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Bottom CTA placeholder
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: _box(double.infinity, 54, r: 16),
          ),
        ),
      ],
    );
  }
}
