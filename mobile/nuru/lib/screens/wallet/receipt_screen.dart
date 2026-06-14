import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/services/wallet_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../tickets/widgets/dashed_divider.dart';

/// ReceiptScreen - premium printable receipt for a single transaction.
/// Redesigned to match the TicketDetailsScreen aesthetic:
/// white background, SVG icons, GoogleFonts, rounded card with notched dividers.
class ReceiptScreen extends StatefulWidget {
  final String transactionCode;
  const ReceiptScreen({super.key, required this.transactionCode});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  Map<String, dynamic>? _tx;
  bool _loading = true;
  String? _error;
  final GlobalKey _cardKey = GlobalKey();
  bool _sharingPng = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await WalletService.getStatus(widget.transactionCode);
    if (!mounted) return;
    if (res['success'] == true && res['data'] != null) {
      setState(() {
        _tx = Map<String, dynamic>.from(res['data'] as Map);
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message']?.toString() ?? 'Receipt not found';
        _loading = false;
      });
    }
  }

  String get _verifyUrl =>
      'https://nuru.tz/wallet/receipt/${widget.transactionCode}';

  Future<void> _share() async {
    await Share.share('Nuru receipt ${widget.transactionCode}\n$_verifyUrl', sharePositionOrigin: sharePositionOrigin(context));
  }

  Future<void> _shareAsPng() async {
    if (_sharingPng) return;
    setState(() => _sharingPng = true);
    try {
      final ctx = _cardKey.currentContext;
      if (ctx == null) throw Exception('Receipt not ready');
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('Failed to encode image');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/nuru-receipt-${widget.transactionCode}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'Nuru Receipt',
        text: 'Nuru receipt ${widget.transactionCode}',
        sharePositionOrigin: sharePositionOrigin(context),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share receipt: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingPng = false);
    }
  }

  Future<void> _printOrSavePdf() async {
    if (_tx == null) return;
    final tx = _tx!;
    pw.MemoryImage? logoImage;
    try {
      final bytes = await rootBundle.load('assets/images/nuru-logo-square.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final doc = pw.Document();
        doc.addPage(
          pw.Page(pageFormat: format, build: (ctx) => _buildPdf(tx, logoImage)),
        );
        return doc.save();
      },
      name: 'Nuru-Receipt-${widget.transactionCode}',
    );
  }

  pw.Widget _buildPdf(Map<String, dynamic> tx, pw.MemoryImage? logoImage) {
    final currency = (tx['currency_code'] ?? '').toString();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'NURU RECEIPT',
                  style: pw.TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  formatMoney(
                    (tx['gross_amount'] ?? 0) as num,
                    currency: currency,
                  ),
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  (tx['description'] ??
                          (tx['target_type'] ?? '').toString().replaceAll(
                            '_',
                            ' ',
                          ))
                      .toString(),
                ),
              ],
            ),
            pw.Stack(
              alignment: pw.Alignment.center,
              children: [
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(
                    errorCorrectLevel: pw.BarcodeQRCorrectionLevel.high,
                  ),
                  data: _verifyUrl,
                  width: 96,
                  height: 96,
                  drawText: false,
                ),
                if (logoImage != null)
                  pw.Container(
                    width: 22,
                    height: 22,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      shape: pw.BoxShape.circle,
                    ),
                    padding: const pw.EdgeInsets.all(2),
                    child: pw.Image(logoImage),
                  ),
              ],
            ),
          ],
        ),
        pw.Divider(),
        _pdfRow('Reference', (tx['transaction_code'] ?? '').toString()),
        _pdfRow('Date', (tx['initiated_at'] ?? '').toString()),
        if (tx['completed_at'] != null)
          _pdfRow('Completed', tx['completed_at'].toString()),
        _pdfRow('Status', (tx['status'] ?? '').toString().toUpperCase()),
        if (tx['provider'] != null)
          _pdfRow('Method', (tx['provider']['display_name'] ?? '').toString()),
        pw.Divider(),
        _pdfRow(
          'Subtotal',
          formatMoney((tx['net_amount'] ?? 0) as num, currency: currency),
        ),
        _pdfRow(
          'Service fee',
          formatMoney(
            ((tx['gross_amount'] ?? 0) as num) -
                ((tx['net_amount'] ?? 0) as num),
            currency: currency,
          ),
        ),
        _pdfRow(
          'Total',
          formatMoney((tx['gross_amount'] ?? 0) as num, currency: currency),
          bold: true,
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Verify at $_verifyUrl',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    );
  }

  pw.Widget _pdfRow(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: _ReceiptCard(tx: _tx!, verifyUrl: _verifyUrl),
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
            child: SvgPicture.asset(
              'assets/icons/arrow-left-icon.svg',
              width: 22,
              height: 22,
              colorFilter: const ColorFilter.mode(
                AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
      centerTitle: true,
      title: Text(
        'Receipt',
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4, top: 6, bottom: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _sharingPng ? null : _shareAsPng,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: _sharingPng
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : SvgPicture.asset(
                        'assets/icons/share-icon.svg',
                        width: 18,
                        height: 18,
                        colorFilter: const ColorFilter.mode(
                          AppColors.textPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 6, bottom: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _printOrSavePdf,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/print-icon.svg',
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(
                    AppColors.textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final Map<String, dynamic> tx;
  final String verifyUrl;
  const _ReceiptCard({required this.tx, required this.verifyUrl});

  @override
  Widget build(BuildContext context) {
    final status = (tx['status'] ?? '').toString();
    final currency = (tx['currency_code'] ?? '').toString();
    final fee =
        ((tx['gross_amount'] ?? 0) as num) - ((tx['net_amount'] ?? 0) as num);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDEDF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero header with soft gradient ──
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1F1F2E), Color(0xFF111827)],
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'RECEIPT',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _StatusPill(status: status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'AMOUNT',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(
                      (tx['gross_amount'] ?? 0) as num,
                      currency: currency,
                    ),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (tx['description'] ??
                            (tx['target_type'] ?? '').toString().replaceAll(
                              '_',
                              ' ',
                            ))
                        .toString(),
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Details with SVG icon rows ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _iconRow(
                  'assets/icons/secure-shield-icon.svg',
                  'Reference',
                  (tx['transaction_code'] ?? '').toString(),
                ),
                const SizedBox(height: 12),
                _iconRow(
                  'assets/icons/calendar-icon.svg',
                  'Date',
                  _fmt(tx['initiated_at']),
                ),
                if (tx['completed_at'] != null) ...[
                  const SizedBox(height: 12),
                  _iconRow(
                    'assets/icons/clock-icon.svg',
                    'Completed',
                    _fmt(tx['completed_at']),
                  ),
                ],
                const SizedBox(height: 12),
                _iconRow(
                  'assets/icons/info-icon.svg',
                  'Status',
                  _statusLabel(status),
                  valueColor: _statusColor(status),
                ),
                if (tx['provider'] != null) ...[
                  const SizedBox(height: 12),
                  _iconRow(
                    'assets/icons/card-icon.svg',
                    'Method',
                    (tx['provider']['display_name'] ?? '').toString(),
                  ),
                ],
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: NotchedDashedDivider(),
          ),

          // ── Summary breakdown ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                _summaryRow('Subtotal', formatMoney(
                  (tx['net_amount'] ?? 0) as num,
                  currency: currency,
                )),
                const SizedBox(height: 12),
                _summaryRow('Service fee', fee > 0
                    ? formatMoney(fee, currency: currency)
                    : '-',
                    muted: true),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        formatMoney(
                          (tx['gross_amount'] ?? 0) as num,
                          currency: currency,
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: NotchedDashedDivider(),
          ),

          // ── QR code + verify ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFEDEDF2)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: verifyUrl,
                    version: QrVersions.auto,
                    size: 120,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                    embeddedImage: const AssetImage(
                      'assets/images/nuru-logo-square.png',
                    ),
                    embeddedImageStyle: const QrEmbeddedImageStyle(
                      size: Size(22, 22),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'SCAN TO VERIFY',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    letterSpacing: 1.3,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Verify this receipt at\n$verifyUrl',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          if (tx['failure_reason'] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  tx['failure_reason'].toString(),
                  style: GoogleFonts.inter(
                    color: AppColors.error,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconRow(String svg, String label, String value,
      {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset(
          svg,
          width: 16,
          height: 16,
          colorFilter: const ColorFilter.mode(
            AppColors.textTertiary,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, {bool muted = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: muted ? AppColors.textTertiary : AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: muted ? AppColors.textTertiary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      const wk = [
        'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
      ];
      const mo = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${wk[d.weekday % 7]} ${d.day} ${mo[d.month - 1]} ${d.year}  •  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return v.toString();
    }
  }

  String _statusLabel(String s) {
    return {
      'succeeded': 'Paid',
      'pending': 'Pending',
      'processing': 'Processing',
      'failed': 'Failed',
      'cancelled': 'Cancelled',
      'refunded': 'Refunded',
    }[s] ??
        s[0].toUpperCase() + s.substring(1);
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'succeeded':
        return AppColors.success;
      case 'pending':
      case 'processing':
        return AppColors.warning;
      case 'failed':
      case 'cancelled':
        return AppColors.error;
      case 'refunded':
        return AppColors.info;
      default:
        return AppColors.textPrimary;
    }
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  Color get _bg {
    switch (status) {
      case 'succeeded':
        return const Color(0xFFDCFCE7);
      case 'pending':
      case 'processing':
        return const Color(0xFFFEF3C7);
      case 'failed':
      case 'cancelled':
        return const Color(0xFFFEE2E2);
      case 'refunded':
        return const Color(0xFFDBEAFE);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  Color get _fg {
    switch (status) {
      case 'succeeded':
        return const Color(0xFF15803D);
      case 'pending':
      case 'processing':
        return const Color(0xFFB45309);
      case 'failed':
      case 'cancelled':
        return const Color(0xFFB91C1C);
      case 'refunded':
        return const Color(0xFF1D4ED8);
      default:
        return AppColors.textPrimary;
    }
  }

  String get _label {
    return {
      'succeeded': 'Paid',
      'pending': 'Pending',
      'processing': 'Processing',
      'failed': 'Failed',
      'cancelled': 'Cancelled',
      'refunded': 'Refunded',
    }[status] ??
        status[0].toUpperCase() + status.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _fg,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
