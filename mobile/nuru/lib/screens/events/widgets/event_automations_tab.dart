import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/nuru_date_time_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/automations_service.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../core/widgets/nuru_skeleton.dart';


bool _apiOk(Map<String, dynamic> res) =>
    res['success'] == true ||
    res['success']?.toString().toLowerCase() == 'true' ||
    res['status']?.toString().toLowerCase() == 'success' ||
    res['status']?.toString() == '200';

String _apiMessage(Map<String, dynamic> res, String fallback) {
  final message = res['message']?.toString().trim();
  if (message != null && message.isNotEmpty) return message;
  final errors = res['errors'];
  if (errors is List && errors.isNotEmpty) return errors.first.toString();
  return fallback;
}

Map<String, dynamic> _responseMap(Map<String, dynamic> res) {
  final data = res['data'];
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return const {};
}

List<Map<String, dynamic>> _responseItems(
  Map<String, dynamic> res, {
  String fallbackKey = 'items',
}) {
  final direct = res['data'];
  if (direct is List) {
    return direct.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  final data = _responseMap(res);
  final nested = data['data'];
  final source = nested is Map ? Map<String, dynamic>.from(nested) : data;
  final raw = source['items'] ?? source[fallbackKey];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

/// Mobile Event Automations tab.
///
/// Mirrors the web EventAutomationsPage end-to-end: list, create, edit,
/// preview, schedule, enable/disable, send-now, and run history with
/// per-recipient drill-down. Custom SVG icons only - no Lucide/Material
/// glyphs in the visible UI.
class EventAutomationsTab extends StatefulWidget {
  final String eventId;
  final bool isCreator;

  const EventAutomationsTab({
    super.key,
    required this.eventId,
    required this.isCreator,
  });

  @override
  State<EventAutomationsTab> createState() => _EventAutomationsTabState();
}

class _EventAutomationsTabState extends State<EventAutomationsTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  bool _initialLoad = true;
  List<Map<String, dynamic>> _items = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_initialLoad) setState(() => _loading = true);
    final res = await AutomationsService.list(widget.eventId);
    if (!mounted) return;
    setState(() {
      _items = _apiOk(res)
          ? _responseItems(res, fallbackKey: 'automations')
          : const <Map<String, dynamic>>[];
      _loading = false;
      _initialLoad = false;
    });
    if (!_apiOk(res)) {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not load reminders');
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? automation}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AutomationEditorSheet(
        eventId: widget.eventId,
        automation: automation,
      ),
    );
    if (saved == true) {
      if (!mounted) return;
      AppSnackbar.success(
        context,
        automation == null ? 'Automation created' : 'Automation updated',
      );
      await _load();
    }
  }

  Future<void> _openDetail(Map<String, dynamic> a) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AutomationDetailSheet(eventId: widget.eventId, automation: a),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!widget.isCreator) {
      return _emptyState(
        title: 'Reminders are organiser-only',
        body:
            'Only the event creator can configure WhatsApp reminders for contributors and guests.',
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final fabBottom = bottomInset + 28;
    final listBottomPad = bottomInset + 110;

    return Stack(
      children: [
        NuruRefreshIndicator(
          onRefresh: _load,
          child: _loading && _initialLoad
              ? _skeleton()
              : _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16, 16, 16, listBottomPad),
                      children: [
                        _intro(),
                        _emptyState(
                          title: 'No automations yet',
                          body:
                              'Create your first automation to remind contributors or guests on WhatsApp. You can preview, schedule and track delivery for each one.',
                        ),
                      ],
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, listBottomPad),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _intro(),
                        const SizedBox(height: 12),
                        for (final a in _items) ...[
                          _AutomationCard(
                            automation: a,
                            eventId: widget.eventId,
                            onChanged: _load,
                            onEdit: () => _openEditor(automation: a),
                            onDetail: () => _openDetail(a),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
        ),
        Positioned(
          right: 16,
          bottom: fabBottom,
          child: _PrimaryFab(
            label: 'New automation',
            iconAsset: 'assets/icons/plus-icon.svg',
            onTap: () => _openEditor(),
          ),
        ),
      ],
    );
  }

  Widget _intro() => Container(
        margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _svg('assets/icons/bell-icon.svg', size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Keep your event on track',
                      style: _f(size: 13.5, weight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    'Send friendly WhatsApp reminders so your guests do not miss key updates and contributors complete their pledges on time.',
                    style: _f(size: 11.5, color: AppColors.textTertiary, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _emptyState({required String title, required String body}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: _svg('assets/icons/bell-icon.svg', size: 28, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: _f(size: 14, weight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: _f(size: 12, color: AppColors.textTertiary, height: 1.45)),
          ],
        ),
      );

  Widget _skeleton() {
    Widget box({double? w, required double h, double r = 12}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AppColors.borderLight,
            borderRadius: BorderRadius.circular(r),
          ),
        );
    Widget card() => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                box(h: 40, w: 40, r: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      box(h: 13, w: 160, r: 4),
                      const SizedBox(height: 8),
                      box(h: 10, w: 100, r: 4),
                    ],
                  ),
                ),
                box(h: 28, w: 44, r: 999), // toggle switch
              ]),
              const SizedBox(height: 14),
              box(h: 10, w: double.infinity, r: 4),
              const SizedBox(height: 6),
              box(h: 10, w: 220, r: 4),
              const SizedBox(height: 14),
              Row(children: [
                box(h: 22, w: 90, r: 999),
                const SizedBox(width: 8),
                box(h: 22, w: 70, r: 999),
              ]),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        // Intro banner skeleton
        Container(
          margin: const EdgeInsets.fromLTRB(0, 8, 0, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withOpacity(0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              box(h: 20, w: 20, r: 6),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    box(h: 13, w: 180, r: 4),
                    const SizedBox(height: 8),
                    box(h: 10, w: double.infinity, r: 4),
                    const SizedBox(height: 4),
                    box(h: 10, w: 240, r: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < 3; i++) card(),
      ],
    );
  }
}


// ─── Automation card ───────────────────────────────────────────────────────

class _AutomationCard extends StatefulWidget {
  final Map<String, dynamic> automation;
  final String eventId;
  final VoidCallback onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDetail;

  const _AutomationCard({
    required this.automation,
    required this.eventId,
    required this.onChanged,
    required this.onEdit,
    required this.onDetail,
  });

  @override
  State<_AutomationCard> createState() => _AutomationCardState();
}

class _AutomationCardState extends State<_AutomationCard> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final id = widget.automation['id']?.toString() ?? '';
    final res = value
        ? await AutomationsService.enable(widget.eventId, id)
        : await AutomationsService.disable(widget.eventId, id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (_apiOk(res)) {
      widget.onChanged();
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not update');
    }
  }

  Future<void> _sendNow() async {
    final atype = (widget.automation['automation_type'] ?? '').toString();
    final isGuest = atype == 'guest_remind';
    final confirmed = await _confirm(
      context,
      title: isGuest ? 'Send reminder to guests?' : 'Send reminder now?',
      body: isGuest
          ? 'We will message your guests on WhatsApp using their saved phone numbers.'
          : 'We will message your contributors on WhatsApp using their saved phone numbers.',
      cta: 'Send now',
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final id = widget.automation['id']?.toString() ?? '';
    final res = await AutomationsService.sendNow(widget.eventId, id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (_apiOk(res)) {
      AppSnackbar.success(
        context,
        isGuest
            ? 'Guest reminders are being sent. We will notify your guests using the available contact details.'
            : 'Payment reminders are being sent to contributors with outstanding pledges.',
      );
      widget.onChanged();
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) widget.onDetail();
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not send');
    }
  }

  Future<void> _delete() async {
    final confirmed = await _confirm(
      context,
      title: 'Delete automation?',
      body: 'This cannot be undone. Run history is preserved.',
      cta: 'Delete',
      destructive: true,
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final id = widget.automation['id']?.toString() ?? '';
    final res = await AutomationsService.remove(widget.eventId, id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (_apiOk(res)) {
      widget.onChanged();
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not delete');
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.automation;
    final type = a['automation_type']?.toString() ?? 'fundraise_attend';
    final lang = a['language']?.toString() ?? 'en';
    final enabled = a['enabled'] == true;
    final name = (a['name']?.toString().isNotEmpty == true)
        ? a['name'].toString()
        : (kAutomationTypeLabelsEn[type] ?? type);
    final summary = _scheduleSummary(a);
    final lastRun = a['last_run'] is Map ? Map<String, dynamic>.from(a['last_run']) : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: _svg(_iconForType(type), size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: _f(size: 13.5, weight: FontWeight.w800),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _chip(lang.toUpperCase(), AppColors.primarySoft, AppColors.primary),
                          _chip(
                            enabled ? 'Enabled' : 'Disabled',
                            enabled
                                ? const Color(0x1410B981)
                                : const Color(0x14999999),
                            enabled
                                ? const Color(0xFF0F8C5C)
                                : AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _IconBtn(
                  iconAsset: 'assets/icons/pen-icon.svg',
                  onTap: widget.onEdit,
                  tooltip: 'Edit',
                ),
                _IconBtn(
                  iconAsset: 'assets/icons/delete-icon.svg',
                  onTap: _delete,
                  tooltip: 'Delete',
                  destructive: true,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _svg('assets/icons/clock-icon.svg', size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(summary,
                      style: _f(size: 12, color: AppColors.textTertiary, height: 1.45)),
                ),
              ],
            ),
          ),
          if (lastRun != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  _svg('assets/icons/double-check-icon.svg',
                      size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Last run ${_formatTime(lastRun['started_at']?.toString())} • '
                      '${lastRun['sent_count'] ?? 0} sent / '
                      '${lastRun['failed_count'] ?? 0} failed',
                      style: _f(size: 11.5, color: AppColors.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                _ToggleRow(value: enabled, busy: _busy, onChanged: _toggle),
                const Spacer(),
                _TextBtn(
                  label: 'History',
                  iconAsset: 'assets/icons/view-icon.svg',
                  onTap: widget.onDetail,
                ),
                const SizedBox(width: 4),
                _TextBtn(
                  label: 'Send now',
                  iconAsset: 'assets/icons/send-icon.svg',
                  primary: true,
                  loading: _busy,
                  onTap: _busy ? null : _sendNow,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Editor sheet ──────────────────────────────────────────────────────────

class _AutomationEditorSheet extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic>? automation;
  const _AutomationEditorSheet({required this.eventId, this.automation});

  @override
  State<_AutomationEditorSheet> createState() => _AutomationEditorSheetState();
}

class _AutomationEditorSheetState extends State<_AutomationEditorSheet> {
  late String _type;
  late String _language;
  late final TextEditingController _name;
  late final TextEditingController _body;
  String _scheduleKind = 'now';
  DateTime? _scheduleAt;
  late final TextEditingController _daysBefore;
  late final TextEditingController _hoursBefore;
  late final TextEditingController _repeatInterval;
  late final TextEditingController _minGap;
  bool _enabled = true;
  String _preview = '';
  bool _saving = false;
  bool _loadingTemplate = false;
  final GlobalKey _dateTimeKey = GlobalKey();
  final GlobalKey _previewKey = GlobalKey();

  String? _prefix;
  String? _suffix;
  List<String> _required = const [];
  String _defaultBody = '';

  @override
  void initState() {
    super.initState();
    final a = widget.automation;
    _type = a?['automation_type']?.toString() ?? 'fundraise_attend';
    _language = a?['language']?.toString() ?? 'en';
    _name = TextEditingController(text: a?['name']?.toString() ?? '');
    _body = TextEditingController(text: a?['body_override']?.toString() ?? '');
    _scheduleKind = a?['schedule_kind']?.toString() ?? 'now';
    final at = a?['schedule_at']?.toString();
    if (at != null && at.isNotEmpty) _scheduleAt = DateTime.tryParse(at)?.toLocal();
    _daysBefore = TextEditingController(text: (a?['days_before'] ?? 1).toString());
    _hoursBefore = TextEditingController(text: (a?['hours_before'] ?? 6).toString());
    _repeatInterval =
        TextEditingController(text: (a?['repeat_interval_hours'] ?? 24).toString());
    _minGap = TextEditingController(text: (a?['min_gap_hours'] ?? 24).toString());
    _enabled = a?['enabled'] != false;
    _loadTemplate();
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    _daysBefore.dispose();
    _hoursBefore.dispose();
    _repeatInterval.dispose();
    _minGap.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    setState(() => _loadingTemplate = true);
    final res = await AutomationsService.listTemplates(
      automationType: _type,
      language: _language,
    );
    if (!mounted) return;
    setState(() {
      _loadingTemplate = false;
      final items = _apiOk(res) ? _responseItems(res) : const <Map<String, dynamic>>[];
      if (items.isNotEmpty) {
        final t = items.first;
        _prefix = t['protected_prefix']?.toString();
        _suffix = t['protected_suffix']?.toString();
        _required = const [];
        _defaultBody = t['body_default']?.toString() ?? '';
        if (widget.automation == null && _type != 'fundraise_attend') {
          _body.clear();
        }
      }
    });
  }

  Future<void> _doPreview() async {
    final a = widget.automation;
    if (a == null) {
      // local substitution
      final sample = {
        '{{1}}': 'Asha',
        '{{2}}': 'Your event',
        '{{3}}': DateFormat('d MMM yyyy').format(DateTime.now()),
      };
      final previewBody = _type == 'fundraise_attend' ? _body.text : _defaultBody;
      var out =
          '${_prefix ?? ''}\n$previewBody\n${_suffix ?? ''}';
      sample.forEach((k, v) => out = out.replaceAll(k, v));
      setState(() => _preview = out.trim());
      _scrollToPreview();
      return;
    }
    final res = await AutomationsService.preview(
      widget.eventId,
      a['id']?.toString() ?? '',
      bodyOverride: _type == 'fundraise_attend' ? _body.text : null,
      language: _language,
    );
    if (!mounted) return;
    final data = res['data'];
    String rendered = '';
    if (data is Map) {
      final inner = data['data'] is Map ? data['data'] : data;
      rendered = inner['rendered']?.toString() ?? '';
    }
    if (!_apiOk(res)) {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Preview failed');
      return;
    }
    setState(() => _preview = rendered);
    _scrollToPreview();
  }

  void _scrollToPreview() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _previewKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    });
  }

  void _focusDateTimeField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _dateTimeKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    });
  }

  void _setScheduleKind(String kind) {
    setState(() => _scheduleKind = kind);
    if (kind == 'datetime') _focusDateTimeField();
  }

  Future<void> _save() async {
    if (_loadingTemplate) {
      AppSnackbar.info(context, 'Please wait for the template to finish loading');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'automation_type': _type,
      'language': _language,
      if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
      if (_type == 'fundraise_attend' && _body.text.trim().isNotEmpty)
        'body_override': _body.text.trim(),
      'schedule_kind': _scheduleKind,
      if (_scheduleKind == 'datetime' && _scheduleAt != null)
        'schedule_at': _scheduleAt!.toUtc().toIso8601String(),
      if (_scheduleKind == 'days_before')
        'days_before': int.tryParse(_daysBefore.text) ?? 1,
      if (_scheduleKind == 'hours_before')
        'hours_before': int.tryParse(_hoursBefore.text) ?? 6,
      if (_scheduleKind == 'repeat')
        'repeat_interval_hours': int.tryParse(_repeatInterval.text) ?? 24,
      'min_gap_hours': int.tryParse(_minGap.text) ?? 24,
      'timezone': 'Africa/Nairobi',
      'enabled': _enabled,
    };
    print('[Automations Sheet] saving ${widget.automation == null ? 'create' : 'update'} for event ${widget.eventId}');
    print('[Automations Sheet] request payload: $payload');
    try {
      final res = widget.automation == null
          ? await AutomationsService.create(widget.eventId, payload)
          : await AutomationsService.update(
              widget.eventId, widget.automation!['id'].toString(), payload);
      print('[Automations Sheet] normalized response: $res');
      print('[Automations Sheet] success parsed as: ${_apiOk(res)}');
      if (!mounted) return;
      if (_apiOk(res)) {
        setState(() => _saving = false);
        print('[Automations Sheet] closing sheet with success result');
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _saving = false);
      print('[Automations Sheet] save failed message: ${_apiMessage(res, 'Save failed')}');
      AppSnackbar.error(context, _apiMessage(res, 'Save failed'));
    } catch (e, st) {
      print('[Automations Sheet] save exception: $e');
      print('[Automations Sheet] save stack: $st');
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackbar.error(context, 'Save failed. Please try again.');
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final picked = await showNuruDateTimePicker(
      context: context,
      initial: _scheduleAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _scheduleAt = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: widget.automation == null ? 'New automation' : 'Edit automation',
      iconAsset: 'assets/icons/bell-icon.svg',
      footer: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _OutlineBtn(
                  label: 'Preview',
                  iconAsset: 'assets/icons/view-icon.svg',
                  onTap: _doPreview,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _FilledBtn(
                  label: _saving
                      ? 'Saving…'
                      : (widget.automation == null ? 'Create' : 'Save'),
                  iconAsset: 'assets/icons/double-check-icon.svg',
                  loading: _saving,
                  onTap: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          _SectionLabel('Type'),
          _OptionGrid<String>(
            value: _type,
            options: const [
              ('fundraise_attend', 'Fundraising attendance'),
              ('pledge_remind', 'Payment reminder'),
              ('guest_remind', 'Guest reminder'),
            ],
            onChanged: (v) {
              setState(() => _type = v);
              _loadTemplate();
            },
          ),
          const SizedBox(height: 14),
          _SectionLabel('Language'),
          _OptionGrid<String>(
            value: _language,
            options: const [
              ('en', 'English'),
              ('sw', 'Kiswahili'),
            ],
            onChanged: (v) {
              setState(() => _language = v);
              _loadTemplate();
            },
          ),
          const SizedBox(height: 14),
          _SectionLabel('Internal name (optional)'),
          _TextField(
            controller: _name,
            hint: 'eg. Round 1 reminders',
          ),
          if (_loadingTemplate) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (!_loadingTemplate && _type == 'fundraise_attend' && _prefix != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _svg('assets/icons/shield-icon.svg',
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Text('Protected wrapper (cannot be edited)',
                        style: _f(size: 11, weight: FontWeight.w700, color: AppColors.textTertiary)),
                  ]),
                  const SizedBox(height: 6),
                  Text('Prefix: ${_prefix!}',
                      style: _f(size: 11, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('Suffix: ${_suffix ?? ''}',
                      style: _f(size: 11, color: AppColors.textPrimary)),
                  if (_required.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final p in _required)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('{{$p}}',
                                style: _f(
                                  size: 10.5,
                                  weight: FontWeight.w700,
                                  color: AppColors.primary,
                                )),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (_type == 'fundraise_attend') ...[
            const SizedBox(height: 14),
            _SectionLabel('Message body'),
            _TextField(
              controller: _body,
              hint: 'Write the message body here…',
              minLines: 5,
              maxLines: 10,
            ),
            const SizedBox(height: 6),
            Text(
              'Cannot start or end with a placeholder. Required placeholders must remain.',
              style: _f(size: 10.5, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 14),
          ] else if (_defaultBody.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SectionLabel('Message template'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                [
                  if ((_prefix ?? '').isNotEmpty) _prefix,
                  _defaultBody,
                  if ((_suffix ?? '').isNotEmpty) _suffix,
                ].whereType<String>().join('\n'),
                style: _f(size: 12, height: 1.5, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'This template is pre-approved and cannot be edited. Use Preview to see it with sample details filled in.',
              style: _f(size: 10.5, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 14),
          ],
          _SectionLabel('Schedule'),
          Text(
            'When should this reminder be sent? You can change this any time.',
            style: _f(size: 10.5, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _PresetChip(
                label: 'Manual send',
                onTap: () => _setScheduleKind('now'),
                selected: _scheduleKind == 'now',
              ),
              _PresetChip(
                label: '1 day before',
                onTap: () {
                  setState(() => _daysBefore.text = '1');
                  _setScheduleKind('days_before');
                },
                selected: _scheduleKind == 'days_before' && _daysBefore.text == '1',
              ),
              _PresetChip(
                label: '3 days before',
                onTap: () {
                  setState(() => _daysBefore.text = '3');
                  _setScheduleKind('days_before');
                },
                selected: _scheduleKind == 'days_before' && _daysBefore.text == '3',
              ),
              _PresetChip(
                label: '6 hours before',
                onTap: () {
                  setState(() => _hoursBefore.text = '6');
                  _setScheduleKind('hours_before');
                },
                selected: _scheduleKind == 'hours_before' && _hoursBefore.text == '6',
              ),
              _PresetChip(
                label: 'Every 24h',
                onTap: () {
                  setState(() => _repeatInterval.text = '24');
                  _setScheduleKind('repeat');
                },
                selected: _scheduleKind == 'repeat',
              ),
              _PresetChip(
                label: 'Specific date',
                onTap: () => _setScheduleKind('datetime'),
                selected: _scheduleKind == 'datetime',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _OptionGrid<String>(
            value: _scheduleKind,
            options: const [
              ('now', 'Send now (manual)'),
              ('datetime', 'Specific date & time'),
              ('days_before', 'Days before event'),
              ('hours_before', 'Hours before event'),
              ('repeat', 'Repeating'),
            ],
            onChanged: _setScheduleKind,
          ),
          const SizedBox(height: 10),
          if (_scheduleKind == 'datetime') KeyedSubtree(key: _dateTimeKey, child: _datetimePicker()),
          if (_scheduleKind == 'days_before')
            _NumberField(controller: _daysBefore, label: 'Days before event'),
          if (_scheduleKind == 'hours_before')
            _NumberField(controller: _hoursBefore, label: 'Hours before event'),
          if (_scheduleKind == 'repeat') ...[
            _NumberField(controller: _repeatInterval, label: 'Interval (hours)'),
            const SizedBox(height: 8),
            _NumberField(controller: _minGap, label: 'Min gap per recipient (hours)'),
          ],
          if (_scheduleKind != 'repeat') ...[
            const SizedBox(height: 8),
            _NumberField(controller: _minGap, label: 'Min gap per recipient (hours)'),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text('Enabled', style: _f(size: 13, weight: FontWeight.w700)),
              ),
              Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                activeColor: AppColors.primary,
              ),
            ],
          ),
          if (_preview.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              key: _previewKey,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _svg('assets/icons/view-icon.svg',
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Text('Preview',
                        style: _f(size: 11, weight: FontWeight.w700, color: AppColors.textTertiary)),
                  ]),
                  const SizedBox(height: 8),
                  Text(_preview,
                      style: _f(size: 12.5, color: AppColors.textPrimary, height: 1.45)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _datetimePicker() {
    final label = _scheduleAt == null
        ? 'Pick a date & time'
        : DateFormat('EEE d MMM yyyy • HH:mm').format(_scheduleAt!);
    return GestureDetector(
      onTap: _pickDateTime,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            _svg('assets/icons/calendar-icon.svg',
                size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: _f(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: _scheduleAt == null
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                  )),
            ),
            _svg('assets/icons/chevron-right-icon.svg',
                size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─── Detail (runs + recipients) sheet ──────────────────────────────────────

class _AutomationDetailSheet extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic> automation;
  const _AutomationDetailSheet({required this.eventId, required this.automation});

  @override
  State<_AutomationDetailSheet> createState() => _AutomationDetailSheetState();
}

class _AutomationDetailSheetState extends State<_AutomationDetailSheet> {
  int _tab = 0;
  List<Map<String, dynamic>> _runs = const [];
  Map<String, dynamic>? _activeRun;
  List<Map<String, dynamic>> _recipients = const [];
  String _filter = '';
  Timer? _poll;
  bool _loadingRuns = true;
  bool _loadingRecipients = false;

  @override
  void initState() {
    super.initState();
    _loadRuns(initial: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadRuns({bool initial = false}) async {
    if (initial) setState(() => _loadingRuns = true);
    final id = widget.automation['id']?.toString() ?? '';
    final res = await AutomationsService.listRuns(widget.eventId, id);
    if (!mounted) return;
    final runs = _apiOk(res) ? _responseItems(res) : const <Map<String, dynamic>>[];
    setState(() {
      _runs = runs;
      _loadingRuns = false;
      if (_activeRun == null) {
        _activeRun = runs.isNotEmpty ? runs.first : null;
      } else {
        _activeRun = runs.cast<Map<String, dynamic>?>().firstWhere(
              (r) => r?['id']?.toString() == _activeRun?['id']?.toString(),
              orElse: () => runs.isNotEmpty ? runs.first : null,
            );
      }
    });
    if (_activeRun != null) _loadRecipients(_activeRun!['id'].toString());
    _maybeStartPoll();
  }

  Future<void> _loadRecipients(String runId) async {
    setState(() => _loadingRecipients = true);
    final id = widget.automation['id']?.toString() ?? '';
    final res = await AutomationsService.listRecipients(
      widget.eventId,
      id,
      runId,
      status: _filter.isEmpty ? null : _filter,
    );
    if (!mounted) return;
    setState(() {
      _recipients = _apiOk(res) ? _responseItems(res) : const <Map<String, dynamic>>[];
      _loadingRecipients = false;
    });
  }

  void _maybeStartPoll() {
    _poll?.cancel();
    final status = _activeRun?['status']?.toString();
    if (status == 'running' || status == 'pending') {
      _poll = Timer.periodic(const Duration(seconds: 5), (_) {
        _loadRuns();
      });
    }
  }

  Future<void> _resendFailed() async {
    final run = _activeRun;
    if (run == null) return;
    final id = widget.automation['id']?.toString() ?? '';
    final res = await AutomationsService.resendFailed(
        widget.eventId, id, run['id'].toString());
    if (!mounted) return;
    if (_apiOk(res)) {
      AppSnackbar.success(context, 'Resend queued');
      Future.delayed(const Duration(milliseconds: 1500),
          () => _loadRecipients(run['id'].toString()));
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Resend failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.automation;
    final title = (a['name']?.toString().isNotEmpty == true)
        ? a['name'].toString()
        : (kAutomationTypeLabelsEn[a['automation_type']?.toString() ?? ''] ??
            'Automation');
    return _SheetShell(
      title: title,
      iconAsset: 'assets/icons/clock-icon.svg',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _SegBtn(
                  label: 'Runs',
                  active: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                _SegBtn(
                  label: 'Recipients',
                  active: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
              ],
            ),
          ),
          Flexible(
            child: _tab == 0 ? _runsView() : _recipientsView(),
          ),
        ],
      ),
    );
  }

  Widget _runsView() {
    if (_loadingRuns) {
      return const NuruSkeletonList(
        itemCount: 3,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        showAvatar: false,
        showTrailing: true,
      );
    }
    if (_runs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Text(
          'No runs yet. Hit Send now from the automation card to trigger one.',
          textAlign: TextAlign.center,
          style: _f(size: 12.5, color: AppColors.textTertiary),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _runs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _runs[i];
        final isActive = _activeRun?['id'] == r['id'];
        final status = r['status']?.toString() ?? 'pending';
        return GestureDetector(
          onTap: () {
            setState(() => _activeRun = r);
            _loadRecipients(r['id'].toString());
            _maybeStartPoll();
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? AppColors.primary : AppColors.borderLight,
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _statusPill(status),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_formatTime(r['started_at']?.toString()),
                      style: _f(size: 12, color: AppColors.textTertiary)),
                ),
                Text(
                  '${r['sent_count'] ?? 0}/${r['total_recipients'] ?? 0} sent • ${r['failed_count'] ?? 0} failed',
                  style: _f(size: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _recipientsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _FilterPills(
                  value: _filter,
                  options: const [
                    ('', 'All'),
                    ('sent', 'Sent'),
                    ('failed', 'Failed'),
                    ('pending', 'Pending'),
                    ('skipped', 'Skipped'),
                  ],
                  onChanged: (v) {
                    setState(() => _filter = v);
                    if (_activeRun != null) {
                      _loadRecipients(_activeRun!['id'].toString());
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              _IconBtn(
                iconAsset: 'assets/icons/send-icon.svg',
                onTap: _activeRun == null ? null : _resendFailed,
                tooltip: 'Resend failed',
              ),
            ],
          ),
        ),
        Flexible(
          child: _loadingRecipients
              ? const NuruSkeletonList(
                  itemCount: 5,
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  showTrailing: true,
                )
              : _recipients.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
                      child: Text(
                        'No recipients match this filter.',
                        textAlign: TextAlign.center,
                        style: _f(size: 12.5, color: AppColors.textTertiary),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _recipients.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final r = _recipients[i];
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderLight),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r['name']?.toString().isNotEmpty == true
                                          ? r['name'].toString()
                                          : (r['phone']?.toString() ?? 'Recipient'),
                                      style: _f(size: 12.5, weight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${r['phone'] ?? ''} • ${r['channel'] ?? '-'}'
                                      '${r['error'] != null ? ' • ${r['error']}' : ''}',
                                      style: _f(size: 10.5, color: AppColors.textTertiary),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              _statusPill(r['status']?.toString() ?? 'pending'),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ─── Shared little widgets ─────────────────────────────────────────────────

class _SheetShell extends StatelessWidget {
  final String title;
  final String iconAsset;
  final Widget child;
  final Widget? footer;
  const _SheetShell({
    required this.title,
    required this.iconAsset,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.92;
    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: _svg(iconAsset, size: 16, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: _f(size: 14.5, weight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  _IconBtn(
                    iconAsset: 'assets/icons/close-icon.svg',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: PrimaryScrollController(
                controller: controller,
                child: child,
              ),
            ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}

class _PrimaryFab extends StatelessWidget {
  final String label;
  final String iconAsset;
  final VoidCallback onTap;
  const _PrimaryFab({required this.label, required this.iconAsset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(28),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _svg(iconAsset, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(label, style: _f(size: 13, weight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final String iconAsset;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool destructive;
  const _IconBtn({
    required this.iconAsset,
    this.onTap,
    this.tooltip,
    this.destructive = false,
  });
  @override
  Widget build(BuildContext context) {
    final btn = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: _svg(
          iconAsset,
          size: 16,
          color: destructive
              ? const Color(0xFFC0392B)
              : AppColors.textTertiary,
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

class _TextBtn extends StatelessWidget {
  final String label;
  final String iconAsset;
  final VoidCallback? onTap;
  final bool primary;
  final bool loading;
  const _TextBtn({
    required this.label,
    required this.iconAsset,
    required this.onTap,
    this.primary = false,
    this.loading = false,
  });
  @override
  Widget build(BuildContext context) {
    final color = primary ? AppColors.primary : AppColors.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              _svg(iconAsset, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: _f(size: 12, weight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final String iconAsset;
  final VoidCallback? onTap;
  const _OutlineBtn({required this.label, required this.iconAsset, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _svg(iconAsset, size: 14, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Text(label, style: _f(size: 12.5, weight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilledBtn extends StatelessWidget {
  final String label;
  final String iconAsset;
  final VoidCallback? onTap;
  final bool loading;
  const _FilledBtn({
    required this.label,
    required this.iconAsset,
    required this.onTap,
    this.loading = false,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? AppColors.primary.withOpacity(0.6) : AppColors.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                _svg(iconAsset, size: 14, color: Colors.white),
              const SizedBox(width: 8),
              Text(label,
                  style: _f(size: 12.5, weight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.value, required this.busy, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Transform.scale(
        scale: 0.85,
        child: Switch(
          value: value,
          onChanged: busy ? null : onChanged,
          activeColor: AppColors.primary,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: _f(size: 11.5, weight: FontWeight.w700, color: AppColors.textTertiary)),
      );
}

class _OptionGrid<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const _OptionGrid({required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final opt in options)
          GestureDetector(
            onTap: () => onChanged(opt.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: opt.$1 == value ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: opt.$1 == value ? AppColors.primary : AppColors.borderLight,
                ),
              ),
              child: Text(
                opt.$2,
                style: _f(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: opt.$1 == value ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PresetChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: _f(
            size: 11.5,
            weight: FontWeight.w700,
            color: selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int minLines;
  final int maxLines;
  const _TextField({
    required this.controller,
    required this.hint,
    this.minLines = 1,
    this.maxLines = 1,
  });
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      minLines: minLines,
      maxLines: maxLines,
      style: _f(size: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _f(size: 13, color: AppColors.textHint),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _NumberField({required this.controller, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: _f(size: 12.5, weight: FontWeight.w700)),
        ),
        SizedBox(
          width: 90,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            autocorrect: false,
            enableSuggestions: false,
            style: _f(size: 13, weight: FontWeight.w700),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }
}

class _SegBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegBtn({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(label,
              style: _f(
                size: 12.5,
                weight: FontWeight.w800,
                color: active ? AppColors.textPrimary : AppColors.textTertiary,
              )),
        ),
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  const _FilterPills({required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final opt in options) ...[
            GestureDetector(
              onTap: () => onChanged(opt.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: opt.$1 == value ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: opt.$1 == value ? AppColors.primary : AppColors.borderLight,
                  ),
                ),
                child: Text(
                  opt.$2,
                  style: _f(
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: opt.$1 == value ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── helpers ───────────────────────────────────────────────────────────────

Widget _svg(String asset, {double size = 16, Color? color}) => SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: color == null ? null : ColorFilter.mode(color, BlendMode.srcIn),
    );

TextStyle _f({double size = 13, FontWeight weight = FontWeight.w500, Color? color, double? height}) =>
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.textPrimary,
      height: height,
      letterSpacing: -0.1,
      decorationThickness: 0,
    );

Widget _chip(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: _f(size: 10, weight: FontWeight.w800, color: fg)),
    );

Widget _statusPill(String status) {
  Color bg;
  Color fg;
  switch (status) {
    case 'sent':
    case 'completed':
      bg = const Color(0x1410B981);
      fg = const Color(0xFF0F8C5C);
      break;
    case 'failed':
      bg = const Color(0x14C0392B);
      fg = const Color(0xFFC0392B);
      break;
    case 'pending':
      bg = const Color(0x14F59E0B);
      fg = const Color(0xFFA86A00);
      break;
    case 'running':
      bg = const Color(0x143B82F6);
      fg = const Color(0xFF1D4ED8);
      break;
    case 'skipped':
    case 'cancelled':
    default:
      bg = const Color(0x146D28D9);
      fg = const Color(0xFF6D28D9);
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(status,
        style: _f(size: 10, weight: FontWeight.w800, color: fg)),
  );
}

String _scheduleSummary(Map<String, dynamic> a) {
  switch (a['schedule_kind']?.toString()) {
    case 'now':
      return 'Manual send';
    case 'datetime':
      return 'On ${_formatTime(a['schedule_at']?.toString())}';
    case 'days_before':
      return '${a['days_before'] ?? 0} day(s) before event';
    case 'hours_before':
      return '${a['hours_before'] ?? 0} hour(s) before event';
    case 'repeat':
      return 'Every ${a['repeat_interval_hours'] ?? 24}h '
          '(min gap ${a['min_gap_hours'] ?? 24}h)';
    default:
      return a['schedule_kind']?.toString() ?? '';
  }
}

String _formatTime(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('d MMM yyyy • HH:mm').format(dt);
  } catch (_) {
    return iso;
  }
}

String _iconForType(String type) {
  switch (type) {
    case 'pledge_remind':
      return 'assets/icons/money-icon.svg';
    case 'guest_remind':
      return 'assets/icons/users-icon.svg';
    case 'fundraise_attend':
    default:
      return 'assets/icons/bell-icon.svg';
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String cta,
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _f(size: 15, weight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(body,
                style: _f(size: 12.5, color: AppColors.textTertiary, height: 1.45)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel',
                      style: _f(size: 12.5, weight: FontWeight.w700, color: AppColors.textTertiary)),
                ),
                const SizedBox(width: 6),
                Material(
                  color: destructive ? const Color(0xFFC0392B) : AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).pop(true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      child: Text(cta,
                          style: _f(
                              size: 12.5,
                              weight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
