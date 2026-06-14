import '../../core/widgets/nuru_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/money_format.dart';
import '../../core/services/user_services_service.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/cancel_booking_dialog.dart';
import 'widgets/vendor_offline_payments_card.dart';
import '../../core/widgets/nuru_skeleton.dart';

/// Booking detail - clean, hero-led layout that mirrors the rest of the app
/// (SVG icons, soft cards, currency from WalletProvider, Sora/Inter type).
class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  final bool startAsVendor;
  const BookingDetailScreen({
    super.key,
    required this.bookingId,
    this.startAsVendor = false,
  });

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  Map<String, dynamic>? _booking;
  bool _loading = true;
  String? _error;

  static const _statusColor = <String, Color>{
    'pending': AppColors.warning,
    'accepted': AppColors.success,
    'rejected': AppColors.error,
    'completed': AppColors.blue,
    'cancelled': AppColors.error,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await UserServicesService.getBookingDetail(widget.bookingId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        _booking = data is Map ? Map<String, dynamic>.from(data) : null;
        if (_booking == null) _error = 'Booking not found';
      } else {
        _error = res['message']?.toString() ?? 'Unable to load booking';
      }
    });
  }

  // ──────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: NuruSubPageAppBar(title: context.tr('booking_details')),
      body: _loading
          ? _skeleton()
          : _error != null
              ? _errorView()
              : NuruRefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _heroCard(),
                      const SizedBox(height: 14),
                      _statusBadge(),
                      const SizedBox(height: 14),
                      _eventCard(),
                      const SizedBox(height: 12),
                      _partyCards(),
                      const SizedBox(height: 12),
                      _financialsCard(),
                      const SizedBox(height: 12),
                      VendorOfflinePaymentsCard(
                        eventId: (_booking?['event'] is Map<String, dynamic>)
                            ? (_booking!['event']['id']?.toString())
                            : (_booking?['event_id']?.toString()),
                      ),
                      const SizedBox(height: 12),
                      _timelineCard(),
                      const SizedBox(height: 16),
                      _actionsRow(),
                    ],
                  ),
                ),
    );
  }

  Widget _skeleton() => NuruSkeletonGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            NuruSkeleton.box(height: 180, radius: 16),
            const SizedBox(height: 14),
            NuruSkeleton.box(height: 64, radius: 16),
            const SizedBox(height: 12),
            NuruSkeleton.box(height: 110, radius: 16),
            const SizedBox(height: 12),
            NuruSkeleton.box(height: 110, radius: 16),
          ],
        ),
      );


  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset('assets/icons/info-icon.svg',
                  width: 36, height: 36,
                  colorFilter: ColorFilter.mode(
                      AppColors.error.withOpacity(.6), BlendMode.srcIn)),
              const SizedBox(height: 12),
              Text(_error ?? 'Booking not found',
                  style: GoogleFonts.inter(
                      fontSize: 14, color: AppColors.textTertiary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

  // ──────────────────────────────────────────────────────────
  // Sections
  // ──────────────────────────────────────────────────────────

  Widget _heroCard() {
    final service = _booking?['service'] is Map<String, dynamic>
        ? _booking!['service'] as Map<String, dynamic>
        : <String, dynamic>{};
    final event = _booking?['event'] is Map<String, dynamic>
        ? _booking!['event'] as Map<String, dynamic>
        : <String, dynamic>{};

    final eventName = (_booking?['event_name']?.toString() ??
            event['name']?.toString() ??
            event['title']?.toString() ??
            '')
        .trim();
    final serviceName = (service['title']?.toString() ??
            service['name']?.toString() ??
            'Service')
        .trim();
    final category = service['category']?.toString() ?? '';

    String pickImage(List<String?> candidates) {
      for (final c in candidates) {
        final s = c?.trim();
        if (s != null && s.isNotEmpty) return s;
      }
      return '';
    }

    final eventImg = pickImage([
      event['image']?.toString(),
      event['cover_image']?.toString(),
      event['featured_image']?.toString(),
    ]);
    final serviceImg = pickImage([
      service['primary_image']?.toString(),
      service['cover_image']?.toString(),
      service['image']?.toString(),
      service['image_url']?.toString(),
    ]);
    final cover = eventImg.isNotEmpty ? eventImg : serviceImg;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: cover.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: AppColors.surfaceVariant),
                    errorWidget: (_, __, ___) => _heroFallback(),
                  )
                : _heroFallback(),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(.78),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(category,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: .3,
                        )),
                  ),
                if (category.isNotEmpty) const SizedBox(height: 8),
                Text(
                  eventName.isNotEmpty ? eventName : serviceName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sora(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
                if (eventName.isNotEmpty && serviceName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    serviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroFallback() => Container(
        color: AppColors.surfaceVariant,
        alignment: Alignment.center,
        child: SvgPicture.asset('assets/icons/image-icon.svg',
            width: 32, height: 32,
            colorFilter: const ColorFilter.mode(
                AppColors.textHint, BlendMode.srcIn)),
      );

  Widget _statusBadge() {
    final status = (_booking?['status']?.toString() ?? 'pending').toLowerCase();
    final color = _statusColor[status] ?? AppColors.blue;
    final id = _booking?['id']?.toString() ?? '';
    final shortId = id.length >= 8 ? id.substring(0, 8) : id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_statusLabel(status),
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color)),
                if (shortId.isNotEmpty)
                  Text('Booking #$shortId',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          if (id.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Clipboard.setData(ClipboardData(text: id));
                AppSnackbar.success(context, 'Booking ID copied');
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: SvgPicture.asset('assets/icons/share-icon.svg',
                    width: 14, height: 14,
                    colorFilter: const ColorFilter.mode(
                        AppColors.textTertiary, BlendMode.srcIn)),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'accepted':
        return 'Accepted';
      case 'rejected':
        return 'Declined';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending response';
    }
  }

  Widget _eventCard() {
    final event = _booking?['event'] is Map<String, dynamic>
        ? _booking!['event'] as Map<String, dynamic>
        : <String, dynamic>{};
    final eventDate = (_booking?['event_date']?.toString() ??
            event['date']?.toString() ??
            event['start_date']?.toString() ??
            '')
        .trim();
    final time = (event['start_time']?.toString() ??
            _booking?['event_time']?.toString() ??
            '')
        .trim();
    final venue = (_booking?['venue']?.toString() ??
            event['venue']?.toString() ??
            _booking?['location']?.toString() ??
            event['location']?.toString() ??
            '')
        .trim();
    final guestCount = _booking?['guest_count'] ?? event['guest_count'];

    return _card(
      title: 'Event Details',
      child: Column(
        children: [
          if (eventDate.isNotEmpty)
            _detailRow('assets/icons/calendar-icon.svg',
                _formatDate(eventDate),
                sub: time.isNotEmpty ? time : null),
          if (venue.isNotEmpty)
            _detailRow('assets/icons/location-icon.svg', venue),
          if (guestCount != null)
            _detailRow('assets/icons/user-icon.svg',
                '$guestCount guests expected'),
        ],
      ),
    );
  }

  Widget _partyCards() {
    final provider = _booking?['provider'] is Map<String, dynamic>
        ? _booking!['provider'] as Map<String, dynamic>
        : null;
    final client = _booking?['client'] is Map<String, dynamic>
        ? _booking!['client'] as Map<String, dynamic>
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider != null)
          Expanded(child: _partyCard('Service Provider', provider)),
        if (provider != null && client != null) const SizedBox(width: 10),
        if (client != null) Expanded(child: _partyCard('Client', client)),
      ],
    );
  }

  Widget _partyCard(String label, Map<String, dynamic> p) {
    final name = p['name']?.toString() ?? 'Unknown';
    final phone = p['phone']?.toString() ?? '';
    final email = p['email']?.toString() ?? '';
    final avatar = p['avatar']?.toString() ?? '';
    return _card(
      title: label.toUpperCase(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(name, avatar, 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
            ],
          ),
          if (phone.isNotEmpty || email.isNotEmpty) const SizedBox(height: 10),
          if (phone.isNotEmpty)
            _linkRow('assets/icons/call-icon.svg', phone,
                () => launchUrl(Uri.parse('tel:$phone'))),
          if (email.isNotEmpty)
            _linkRow('assets/icons/send-icon.svg', email,
                () => launchUrl(Uri.parse('mailto:$email'))),
        ],
      ),
    );
  }

  Widget _avatar(String name, String url, double size) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withOpacity(.12),
        image: url.isNotEmpty
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: url.isEmpty
          ? Text(initial,
              style: GoogleFonts.inter(
                fontSize: size * .4,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ))
          : null,
    );
  }

  Widget _financialsCard() {
    final agreed = _toNum(_booking?['agreed_price']);
    final quoted = _toNum(_booking?['quoted_price']);
    final deposit = _toNum(_booking?['deposit_required']);
    final paid = _toNum(_booking?['amount_paid']);

    if (agreed == null && quoted == null && deposit == null && paid == null) {
      return const SizedBox.shrink();
    }

    return _card(
      title: 'Financials',
      child: Column(
        children: [
          if (agreed != null)
            _moneyRow('Agreed price', agreed, highlight: true),
          if (quoted != null) _moneyRow('Quoted price', quoted),
          if (deposit != null) _moneyRow('Deposit required', deposit),
          if (paid != null) _moneyRow('Amount paid', paid, success: true),
        ],
      ),
    );
  }

  num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is bool) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  Widget _timelineCard() {
    final status = (_booking?['status']?.toString() ?? 'pending').toLowerCase();
    final created = _booking?['created_at']?.toString() ?? '';
    final responded = _booking?['responded_at']?.toString() ?? '';
    final completed = _booking?['completed_at']?.toString() ?? '';
    final cancelled = _booking?['cancelled_at']?.toString() ?? '';

    final steps = <_TimelineStep>[
      _TimelineStep('Requested',
          created.isNotEmpty ? _formatDate(created) : 'Pending', true),
      _TimelineStep(
        status == 'rejected' ? 'Declined' : 'Accepted',
        responded.isNotEmpty ? _formatDate(responded) : '-',
        status == 'accepted' || status == 'rejected' || status == 'completed',
      ),
      if (status == 'completed' || completed.isNotEmpty)
        _TimelineStep('Completed',
            completed.isNotEmpty ? _formatDate(completed) : '-', true),
      if (status == 'cancelled' || cancelled.isNotEmpty)
        _TimelineStep('Cancelled',
            cancelled.isNotEmpty ? _formatDate(cancelled) : '-', true),
    ];

    return _card(
      title: 'Status Timeline',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            _timelineItem(steps[i], isLast: i == steps.length - 1),
        ],
      ),
    );
  }

  Widget _timelineItem(_TimelineStep s, {required bool isLast}) {
    final color = s.done ? AppColors.success : AppColors.textHint;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: s.done ? color : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.label,
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(s.subtitle,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textTertiary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionsRow() {
    final status = (_booking?['status']?.toString() ?? 'pending').toLowerCase();
    final id = _booking?['id']?.toString() ?? '';
    if (id.isEmpty) return const SizedBox.shrink();

    if (status == 'pending' || status == 'accepted') {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () async {
            final cancelled = await showCancelBookingDialog(context,
                bookingId: id, cancellingParty: 'organiser');
            if (cancelled) await _load();
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: AppColors.error),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text('Cancel booking',
              style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error)),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // ──────────────────────────────────────────────────────────
  // Reusable bits
  // ──────────────────────────────────────────────────────────

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.textTertiary)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _detailRow(String svgPath, String text, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(svgPath,
              width: 16,
              height: 16,
              colorFilter:
                  const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textTertiary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(String svgPath, String text, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SvgPicture.asset(svgPath,
                  width: 14,
                  height: 14,
                  colorFilter: const ColorFilter.mode(
                      AppColors.primary, BlendMode.srcIn)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moneyRow(String label, num amount,
      {bool highlight = false, bool success = false}) {
    final currency =
        context.select<WalletProvider, String>((w) => w.currency);
    final color = success
        ? AppColors.success
        : (highlight ? AppColors.textPrimary : AppColors.textPrimary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textTertiary)),
          Text(formatMoney(amount, currency: currency),
              style: GoogleFonts.sora(
                  fontSize: highlight ? 15 : 13,
                  fontWeight: highlight ? FontWeight.w800 : FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      const m = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${d.day} ${m[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

class _TimelineStep {
  final String label;
  final String subtitle;
  final bool done;
  _TimelineStep(this.label, this.subtitle, this.done);
}
