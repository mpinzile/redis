import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart' show getActiveCurrency;
import 'your_ticket_screen.dart';
import 'widgets/dashed_divider.dart';

/// Premium ticket details screen.
/// Pure presentation layer - data is read from the [ticket] map passed in.
class TicketDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const TicketDetailsScreen({super.key, required this.ticket});

  @override
  State<TicketDetailsScreen> createState() => _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends State<TicketDetailsScreen> {
  bool _expanded = false;
  bool _sharing = false;
  final GlobalKey _cardKey = GlobalKey();

  Map<String, dynamic> get _t => widget.ticket;
  Map<String, dynamic> get _event =>
      _t['event'] is Map<String, dynamic> ? _t['event'] as Map<String, dynamic> : <String, dynamic>{};

  String get _eventName =>
      _event['name']?.toString() ?? _t['event_name']?.toString() ?? _t['ticket_class_name']?.toString() ?? 'Event';
  String get _ticketCode => _t['ticket_code']?.toString() ?? '';
  String get _ticketClass => (_t['ticket_class_name'] ?? _t['ticket_class'])?.toString() ?? '';
  String get _status => _t['status']?.toString() ?? 'pending';
  bool get _checkedIn => _t['checked_in'] == true;
  String get _checkedInAt => _t['checked_in_at']?.toString() ?? '';
  String get _location => _event['location']?.toString() ?? '';
  String get _coverImage => _event['cover_image']?.toString() ?? '';
  String get _description => _event['description']?.toString() ?? '';
  int get _quantity => (_t['quantity'] is int) ? _t['quantity'] as int : 1;

  DateTime? get _date {
    try { return DateTime.parse(_event['start_date']?.toString() ?? ''); } catch (_) { return null; }
  }
  String _formatTime() {
    final t = _event['start_time']?.toString() ?? '';
    return t.length >= 5 ? t.substring(0, 5) : '';
  }
  String _formatDate(DateTime d) {
    const wk = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${wk[d.weekday-1]}, ${d.day} ${mo[d.month-1]} ${d.year}';
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

  // Status pill colors (soft background + strong text), matching mockup
  Color get _statusBg {
    switch (_status) {
      case 'confirmed':
      case 'approved':
      case 'paid':
        return const Color(0xFFDCFCE7); // soft green
      case 'cancelled':
      case 'rejected':
        return const Color(0xFFFEE2E2); // soft red
      default:
        return const Color(0xFFFEF3C7); // soft amber
    }
  }
  Color get _statusFg {
    switch (_status) {
      case 'confirmed':
      case 'approved':
      case 'paid':
        return const Color(0xFF15803D);
      case 'cancelled':
      case 'rejected':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFFB45309);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _date;
    final currency = _t['currency']?.toString() ?? getActiveCurrency();
    final totalAmount = _t['total_amount'];
    final organizer = _event['organizer'] is Map<String, dynamic>
        ? _event['organizer'] as Map<String, dynamic>
        : <String, dynamic>{};
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          child: RepaintBoundary(
            key: _cardKey,
            child: Container(
              color: Colors.white,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEDEDF2)),
                ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_eventName,
                        style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.25)),
                      if (_checkedIn) ...[
                        const SizedBox(height: 10),
                        _usedBanner(),
                      ],
                      const SizedBox(height: 12),
                      if (d != null)
                        _iconRow('assets/icons/calendar-icon.svg',
                          '${_formatDate(d)}  •  ${_formatTime().isNotEmpty ? _formatTime() : ""}'),
                      if (_location.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _iconRow('assets/icons/location-icon.svg', _location),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: NotchedDashedDivider(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _buildInfoGrid(currency, totalAmount),
                ),
                if (_description.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: NotchedDashedDivider(),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('About this event', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 8),
                        Text(
                          _description,
                          maxLines: _expanded ? null : 4,
                          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textSecondary, height: 1.55),
                        ),
                        if (_description.length > 180)
                          GestureDetector(
                            onTap: () => setState(() => _expanded = !_expanded),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(_expanded ? 'View less' : 'View more',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (organizer.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: NotchedDashedDivider(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: _buildOrganizerRow(organizer),
                  ),
                ] else
                  const SizedBox(height: 18),
              ],
              ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: const Color(0xFFF7F7F8),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => YourTicketScreen(ticket: _t)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code_2_rounded, size: 22, color: Colors.black87),
                  const SizedBox(width: 10),
                  Text('View Your Ticket',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
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
      title: Text('Ticket Details',
        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Stack(
        children: [
          SizedBox(
            height: 200, width: double.infinity,
            child: _coverImage.isNotEmpty
                ? CachedNetworkImage(imageUrl: _coverImage, fit: BoxFit.cover, errorWidget: (_, __, ___) => _heroFallback())
                : _heroFallback(),
          ),
          // Subtle bottom darken so pills are readable
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.30)],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14, right: 14, bottom: 14,
            child: Row(
              children: [
                if (_ticketClass.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: _classColor, borderRadius: BorderRadius.circular(8)),
                    child: Text(_ticketClass.toUpperCase(),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFF7F7F8), letterSpacing: 0.6)),
                  ),
                const Spacer(),
                Builder(builder: (_) {
                  final showUsed = _checkedIn;
                  final label = showUsed ? 'Used' : (_status[0].toUpperCase() + _status.substring(1));
                  final bg = showUsed ? const Color(0xFFE5E7EB) : _statusBg;
                  final fg = showUsed ? const Color(0xFF374151) : _statusFg;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                    child: Text(label,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: fg, letterSpacing: 0.2)),
                  );
                }),
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
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF1F1F2E), Color(0xFF111827)],
      ),
    ),
  );

  Widget _iconRow(String svg, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset(svg, width: 16, height: 16,
          colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500, height: 1.4)),
        ),
      ],
    );
  }

  Widget _buildInfoGrid(String currency, dynamic totalAmount) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _gridCell(Icons.confirmation_number_outlined, 'TICKET TYPE',
              _ticketClass.isNotEmpty ? _ticketClass : '-')),
            const SizedBox(width: 14),
            Expanded(child: _gridCell(Icons.person_outline, 'TICKET FOR',
              '$_quantity ${_quantity > 1 ? "People" : "Person"}')),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _gridCell(Icons.attach_money, 'AMOUNT PAID',
              totalAmount != null ? '$currency ${_formatAmount(totalAmount)}' : '-')),
            const SizedBox(width: 14),
            Expanded(child: _gridCell(Icons.receipt_long_outlined, 'ORDER ID',
              _ticketCode.isNotEmpty ? _ticketCode : '-', mono: true)),
          ],
        ),
      ],
    );
  }

  Widget _gridCell(IconData icon, String label, String value, {bool mono = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 1.2)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: (mono ? GoogleFonts.spaceMono : GoogleFonts.inter)(
            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
          )),
      ],
    );
  }

  Widget _buildOrganizerRow(Map<String, dynamic> organizer) {
    final name = organizer['name']?.toString() ?? organizer['full_name']?.toString() ?? 'Organizer';
    final avatar = organizer['avatar']?.toString() ?? organizer['profile_image']?.toString() ?? '';
    final isVerified = organizer['is_verified'] == true || organizer['verified'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Organizer', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primarySoft,
              backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
              child: avatar.isEmpty
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'N',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary))
                : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Text(name, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ),
                if (isVerified) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified_rounded, color: AppColors.primary, size: 16),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 22),
          ],
        ),
      ],
    );
  }

  Widget _usedBanner() {
    String when = '';
    if (_checkedInAt.isNotEmpty) {
      final raw = _checkedInAt;
      final iso = (raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw)) ? raw : '${raw}Z';
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt != null) {
        const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        when = ' · ${dt.day} ${mo[dt.month-1]} ${dt.year}, '
            '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E2E8)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Flexible(
          child: Text('Used at the gate$when',
              style: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ),
      ]),
    );
  }

  Future<void> _shareAsPng() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final ctx = _cardKey.currentContext;
      if (ctx == null) throw Exception('Ticket not ready');
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('Failed to encode image');
      final dir = await getTemporaryDirectory();
      final safe = _ticketCode.isNotEmpty
          ? _ticketCode
          : DateTime.now().millisecondsSinceEpoch.toString();
      final file = File('${dir.path}/nuru-ticket-details-$safe.png');
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
}
