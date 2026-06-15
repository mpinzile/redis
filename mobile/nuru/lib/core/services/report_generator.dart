import '../../core/utils/money_format.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as xl;
import 'events_service.dart';

/// Premium PDF & Excel report generator for Nuru Events.
/// Design language: editorial, clean, modern - inspired by Stripe/Linear reports.
/// Aligned with web version report generators.
class ReportGenerator {
  static final _currencyFormat = NumberFormat('#,##0', 'en');

  // ─── Premium Color Palette ───
  static const _ink = PdfColor.fromInt(0xFF0A1C40);
  static const _inkMed = PdfColor.fromInt(0xFF3A4D6A);
  static const _inkLight = PdfColor.fromInt(0xFF6B7F9E);
  static const _inkMuted = PdfColor.fromInt(0xFF9EADC2);
  static const _surface = PdfColor.fromInt(0xFFFFFFFF);
  static const _surfaceTint = PdfColor.fromInt(0xFFF6F7F9);
  static const _surfaceWarm = PdfColor.fromInt(0xFFFAF9F7);
  static const _borderSoft = PdfColor.fromInt(0xFFE8ECF2);
  static const _borderFaint = PdfColor.fromInt(0xFFF0F2F5);
  static const _accentOrange = PdfColor.fromInt(0xFFE7A622);
  static const _accentOrangeSoft = PdfColor.fromInt(0xFFFFF4F0);
  static const _accentGreen = PdfColor.fromInt(0xFF22C55E);
  static const _accentGreenSoft = PdfColor.fromInt(0xFFF0FDF4);
  static const _accentBlue = PdfColor.fromInt(0xFF2471E7);
  static const _accentBlueSoft = PdfColor.fromInt(0xFFF0F5FF);
  static const _accentAmber = PdfColor.fromInt(0xFFF59E0B);
  static const _accentAmberSoft = PdfColor.fromInt(0xFFFFFBEB);
  static const _accentRed = PdfColor.fromInt(0xFFDC2626);
  static const _accentRedSoft = PdfColor.fromInt(0xFFFEF2F2);
  static const _accentPurple = PdfColor.fromInt(0xFF7C3AED);

  // ─── Helpers ───

  static String _fmt(dynamic amount) {
    if (amount == null) return '${getActiveCurrency()} 0';
    final n = _toNum(amount);
    return '${getActiveCurrency()} ${_currencyFormat.format(n.round())}';
  }

  static double _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static String _s(dynamic v) {
    if (v == null) return '';
    if (v is Map) {
      // Extract name/title/label from map objects (e.g. event_type: {id:..., name: Wedding, icon: Ring})
      return (v['name'] ?? v['title'] ?? v['label'] ?? '').toString();
    }
    return v.toString();
  }

  static String _dateNow() => DateFormat('d MMMM yyyy').format(DateTime.now());

  static String _timeNow() => DateFormat('h:mm a').format(DateTime.now());

  static String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '-';
    final s = dateStr.toString();
    if (s.isEmpty) return '-';
    try {
      return DateFormat('d MMM yyyy').format(DateTime.parse(s));
    } catch (_) {
      return s;
    }
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  // ════════════════════════════════════════════════════════════════
  //  PREMIUM PDF DESIGN SYSTEM
  // ════════════════════════════════════════════════════════════════

  static Future<Uint8List?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/images/nuru-logo-square.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Clean editorial header - no colored top bar. Logo + slogan on left,
  /// report type + event subtitle + date on right, separated by a hairline.
  static pw.Widget _coverHeader(String reportType, String subtitle, {Uint8List? logoBytes, String? eventTitle}) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 22),
      padding: const pw.EdgeInsets.only(bottom: 14),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _borderSoft, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoBytes != null)
                pw.Container(width: 36, height: 36, child: pw.Image(pw.MemoryImage(logoBytes)))
              else
                pw.Text('Nuru', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink)),
              pw.SizedBox(height: 4),
              pw.Text('Plan Smarter', style: pw.TextStyle(fontSize: 8, color: _inkMuted, letterSpacing: 0.4)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(reportType, style: pw.TextStyle(
                fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink, letterSpacing: 0.2,
              )),
              pw.SizedBox(height: 3),
              pw.Text(
                eventTitle ?? subtitle,
                style: pw.TextStyle(fontSize: 9.5, color: _inkMed),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                '${_dateNow()} · ${_timeNow()}',
                style: pw.TextStyle(fontSize: 8, color: _inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Quiet footer with attribution and pagination.
  static pw.Widget _pageFooter(pw.Context ctx) {
    final year = DateTime.now().year;
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borderFaint, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Nuru Events Workspace  \u00b7  \u00a9 $year SEWMR TECHNOLOGIES',
            style: pw.TextStyle(fontSize: 7, color: _inkMuted, letterSpacing: 0.3),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 7, color: _inkMuted),
          ),
        ],
      ),
    );
  }

  /// Clean metric tile - no colored side strip. Accent/value colors accepted
  /// for signature compatibility but ignored to keep the look monochrome.
  static pw.Widget _metricCard(String label, String value, {PdfColor accent = _accentOrange, PdfColor? valueColor}) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: pw.BoxDecoration(
          color: _surface,
          border: pw.Border.all(color: _borderSoft, width: 0.6),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label.toUpperCase(), style: pw.TextStyle(
              fontSize: 6.5, color: _inkMuted, letterSpacing: 0.8,
            )),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(
              fontSize: 13.5, fontWeight: pw.FontWeight.bold, color: _ink,
            )),
          ],
        ),
      ),
    );
  }

  /// Editorial section heading - no colored bar, just an uppercase title with
  /// a thin underline rule. Keeps the document calm and readable.
  static pw.Widget _sectionHeading(String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10, top: 6),
      padding: const pw.EdgeInsets.only(bottom: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _borderSoft, width: 0.6)),
      ),
      child: pw.Text(text.toUpperCase(), style: pw.TextStyle(
        fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _inkMed, letterSpacing: 1.4,
      )),
    );
  }

  /// Clean table - neutral header, hairline row separators, no row shading.
  static pw.Widget _premiumTable({
    required List<String> headers,
    required List<List<String>> data,
    Map<int, pw.FlexColumnWidth>? columnWidths,
    Map<int, pw.Alignment>? alignments,
  }) {
    final defaultAlignments = <int, pw.Alignment>{};
    if (alignments != null) defaultAlignments.addAll(alignments);

    return pw.Table(
      border: null,
      columnWidths: columnWidths?.map((k, v) => MapEntry(k, v)) ?? {},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.8)),
          ),
          children: headers.asMap().entries.map((e) => pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            alignment: defaultAlignments[e.key] ?? pw.Alignment.centerLeft,
            child: pw.Text(e.value.toUpperCase(), style: pw.TextStyle(
              fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: _inkMed, letterSpacing: 0.6,
            )),
          )).toList(),
        ),
        ...data.asMap().entries.map((e) => pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _borderFaint, width: 0.4)),
          ),
          children: e.value.asMap().entries.map((cell) => pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            alignment: defaultAlignments[cell.key] ?? pw.Alignment.centerLeft,
            child: pw.Text(cell.value, style: pw.TextStyle(
              fontSize: 8.5, color: _ink,
            )),
          )).toList(),
        )),
      ],
    );
  }

  /// Minimal status badge - outlined pill, single ink colour. No tinted fills.
  static pw.Widget _statusBadge(String status) {
    final normalized = status.toLowerCase().replaceAll('_', ' ');
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _borderSoft, width: 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Text(
        normalized.isEmpty ? '-' : normalized[0].toUpperCase() + normalized.substring(1),
        style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _inkMed),
      ),
    );
  }

  static pw.Widget _premiumTableWithBadges({
    required List<String> headers,
    required List<List<dynamic>> data,
    required int statusColumnIndex,
    Map<int, pw.FlexColumnWidth>? columnWidths,
    Map<int, pw.Alignment>? alignments,
  }) {
    final defaultAlignments = <int, pw.Alignment>{};
    if (alignments != null) defaultAlignments.addAll(alignments);

    return pw.Table(
      border: null,
      columnWidths: columnWidths?.map((k, v) => MapEntry(k, v)) ?? {},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.8)),
          ),
          children: headers.asMap().entries.map((e) => pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            alignment: defaultAlignments[e.key] ?? pw.Alignment.centerLeft,
            child: pw.Text(e.value.toUpperCase(), style: pw.TextStyle(
              fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: _inkMed, letterSpacing: 0.6,
            )),
          )).toList(),
        ),
        ...data.asMap().entries.map((e) => pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _borderFaint, width: 0.4)),
          ),
          children: e.value.asMap().entries.map((cell) => pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            alignment: defaultAlignments[cell.key] ?? pw.Alignment.centerLeft,
            child: cell.key == statusColumnIndex
                ? _statusBadge(cell.value.toString())
                : _buildCellText(cell.value.toString(), cell.key),
          )).toList(),
        )),
      ],
    );
  }

  /// "est." marker - small uppercase tag, no color fill.
  static pw.Widget _buildCellText(String text, int colIndex) {
    if (text.endsWith(' est.')) {
      final mainText = text.substring(0, text.length - 5);
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(mainText, style: pw.TextStyle(fontSize: 8.5, color: _ink)),
          pw.SizedBox(width: 4),
          pw.Text('est.', style: pw.TextStyle(
            fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: _inkMuted, letterSpacing: 0.5,
          )),
        ],
      );
    }
    return pw.Text(text, style: pw.TextStyle(fontSize: 8.5, color: _ink));
  }

  /// Summary total row - thin top rule, no fill, accent param ignored.
  static pw.Widget _summaryRow(String label, String value, {PdfColor accent = _ink}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _ink, width: 0.8)),
      ),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _inkMed)),
        pw.Text(value, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _ink)),
      ]),
    );
  }

  /// Minimal progress bar - no surrounding panel. Single ink fill.
  static pw.Widget _progressBar(String label, double percentage, {PdfColor color = _accentOrange}) {
    final clamped = percentage.clamp(0.0, 100.0);
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _inkMed)),
          pw.Text('${clamped.toStringAsFixed(1)}%', style: pw.TextStyle(
            fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink,
          )),
        ]),
        pw.SizedBox(height: 5),
        pw.Container(
          width: double.infinity,
          height: 4,
          decoration: pw.BoxDecoration(
            color: _borderFaint,
            borderRadius: pw.BorderRadius.circular(2),
          ),
          child: pw.Row(children: [
            pw.Expanded(
              flex: (clamped * 10).round().clamp(1, 1000),
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  color: _ink,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
            ),
            if (clamped < 100)
              pw.Expanded(
                flex: ((100 - clamped) * 10).round().clamp(1, 1000),
                child: pw.SizedBox(),
              ),
          ]),
        ),
      ]),
    );
  }

  /// Quiet note box - neutral border, no colored side bar or tinted fill.
  static pw.Widget _callout(String text, {PdfColor bg = _accentBlueSoft, PdfColor border = _accentBlue, PdfColor textColor = _inkMed}) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _borderSoft, width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 8.5, color: _inkMed, lineSpacing: 2.5)),
    );
  }

  /// Key-value detail row for event info
  static pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(children: [
        pw.SizedBox(
          width: 100,
          child: pw.Text(label, style: pw.TextStyle(fontSize: 8.5, color: _inkMuted)),
        ),
        pw.Expanded(
          child: pw.Text(value, style: pw.TextStyle(fontSize: 8.5, color: _ink, fontWeight: pw.FontWeight.bold)),
        ),
      ]),
    );
  }

  // ─── Save helpers ───

  static Future<Map<String, dynamic>> _savePdf(pw.Document pdf, String prefix) async {
    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${prefix}_$ts.pdf');
    await file.writeAsBytes(bytes);
    return {'success': true, 'message': 'Report generated', 'path': file.path, 'bytes': Uint8List.fromList(bytes)};
  }

  // ════════════════════════════════════════════════════════════════
  //  XLSX HELPERS
  // ════════════════════════════════════════════════════════════════

  static xl.CellStyle _xlHeaderStyle() {
    return xl.CellStyle(
      bold: true,
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: xl.ExcelColor.fromHexString('#0A1C40'),
      horizontalAlign: xl.HorizontalAlign.Center,
      verticalAlign: xl.VerticalAlign.Center,
      fontSize: 11,
    );
  }

  static xl.CellStyle _xlTitleStyle() {
    return xl.CellStyle(
      bold: true, fontSize: 14,
      fontColorHex: xl.ExcelColor.fromHexString('#0A1C40'),
    );
  }

  static xl.CellStyle _xlSubtitleStyle() {
    return xl.CellStyle(
      bold: true, fontSize: 11,
      fontColorHex: xl.ExcelColor.fromHexString('#3A4D6A'),
    );
  }

  static xl.CellStyle _xlTotalStyle() {
    return xl.CellStyle(
      bold: true, fontSize: 11,
      fontColorHex: xl.ExcelColor.fromHexString('#0A1C40'),
      backgroundColorHex: xl.ExcelColor.fromHexString('#F6F7F9'),
      topBorder: xl.Border(borderStyle: xl.BorderStyle.Thin),
    );
  }

  static void _xlSetRow(xl.Sheet sheet, int row, List<String> values, {xl.CellStyle? style}) {
    for (int col = 0; col < values.length; col++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
      cell.value = xl.TextCellValue(values[col]);
      if (style != null) cell.cellStyle = style;
    }
  }

  static Future<Map<String, dynamic>> _saveXlsx(xl.Excel excel, String prefix) async {
    final bytes = excel.save();
    if (bytes == null) return {'success': false, 'message': 'Failed to generate Excel file'};
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${prefix}_$ts.xlsx');
    await file.writeAsBytes(bytes);
    return {'success': true, 'message': 'Report generated', 'path': file.path};
  }

  // ════════════════════════════════════════════════════════════════
  //  1. BUDGET REPORT
  //  Web: generateBudgetItemsReport.ts
  //  Summary cards: Event Budget, Total Estimated, Total Actual
  //  Table: S/N, Category, Item, Vendor, Budget (combined est/actual with "est." label), Status
  // ════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> generateBudgetReport(
    String eventId, {
    required String format,
    List<dynamic>? budgetItems,
    Map<String, dynamic>? summary,
    List<dynamic>? expenses,
    Map<String, dynamic>? expenseSummary,
    String? eventTitle,
    double? eventBudget,
  }) async {
    try {
      budgetItems ??= [];
      expenses ??= [];
      if (budgetItems.isEmpty) {
        final results = await Future.wait([
          EventsService.getBudget(eventId),
          EventsService.getExpenses(eventId),
        ]);
        if (results[0]['success'] == true) {
          budgetItems = results[0]['data']?['items'] ?? results[0]['data']?['budget_items'] ?? [];
          summary = _asMap(results[0]['data']?['summary']);
        }
        if (results[1]['success'] == true) {
          expenses = results[1]['data']?['expenses'] ?? [];
          expenseSummary = _asMap(results[1]['data']?['summary']);
        }
      }
      summary ??= {};
      expenseSummary ??= {};

      if (format == 'xlsx') {
        return await _budgetXlsx(budgetItems!, summary, expenses!);
      } else {
        return await _budgetPdf(budgetItems!, summary, expenses!, expenseSummary, eventTitle: eventTitle, eventBudget: eventBudget);
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed: $e'};
    }
  }

  /// Helper: get effective cost (actual if > 0, else estimate) - matches web logic
  static double _getEffectiveCost(Map<String, dynamic> item) {
    final actual = _toNum(item['actual_cost']);
    return actual > 0 ? actual : _toNum(item['estimated_cost']);
  }

  /// Helper: is this an estimate? (no actual cost) - matches web "est." label
  static bool _isEstimate(Map<String, dynamic> item) {
    final actual = _toNum(item['actual_cost']);
    return actual <= 0 && _toNum(item['estimated_cost']) > 0;
  }

  static Future<Map<String, dynamic>> _budgetPdf(
    List<dynamic> items, Map<String, dynamic> summary,
    List<dynamic> expenses, Map<String, dynamic> expSummary, {
    String? eventTitle,
    double? eventBudget,
  }) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final sorted = items.map(_asMap).toList()
      ..sort((a, b) => _s(a['category']).compareTo(_s(b['category'])));

    final totalEstimated = _toNum(summary['total_estimated']);
    final totalActual = _toNum(summary['total_actual']);
    // Overall budget = sum of effective costs (matches web)
    final overallBudget = sorted.fold<double>(0, (sum, item) => sum + _getEffectiveCost(item));
    final includesEstimates = sorted.any((item) => _isEstimate(item));
    final budget = eventBudget ?? _toNum(summary['event_budget']);

    // Category breakdown matching web
    final Map<String, Map<String, dynamic>> catMap = {};
    for (final item in sorted) {
      final cat = _s(item['category']).isEmpty ? 'Uncategorized' : _s(item['category']);
      catMap.putIfAbsent(cat, () => {'estimated': 0.0, 'actual': 0.0, 'effective': 0.0, 'count': 0});
      catMap[cat]!['estimated'] = (catMap[cat]!['estimated'] as double) + _toNum(item['estimated_cost']);
      catMap[cat]!['actual'] = (catMap[cat]!['actual'] as double) + _toNum(item['actual_cost']);
      catMap[cat]!['effective'] = (catMap[cat]!['effective'] as double) + _getEffectiveCost(item);
      catMap[cat]!['count'] = (catMap[cat]!['count'] as int) + 1;
    }
    final sortedCategories = catMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    final title = _s(eventTitle).isNotEmpty ? _s(eventTitle) : 'Budget Report';

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      header: (ctx) => ctx.pageNumber == 1
          ? _coverHeader('Budget Report', title, logoBytes: logo, eventTitle: eventTitle)
          : pw.SizedBox(),
      footer: (ctx) => _pageFooter(ctx),
      build: (ctx) => [
        // Summary cards matching web: Event Budget, Total Estimated, Total Actual
        pw.Row(children: [
          if (budget > 0) ...[
            _metricCard('Event Budget', _fmt(budget), accent: _accentOrange),
            pw.SizedBox(width: 8),
          ],
          _metricCard('Total Estimated', _fmt(totalEstimated), accent: _accentBlue),
          pw.SizedBox(width: 8),
          _metricCard('Total Actual', _fmt(totalActual), accent: _accentGreen),
        ]),
        pw.SizedBox(height: 18),

        // Category Summary table (matches web)
        _sectionHeading('Category Summary'),
        _premiumTable(
          headers: ['S/N', 'Category', 'Items', 'Budget'],
          columnWidths: {
            0: const pw.FlexColumnWidth(0.5),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(0.8),
            3: const pw.FlexColumnWidth(1.5),
          },
          alignments: {2: pw.Alignment.center, 3: pw.Alignment.centerRight},
          data: sortedCategories.asMap().entries.map((e) {
            final cat = e.value;
            return [
              '${e.key + 1}',
              cat.key,
              '${cat.value['count']}',
              _fmt(cat.value['effective']),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 18),

        // Budget Items table - combined "Budget" column with "est." label (matches web)
        _sectionHeading('Budget Items'),
        _premiumTableWithBadges(
          headers: ['S/N', 'Category', 'Item', 'Vendor', 'Budget', 'Status'],
          statusColumnIndex: 5,
          columnWidths: {
            0: const pw.FlexColumnWidth(0.4),
            1: const pw.FlexColumnWidth(1.3),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(1.3),
            4: const pw.FlexColumnWidth(1.3),
            5: const pw.FlexColumnWidth(1),
          },
          alignments: {4: pw.Alignment.centerRight},
          data: sorted.asMap().entries.map((e) {
            final item = e.value;
            final cost = _getEffectiveCost(item);
            final isEst = _isEstimate(item);
            return [
              '${e.key + 1}',
              _s(item['category']),
              _s(item['description'] ?? item['item_name']),
              _s(item['vendor_name']),
              '${_fmt(cost)}${isEst ? ' est.' : ''}',
              _s(item['status'] ?? 'pending'),
            ];
          }).toList(),
        ),
        _summaryRow(
          '${includesEstimates ? 'Overall Event Budget (includes estimates)' : 'Overall Event Budget'} (${sorted.length} items)',
          _fmt(overallBudget),
        ),
      ],
    ));

    return _savePdf(pdf, 'budget_report');
  }

  static Future<Map<String, dynamic>> _budgetXlsx(
    List<dynamic> items, Map<String, dynamic> summary, List<dynamic> expenses,
  ) async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Budget Report'];

    int row = 0;
    _xlSetRow(sheet, row++, ['BUDGET REPORT'], style: _xlTitleStyle());
    _xlSetRow(sheet, row++, ['Generated: ${DateFormat('MMM d, yyyy HH:mm').format(DateTime.now())}']);
    row++;
    _xlSetRow(sheet, row++, ['SUMMARY'], style: _xlSubtitleStyle());
    _xlSetRow(sheet, row++, ['Total Estimated', _fmt(_toNum(summary['total_estimated']))]);
    _xlSetRow(sheet, row++, ['Total Actual', _fmt(_toNum(summary['total_actual']))]);
    _xlSetRow(sheet, row++, ['Variance', _fmt(_toNum(summary['variance']))]);
    row++;
    _xlSetRow(sheet, row++, ['BUDGET ITEMS'], style: _xlSubtitleStyle());
    _xlSetRow(sheet, row++, ['Category', 'Description', 'Estimated', 'Actual', 'Status', 'Vendor'], style: _xlHeaderStyle());

    for (final raw in items) {
      final item = _asMap(raw);
      _xlSetRow(sheet, row++, [
        _s(item['category']), _s(item['description'] ?? item['item_name']),
        _toNum(item['estimated_cost']).toStringAsFixed(0),
        _toNum(item['actual_cost']).toStringAsFixed(0),
        _s(item['status'] ?? 'pending'), _s(item['vendor_name']),
      ]);
    }

    if (expenses.isNotEmpty) {
      row++;
      _xlSetRow(sheet, row++, ['EXPENSES'], style: _xlSubtitleStyle());
      _xlSetRow(sheet, row++, ['Category', 'Description', 'Amount', 'Vendor', 'Date'], style: _xlHeaderStyle());
      for (final raw in expenses) {
        final exp = _asMap(raw);
        _xlSetRow(sheet, row++, [
          _s(exp['category']), _s(exp['description']),
          _toNum(exp['amount']).toStringAsFixed(0),
          _s(exp['vendor_name']),
          _formatDate(exp['expense_date'] ?? exp['created_at']),
        ]);
      }
    }

    for (int c = 0; c < 6; c++) sheet.setColumnWidth(c, 20);
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    return _saveXlsx(excel, 'budget_report');
  }

  // ════════════════════════════════════════════════════════════════
  //  2. AI BUDGET ESTIMATE REPORT
  //  Web: generateBudgetReport.ts
  //  Summary cards: Report Type (AI Budget Estimate), Generated date, Currency
  //  Info bar matches web
  // ════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> generateAiBudgetEstimateReport({
    required List<dynamic> items,
    String? eventTitle,
    String? eventType,
    String? location,
    String? expectedGuests,
    String? total,
    String? content,
  }) async {
    try {
      return await _aiBudgetEstimatePdf(
        items,
        eventTitle: eventTitle,
        eventType: eventType,
        location: location,
        expectedGuests: expectedGuests,
        total: total,
        content: content,
      );
    } catch (e) {
      return {'success': false, 'message': 'Failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> _aiBudgetEstimatePdf(
    List<dynamic> items, {
    String? eventTitle,
    String? eventType,
    String? location,
    String? expectedGuests,
    String? total,
    String? content,
  }) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final sorted = items.map(_asMap).toList()..sort((a, b) => _s(a['category']).compareTo(_s(b['category'])));
    final extractedTotal = _toNum(total);
    final estimatedTotal = extractedTotal > 0 ? extractedTotal : sorted.fold<double>(0, (sum, item) => sum + _toNum(item['estimated_cost']));
    final notes = _extractAiBudgetNotes(content);
    final title = _s(eventTitle).isNotEmpty ? _s(eventTitle) : 'Budget Estimate';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
        header: (ctx) => ctx.pageNumber == 1
            ? _coverHeader('Budget Estimate', title, logoBytes: logo, eventTitle: eventTitle)
            : pw.SizedBox(),
        footer: (ctx) => _pageFooter(ctx),
        build: (ctx) => [
          // AI badge - neutral framed note
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderSoft, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('AI-Generated Estimate', style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink,
                )),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Based on your event brief and current conversation context.',
                  style: pw.TextStyle(fontSize: 8.5, color: _inkMed, lineSpacing: 2),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          // Info bar - outline only, no fill
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderSoft, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(children: [
              pw.Text('Report Type: ', style: pw.TextStyle(fontSize: 8, color: _inkMuted)),
              pw.Text('AI Budget Estimate', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _ink)),
              pw.SizedBox(width: 24),
              pw.Text('Generated: ', style: pw.TextStyle(fontSize: 8, color: _inkMuted)),
              pw.Text(_dateNow(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _ink)),
              pw.SizedBox(width: 24),
              pw.Text('Currency: ', style: pw.TextStyle(fontSize: 8, color: _inkMuted)),
              pw.Text('TZS', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _ink)),
            ]),
          ),
          pw.SizedBox(height: 18),
          if (_s(eventType).isNotEmpty || _s(location).isNotEmpty || _s(expectedGuests).isNotEmpty) ...[
            _sectionHeading('Event Details'),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (_s(eventType).isNotEmpty) _detailRow('Event Type', _s(eventType)),
                if (_s(location).isNotEmpty) _detailRow('Location', _s(location)),
                if (_s(expectedGuests).isNotEmpty) _detailRow('Expected Guests', _s(expectedGuests)),
              ]),
            ),
            pw.SizedBox(height: 14),
          ],
          _sectionHeading('Budget Breakdown'),
          _premiumTable(
            headers: ['#', 'Category', 'Description', 'Estimated Cost'],
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(3),
              3: const pw.FlexColumnWidth(1.5),
            },
            alignments: {3: pw.Alignment.centerRight},
            data: sorted.asMap().entries.map((entry) {
              final item = entry.value;
              return ['${entry.key + 1}', _s(item['category']), _s(item['item_name'] ?? item['description']), _fmt(item['estimated_cost'])];
            }).toList(),
          ),
          _summaryRow('Estimated Total (${sorted.length} items)', _fmt(estimatedTotal)),
          if (notes.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _sectionHeading('Planning Notes'),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: notes.map((note) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Container(
                      width: 3, height: 3,
                      margin: const pw.EdgeInsets.only(top: 5, right: 8),
                      decoration: const pw.BoxDecoration(color: _ink, shape: pw.BoxShape.circle),
                    ),
                    pw.Expanded(child: pw.Text(note, style: pw.TextStyle(fontSize: 8.5, color: _inkMed, lineSpacing: 2))),
                  ]),
                )).toList(),
              ),
            ),
          ],
          _callout(
            'This is an AI-generated estimate. Actual costs may vary based on vendor availability, season, and specific requirements.',
            bg: _accentAmberSoft,
            border: _accentAmber,
          ),
        ],
      ),
    );

    return _savePdf(pdf, 'budget_estimate');
  }

  static List<String> _extractAiBudgetNotes(String? content) {
    if (content == null || content.trim().isEmpty) return const [];
    return content
        .split('\n')
        .map((line) => line.trim().replaceAll('**', ''))
        .where((line) => line.isNotEmpty && !line.contains('|') && !line.startsWith('#') && !RegExp(r'^[-: ]+$').hasMatch(line))
        .take(3)
        .toList();
  }

  // ════════════════════════════════════════════════════════════════
  //  3. CONTRIBUTIONS REPORT
  //  Web: generatePdf.ts (generateContributionReportHtml)
  //  Summary cards: Event Budget, Total Collected, Budget Shortfall,
  //                 Total Pledged, Outstanding Pledge, Unpledged
  //  + Budget/Pledge coverage text
  // ════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> generateContributionsReport(
    String eventId, {
    required String format,
    List<dynamic>? contributions,
    Map<String, dynamic>? summary,
    double? eventBudget,
    String? eventTitle,
  }) async {
    try {
      if (contributions == null || contributions.isEmpty) {
        final res = await EventsService.getEventContributors(eventId);
        if (res['success'] == true) {
          contributions = res['data']?['event_contributors'] ?? [];
          summary = _asMap(res['data']?['summary']);
        }
      }
      contributions ??= [];
      summary ??= {};

      if (format == 'xlsx') {
        return await _contributionsXlsx(contributions, summary, eventBudget);
      } else {
        return await _contributionsPdf(contributions, summary, eventBudget, eventTitle: eventTitle);
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> _contributionsPdf(
    List<dynamic> items, Map<String, dynamic> summary, double? eventBudget, {String? eventTitle}
  ) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final sorted = items.map(_asMap).toList()
      ..sort((a, b) {
        final nameA = _s(a['contributor'] is Map ? (a['contributor'] as Map)['name'] : a['contributor_name']);
        final nameB = _s(b['contributor'] is Map ? (b['contributor'] as Map)['name'] : b['contributor_name']);
        return nameA.compareTo(nameB);
      });

    final totalPledged = _toNum(summary['total_pledged'] ?? summary['total_amount']);
    final totalPaid = _toNum(summary['total_paid'] ?? summary['total_confirmed']);
    final totalBalance = sorted.fold<double>(0, (sum, c) {
      final explicit = c['balance'];
      if (explicit != null) return sum + _toNum(explicit);
      final pledged = _toNum(c['pledge_amount']);
      final paid = _toNum(c['total_paid'] ?? c['amount']);
      return sum + (pledged - paid).clamp(0.0, double.infinity).toDouble();
    });
    final outstandingPledge = totalBalance;
    final budget = eventBudget ?? 0.0;
    final budgetShortfall = budget > 0 ? (budget - totalPaid).clamp(0.0, double.infinity) : 0.0;
    final unpledged = budget > 0 ? (budget - totalPledged).clamp(0.0, double.infinity) : 0.0;

    final title = _s(eventTitle).isNotEmpty ? _s(eventTitle) : 'Contribution Report';

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      header: (ctx) => ctx.pageNumber == 1
          ? _coverHeader('Contribution Report', title, logoBytes: logo, eventTitle: eventTitle)
          : pw.SizedBox(),
      footer: (ctx) => _pageFooter(ctx),
      build: (ctx) => [
        // Row 1: Event Budget, Total Collected, Budget Shortfall (matches web)
        if (budget > 0) ...[
          pw.Row(children: [
            _metricCard('Event Budget', _fmt(budget), accent: _accentOrange),
            pw.SizedBox(width: 8),
            _metricCard('Total Collected', _fmt(totalPaid), accent: _accentGreen, valueColor: _accentGreen),
            pw.SizedBox(width: 8),
            _metricCard('Budget Shortfall', _fmt(budgetShortfall), accent: _accentRed, valueColor: budgetShortfall > 0 ? _accentRed : _accentGreen),
          ]),
          pw.SizedBox(height: 8),
          // Row 2: Total Pledged, Outstanding Pledge, Unpledged (matches web)
          pw.Row(children: [
            _metricCard('Total Pledged', _fmt(totalPledged), accent: _accentPurple, valueColor: _accentPurple),
            pw.SizedBox(width: 8),
            _metricCard('Outstanding Pledge', _fmt(outstandingPledge), accent: _accentAmber, valueColor: _accentAmber),
            pw.SizedBox(width: 8),
            _metricCard('Unpledged', _fmt(unpledged), accent: _inkMuted),
          ]),
        ] else ...[
          // Without budget: show pledged, collected, outstanding
          pw.Row(children: [
            _metricCard('Total Pledged', _fmt(totalPledged), accent: _accentPurple, valueColor: _accentPurple),
            pw.SizedBox(width: 8),
            _metricCard('Total Collected', _fmt(totalPaid), accent: _accentGreen, valueColor: _accentGreen),
            pw.SizedBox(width: 8),
            _metricCard('Outstanding Pledge', _fmt(outstandingPledge), accent: _accentAmber, valueColor: _accentAmber),
          ]),
        ],
        // Budget/Pledge coverage text (matches web)
        if (budget > 0) ...[
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.RichText(text: pw.TextSpan(children: [
                pw.TextSpan(text: 'Budget coverage: ', style: pw.TextStyle(fontSize: 8, color: _inkLight)),
                pw.TextSpan(text: '${(totalPaid / budget * 100).toStringAsFixed(1)}%', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _accentGreen)),
                pw.TextSpan(text: ' of event budget collected.', style: pw.TextStyle(fontSize: 8, color: _inkLight)),
              ])),
              pw.RichText(text: pw.TextSpan(children: [
                pw.TextSpan(text: 'Pledge coverage: ', style: pw.TextStyle(fontSize: 8, color: _inkLight)),
                pw.TextSpan(text: '${(totalPledged / budget * 100).toStringAsFixed(1)}%', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _accentPurple)),
                pw.TextSpan(text: ' of event budget.', style: pw.TextStyle(fontSize: 8, color: _inkLight)),
              ])),
            ]),
          ),
        ],
        if (totalPledged > 0) _progressBar(
          'Collection Rate',
          totalPaid / totalPledged * 100,
          color: _accentGreen,
        ),
        if (budget > 0) _progressBar(
          'Budget Coverage',
          totalPaid / budget * 100,
          color: _accentOrange,
        ),
        pw.SizedBox(height: 24),
        _sectionHeading('Contributor Details'),
        _premiumTable(
          headers: ['S/N', 'Contributor', 'Pledged', 'Paid', 'Balance'],
          columnWidths: {
            0: const pw.FlexColumnWidth(0.5),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1.5),
          },
          alignments: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
          data: sorted.asMap().entries.map((e) {
            final c = e.value;
            final name = c['contributor'] is Map ? _s((c['contributor'] as Map)['name']) : _s(c['contributor_name']);
            final pledged = _toNum(c['pledge_amount']);
            final paid = _toNum(c['total_paid'] ?? c['amount']);
            final balance = c['balance'] != null
                ? _toNum(c['balance'])
                : (pledged - paid).clamp(0.0, double.infinity).toDouble();
            return [
              '${e.key + 1}',
              name.isEmpty ? 'Anonymous' : name,
              _fmt(pledged), _fmt(paid), _fmt(balance),
            ];
          }).toList(),
        ),
        _summaryRow('Balance Total (${sorted.length} contributors)', _fmt(totalBalance), accent: totalBalance > 0 ? _accentRed : _accentGreen),
      ],
    ));

    return _savePdf(pdf, 'contributions_report');
  }

  static Future<Map<String, dynamic>> _contributionsXlsx(
    List<dynamic> items, Map<String, dynamic> summary, double? eventBudget,
  ) async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Contributions'];
    final totalPledged = _toNum(summary['total_pledged'] ?? summary['total_amount']);
    final totalPaid = _toNum(summary['total_paid'] ?? summary['total_confirmed']);
    double totalBalance = 0;

    int row = 0;
    _xlSetRow(sheet, row++, ['CONTRIBUTIONS REPORT'], style: _xlTitleStyle());
    _xlSetRow(sheet, row++, ['Generated: ${DateFormat('MMM d, yyyy HH:mm').format(DateTime.now())}']);
    row++;
    _xlSetRow(sheet, row++, ['Total Pledged', _fmt(totalPledged)]);
    _xlSetRow(sheet, row++, ['Total Paid', _fmt(totalPaid)]);
    if (eventBudget != null) _xlSetRow(sheet, row++, ['Event Budget', _fmt(eventBudget)]);
    _xlSetRow(sheet, row++, ['Contributors', '${items.length}']);
    row++;
    _xlSetRow(sheet, row++, ['Contributor', 'Pledged', 'Paid', 'Balance'], style: _xlHeaderStyle());

    for (final raw in items) {
      final c = _asMap(raw);
      final name = c['contributor'] is Map ? _s((c['contributor'] as Map)['name']) : _s(c['contributor_name']);
      final pledged = _toNum(c['pledge_amount']);
      final paid = _toNum(c['total_paid'] ?? c['amount']);
      final balance = c['balance'] != null
          ? _toNum(c['balance'])
          : (pledged - paid).clamp(0.0, double.infinity).toDouble();
      totalBalance += balance;
      _xlSetRow(sheet, row++, [
        name.isEmpty ? 'Anonymous' : name,
        pledged.toStringAsFixed(0), paid.toStringAsFixed(0),
        balance.toStringAsFixed(0),
      ]);
    }

    _xlSetRow(sheet, row, ['TOTAL', totalPledged.toStringAsFixed(0), totalPaid.toStringAsFixed(0), totalBalance.toStringAsFixed(0)], style: _xlTotalStyle());

    for (int c = 0; c < 4; c++) sheet.setColumnWidth(c, 22);
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    return _saveXlsx(excel, 'contributions_report');
  }

  // ════════════════════════════════════════════════════════════════
  //  4. EXPENSES REPORT
  //  Web: generatePdf.ts (generateExpenseReportHtml)
  //  Summary cards: Event Budget, Total Collected, Total Expenses, Remaining Balance
  //  + Category Summary table
  // ════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> generateExpensesReport(
    String eventId, {
    required String format,
    List<dynamic>? expenses,
    Map<String, dynamic>? summary,
    String? eventTitle,
    double? eventBudget,
    double? totalRaised,
  }) async {
    try {
      if (expenses == null || expenses.isEmpty) {
        final res = await EventsService.getExpenses(eventId);
        if (res['success'] == true) {
          expenses = res['data']?['expenses'] ?? [];
          summary = _asMap(res['data']?['summary']);
        }
      }
      expenses ??= [];
      summary ??= {};

      if (format == 'xlsx') {
        return await _expensesXlsx(expenses, summary);
      } else {
        return await _expensesPdf(expenses, summary, eventTitle: eventTitle, eventBudget: eventBudget, totalRaised: totalRaised);
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> _expensesPdf(
    List<dynamic> items, Map<String, dynamic> summary, {
    String? eventTitle,
    double? eventBudget,
    double? totalRaised,
  }) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final sorted = items.map(_asMap).toList();
    final totalExpenses = _toNum(summary['total_expenses']);
    final budget = eventBudget ?? _toNum(summary['budget']);
    final raised = totalRaised ?? _toNum(summary['total_raised']);
    final remaining = raised - totalExpenses;
    final title = _s(eventTitle).isNotEmpty ? _s(eventTitle) : 'Expense Report';

    // Group by category for breakdown (matches web)
    final Map<String, Map<String, dynamic>> byCategory = {};
    for (final item in sorted) {
      final cat = _s(item['category']).isEmpty ? 'Uncategorized' : _s(item['category']);
      byCategory.putIfAbsent(cat, () => {'total': 0.0, 'count': 0});
      byCategory[cat]!['total'] = (byCategory[cat]!['total'] as double) + _toNum(item['amount']);
      byCategory[cat]!['count'] = (byCategory[cat]!['count'] as int) + 1;
    }
    final sortedCategories = byCategory.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      header: (ctx) => ctx.pageNumber == 1
          ? _coverHeader('Expense Report', title, logoBytes: logo, eventTitle: eventTitle)
          : pw.SizedBox(),
      footer: (ctx) => _pageFooter(ctx),
      build: (ctx) => [
        // Summary cards matching web: Event Budget, Total Collected, Total Expenses, Remaining Balance
        pw.Row(children: [
          if (budget > 0) ...[
            _metricCard('Event Budget', _fmt(budget), accent: _accentOrange),
            pw.SizedBox(width: 8),
          ],
          _metricCard('Total Collected', _fmt(raised), accent: _accentGreen, valueColor: _accentGreen),
          pw.SizedBox(width: 8),
          _metricCard('Total Expenses', _fmt(totalExpenses), accent: _accentRed, valueColor: _accentRed),
          pw.SizedBox(width: 8),
          _metricCard('Remaining Balance', _fmt(remaining), accent: remaining >= 0 ? _accentGreen : _accentRed, valueColor: remaining >= 0 ? _accentGreen : _accentRed),
        ]),

        // Category Summary table (matches web)
        if (sortedCategories.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          _sectionHeading('Category Summary'),
          _premiumTable(
            headers: ['S/N', 'Category', 'Items', 'Total'],
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(0.8),
              3: const pw.FlexColumnWidth(1.5),
            },
            alignments: {2: pw.Alignment.center, 3: pw.Alignment.centerRight},
            data: sortedCategories.asMap().entries.map((e) {
              final cat = e.value;
              return [
                '${e.key + 1}',
                cat.key,
                '${cat.value['count']}',
                _fmt(cat.value['total']),
              ];
            }).toList(),
          ),
        ],
        pw.SizedBox(height: 24),
        _sectionHeading('Expense Details'),
        _premiumTable(
          headers: ['S/N', 'Date', 'Vendor', 'Category', 'Description', 'Amount'],
          columnWidths: {
            0: const pw.FlexColumnWidth(0.4),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.3),
            4: const pw.FlexColumnWidth(2),
            5: const pw.FlexColumnWidth(1.2),
          },
          alignments: {5: pw.Alignment.centerRight},
          data: sorted.asMap().entries.map((e) {
            final exp = e.value;
            return [
              '${e.key + 1}',
              _formatDate(exp['expense_date'] ?? exp['created_at']),
              _s(exp['vendor_name']),
              _s(exp['category']),
              _s(exp['description']),
              _fmt(exp['amount']),
            ];
          }).toList(),
        ),
        _summaryRow('Total (${sorted.length} expenses)', _fmt(totalExpenses)),
      ],
    ));

    return _savePdf(pdf, 'expenses_report');
  }

  static Future<Map<String, dynamic>> _expensesXlsx(
    List<dynamic> items, Map<String, dynamic> summary,
  ) async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Expenses'];

    int row = 0;
    _xlSetRow(sheet, row++, ['EXPENSES REPORT'], style: _xlTitleStyle());
    _xlSetRow(sheet, row++, ['Generated: ${DateFormat('MMM d, yyyy HH:mm').format(DateTime.now())}']);
    row++;
    _xlSetRow(sheet, row++, ['Total Expenses', _fmt(_toNum(summary['total_expenses']))]);
    row++;
    _xlSetRow(sheet, row++, ['Date', 'Category', 'Description', 'Amount', 'Vendor'], style: _xlHeaderStyle());

    for (final raw in items) {
      final exp = _asMap(raw);
      _xlSetRow(sheet, row++, [
        _formatDate(exp['expense_date'] ?? exp['created_at']),
        _s(exp['category']), _s(exp['description']),
        _toNum(exp['amount']).toStringAsFixed(0), _s(exp['vendor_name']),
      ]);
    }

    for (int c = 0; c < 5; c++) sheet.setColumnWidth(c, 20);
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    return _saveXlsx(excel, 'expenses_report');
  }

  // ════════════════════════════════════════════════════════════════
  //  5. EVENT SUMMARY REPORT
  //  Web: generateEventReport.ts
  //  Shows: Event Overview (title, status badge, description),
  //         Event Details (type, status, dates, time, location, dress code),
  //         Guest Summary (Expected, Total RSVPs, Confirmed, Pending, Declined, Checked In),
  //         Financial Summary (Budget, Total Collected, Contributors, Committee)
  //         + Budget Coverage bar
  // ════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> generateEventReport(
    String eventId, {
    required String format,
    Map<String, dynamic>? eventData,
  }) async {
    try {
      if (eventData == null || eventData.isEmpty) {
        final res = await EventsService.getEventById(eventId);
        if (res['success'] == true) eventData = _asMap(res['data']);
      }
      eventData ??= {};

      final results = await Future.wait([
        EventsService.getGuests(eventId, limit: 1),
        EventsService.getEventContributors(eventId, limit: 1),
        EventsService.getCommittee(eventId),
        EventsService.getBudget(eventId),
        EventsService.getExpenses(eventId),
        EventsService.getEventServices(eventId),
        EventsService.getManagementOverview(eventId),
      ]);

      final guestData = _asMap(results[0]);
      final contribData = _asMap(results[1]);
      final committeeData = _asMap(results[2]);
      final budgetData = _asMap(results[3]);
      final expenseData = _asMap(results[4]);
      final servicesData = _asMap(results[5]);
      final overviewData = _asMap(results[6]);

      final guestDataInner = _asMap(guestData['data']);
      final guestSummary = _asMap(guestDataInner['summary']);
      final guestPagination = _asMap(guestDataInner['pagination']);

      final guestCount = _toNum(guestPagination['totalItems'] ?? guestDataInner['total']).toInt();
      final confirmedGuests = _toNum(guestSummary['confirmed'] ?? guestSummary['attending']).toInt();
      final pendingGuests = _toNum(guestSummary['pending']).toInt();
      final declinedGuests = _toNum(guestSummary['declined']).toInt();
      final maybeGuests = _toNum(guestSummary['maybe']).toInt();
      final checkedIn = _toNum(guestSummary['checked_in']).toInt();
      final invitationsSent = _toNum(guestSummary['invitations_sent'] ?? eventData!['invitations_sent']).toInt();

      final contribDataInner = _asMap(contribData['data']);
      final contribSummary = _asMap(contribDataInner['summary']);
      final totalCollected = _toNum(contribSummary['total_paid'] ?? contribSummary['total_confirmed']);
      final totalPledged = _toNum(contribSummary['total_pledged'] ?? contribSummary['total_amount'] ?? eventData!['contribution_target']);
      final contribList = contribDataInner['event_contributors'];
      final contribCount = contribList is List ? contribList.length : _toNum(contribDataInner['total']).toInt();

      final committeeDataInner = _asMap(committeeData['data']);
      final membersList = committeeDataInner['members'] ?? committeeDataInner;
      final committeeCount = membersList is List ? membersList.length : 0;

      final budgetInner = _asMap(budgetData['data']);
      final budgetItems = budgetInner['items'] is List ? budgetInner['items'] as List : const [];
      final budgetSummary = _asMap(budgetInner['summary']);
      final expenseInner = _asMap(expenseData['data']);
      final expenses = expenseInner['expenses'] is List ? expenseInner['expenses'] as List : const [];
      final expenseSummary = _asMap(expenseInner['summary']);
      final servicesInner = servicesData['data'];
      final services = servicesInner is List
          ? servicesInner
          : (servicesInner is Map ? (servicesInner['services'] ?? servicesInner['items'] ?? const []) : const []);
      final overviewInner = _asMap(overviewData['data']);
      final ticketSales = _asMap(overviewInner['ticket_sales']);
      final revenueSummary = _asMap(overviewInner['revenue_summary']);
      final sponsorSummary = _asMap(overviewInner['sponsors']);
      final ticketsSold = _toNum(ticketSales['total_sold'] ?? eventData!['tickets_sold']).toInt();
      final ticketCapacity = _toNum(ticketSales['total_capacity'] ?? eventData!['tickets_capacity']).toInt();
      final sponsorRevenue = _toNum(revenueSummary['sponsors'] ?? sponsorSummary['revenue']);
      final totalExpenses = _toNum(expenseSummary['total_expenses']);
      final totalEstimated = _toNum(budgetSummary['total_estimated']);
      final totalActual = _toNum(budgetSummary['total_actual']);
      final vendorCount = services is List ? services.length : 0;

      if (format == 'xlsx') {
        return await _eventXlsx(eventData!, guestCount, confirmedGuests, pendingGuests, declinedGuests, maybeGuests, checkedIn, invitationsSent, totalCollected, totalPledged, contribCount, committeeCount, vendorCount, ticketsSold, ticketCapacity, sponsorRevenue, totalExpenses, totalEstimated, totalActual, budgetItems.length, expenses.length);
      } else {
        return await _eventPdf(eventData!, guestCount, confirmedGuests, pendingGuests, declinedGuests, maybeGuests, checkedIn, invitationsSent, totalCollected, totalPledged, contribCount, committeeCount, vendorCount, ticketsSold, ticketCapacity, sponsorRevenue, totalExpenses, totalEstimated, totalActual, budgetItems.length, expenses.length);
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> _eventPdf(
    Map<String, dynamic> event, int guestCount, int confirmed, int pending, int declined, int maybe,
    int checkedIn, int invitationsSent, double totalCollected, double totalPledged, int contribCount,
    int committeeCount, int vendorCount, int ticketsSold, int ticketCapacity, double sponsorRevenue,
    double totalExpenses, double totalEstimated, double totalActual, int budgetItemCount, int expenseCount,
  ) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final title = _s(event['title']);
    final budget = _toNum(event['budget']);
    final expectedGuests = _toNum(event['expected_guests']).toInt();
    final confirmRate = guestCount > 0 ? (confirmed / guestCount * 100) : 0.0;
    final budgetCoverage = budget > 0 ? (totalCollected / budget * 100) : 0.0;
    final budgetShortfall = budget > 0 ? (budget - totalCollected).clamp(0.0, double.infinity).toDouble() : 0.0;
    final pledgeShortfall = budget > 0 ? (budget - totalPledged).clamp(0.0, double.infinity).toDouble() : 0.0;

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      header: (ctx) => ctx.pageNumber == 1
          ? _coverHeader('Event Report', title.isEmpty ? 'Event Summary' : title, logoBytes: logo, eventTitle: title.isEmpty ? null : title)
          : pw.SizedBox(),
      footer: (ctx) => _pageFooter(ctx),
      build: (ctx) => [
        // Event Overview section (matches web - title + status + description)
        _sectionHeading('Event Overview'),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (title.isNotEmpty) pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _ink)),
            if (_s(event['status']).isNotEmpty) ...[
              pw.SizedBox(height: 6),
              _statusBadge(_s(event['status'])),
            ],
            if (_s(event['description']).isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text(_s(event['description']), style: pw.TextStyle(fontSize: 9, color: _inkMed, lineSpacing: 2.5)),
            ],
          ]),
        ),
        pw.SizedBox(height: 18),

        _sectionHeading('Event Details'),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (_s(event['event_type']).isNotEmpty) _detailRow('Event Type', _s(event['event_type'])),
            if (_s(event['status']).isNotEmpty) _detailRow('Status', _s(event['status'])),
            if (_s(event['start_date']).isNotEmpty) _detailRow('Start Date', _formatDate(event['start_date'])),
            if (_s(event['end_date']).isNotEmpty) _detailRow('End Date', _formatDate(event['end_date'])),
            _detailRow('Time', '${_s(event['start_time']).isNotEmpty ? _s(event['start_time']) : '-'}${_s(event['end_time']).isNotEmpty ? ' - ${_s(event['end_time'])}' : ''}'),
            if (_s(event['location'] ?? event['venue']).isNotEmpty) _detailRow('Location', _s(event['location'] ?? event['venue'])),
            if (_s(event['dress_code']).isNotEmpty) _detailRow('Dress Code', _s(event['dress_code'])),
            if (_s(event['special_instructions']).isNotEmpty) _detailRow('Special Instructions', _s(event['special_instructions'])),
            if (budget > 0) _detailRow('Budget', _fmt(budget)),
          ]),
        ),
        pw.SizedBox(height: 22),

        // Guest summary (matches web - Expected, Total RSVPs, Confirmed, Pending, Declined, Checked In)
        _sectionHeading('Guest Summary'),
        pw.Row(children: [
          _metricCard('Expected', '$expectedGuests', accent: _accentBlue),
          pw.SizedBox(width: 6),
          _metricCard('Total RSVPs', '$guestCount', accent: _accentBlue),
          pw.SizedBox(width: 6),
          _metricCard('Confirmed', '$confirmed', accent: _accentGreen, valueColor: _accentGreen),
        ]),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          _metricCard('Pending', '$pending', accent: _accentAmber, valueColor: _accentAmber),
          pw.SizedBox(width: 6),
          _metricCard('Maybe', '$maybe', accent: _accentBlue, valueColor: _accentBlue),
          pw.SizedBox(width: 6),
          _metricCard('Declined', '$declined', accent: _accentRed, valueColor: _accentRed),
        ]),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          _metricCard('Checked In', '$checkedIn', accent: _accentBlue, valueColor: _accentBlue),
          pw.SizedBox(width: 6),
          _metricCard('Invitations Sent', '$invitationsSent', accent: _accentBlue),
          pw.SizedBox(width: 6),
          _metricCard('Ticket Check-ins', '$ticketsSold / $ticketCapacity', accent: _accentBlue),
        ]),
        if (guestCount > 0) _progressBar('Confirmation Rate', confirmRate, color: _accentGreen),
        if (checkedIn > 0) _progressBar(
          'Check-in Rate',
          confirmed > 0 ? (checkedIn / confirmed * 100) : 0,
          color: _accentBlue,
        ),
        pw.SizedBox(height: 22),

        // Financial summary (matches web - Budget, Total Collected, Contributors, Committee)
        _sectionHeading('Financial Summary'),
        pw.Row(children: [
          _metricCard('Event Budget', budget > 0 ? _fmt(budget) : '-', accent: _accentOrange),
          pw.SizedBox(width: 8),
          _metricCard('Total Collected', _fmt(totalCollected), accent: _accentGreen, valueColor: _accentGreen),
          pw.SizedBox(width: 8),
          _metricCard('Budget Shortfall', _fmt(budgetShortfall), accent: _accentRed, valueColor: budgetShortfall > 0 ? _accentRed : _accentGreen),
        ]),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          _metricCard('Total Pledged', _fmt(totalPledged), accent: _accentPurple, valueColor: _accentPurple),
          pw.SizedBox(width: 8),
          _metricCard('Pledge Shortfall', _fmt(pledgeShortfall), accent: _accentAmber, valueColor: pledgeShortfall > 0 ? _accentAmber : _accentGreen),
          pw.SizedBox(width: 8),
          _metricCard('Sponsor Revenue', _fmt(sponsorRevenue), accent: _accentGreen, valueColor: _accentGreen),
        ]),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          _metricCard('Unique Contributors', '$contribCount', accent: _accentBlue),
          pw.SizedBox(width: 8),
          _metricCard('Committee Members', '$committeeCount', accent: _accentOrange),
          pw.SizedBox(width: 8),
          _metricCard('Vendors', '$vendorCount', accent: _accentBlue),
        ]),
        if (budget > 0) _progressBar('Budget Coverage', budgetCoverage, color: _accentOrange),
        pw.SizedBox(height: 22),

        _sectionHeading('Planning Detail'),
        pw.Row(children: [
          _metricCard('Budget Items', '$budgetItemCount', accent: _accentOrange),
          pw.SizedBox(width: 8),
          _metricCard('Estimated Costs', _fmt(totalEstimated), accent: _accentOrange),
          pw.SizedBox(width: 8),
          _metricCard('Actual Costs', _fmt(totalActual), accent: _accentOrange),
        ]),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          _metricCard('Expense Entries', '$expenseCount', accent: _accentRed),
          pw.SizedBox(width: 8),
          _metricCard('Total Expenses', _fmt(totalExpenses), accent: _accentRed),
          pw.SizedBox(width: 8),
          _metricCard('Net Cash', _fmt(totalCollected + sponsorRevenue - totalExpenses), accent: _accentGreen),
        ]),
      ],
    ));

    return _savePdf(pdf, 'event_report');
  }

  static Future<Map<String, dynamic>> _eventXlsx(
    Map<String, dynamic> event, int guestCount, int confirmed, int pending, int declined, int maybe,
    int checkedIn, int invitationsSent, double totalCollected, double totalPledged, int contribCount,
    int committeeCount, int vendorCount, int ticketsSold, int ticketCapacity, double sponsorRevenue,
    double totalExpenses, double totalEstimated, double totalActual, int budgetItemCount, int expenseCount,
  ) async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Event Summary'];

    int row = 0;
    _xlSetRow(sheet, row++, ['EVENT SUMMARY REPORT'], style: _xlTitleStyle());
    _xlSetRow(sheet, row++, ['Generated: ${DateFormat('MMM d, yyyy HH:mm').format(DateTime.now())}']);
    row++;
    _xlSetRow(sheet, row++, ['Title', _s(event['title'])]);
    _xlSetRow(sheet, row++, ['Status', _s(event['status'])]);
    _xlSetRow(sheet, row++, ['Start Date', _s(event['start_date'])]);
    _xlSetRow(sheet, row++, ['End Date', _s(event['end_date'])]);
    _xlSetRow(sheet, row++, ['Location', _s(event['location'] ?? event['venue'])]);
    row++;
    _xlSetRow(sheet, row++, ['GUEST SUMMARY'], style: _xlSubtitleStyle());
    _xlSetRow(sheet, row++, ['Expected Guests', '${_toNum(event['expected_guests']).toInt()}']);
    _xlSetRow(sheet, row++, ['Total RSVPs', '$guestCount']);
    _xlSetRow(sheet, row++, ['Confirmed', '$confirmed']);
    _xlSetRow(sheet, row++, ['Maybe', '$maybe']);
    _xlSetRow(sheet, row++, ['Pending', '$pending']);
    _xlSetRow(sheet, row++, ['Declined', '$declined']);
    _xlSetRow(sheet, row++, ['Checked In', '$checkedIn']);
    _xlSetRow(sheet, row++, ['Invitations Sent', '$invitationsSent']);
    _xlSetRow(sheet, row++, ['Tickets Sold', '$ticketsSold']);
    _xlSetRow(sheet, row++, ['Ticket Capacity', '$ticketCapacity']);
    row++;
    _xlSetRow(sheet, row++, ['FINANCIAL SUMMARY'], style: _xlSubtitleStyle());
    final budget = _toNum(event['budget']);
    final budgetShortfall = budget > 0 ? (budget - totalCollected).clamp(0.0, double.infinity).toDouble() : 0.0;
    final pledgeShortfall = budget > 0 ? (budget - totalPledged).clamp(0.0, double.infinity).toDouble() : 0.0;
    _xlSetRow(sheet, row++, ['Budget', _fmt(budget)]);
    _xlSetRow(sheet, row++, ['Total Collected', _fmt(totalCollected)]);
    _xlSetRow(sheet, row++, ['Total Pledged', _fmt(totalPledged)]);
    _xlSetRow(sheet, row++, ['Budget Shortfall', _fmt(budgetShortfall)]);
    _xlSetRow(sheet, row++, ['Pledge Shortfall', _fmt(pledgeShortfall)]);
    _xlSetRow(sheet, row++, ['Sponsor Revenue', _fmt(sponsorRevenue)]);
    _xlSetRow(sheet, row++, ['Total Expenses', _fmt(totalExpenses)]);
    _xlSetRow(sheet, row++, ['Net Cash', _fmt(totalCollected + sponsorRevenue - totalExpenses)]);
    _xlSetRow(sheet, row++, ['Contributors', '$contribCount']);
    _xlSetRow(sheet, row++, ['Committee Members', '$committeeCount']);
    _xlSetRow(sheet, row++, ['Vendors', '$vendorCount']);
    row++;
    _xlSetRow(sheet, row++, ['PLANNING DETAIL'], style: _xlSubtitleStyle());
    _xlSetRow(sheet, row++, ['Budget Items', '$budgetItemCount']);
    _xlSetRow(sheet, row++, ['Estimated Costs', _fmt(totalEstimated)]);
    _xlSetRow(sheet, row++, ['Actual Costs', _fmt(totalActual)]);
    _xlSetRow(sheet, row++, ['Expense Entries', '$expenseCount']);

    for (int c = 0; c < 2; c++) sheet.setColumnWidth(c, 25);
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    return _saveXlsx(excel, 'event_report');
  }

  // ════════════════════════════════════════════════════════════════
  //  6. RSVP / GUEST LIST REPORT
  // ════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> generateRsvpReport(
    String eventId, {
    required String format,
    List<dynamic>? guests,
    String? eventTitle,
  }) async {
    try {
      if (guests == null || guests.isEmpty) {
        // Page through every guest so the report never silently truncates.
        final List<dynamic> all = [];
        int page = 1;
        while (true) {
          final res = await EventsService.getGuests(eventId, page: page, limit: 100);
          if (res['success'] != true) break;
          final data = _asMap(res['data']);
          final list = (data['guests'] ?? data['items'] ?? []) as List;
          all.addAll(list);
          final pag = _asMap(data['pagination']);
          final totalPages = _toNum(pag['total_pages'] ?? pag['totalPages'] ?? 1).toInt();
          if (list.isEmpty || page >= totalPages) break;
          page++;
          if (page > 500) break; // safety
        }
        guests = all;
      }
      guests ??= [];

      if (format == 'xlsx') {
        return await _rsvpXlsx(guests, eventTitle);
      } else {
        return await _rsvpPdf(guests, eventTitle);
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> _rsvpPdf(List<dynamic> guests, String? eventTitle) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final sorted = guests.map(_asMap).toList()
      ..sort((a, b) => _s(a['name']).compareTo(_s(b['name'])));

    final total = sorted.length;
    final attending = sorted.where((g) => ['attending', 'confirmed'].contains(_s(g['rsvp_status']))).length;
    final pending = sorted.where((g) => _s(g['rsvp_status']) == 'pending' || g['rsvp_status'] == null).length;
    final declined = sorted.where((g) => _s(g['rsvp_status']) == 'declined').length;
    final maybe = sorted.where((g) => _s(g['rsvp_status']) == 'maybe').length;
    final confirmRate = total > 0 ? (attending / total * 100) : 0.0;

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      header: (ctx) => ctx.pageNumber == 1
          ? _coverHeader('RSVP Report', eventTitle ?? 'Guest List', logoBytes: logo, eventTitle: eventTitle)
          : pw.SizedBox(),
      footer: (ctx) => _pageFooter(ctx),
      build: (ctx) => [
        _sectionHeading('Attendance Summary'),
        pw.Row(children: [
          _metricCard('Total Invited', '$total', accent: _accentBlue),
          pw.SizedBox(width: 6),
          _metricCard('Attending', '$attending', accent: _accentGreen, valueColor: _accentGreen),
          pw.SizedBox(width: 6),
          _metricCard('Maybe', '$maybe', accent: _accentBlue, valueColor: _accentBlue),
          pw.SizedBox(width: 6),
          _metricCard('Pending', '$pending', accent: _accentAmber, valueColor: _accentAmber),
          pw.SizedBox(width: 6),
          _metricCard('Declined', '$declined', accent: _accentRed, valueColor: _accentRed),
        ]),
        if (total > 0) _progressBar('Confirmation Rate', confirmRate, color: _accentGreen),
        pw.SizedBox(height: 24),
        _sectionHeading('Guest List ($total)'),
        _premiumTableWithBadges(
          headers: ['#', 'Full Name', 'Phone', 'Status', 'Plus Ones', 'Checked In'],
          statusColumnIndex: 3,
          columnWidths: {
            0: const pw.FlexColumnWidth(0.4),
            1: const pw.FlexColumnWidth(2.5),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(0.8),
            5: const pw.FlexColumnWidth(0.8),
          },
          alignments: {4: pw.Alignment.center, 5: pw.Alignment.center},
          data: sorted.asMap().entries.map((e) {
            final g = e.value;
            return [
              '${e.key + 1}',
              _s(g['name']),
              _s(g['phone']),
              _s(g['rsvp_status'] ?? 'pending'),
              _toNum(g['plus_ones']).toInt() > 0 ? '+${_toNum(g['plus_ones']).toInt()}' : '-',
              g['checked_in'] == true ? 'Yes' : 'No',
            ];
          }).toList(),
        ),
      ],
    ));

    return _savePdf(pdf, 'rsvp_report');
  }

  static Future<Map<String, dynamic>> _rsvpXlsx(List<dynamic> guests, String? eventTitle) async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['RSVP Report'];

    int row = 0;
    _xlSetRow(sheet, row++, ['RSVP REPORT', eventTitle ?? ''], style: _xlTitleStyle());
    _xlSetRow(sheet, row++, ['Generated: ${DateFormat('MMM d, yyyy HH:mm').format(DateTime.now())}']);
    row++;
    _xlSetRow(sheet, row++, ['Name', 'Phone', 'RSVP Status', 'Plus Ones', 'Checked In'], style: _xlHeaderStyle());

    for (final raw in guests) {
      final g = _asMap(raw);
      _xlSetRow(sheet, row++, [
        _s(g['name']), _s(g['phone']),
        _s(g['rsvp_status'] ?? 'pending'),
        '${_toNum(g['plus_ones']).toInt()}',
        g['checked_in'] == true ? 'Yes' : 'No',
      ]);
    }

    for (int c = 0; c < 5; c++) sheet.setColumnWidth(c, 20);
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    return _saveXlsx(excel, 'rsvp_report');
  }

  // ════════════════════════════════════════════════════════════════
  //  7. COMMITTEE REPORT
  // ════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> generateCommitteeReport(
    String eventId, {
    required String format,
    List<dynamic>? members,
    String? eventTitle,
  }) async {
    try {
      if (members == null || members.isEmpty) {
        final res = await EventsService.getCommittee(eventId);
        if (res['success'] == true) {
          final data = res['data'];
          if (data is Map) {
            members = (data as Map)['members'] ?? [];
          } else if (data is List) {
            members = data;
          }
        }
      }
      members ??= [];

      if (format == 'xlsx') {
        return await _committeeXlsx(members, eventTitle);
      } else {
        return await _committeePdf(members, eventTitle);
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> _committeePdf(List<dynamic> members, String? eventTitle) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final sorted = members.map(_asMap).toList()
      ..sort((a, b) => _s(a['name']).compareTo(_s(b['name'])));

    final active = sorted.where((m) => _s(m['status']) == 'active').length;
    final invited = sorted.where((m) => _s(m['status']) == 'invited').length;

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      header: (ctx) => ctx.pageNumber == 1
          ? _coverHeader('Committee Report', eventTitle ?? 'Team Overview', logoBytes: logo, eventTitle: eventTitle)
          : pw.SizedBox(),
      footer: (ctx) => _pageFooter(ctx),
      build: (ctx) => [
        pw.Row(children: [
          _metricCard('Total Members', '${sorted.length}', accent: _accentBlue),
          pw.SizedBox(width: 8),
          _metricCard('Active', '$active', accent: _accentGreen, valueColor: _accentGreen),
          pw.SizedBox(width: 8),
          _metricCard('Invited', '$invited', accent: _accentAmber, valueColor: _accentAmber),
        ]),
        pw.SizedBox(height: 24),
        _sectionHeading('Committee Members'),
        _premiumTableWithBadges(
          headers: ['#', 'Name', 'Role', 'Phone', 'Email', 'Status'],
          statusColumnIndex: 5,
          columnWidths: {
            0: const pw.FlexColumnWidth(0.4),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(2),
            5: const pw.FlexColumnWidth(1),
          },
          data: sorted.asMap().entries.map((e) {
            final m = e.value;
            return [
              '${e.key + 1}',
              _s(m['name']), _s(m['role']), _s(m['phone']), _s(m['email']),
              _s(m['status']),
            ];
          }).toList(),
        ),
      ],
    ));

    return _savePdf(pdf, 'committee_report');
  }

  static Future<Map<String, dynamic>> _committeeXlsx(List<dynamic> members, String? eventTitle) async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Committee'];

    int row = 0;
    _xlSetRow(sheet, row++, ['COMMITTEE REPORT', eventTitle ?? ''], style: _xlTitleStyle());
    _xlSetRow(sheet, row++, ['Generated: ${DateFormat('MMM d, yyyy HH:mm').format(DateTime.now())}']);
    row++;
    _xlSetRow(sheet, row++, ['Name', 'Role', 'Phone', 'Email', 'Status'], style: _xlHeaderStyle());

    for (final raw in members) {
      final m = _asMap(raw);
      _xlSetRow(sheet, row++, [
        _s(m['name']), _s(m['role']), _s(m['phone']), _s(m['email']), _s(m['status']),
      ]);
    }

    for (int c = 0; c < 5; c++) sheet.setColumnWidth(c, 20);
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    return _saveXlsx(excel, 'committee_report');
  }
}
