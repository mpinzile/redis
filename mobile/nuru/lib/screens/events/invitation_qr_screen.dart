import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/events_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../invitation_cards/svg_card_renderer.dart';
import '../invitation_cards/svg_template_registry.dart';
import '../tickets/widgets/dashed_divider.dart';

/// Premium invitation card screen for confirmed guests.
/// - Two templates (Classic & Editorial) - mirror web invitation cards
/// - Uses event theme color when available
/// - Download / share full-resolution PNG
class InvitationQRScreen extends StatefulWidget {
  final String eventId;
  const InvitationQRScreen({super.key, required this.eventId});

  @override
  State<InvitationQRScreen> createState() => _InvitationQRScreenState();
}

class _InvitationQRScreenState extends State<InvitationQRScreen> {
  bool _loading = true;
  bool _downloading = false;
  String? _error;

  String _qrValue = '';
  String _eventTitle = '';
  String _eventType = '';
  String _guestName = '';
  String _eventDate = '';
  String _eventTime = '';
  String _venue = '';
  String _organizer = '';
  String _invitationCode = '';
  String _dressCode = '';
  String _coverImage = '';
  /// Pre-rendered invitation card image (delivered to the guest via WhatsApp).
  /// When present, we show this exact image instead of the live in-app design.
  String _renderedCardUrl = '';

  Color _accent = const Color(0xFFD4AF37); // gold default

  /// Selected SVG template (set by organiser via web/mobile editor) - when
  /// non-null we render the bespoke design instead of the legacy classic/editorial.
  SvgCardTemplate? _svgTemplate;
  InvitationContent? _svgContent;

  /// Selected template: 'classic' or 'editorial'
  String _template = 'classic';
  static const _prefsKey = 'invitation_card_style';

  final GlobalKey _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadCard();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('${_prefsKey}_${widget.eventId}') ??
        prefs.getString(_prefsKey);
    if (stored != null && (stored == 'classic' || stored == 'editorial')) {
      if (mounted) setState(() => _template = stored);
    }
  }

  Future<void> _loadCard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await EventsService.getInvitationCard(widget.eventId);
      if (!mounted) return;
      final data = (res['data'] is Map ? res['data'] as Map : res).cast<String, dynamic>();
      final ok = res['success'] == true || data['guest'] != null;
      if (!ok) {
        setState(() {
          _error = res['message']?.toString() ?? 'Failed to load invitation';
          _loading = false;
        });
        return;
      }
      final guest = (data['guest'] is Map ? data['guest'] as Map : {}).cast<String, dynamic>();
      final event = (data['event'] is Map ? data['event'] as Map : {}).cast<String, dynamic>();
      final org = (data['organizer'] is Map ? data['organizer'] as Map : {}).cast<String, dynamic>();
      final themeColor = event['theme_color']?.toString();

      setState(() {
        _qrValue = guest['attendee_id']?.toString() ??
            data['invitation_code']?.toString() ??
            data['qr_code_data']?.toString() ??
            widget.eventId;
        _eventTitle = event['title']?.toString() ?? 'Event';
        _eventType = event['event_type']?.toString() ?? '';
        _guestName = guest['name']?.toString() ?? '';
        _eventDate = event['start_date']?.toString() ?? '';
        _eventTime = event['start_time']?.toString() ?? '';
        _venue = event['venue']?.toString() ?? event['location']?.toString() ?? '';
        _organizer = org['name']?.toString() ?? '';
        _invitationCode = data['invitation_code']?.toString() ?? '';
        _dressCode = event['dress_code']?.toString() ?? '';
        _coverImage = event['cover_image']?.toString() ??
            event['cover_image_url']?.toString() ??
            event['banner']?.toString() ??
            '';
        _renderedCardUrl = data['rendered_card_url']?.toString() ?? '';
        _accent = _hexToColor(themeColor) ?? const Color(0xFFD4AF37);

        final tplId = event['invitation_template_id']?.toString();
        _svgTemplate = (tplId != null && tplId.isNotEmpty) ? templateById(tplId) : null;
        final ic = event['invitation_content'];
        _svgContent = (ic is Map) ? InvitationContent.fromJson(ic.cast<String, dynamic>()) : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load invitation';
        _loading = false;
      });
    }
  }

  Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dateStr);
      const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      const months = [
        'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
        'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
      ];
      return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatTime(String t) {
    if (t.isEmpty) return '';
    final parts = t.split(':');
    if (parts.length < 2) return t;
    int h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1].padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    if (h == 0) h = 12;
    if (h > 12) h -= 12;
    return '$h:$m $ampm';
  }

  Future<void> _setTemplate(String t) async {
    setState(() => _template = t);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefsKey}_${widget.eventId}', t);
  }

  Future<void> _downloadCard({bool share = false}) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      // Wait one frame so the boundary is painted at full size.
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw 'Card not ready';
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) throw 'Failed to render';
      final bytes = bd.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final safeTitle = _eventTitle.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final file = File(
          '${dir.path}/invitation_${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (share) {
        await Share.shareXFiles([XFile(file.path)],
            subject: '$_eventTitle invitation',
            text: 'My invitation to $_eventTitle',
          sharePositionOrigin: sharePositionOrigin(context),
        );
      } else {
        if (!mounted) return;
        AppSnackbar.success(context, 'Saved to ${file.path.split('/').last}');
        await Share.shareXFiles([XFile(file.path)], subject: '$_eventTitle invitation', sharePositionOrigin: sharePositionOrigin(context));
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Could not save card');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset('assets/icons/arrow-left-icon.svg',
              width: 22,
              height: 22,
              colorFilter: const ColorFilter.mode(
                  AppColors.textPrimary, BlendMode.srcIn)),
          onPressed: () => Navigator.maybePop(context),
        ),
        centerTitle: true,
        title: Text('My Invitation',
            style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share_rounded,
                    color: AppColors.textPrimary),
            onPressed:
                _downloading ? null : () => _downloadCard(share: true),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? SkeletonGroup(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: SkeletonBox(width: 240, height: 240, radius: 16),
                    ),
                    const SizedBox(height: 24),
                    const SkeletonLine(widthFactor: 0.5, height: 14),
                    const SizedBox(height: 10),
                    const SkeletonLine(widthFactor: 0.7, height: 12),
                    const SizedBox(height: 8),
                    const SkeletonLine(widthFactor: 0.4, height: 12),
                  ],
                ),
              )
            : _error != null
                ? _errorView()
                : _content(),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.textTertiary, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              style: GoogleFonts.inter(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loadCard,
            child: Text('Retry',
                style: GoogleFonts.inter(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _content() {
    return Column(
      children: [
        // Template switcher (hidden when organiser picked a bespoke SVG template
        // or when we have a pre-rendered invitation card image to show as-is)
        if (_svgTemplate == null && _renderedCardUrl.isEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                _templateChip('classic', 'Classic'),
                _templateChip('editorial', 'Editorial'),
              ],
            ),
          ),

        // Card preview
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Center(
              child: RepaintBoundary(
                key: _captureKey,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: _renderedCardUrl.isNotEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final maxW = constraints.maxWidth;
                            final cardW = maxW.clamp(280.0, 360.0).toDouble();
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: CachedNetworkImage(
                                imageUrl: _renderedCardUrl,
                                width: cardW,
                                fit: BoxFit.contain,
                                placeholder: (_, __) => SizedBox(
                                  width: cardW,
                                  height: cardW * 1.4,
                                  child: const Center(
                                      child: CircularProgressIndicator()),
                                ),
                                errorWidget: (_, __, ___) =>
                                    _svgTemplate != null
                                        ? SvgCardRenderer(
                                            template: _svgTemplate!,
                                            data: SvgCardData(
                                              guestName: _guestName,
                                              eventTitle: _eventTitle,
                                              date: _formatDate(_eventDate),
                                              time: _formatTime(_eventTime),
                                              venue: _venue,
                                              qrValue: _qrValue,
                                            ),
                                            contentOverrides: _svgContent,
                                          )
                                        : (_template == 'editorial'
                                            ? _editorialCard()
                                            : _classicCard()),
                              ),
                            );
                          },
                        )
                      : _svgTemplate != null
                          ? LayoutBuilder(
                              builder: (context, constraints) {
                                final maxW = constraints.maxWidth;
                                final cardW = maxW.clamp(280.0, 360.0).toDouble();
                                return SizedBox(
                                  width: cardW,
                                  child: SvgCardRenderer(
                                    template: _svgTemplate!,
                                    data: SvgCardData(
                                      guestName: _guestName,
                                      eventTitle: _eventTitle,
                                      date: _formatDate(_eventDate),
                                      time: _formatTime(_eventTime),
                                      venue: _venue,
                                      qrValue: _qrValue,
                                    ),
                                    contentOverrides: _svgContent,
                                  ),
                                );
                              },
                            )
                          : (_template == 'editorial'
                              ? _editorialCard()
                              : _classicCard()),
                ),
              ),
            ),
          ),
        ),



        // Bottom actions
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _downloading ? null : () => _downloadCard(share: true),
                  icon: const Icon(Icons.ios_share_rounded,
                      color: AppColors.textPrimary, size: 18),
                  label: Text('Share',
                      style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFEDEDF2)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _downloading ? null : () => _downloadCard(),
                  icon: _downloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.download_rounded,
                          color: Colors.black, size: 20),
                  label: Text(
                    _downloading ? 'Saving…' : 'Download Card',
                    style: GoogleFonts.inter(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 14),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _templateChip(String id, String label) {
    final active = _template == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setTemplate(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.textPrimary : AppColors.textTertiary,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Shared sub-widgets ───
  // ───────── Ticket-style invitation card (shared by Classic & Editorial) ─────────

  static const double _heroHeight = 190;

  Widget _classicCard() => _ticketCard(
        paper: Colors.white,
        ink: const Color(0xFF1F1B16),
        accent: _accent,
        greetingText: _classicGreeting(),
        greetingIsScript: false,
        greetingFontSize: 22,
        nameItalic: true,
      );

  Widget _editorialCard() => _ticketCard(
        paper: const Color(0xFFFDFAF3),
        ink: const Color(0xFF14110D),
        accent: _accent,
        greetingText: "You're Invited",
        greetingIsScript: true,
        greetingFontSize: 36,
        nameItalic: false,
      );

  String _classicGreeting() {
    switch (_eventType.toLowerCase()) {
      case 'wedding':
        return 'Together with their families';
      case 'birthday':
        return 'Join us to celebrate';
      case 'burial':
      case 'memorial':
        return 'In loving memory';
      case 'anniversary':
        return 'A lifetime together';
      default:
        return 'You are cordially invited';
    }
  }

  Widget _ticketCard({
    required Color paper,
    required Color ink,
    required Color accent,
    required String greetingText,
    required bool greetingIsScript,
    required double greetingFontSize,
    required bool nameItalic,
  }) {
    final dateStr = _formatDate(_eventDate);
    final timeStr = _formatTime(_eventTime);
    final dashColor = ink.withOpacity(0.18);
    final greetingStyle = greetingIsScript
        ? GoogleFonts.greatVibes(
            fontSize: greetingFontSize, color: ink, height: 1.0)
        : GoogleFonts.playfairDisplay(
            fontSize: greetingFontSize,
            color: ink,
            fontWeight: FontWeight.w700,
            height: 1.15);

    return ClipPath(
      clipper: TicketShapeClipper(
        notchY: _heroHeight,
        notchRadius: 12,
        scallopedBottom: true,
        scallopRadius: 7,
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: paper,
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.22),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heroBlock(accent: accent),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(children: [
                Text(greetingText,
                    textAlign: TextAlign.center, style: greetingStyle),
                const SizedBox(height: 8),
                _ornamentDivider(accent),
              ]),
            ),
            const SizedBox(height: 16),
            if (_guestName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(children: [
                  Text('DEAR',
                      style: GoogleFonts.inter(
                          fontSize: 9,
                          letterSpacing: 3.5,
                          color: ink.withOpacity(0.55),
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    _guestName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 26,
                      color: ink,
                      fontStyle:
                          nameItalic ? FontStyle.italic : FontStyle.normal,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ]),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: DashedDivider(color: Color(0xFFE5E7EB)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoCell('DATE', dateStr.isEmpty ? '-' : dateStr, ink),
                  _infoCell('TIME', timeStr.isEmpty ? '-' : timeStr, ink),
                  _infoCell('VENUE', _venue.isEmpty ? '-' : _venue, ink),
                ],
              ),
            ),
            if (_dressCode.isNotEmpty) ...[
              const SizedBox(height: 14),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    border: Border.all(color: accent.withOpacity(0.35)),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text('DRESS CODE · ${_dressCode.toUpperCase()}',
                      style: GoogleFonts.inter(
                          fontSize: 8.5,
                          letterSpacing: 2,
                          color: accent,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: DashedDivider(color: dashColor),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEDEDF2)),
                ),
                child: QrImageView(
                  data: _qrValue,
                  version: QrVersions.auto,
                  size: 160,
                  backgroundColor: Colors.white,
                  eyeStyle:
                      QrEyeStyle(eyeShape: QrEyeShape.square, color: ink),
                  dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square, color: ink),
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('SCAN TO CHECK IN',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 9.5,
                    letterSpacing: 3,
                    color: accent,
                    fontWeight: FontWeight.w800)),
            if (_invitationCode.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_invitationCode,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceMono(
                      fontSize: 12,
                      letterSpacing: 1.6,
                      color: ink.withOpacity(0.55),
                      fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            if (_organizer.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'Hosted by  ',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: ink.withOpacity(0.55))),
                    TextSpan(
                        text: _organizer,
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: ink.withOpacity(0.85),
                            fontWeight: FontWeight.w800)),
                  ]),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _heroBlock({required Color accent}) {
    return SizedBox(
      height: _heroHeight,
      width: double.infinity,
      child: Stack(children: [
        Positioned.fill(
          child: _coverImage.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: _coverImage,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _heroFallback(accent),
                )
              : _heroFallback(accent),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.30),
                  Colors.black.withOpacity(0.78),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          top: 16,
          child: Row(children: [
            Image.asset('assets/images/nuru-logo.png',
                height: 22,
                errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/nuru-logo-square.png',
                    height: 22)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('INVITATION',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.6)),
            ),
          ]),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_eventType.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    border: Border.all(color: Colors.white.withOpacity(0.45), width: 0.8),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(_eventType.toUpperCase(),
                      style: GoogleFonts.inter(
                          fontSize: 9,
                          letterSpacing: 2.4,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
              ],
              Text(_eventTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _heroFallback(Color accent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(0.85),
            const Color(0xFF1F1F2E),
          ],
        ),
      ),
    );
  }

  Widget _infoCell(String label, String value, Color ink) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 9.5,
                    letterSpacing: 1.4,
                    color: ink.withOpacity(0.5),
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: ink,
                    fontWeight: FontWeight.w700,
                    height: 1.3)),
          ],
        ),
      ),
    );
  }

  Widget _ornamentDivider(Color accent, {double width = 110}) {
    return SizedBox(
      width: width,
      child: Row(children: [
        Expanded(child: Container(height: 1, color: accent.withOpacity(0.5))),
        const SizedBox(width: 6),
        Transform.rotate(
          angle: 0.785,
          child: Container(width: 5, height: 5, color: accent),
        ),
        const SizedBox(width: 6),
        Expanded(child: Container(height: 1, color: accent.withOpacity(0.5))),
      ]),
    );
  }
}
