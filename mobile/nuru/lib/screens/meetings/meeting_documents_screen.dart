import '../../core/widgets/nuru_refresh_indicator.dart';
import '../../core/widgets/nuru_scrollable_tabs.dart';

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:nuru/core/services/meeting_docs_service.dart';
import 'package:nuru/core/l10n/app_translations.dart';
import 'package:nuru/providers/locale_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:nuru/screens/events/report_preview_screen.dart';

class MeetingDocumentsScreen extends StatefulWidget {
  final String eventId;
  final String meetingId;
  final String meetingTitle;
  final String? meetingDescription;
  final String meetingDate;
  final bool isCreator;
  final String? eventName;

  const MeetingDocumentsScreen({
    super.key,
    required this.eventId,
    required this.meetingId,
    required this.meetingTitle,
    this.meetingDescription,
    required this.meetingDate,
    required this.isCreator,
    this.eventName,
  });

  @override
  State<MeetingDocumentsScreen> createState() => _MeetingDocumentsScreenState();
}

class _MeetingDocumentsScreenState extends State<MeetingDocumentsScreen> with SingleTickerProviderStateMixin {
  final MeetingDocsService _service = MeetingDocsService();
  late TabController _tabCtrl;

  List<Map<String, dynamic>> _agendaItems = [];
  Map<String, dynamic>? _minutes;
  bool _loadingAgenda = true;
  bool _loadingMinutes = true;

  String _t(String key) {
    final locale = context.read<LocaleProvider>().languageCode;
    return AppTranslations.tr(key, locale);
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _loadAgenda();
    _loadMinutes();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAgenda() async {
    try {
      final res = await _service.listAgenda(widget.eventId, widget.meetingId);
      if (res['success'] == true && res['data'] != null) {
        setState(() => _agendaItems = List<Map<String, dynamic>>.from(res['data']));
      }
    } catch (_) {}
    setState(() => _loadingAgenda = false);
  }

  Future<void> _loadMinutes() async {
    try {
      final res = await _service.getMinutes(widget.eventId, widget.meetingId);
      if (res['success'] == true) {
        setState(() => _minutes = res['data']);
      }
    } catch (_) {}
    setState(() => _loadingMinutes = false);
  }

  Future<void> _addAgendaItem() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final durationCtrl = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final primary = theme.colorScheme.primary;
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 24),
                // Header
                Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [primary.withOpacity(0.15), primary.withOpacity(0.05)]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.playlist_add_rounded, color: primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_t('add_agenda_item'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        const SizedBox(height: 2),
                        Text('Add a topic to discuss', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 28),

                // Title field
                Text(_t('title').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[500], letterSpacing: 1)),
                const SizedBox(height: 8),
                _modernInput(titleCtrl, _t('agenda_title_placeholder'), Icons.subject_rounded, theme),
                const SizedBox(height: 20),

                // Description field
                Text(_t('description').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[500], letterSpacing: 1)),
                const SizedBox(height: 8),
                _modernInput(descCtrl, _t('agenda_desc_placeholder'), Icons.notes_rounded, theme, maxLines: 3),
                const SizedBox(height: 20),

                // Duration field
                Text(_t('estimated_duration').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[500], letterSpacing: 1)),
                const SizedBox(height: 8),
                _modernInput(durationCtrl, _t('duration_placeholder'), Icons.timer_outlined, theme, keyboardType: TextInputType.number),
                const SizedBox(height: 28),

                // Add button
                SizedBox(
                  width: double.infinity, height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      if (titleCtrl.text.trim().isEmpty) return;
                      Navigator.pop(ctx, true);
                    },
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.add_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(_t('add_item'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == true) {
      try {
        await _service.createAgendaItem(
          widget.eventId, widget.meetingId,
          title: titleCtrl.text.trim(),
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          durationMinutes: durationCtrl.text.trim().isNotEmpty ? int.tryParse(durationCtrl.text.trim()) : null,
        );
        _loadAgenda();
      } catch (_) {}
    }
  }

  Future<void> _toggleComplete(Map<String, dynamic> item) async {
    try {
      await _service.updateAgendaItem(widget.eventId, widget.meetingId, item['id'], {
        'is_completed': !(item['is_completed'] ?? false),
      });
      _loadAgenda();
    } catch (_) {}
  }

  Future<void> _deleteAgendaItem(String itemId) async {
    try {
      await _service.deleteAgendaItem(widget.eventId, widget.meetingId, itemId);
      _loadAgenda();
    } catch (_) {}
  }

  Future<void> _editMinutes() async {
    final contentCtrl = TextEditingController(text: _minutes?['content'] ?? '');
    final summaryCtrl = TextEditingController(text: _minutes?['summary'] ?? '');
    final decisionsCtrl = TextEditingController(text: _minutes?['decisions'] ?? '');
    final actionsCtrl = TextEditingController(text: _minutes?['action_items'] ?? '');

    final result = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (ctx) => _RecordMinutesPage(
        contentCtrl: contentCtrl,
        summaryCtrl: summaryCtrl,
        decisionsCtrl: decisionsCtrl,
        actionsCtrl: actionsCtrl,
        title: _t('record_minutes'),
        saveLabel: _t('save'),
      ),
    ));

    if (result == true && contentCtrl.text.trim().isNotEmpty) {
      try {
        final data = {
          'content': contentCtrl.text.trim(),
          'summary': summaryCtrl.text.trim().isEmpty ? null : summaryCtrl.text.trim(),
          'decisions': decisionsCtrl.text.trim().isEmpty ? null : decisionsCtrl.text.trim(),
          'action_items': actionsCtrl.text.trim().isEmpty ? null : actionsCtrl.text.trim(),
        };
        if (_minutes != null) {
          await _service.updateMinutes(widget.eventId, widget.meetingId, data);
        } else {
          await _service.createMinutes(widget.eventId, widget.meetingId, data);
        }
        _loadMinutes();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_t('minutes_saved')), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          );
        }
      } catch (_) {}
    }
  }

  // ─── PDF Export (preserved from original) ───
  static const _ink = PdfColor.fromInt(0xFF0A1C40);
  static const _inkMed = PdfColor.fromInt(0xFF3A4D6A);
  static const _inkLight = PdfColor.fromInt(0xFF6B7F9E);
  static const _inkMuted = PdfColor.fromInt(0xFF9EADC2);
  static const _surface = PdfColor.fromInt(0xFFFFFFFF);
  static const _surfaceTint = PdfColor.fromInt(0xFFF6F7F9);
  static const _borderSoft = PdfColor.fromInt(0xFFE8ECF2);
  static const _borderFaint = PdfColor.fromInt(0xFFF0F2F5);
  static const _accentOrange = PdfColor.fromInt(0xFFE7A622);
  static const _accentGreen = PdfColor.fromInt(0xFF22C55E);
  static const _accentBlue = PdfColor.fromInt(0xFF2471E7);
  static const _accentAmber = PdfColor.fromInt(0xFFF59E0B);
  static const _accentPurple = PdfColor.fromInt(0xFF7C3AED);
  static const _accentIndigo = PdfColor.fromInt(0xFF6366F1);

  Future<void> _exportPDF() async {
    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/nuru-logo-square.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {}

    final dateStr = DateTime.tryParse(widget.meetingDate)?.toLocal();
    final totalDuration = _agendaItems.fold<int>(0, (sum, item) => sum + (int.tryParse(item['duration_minutes']?.toString() ?? '') ?? 0));
    final completedCount = _agendaItems.where((i) => i['is_completed'] == true).length;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _buildPdfHeader(logoBytes, dateStr),
        footer: (context) => _buildPdfFooter(context),
        build: (context) => [
          pw.Row(children: [
            _metricCard('Date', dateStr != null ? DateFormat('EEE, MMM d, yyyy').format(dateStr) : '-', accent: _accentBlue, small: true),
            pw.SizedBox(width: 8),
            _metricCard('Time', dateStr != null ? DateFormat('h:mm a').format(dateStr) : '-', accent: _accentPurple, small: true),
            pw.SizedBox(width: 8),
            _metricCard('Agenda Items', '${_agendaItems.length}', accent: _accentOrange),
          ]),
          pw.SizedBox(height: 8),
          pw.Row(children: [
            if (totalDuration > 0) ...[_metricCard('Est. Duration', '$totalDuration min', accent: _accentAmber), pw.SizedBox(width: 8)],
            _metricCard('Completed', '$completedCount/${_agendaItems.length}', accent: _accentGreen, valueColor: _accentGreen),
            if (totalDuration == 0) ...[pw.SizedBox(width: 8), pw.Expanded(child: pw.SizedBox())],
          ]),
          pw.SizedBox(height: 20),
          if (_agendaItems.isNotEmpty) ...[
            _sectionHeading('Agenda'),
            ..._agendaItems.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final completed = item['is_completed'] == true;
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: _surfaceTint,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border(left: pw.BorderSide(color: completed ? _accentGreen : _accentIndigo, width: 3)),
                ),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Row(children: [
                    pw.Container(width: 22, height: 22, decoration: pw.BoxDecoration(color: completed ? _accentGreen : _accentIndigo, shape: pw.BoxShape.circle),
                      child: pw.Center(child: pw.Text('${i + 1}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _surface)))),
                    pw.SizedBox(width: 10),
                    pw.Expanded(child: pw.Text(item['title'] ?? '', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink))),
                    if (completed) pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFDCFCE7), borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Text('DONE', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _accentGreen))),
                  ]),
                  if (item['description'] != null && item['description'].toString().isNotEmpty)
                    pw.Padding(padding: const pw.EdgeInsets.only(left: 32, top: 4), child: pw.Text(item['description'], style: pw.TextStyle(fontSize: 10, color: _inkLight))),
                  if (item['duration_minutes'] != null)
                    pw.Padding(padding: const pw.EdgeInsets.only(left: 32, top: 4), child: pw.Text('Duration: ${item['duration_minutes']} min', style: pw.TextStyle(fontSize: 9, color: _inkMuted))),
                ]),
              );
            }),
            pw.SizedBox(height: 20),
          ],
          if (_minutes != null) ...[
            _sectionHeading('Meeting Minutes'),
            pw.Text(_minutes!['content'] ?? '', style: pw.TextStyle(fontSize: 11, lineSpacing: 6, color: _inkMed)),
            pw.SizedBox(height: 16),
            if (_minutes!['summary'] != null && _minutes!['summary'].toString().isNotEmpty)
              _buildPdfHighlightBox('Summary', _minutes!['summary'], const PdfColor.fromInt(0xFFFFFBEB), _accentAmber),
            if (_minutes!['decisions'] != null && _minutes!['decisions'].toString().isNotEmpty)
              _buildPdfHighlightBox('Key Decisions', _minutes!['decisions'], const PdfColor.fromInt(0xFFF0FDF4), _accentGreen),
            if (_minutes!['action_items'] != null && _minutes!['action_items'].toString().isNotEmpty)
              _buildPdfHighlightBox('Action Items', _minutes!['action_items'], const PdfColor.fromInt(0xFFF0F5FF), _accentBlue),
          ],
        ],
      ),
    );

    final bytes = await pdf.save();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReportPreviewScreen(title: 'Meeting Report', pdfBytes: Uint8List.fromList(bytes))));
  }

  pw.Widget _buildPdfHeader(Uint8List? logoBytes, DateTime? dateStr) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 24),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(width: double.infinity, height: 3, decoration: const pw.BoxDecoration(color: _accentOrange)),
        pw.SizedBox(height: 16),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (logoBytes != null)
              pw.Container(width: 44, height: 44, child: pw.Image(pw.MemoryImage(logoBytes)))
            else
              pw.Container(width: 44, height: 44, decoration: pw.BoxDecoration(color: _accentOrange, borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Center(child: pw.Text('N', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _surface)))),
            pw.SizedBox(height: 6),
            pw.Text('Plan Smarter', style: pw.TextStyle(fontSize: 8.5, color: _inkMuted, fontStyle: pw.FontStyle.italic)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Meeting Report', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _ink)),
            if (widget.eventName != null && widget.eventName!.isNotEmpty) ...[pw.SizedBox(height: 2), pw.Text(widget.eventName!, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _inkMed))],
            pw.SizedBox(height: 2),
            pw.Text(widget.meetingTitle, style: pw.TextStyle(fontSize: 9, color: _inkLight)),
            if (widget.meetingDescription != null && widget.meetingDescription!.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Container(width: 200, child: pw.Text(widget.meetingDescription!, style: pw.TextStyle(fontSize: 8, color: _inkMuted), maxLines: 2)),
            ],
          ]),
        ]),
        pw.SizedBox(height: 14),
        pw.Container(width: double.infinity, height: 0.5, color: _borderSoft),
      ]),
    );
  }

  pw.Widget _buildPdfFooter(pw.Context ctx) {
    final year = DateTime.now().year;
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 16),
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _borderFaint, width: 0.5))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Generated by Nuru Events Workspace  \u00b7  \u00a9 $year Nuru | SEWMR TECHNOLOGIES', style: pw.TextStyle(fontSize: 7, color: _inkMuted, letterSpacing: 0.3)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 7, color: _inkMuted)),
      ]),
    );
  }

  static pw.Widget _metricCard(String label, String value, {PdfColor accent = _accentOrange, PdfColor? valueColor, bool small = false}) {
    return pw.Expanded(
      child: pw.Container(
        decoration: pw.BoxDecoration(color: _surface, border: pw.Border.all(color: _borderSoft, width: 0.6), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(children: [
          pw.Container(width: 3, height: 44, decoration: pw.BoxDecoration(color: accent, borderRadius: const pw.BorderRadius.only(topLeft: pw.Radius.circular(6), bottomLeft: pw.Radius.circular(6)))),
          pw.Expanded(child: pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label.toUpperCase(), style: pw.TextStyle(fontSize: 6.5, color: _inkMuted, letterSpacing: 0.8)),
            pw.SizedBox(height: 2),
            pw.Text(value, style: pw.TextStyle(fontSize: small ? 10 : 13, fontWeight: pw.FontWeight.bold, color: valueColor ?? _ink)),
          ]))),
        ]),
      ),
    );
  }

  static pw.Widget _sectionHeading(String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10, top: 6),
      child: pw.Row(children: [
        pw.Container(width: 3, height: 14, decoration: pw.BoxDecoration(color: _accentOrange, borderRadius: pw.BorderRadius.circular(1.5))),
        pw.SizedBox(width: 8),
        pw.Text(text.toUpperCase(), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _inkMed, letterSpacing: 1.5)),
      ]),
    );
  }

  pw.Widget _buildPdfHighlightBox(String title, String content, PdfColor bg, PdfColor accent) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(6), border: pw.Border(left: pw.BorderSide(color: accent, width: 3))),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title.toUpperCase(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: accent, letterSpacing: 0.8)),
        pw.SizedBox(height: 6),
        pw.Text(content, style: pw.TextStyle(fontSize: 10, lineSpacing: 5, color: _inkMed)),
      ]),
    );
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    context.watch<LocaleProvider>();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111111) : const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset('assets/icons/chevron-left-icon.svg', width: 24, height: 24,
            colorFilter: ColorFilter.mode(theme.colorScheme.onSurface, BlendMode.srcIn)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_t('agenda_minutes'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3)),
            Text(widget.meetingTitle, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.picture_as_pdf_rounded, color: primary, size: 20),
              tooltip: _t('export_pdf'),
              onPressed: _exportPDF,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Pill-style tab bar (YouTube-style).
          NuruPillTabBar(
            controller: _tabCtrl,
            labels: [_t('agenda'), _t('minutes')],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          const SizedBox(height: 4),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildAgendaTab(theme),
                _buildMinutesTab(theme),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabCtrl.index == 0 && widget.isCreator
          ? FloatingActionButton.extended(
              onPressed: _addAgendaItem,
              icon: const Icon(Icons.add_rounded),
              label: Text(_t('add_item'), style: const TextStyle(fontWeight: FontWeight.w700)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
            )
          : _tabCtrl.index == 1 && widget.isCreator
              ? FloatingActionButton.extended(
                  onPressed: _editMinutes,
                  icon: Icon(_minutes == null ? Icons.edit_rounded : Icons.edit_note_rounded),
                  label: Text(_minutes == null ? _t('record_minutes') : _t('edit'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                )
              : null,
    );
  }

  Widget _tabButton(int index, IconData icon, String label, ThemeData theme) {
    final isActive = _tabCtrl.index == index;
    final isDark = theme.brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabCtrl.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? (isDark ? Colors.white.withOpacity(0.12) : Colors.white) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isActive ? theme.colorScheme.primary : Colors.grey[500]),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                fontSize: 13, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? theme.colorScheme.onSurface : Colors.grey[500],
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgendaTab(ThemeData theme) {
    if (_loadingAgenda) return const Center(child: CircularProgressIndicator());
    final isDark = theme.brightness == Brightness.dark;

    if (_agendaItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [theme.colorScheme.primary.withOpacity(0.12), theme.colorScheme.primary.withOpacity(0.04)]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.playlist_add_rounded, size: 40, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Text(_t('no_agenda_yet'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              const SizedBox(height: 8),
              Text(_t('no_agenda_desc'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey, height: 1.5)),
            ],
          ),
        ),
      );
    }

    // Summary bar
    final completedCount = _agendaItems.where((i) => i['is_completed'] == true).length;
    final totalDuration = _agendaItems.fold<int>(0, (s, i) => s + (int.tryParse(i['duration_minutes']?.toString() ?? '') ?? 0));

    return NuruRefreshIndicator(
      onRefresh: _loadAgenda,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        itemCount: _agendaItems.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            // Summary stats
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 12, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  _statPill(Icons.checklist_rounded, '$completedCount/${_agendaItems.length}', 'Done', Colors.green, isDark),
                  const SizedBox(width: 12),
                  if (totalDuration > 0) _statPill(Icons.timer_outlined, '$totalDuration', 'min', theme.colorScheme.primary, isDark),
                ],
              ),
            );
          }

          final idx = i - 1;
          final item = _agendaItems[idx];
          final completed = item['is_completed'] == true;

          return Dismissible(
            key: Key(item['id']),
            direction: widget.isCreator ? DismissDirection.endToStart : DismissDirection.none,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.delete_rounded, color: Colors.white, size: 22),
            ),
            onDismissed: (_) => _deleteAgendaItem(item['id']),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 12, offset: const Offset(0, 2))],
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    // Left accent bar
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: completed ? Colors.green : theme.colorScheme.primary,
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), bottomLeft: Radius.circular(18)),
                      ),
                    ),
                    // Number badge
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      child: GestureDetector(
                        onTap: widget.isCreator ? () => _toggleComplete(item) : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            gradient: completed
                                ? const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF16A34A)])
                                : LinearGradient(colors: [theme.colorScheme.primary.withOpacity(0.12), theme.colorScheme.primary.withOpacity(0.06)]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: completed
                                ? const Icon(Icons.check_rounded, size: 20, color: Colors.white)
                                : Text('${idx + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.primary, fontSize: 15)),
                          ),
                        ),
                      ),
                    ),
                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 14, right: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'] ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14,
                                decoration: completed ? TextDecoration.lineThrough : null,
                                color: completed ? Colors.grey : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                            if (item['description'] != null && item['description'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(item['description'], maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4)),
                              ),
                            if (item['duration_minutes'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.timer_outlined, size: 12, color: theme.colorScheme.primary),
                                    const SizedBox(width: 4),
                                    Text('${item['duration_minutes']} min', style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                                  ]),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statPill(IconData icon, String value, String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
      ]),
    );
  }

  Widget _buildMinutesTab(ThemeData theme) {
    if (_loadingMinutes) return const Center(child: CircularProgressIndicator());
    final isDark = theme.brightness == Brightness.dark;

    if (_minutes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [theme.colorScheme.primary.withOpacity(0.12), theme.colorScheme.primary.withOpacity(0.04)]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.edit_note_rounded, size: 40, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Text(_t('no_minutes_yet'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              const SizedBox(height: 8),
              Text(_t('no_minutes_desc'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey, height: 1.5)),
            ],
          ),
        ),
      );
    }

    return NuruRefreshIndicator(
      onRefresh: _loadMinutes,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recorded by header
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.person_outline_rounded, size: 18, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_t('recorded_by')}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    Text(_minutes!['recorded_by']?['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Notes card
            _modernMinutesCard(Icons.article_rounded, _t('meeting_notes'), _minutes!['content'] ?? '', theme.colorScheme.primary, isDark),
            const SizedBox(height: 12),

            if (_minutes!['summary'] != null && _minutes!['summary'].toString().isNotEmpty) ...[
              _modernMinutesCard(Icons.lightbulb_rounded, _t('summary'), _minutes!['summary'], Colors.amber, isDark),
              const SizedBox(height: 12),
            ],
            if (_minutes!['decisions'] != null && _minutes!['decisions'].toString().isNotEmpty) ...[
              _modernMinutesCard(Icons.gavel_rounded, _t('key_decisions'), _minutes!['decisions'], const Color(0xFF22C55E), isDark),
              const SizedBox(height: 12),
            ],
            if (_minutes!['action_items'] != null && _minutes!['action_items'].toString().isNotEmpty) ...[
              _modernMinutesCard(Icons.task_alt_rounded, _t('action_items'), _minutes!['action_items'], const Color(0xFF3B82F6), isDark),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modernMinutesCard(IconData icon, String title, String content, Color color, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), bottomLeft: Radius.circular(18)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  const SizedBox(width: 10),
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                ]),
                const SizedBox(height: 12),
                Text(content, style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey[700], height: 1.6)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _modernInput(TextEditingController ctrl, String hint, IconData icon, ThemeData theme, {int maxLines = 1, TextInputType? keyboardType}) {
    final isDark = theme.brightness == Brightness.dark;
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(icon, size: 20, color: Colors.grey[400]),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 44),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ─── Record Minutes Page (Modern Redesign) ───

class _RecordMinutesPage extends StatelessWidget {
  final TextEditingController contentCtrl;
  final TextEditingController summaryCtrl;
  final TextEditingController decisionsCtrl;
  final TextEditingController actionsCtrl;
  final String title;
  final String saveLabel;

  const _RecordMinutesPage({
    required this.contentCtrl,
    required this.summaryCtrl,
    required this.decisionsCtrl,
    required this.actionsCtrl,
    required this.title,
    required this.saveLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111111) : const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset('assets/icons/chevron-left-icon.svg', width: 24, height: 24,
            colorFilter: ColorFilter.mode(theme.colorScheme.onSurface, BlendMode.srcIn)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(saveLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () => Navigator.pop(context, true),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionCard(
              icon: Icons.article_rounded,
              title: 'Meeting Notes',
              subtitle: 'Capture the key discussion points',
              color: primary,
              isDark: isDark,
              child: _modernTextField(contentCtrl, 'Type your meeting notes here...', isDark, theme, maxLines: 8),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              icon: Icons.lightbulb_rounded,
              title: 'Summary',
              subtitle: 'Brief overview of the meeting',
              color: Colors.amber,
              isDark: isDark,
              child: _modernTextField(summaryCtrl, 'Add a brief summary...', isDark, theme, maxLines: 3),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              icon: Icons.gavel_rounded,
              title: 'Key Decisions',
              subtitle: 'Decisions made during the meeting',
              color: const Color(0xFF22C55E),
              isDark: isDark,
              child: _modernTextField(decisionsCtrl, 'List the key decisions...', isDark, theme, maxLines: 3),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              icon: Icons.task_alt_rounded,
              title: 'Action Items',
              subtitle: 'Tasks to follow up on',
              color: const Color(0xFF3B82F6),
              isDark: isDark,
              child: _modernTextField(actionsCtrl, 'List action items...', isDark, theme, maxLines: 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), bottomLeft: Radius.circular(18)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                    Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ]),
                ]),
                const SizedBox(height: 14),
                child,
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _modernTextField(TextEditingController ctrl, String hint, bool isDark, ThemeData theme, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87, height: 1.6),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5)),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }
}
