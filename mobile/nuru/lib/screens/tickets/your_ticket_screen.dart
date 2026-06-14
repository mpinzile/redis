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
import '../../core/utils/money_format.dart' show getActiveCurrency;
import 'widgets/dashed_divider.dart';

/// Premium "digital pass" rendering of a single ticket.
/// Single perforated card: dark hero on top, white body below, with
/// semicircle notches on each side between them and a scalloped bottom edge.
class YourTicketScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const YourTicketScreen({super.key, required this.ticket});

  @override
  State<YourTicketScreen> createState() => _YourTicketScreenState();
}

class _YourTicketScreenState extends State<YourTicketScreen> {
  final GlobalKey _ticketKey = GlobalKey();
  bool _sharing = false;

  Map<String, dynamic> get ticket => widget.ticket;

  Map<String, dynamic> get _event =>
      ticket['event'] is Map<String, dynamic> ? ticket['event'] as Map<String, dynamic> : <String, dynamic>{};

  String get _eventName =>
      _event['name']?.toString() ?? ticket['event_name']?.toString() ?? ticket['ticket_class_name']?.toString() ?? 'Event';
  String get _ticketCode => ticket['ticket_code']?.toString() ?? '';
  String get _ticketClass => (ticket['ticket_class_name'] ?? ticket['ticket_class'])?.toString() ?? '';
  String get _status => ticket['status']?.toString() ?? 'pending';
  String get _location => _event['location']?.toString() ?? '';
  String get _coverImage => _event['cover_image']?.toString() ?? '';
  int get _quantity => (ticket['quantity'] is int) ? ticket['quantity'] as int : 1;

  DateTime? get _date {
    try { return DateTime.parse(_event['start_date']?.toString() ?? ''); } catch (_) { return null; }
  }

  String _formatDate(DateTime d) {
    const wk = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${wk[d.weekday-1]}, ${d.day} ${mo[d.month-1]} ${d.year}';
  }

  String _formatTime() {
    final t = _event['start_time']?.toString() ?? '';
    if (t.length >= 5) return t.substring(0, 5);
    return '';
  }

  String _formatAmount(dynamic v) {
    if (v == null) return '0';
    final n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  Color get _classColor {
    final c = _ticketClass.toLowerCase();
    if (c.contains('vip')) return const Color(0xFF7C3AED);
    if (c.contains('premium') || c.contains('platinum')) return const Color(0xFFB45309);
    if (c.contains('gold')) return const Color(0xFFCA8A04);
    return AppColors.primary;
  }

  static const double _heroHeight = 170;

  @override
  Widget build(BuildContext context) {
    final d = _date;
    final currency = ticket['currency']?.toString() ?? getActiveCurrency();
    final totalAmount = ticket['total_amount'];
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: _buildAppBar(context),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: RepaintBoundary(
            key: _ticketKey,
            child: Container(
              color: Colors.white,
              child: ClipPath(
                clipper: TicketShapeClipper(
                  notchY: _heroHeight,
                  notchRadius: 12,
                  scallopedBottom: true,
                  scallopRadius: 7,
                ),
                child: Container(
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHero(d),
                      const SizedBox(height: 24),
                      _buildQrSection(),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
                        child: DashedDivider(),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildInfoRow(currency, totalAmount),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
                        child: DashedDivider(),
                      ),
                      if (_location.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                          child: _buildVenueBlock(),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                        child: _buildImportantBlock(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
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
            child: SvgPicture.asset('assets/icons/arrow-left-icon.svg', width: 22, height: 22,
              colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
          ),
        ),
      ),
      centerTitle: true,
      title: Text('Your Ticket', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 6, bottom: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _sharing ? null : _shareTicketImage,
            child: SizedBox(
              width: 40, height: 40,
              child: Center(
                child: _sharing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : SvgPicture.asset(
                      'assets/icons/share-icon.svg',
                      width: 18, height: 18,
                      colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _shareTicketImage() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final ctx = _ticketKey.currentContext;
      if (ctx == null) throw Exception('Ticket not ready');
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('Failed to encode image');

      final dir = await getTemporaryDirectory();
      final safeCode = _ticketCode.isNotEmpty ? _ticketCode : DateTime.now().millisecondsSinceEpoch.toString();
      final file = File('${dir.path}/nuru-ticket-$safeCode.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'Nuru Ticket',
        text: 'My ticket for $_eventName${_ticketCode.isNotEmpty ? "  -  $_ticketCode" : ""}',
        sharePositionOrigin: sharePositionOrigin(context),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share ticket: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _buildHero(DateTime? d) {
    return SizedBox(
      height: _heroHeight,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: _coverImage.isNotEmpty
                ? CachedNetworkImage(imageUrl: _coverImage, fit: BoxFit.cover, errorWidget: (_, __, ___) => _heroFallback())
                : _heroFallback(),
          ),
          // Dark overlay so logo + title + date are readable
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.40), Colors.black.withOpacity(0.78)],
                ),
              ),
            ),
          ),
          // Top row: nuru logo + class pill
          Positioned(
            left: 18, right: 18, top: 16,
            child: Row(
              children: [
                Image.asset('assets/images/nuru-logo.png', height: 22,
                  errorBuilder: (_, __, ___) => Image.asset('assets/images/nuru-logo-square.png', height: 22)),
                const Spacer(),
                if (_ticketClass.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _classColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_ticketClass.toUpperCase(),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.6)),
                  ),
              ],
            ),
          ),
          // Bottom: event name + date row
          Positioned(
            left: 18, right: 18, bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_eventName, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white, height: 1.25)),
                const SizedBox(height: 6),
                Text(
                  d != null
                    ? '${_formatDate(d)}${_formatTime().isNotEmpty ? "  •  ${_formatTime()}" : ""}'
                    : (_formatTime().isNotEmpty ? _formatTime() : ''),
                  style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1F1F2E), Color(0xFF111827)],
        ),
      ),
    );
  }

  Widget _buildQrSection() {
    final isConfirmed = _status == 'confirmed' || _status == 'approved' || _status == 'paid';
    final isUsed = ticket['checked_in'] == true;
    final usedAt = ticket['checked_in_at']?.toString() ?? '';
    String usedLabel = 'Used at the gate';
    if (usedAt.isNotEmpty) {
      final iso = (usedAt.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(usedAt)) ? usedAt : '${usedAt}Z';
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt != null) {
        const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        usedLabel = 'Used · ${dt.day} ${mo[dt.month-1]} ${dt.year}, '
            '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
      }
    }
    return Column(
      children: [
        Stack(alignment: Alignment.center, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEDEDF2)),
            ),
            child: Opacity(
              opacity: isUsed ? 0.35 : 1.0,
              child: QrImageView(
                data: _ticketCode.isNotEmpty ? 'https://nuru.tz/ticket/$_ticketCode' : 'no-code',
                version: QrVersions.auto,
                size: 180,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          if (isUsed)
            Transform.rotate(
              angle: -0.35,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('USED',
                    style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 4)),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        if (_ticketCode.isNotEmpty)
          Text(_ticketCode,
            style: GoogleFonts.spaceMono(fontSize: 13, color: AppColors.textSecondary, letterSpacing: 1.6, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUsed
                  ? Icons.do_not_disturb_on_rounded
                  : (isConfirmed ? Icons.check_circle_outline : Icons.access_time),
              size: 18,
              color: isUsed
                  ? AppColors.textSecondary
                  : (isConfirmed ? const Color(0xFF15803D) : AppColors.warning),
            ),
            const SizedBox(width: 8),
            Text(
              isUsed ? usedLabel : (_status[0].toUpperCase() + _status.substring(1)),
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isUsed
                      ? AppColors.textSecondary
                      : (isConfirmed ? const Color(0xFF15803D) : AppColors.warning)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          isUsed
              ? 'This ticket has already been used.'
              : (isConfirmed ? 'This ticket is valid for entry.' : 'Awaiting confirmation.'),
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String currency, dynamic totalAmount) {
    final items = <_InfoItem>[
      _InfoItem('TICKET FOR', '$_quantity ${_quantity > 1 ? "People" : "Person"}'),
      if (_ticketClass.isNotEmpty) _InfoItem('ENTRY TYPE', _ticketClass),
      if (totalAmount != null) _InfoItem('AMOUNT PAID', '$currency ${_formatAmount(totalAmount)}'),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(items[i].label,
                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 1.2)),
                const SizedBox(height: 6),
                Text(items[i].value, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVenueBlock() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset('assets/icons/location-icon.svg', width: 16, height: 16,
          colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('VENUE', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text(_location, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImportantBlock() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset('assets/icons/info-icon.svg', width: 16, height: 16,
          colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('IMPORTANT', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text('Please arrive early and present this ticket at the entrance. Non-transferable.',
                style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoItem {
  final String label;
  final String value;
  _InfoItem(this.label, this.value);
}
