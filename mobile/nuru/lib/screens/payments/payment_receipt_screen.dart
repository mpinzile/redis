import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../core/services/wallet_service.dart';
import '../tickets/widgets/dashed_divider.dart';
import '../tickets/select_tickets_screen.dart';
import '../contributors/contribution_details_screen.dart';
import '../bookings/booking_detail_screen.dart';

/// Premium, shareable receipt for any Nuru payment (ticket purchase,
/// contribution, top-up, booking). Designed to match `YourTicketScreen`'s
/// look-and-feel and exportable as PNG via the top-right share button.
class PaymentReceiptScreen extends StatefulWidget {
  /// One row from `received-payments` (or any payment-shaped Map).
  final Map<String, dynamic> payment;
  const PaymentReceiptScreen({super.key, required this.payment});

  @override
  State<PaymentReceiptScreen> createState() => _PaymentReceiptScreenState();
}

class _PaymentReceiptScreenState extends State<PaymentReceiptScreen> {
  final GlobalKey _receiptKey = GlobalKey();
  bool _sharing = false;
  bool _verifying = false;
  late Map<String, dynamic> _payment;

  Map<String, dynamic> get p => _payment;

  @override
  void initState() {
    super.initState();
    _payment = Map<String, dynamic>.from(widget.payment);
  }

  String get _txCode => p['transaction_code']?.toString() ?? '';
  String get _status => p['status']?.toString() ?? 'pending';
  String get _currency => p['currency_code']?.toString() ?? '';
  num get _gross => (p['gross_amount'] is num) ? p['gross_amount'] as num : 0;
  num get _fee =>
      (p['commission_amount'] is num) ? p['commission_amount'] as num : 0;
  String get _description => p['description']?.toString() ?? 'Nuru payment';
  String get _eventName => p['event_name']?.toString() ?? '';
  String get _ticketClass => p['ticket_class_name']?.toString() ?? '';
  String get _cover => p['event_cover_image']?.toString() ?? '';
  String get _method => p['method_type']?.toString() ?? '';
  String get _provider => p['provider_name']?.toString() ?? '';
  bool get _canRetry => p['can_retry'] == true;

  String get _verifyUrl {
    final override = p['verification_url']?.toString();
    if (override != null && override.isNotEmpty) return override;
    return 'https://nuru.tz/wallet/receipt/$_txCode';
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month - 1]} ${d.year} · '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor() {
    switch (_status) {
      case 'credited':
      case 'paid':
        return AppColors.success;
      case 'processing':
      case 'pending':
        return AppColors.warning;
      case 'failed':
      case 'reversed':
        return AppColors.error;
      default:
        return AppColors.textTertiary;
    }
  }

  String _statusLabel() {
    switch (_status) {
      case 'credited':
        return 'Paid';
      case 'paid':
        return 'Received';
      case 'processing':
        return 'Processing';
      case 'pending':
        return 'Pending';
      case 'failed':
        return 'Failed';
      case 'reversed':
        return 'Reversed';
      default:
        return _status;
    }
  }

  Future<void> _shareAsPng() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final ctx = _receiptKey.currentContext;
      if (ctx == null) throw Exception('Receipt not ready');
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('Failed to encode image');

      final dir = await getTemporaryDirectory();
      final safe = _txCode.isNotEmpty
          ? _txCode
          : DateTime.now().millisecondsSinceEpoch.toString();
      final file = File('${dir.path}/nuru-receipt-$safe.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'Nuru Receipt',
        text: 'Nuru receipt $_txCode',
        sharePositionOrigin: sharePositionOrigin(context),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share receipt: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _retry() {
    // Route retry to the flow that originally produced this transaction,
    // not always the ticket purchase screen.
    final targetType = (p['target_type'] ?? '').toString().toLowerCase();
    final eventId = p['event_id']?.toString() ?? '';
    final targetId = p['target_id']?.toString() ?? '';

    // ── Contribution retry → open the per-event Contribution Details
    //    where the user can re-trigger payment for the same pledge.
    if (targetType == 'contribution') {
      if (eventId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot retry: original event not found.')),
        );
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ContributionDetailsScreen(
            initialEvent: {
              'event_id': eventId,
              'event_name': _eventName,
              'event_cover_image': _cover,
            },
          ),
        ),
      );
      return;
    }

    // ── Booking retry → open the booking detail so the customer can
    //    re-pay the escrow / balance from there.
    if (targetType == 'booking') {
      if (targetId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot retry: booking not found.')),
        );
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BookingDetailScreen(bookingId: targetId),
        ),
      );
      return;
    }

    // ── Default: ticket purchase retry.
    if (eventId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot retry: original event not found.')),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SelectTicketsScreen(
          eventId: eventId,
          eventName: _eventName.isNotEmpty ? _eventName : 'Event',
          coverImage: _cover.isNotEmpty ? _cover : null,
        ),
      ),
    );
  }

  /// Force a fresh status pull from the gateway. Same code path the
  /// background poller uses - guarantees the user can self-serve verify.
  Future<void> _verifyStatus() async {
    if (_verifying) return;
    if (_txCode.isEmpty) return;
    setState(() => _verifying = true);
    try {
      final res = await WalletService.getStatus(_txCode);
      if (res['success'] == true && res['data'] is Map) {
        final fresh = Map<String, dynamic>.from(res['data'] as Map);
        // Preserve the enriched event/ticket fields the receipt depends on.
        for (final k in const [
          'event_id', 'event_name', 'event_cover_image',
          'ticket_class_id', 'ticket_class_name', 'ticket_id', 'ticket_code',
        ]) {
          if (_payment[k] != null && fresh[k] == null) fresh[k] = _payment[k];
        }
        if (mounted) setState(() => _payment = fresh);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment status refreshed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: Column(
            children: [
              RepaintBoundary(
                key: _receiptKey,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(2),
                  child: ClipPath(
                  clipper: TicketShapeClipper(
                    notchY: 170,
                    notchRadius: 12,
                    scallopedBottom: false,
                    radius: 22,
                  ),

                  child: Container(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHero(),
                        const SizedBox(height: 22),
                        _buildSummary(),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                          child: DashedDivider(),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _buildDetails(),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                          child: DashedDivider(),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          child: _buildVerifyBlock(),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_status == 'pending' || _status == 'processing')
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _verifying ? null : _verifyStatus,
                    icon: _verifying
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      _verifying ? 'Checking gateway…' : 'Verify payment status',
                      style: GoogleFonts.inter(
                          fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              if (_canRetry) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: Text(
                      'Retry payment',
                      style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFFF7F7F8),
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).maybePop(),
          child: Center(
            child: SvgPicture.asset('assets/icons/arrow-left-icon.svg',
                width: 22, height: 22,
                colorFilter: const ColorFilter.mode(
                    AppColors.textPrimary, BlendMode.srcIn)),
          ),
        ),
      ),
      centerTitle: true,
      title: Text('Receipt',
          style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 6, bottom: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _sharing ? null : _shareAsPng,
            child: SizedBox(
              width: 40, height: 40,
              child: Center(
                child: _sharing
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : SvgPicture.asset('assets/icons/share-icon.svg',
                        width: 18, height: 18,
                        colorFilter: const ColorFilter.mode(
                            AppColors.textPrimary, BlendMode.srcIn)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    return SizedBox(
      height: 170,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: _cover.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: _cover,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _heroFallback())
                : _heroFallback(),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.black.withOpacity(0.65),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor(),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_statusLabel().toUpperCase(),
                          style: GoogleFonts.inter(
                              color: Colors.white, fontSize: 9,
                              letterSpacing: 1, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_eventName.isNotEmpty)
                      Text(_eventName,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              color: Colors.white, fontSize: 18,
                              fontWeight: FontWeight.w800)),
                    if (_ticketClass.isNotEmpty)
                      Text(_ticketClass,
                          style: GoogleFonts.inter(
                              color: Colors.white70, fontSize: 12,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroFallback() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1F2937), Color(0xFF374151)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
      );

  Widget _buildSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/nuru-logo.png',
                height: 20,
                errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/nuru-logo-square.png', height: 20),
              ),
              const Spacer(),
              if (_txCode.isNotEmpty)
                Flexible(
                  child: Text('Receipt #$_txCode',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.robotoMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text('AMOUNT PAID',
              style: GoogleFonts.inter(
                  fontSize: 9, letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textTertiary)),
          const SizedBox(height: 4),
          Text(formatMoney(_gross, currency: _currency),
              style: GoogleFonts.inter(
                  fontSize: 28, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(_description,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    final dateIso = p['completed_at'] ?? p['confirmed_at'] ?? p['initiated_at'];
    final method = [
      if (_method.isNotEmpty) _method.replaceAll('_', ' '),
      if (_provider.isNotEmpty) _provider,
    ].join(' · ');
    return Column(
      children: [
        _detailRow('Reference', _txCode, mono: true),
        _detailRow('Date', _formatDate(dateIso?.toString())),
        if (method.isNotEmpty) _detailRow('Method', method),
        _detailRow('Subtotal',
            formatMoney(_gross - _fee, currency: _currency)),
        if (_fee > 0)
          _detailRow('Service fee',
              formatMoney(_fee, currency: _currency), muted: true),
        const Divider(height: 18, color: AppColors.divider),
        _detailRow('Total',
            formatMoney(_gross, currency: _currency), bold: true),
      ],
    );
  }

  Widget _detailRow(String label, String value,
      {bool bold = false, bool mono = false, bool muted = false,
      bool smallValue = false}) {
    final valueSize = bold ? 14.0 : (smallValue ? 9.5 : 12.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textTertiary)),
          ),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: (mono ? GoogleFonts.robotoMono : GoogleFonts.inter)(
                  fontSize: valueSize,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: muted
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                  letterSpacing: smallValue ? 0.1 : 0,
                )),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('SCAN TO VERIFY',
            style: GoogleFonts.inter(
                fontSize: 9, letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
                color: AppColors.textTertiary)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: QrImageView(
            data: _verifyUrl,
            version: QrVersions.auto,
            size: 168,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.H,
          ),
        ),
        const SizedBox(height: 10),
        Text('Confirm this payment is authentic at',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(_verifyUrl,
            textAlign: TextAlign.center,
            style: GoogleFonts.robotoMono(
                fontSize: 10, color: AppColors.textTertiary)),
      ],
    );
  }
}

