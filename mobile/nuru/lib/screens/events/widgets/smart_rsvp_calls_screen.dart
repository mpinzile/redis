import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/nuru_subpage_app_bar.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/nuru_search_bar.dart';
import '../../../core/services/voice_calls_service.dart';
import '../../../core/services/events_service.dart';
import '../../../core/l10n/app_translations.dart';
import '../../../providers/locale_provider.dart';

String _vt(BuildContext c, String key, [Map<String, String>? vars]) {
  final locale = c.read<LocaleProvider>().languageCode;
  var s = AppTranslations.tr(key, locale);
  if (vars != null) {
    vars.forEach((k, v) => s = s.replaceAll('{$k}', v));
  }
  return s;
}

/// Backend paginated responses wrap payloads as
/// `data: { items: [...], pagination: {...} }`. Older shapes returned a
/// bare list, so accept both.
List<dynamic> _itemsOfTopLevel(dynamic data) {
  if (data is List) return data;
  if (data is Map) {
    final items = data['items'] ?? data['results'] ?? data['data'];
    if (items is List) return items;
  }
  return const [];
}

/// Smart RSVP Calls — Phase 9 of Nuru Voice Assistant.
///
/// Organiser-facing screen that lets the event owner kick off an AI voice
/// campaign against their pending guest list, watch live call status, and
/// inspect the AI outcome / transcript for each call.
///
/// Design language: clean white surfaces, soft depth, custom-feel iconography,
/// Inter typography, Nuru amber accents. No gradients, no decorative sparkles.
class SmartRsvpCallsScreen extends StatefulWidget {
  final String eventId;
  final String? eventTitle;

  const SmartRsvpCallsScreen({
    super.key,
    required this.eventId,
    this.eventTitle,
  });

  @override
  State<SmartRsvpCallsScreen> createState() => _SmartRsvpCallsScreenState();
}

class _SmartRsvpCallsScreenState extends State<SmartRsvpCallsScreen> {
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _campaign;
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _pendingGuests = [];
  List<Map<String, dynamic>> _allGuests = [];
  // Truth-from-DB counters (do not derive from local jobs alone).
  int _pendingTotal = 0;
  int _confirmedTotal = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadCampaign(),
      _loadPendingGuests(),
      _loadRsvpTotals(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  /// Pulls authoritative RSVP counts from the events API so the hero
  /// "Awaiting reply" and "Going" stats reflect the database, not just
  /// the AI call outcomes (a guest may also confirm via WhatsApp, web,
  /// or the organiser manually).
  Future<void> _loadRsvpTotals() async {
    Future<int> count(String status) async {
      final res = await EventsService.getGuests(widget.eventId,
          page: 1, limit: 1, rsvpStatus: status);
      if (res['success'] != true) return 0;
      final pg = (res['data']?['pagination'] as Map?) ?? const {};
      final t = pg['total_items'] ?? pg['totalItems'] ?? pg['total'] ?? 0;
      if (t is int) return t;
      if (t is num) return t.toInt();
      return int.tryParse(t.toString()) ?? 0;
    }

    final results = await Future.wait([count('pending'), count('confirmed')]);
    _pendingTotal = results[0];
    _confirmedTotal = results[1];
    if (mounted) setState(() {});
  }

  /// Delegates to the top-level [_itemsOf] for both list and paginated shapes.
  List<dynamic> _itemsOf(dynamic data) => _itemsOfTopLevel(data);


  Future<void> _loadCampaign() async {
    final res = await VoiceCallsService.listCampaigns(
      eventId: widget.eventId,
      pageSize: 1,
    );
    if (res['success'] == true) {
      final list = _itemsOf(res['data']);
      if (list.isNotEmpty) {
        _campaign = Map<String, dynamic>.from(list.first as Map);
        await _loadJobs();
        _maybeStartPolling();
      } else {
        _campaign = null;
        _jobs = [];
      }
    }
  }

  Future<void> _loadJobs() async {
    final c = _campaign;
    if (c == null) return;
    final res = await VoiceCallsService.listJobs(c['id'].toString());
    if (res['success'] == true) {
      _jobs = _itemsOf(res['data'])
          .map((j) => Map<String, dynamic>.from(j as Map))
          .toList();
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadPendingGuests() async {
    final List<Map<String, dynamic>> pending = [];
    final List<Map<String, dynamic>> all = [];
    int page = 1;
    while (true) {
      final res = await EventsService.getGuests(widget.eventId,
          page: page, limit: 200);
      if (res['success'] != true) break;
      final data = res['data'];
      final list = (data?['guests'] as List?) ?? const [];
      for (final g in list) {
        final m = Map<String, dynamic>.from(g as Map);
        final status = (m['rsvp_status'] ?? '').toString().toLowerCase();
        final phone = (m['phone'] ?? m['phone_number'] ?? '').toString();
        if (phone.isEmpty) continue;
        all.add(m);
        if (status.isEmpty || status == 'pending' || status == 'invited') {
          pending.add(m);
        }
      }
      final pagination = (data?['pagination'] as Map?) ?? const {};
      final totalPages =
          (pagination['total_pages'] ?? pagination['totalPages'] ?? 1) as int;
      if (list.isEmpty || page >= totalPages) break;
      page++;
      if (page > 50) break;
    }
    _pendingGuests = pending;
    _allGuests = all;
  }


  void _maybeStartPolling() {
    _poll?.cancel();
    final status = (_campaign?['status'] ?? '').toString();
    if (status == 'queued' || status == 'running') {
      _poll = Timer.periodic(const Duration(seconds: 8), (_) async {
        await Future.wait([_loadCampaign(), _loadRsvpTotals()]);
      });
    }
  }

  String _campaignLang() {
    // Honour the user's app locale; default to English unless they picked
    // Swahili in the app. This drives the AI conversation language too.
    return context.read<LocaleProvider>().isSwahili ? 'sw' : 'en';
  }

  Future<void> _createAndQueue() async {
    if (_pendingGuests.isEmpty) {
      AppSnackbar.info(context, _vt(context, 'voice_no_pending'));
      return;
    }
    setState(() => _busy = true);

    final lang = _campaignLang();
    final created = await VoiceCallsService.createCampaign(
      eventId: widget.eventId,
      purpose: 'rsvp',
      language: lang,
      title: 'Smart RSVP · ${widget.eventTitle ?? 'Event'}',
    );
    if (created['success'] != true) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnackbar.error(
            context,
            created['message']?.toString() ??
                _vt(context, 'voice_create_failed'));
      }
      return;
    }
    final campaign = Map<String, dynamic>.from(created['data'] as Map);
    final cid = campaign['id'].toString();

    final recipients = _pendingGuests.map((g) {
      return {
        'recipient_type': 'guest',
        'recipient_ref_id': g['id']?.toString(),
        'recipient_name': (g['name'] ?? g['full_name'] ?? '').toString(),
        'phone': (g['phone'] ?? g['phone_number']).toString(),
        'language': lang,
      };
    }).toList();

    final added = await VoiceCallsService.addJobs(cid, recipients, enforceHours: true);
    await VoiceCallsService.startCampaign(cid);
    // Backend has no auto-dialer worker yet — fan out place-call per job
    // so the campaign actually rings, not just gets queued.
    final data = added['data'];
    final dialable = _itemsOfTopLevel(
      (data is Map ? (data['accepted'] ?? data['jobs']) : null),
    );
    for (final j in dialable) {
      if (j is Map && j['id'] != null) {
        // Fire-and-forget so the UI isn't blocked by Twilio round-trips.
        // ignore: unawaited_futures
        VoiceCallsService.placeCall(j['id'].toString());
      }
    }
    await _loadCampaign();
    if (mounted) {
      setState(() => _busy = false);
      AppSnackbar.success(
          context,
          _vt(context, 'voice_dialing_started',
              {'n': '${recipients.length}'}));
    }
  }

  Future<void> _pauseOrResume() async {
    final c = _campaign;
    if (c == null) return;
    setState(() => _busy = true);
    final status = (c['status'] ?? '').toString();
    if (status == 'running' || status == 'queued') {
      await VoiceCallsService.pauseCampaign(c['id'].toString());
    } else if (status == 'paused' || status == 'draft') {
      await VoiceCallsService.startCampaign(c['id'].toString());
    }
    await _loadCampaign();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cancel() async {
    final c = _campaign;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_vt(context, 'voice_cancel_title')),
        content: Text(_vt(context, 'voice_cancel_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_vt(context, 'voice_cancel_no'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_vt(context, 'voice_cancel_yes'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await VoiceCallsService.cancelCampaign(c['id'].toString());
    await _loadCampaign();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>(); // rebuild when locale flips
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: NuruSubPageAppBar(title: _vt(context, 'voice_screen_title')),
      body: _loading
          ? const _RsvpCallsSkeleton()
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _bootstrap,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _heroCard(),
                  const SizedBox(height: 12),
                  _callOneCta(),
                  const SizedBox(height: 16),
                  if (_campaign == null) _emptyState() else _runtimePanel(),
                  if (_campaign != null) ...[
                    const SizedBox(height: 20),
                    _sectionLabel(_vt(context, 'voice_section_recipients')),
                    const SizedBox(height: 8),
                    ..._jobs.map(_jobTile),
                    if (_jobs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(_vt(context, 'voice_no_recipients'),
                              style: GoogleFonts.inter(
                                color: AppColors.textTertiary,
                                fontSize: 13.5,
                              )),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  // ─── Call one person CTA ─────────────────────────────────────────────────
  Widget _callOneCta() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _busy ? null : _openCallOneSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.phone_in_talk_rounded,
                  size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_vt(context, 'voice_call_one_title'),
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(_vt(context, 'voice_call_one_sub'),
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  void _openCallOneSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CallOneSheet(
        eventId: widget.eventId,
        eventTitle: widget.eventTitle,
        guests: _allGuests.isNotEmpty ? _allGuests : _pendingGuests,
        onPlaced: () async {
          await _loadCampaign();
        },
      ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────────────────────
  Widget _heroCard() {
    final pendingDb = _pendingTotal;
    final calledFromCounts = () {
      final c = _campaign?['counts'] as Map?;
      if (c == null) return 0;
      int sum = 0;
      for (final k in const [
        'completed',
        'failed',
        'no_answer',
        'busy',
        'in_progress',
      ]) {
        final v = c[k];
        if (v is int) sum += v;
        if (v is num) sum += v.toInt();
      }
      return sum;
    }();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.elevatedShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.graphic_eq_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_vt(context, 'voice_hero_title'),
                        style: GoogleFonts.inter(
                          color: AppColors.textOnDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        )),
                    const SizedBox(height: 2),
                    Text(_vt(context, 'voice_hero_subtitle'),
                        style: GoogleFonts.inter(
                          color: AppColors.textOnDarkMuted,
                          fontSize: 12.5,
                          height: 1.4,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _heroStat(_vt(context, 'voice_stat_pending'), '$pendingDb'),
              const SizedBox(width: 10),
              _heroStat(_vt(context, 'voice_stat_called'), '$calledFromCounts'),
              const SizedBox(width: 10),
              _heroStat(_vt(context, 'voice_stat_confirmed'),
                  '$_confirmedTotal'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.inter(
                  color: AppColors.textOnDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.inter(
                  color: AppColors.textOnDarkMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }

  // ─── Empty / Idle ────────────────────────────────────────────────────────
  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_vt(context, 'voice_idle_title'),
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              )),
          const SizedBox(height: 6),
          Text(
              _vt(context, 'voice_idle_body',
                  {'n': '${_pendingGuests.length}'}),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              )),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _busy || _pendingGuests.isEmpty ? null : _createAndQueue,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_vt(context, 'voice_start_btn'),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      )),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Runtime / control panel ─────────────────────────────────────────────
  Widget _runtimePanel() {
    final c = _campaign!;
    final status = (c['status'] ?? 'draft').toString();
    final counts = (c['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
    final total = _jobs.length;
    final done = (counts['completed'] ?? 0) as int;
    final progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusPill(status),
              const Spacer(),
              Text('$done / $total',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  )),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.borderLight,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _pauseOrResume,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    (status == 'running' || status == 'queued')
                        ? _vt(context, 'voice_pause')
                        : _vt(context, 'voice_resume'),
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.error.withOpacity(0.4)),
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(_vt(context, 'voice_cancel'),
                      style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final (bg, fg, key) = switch (status) {
      'running' => (AppColors.successSoft, AppColors.success, 'voice_status_running'),
      'queued' => (AppColors.infoSoft, AppColors.info, 'voice_status_queued'),
      'paused' => (AppColors.warningSoft, AppColors.warning, 'voice_status_paused'),
      'completed' => (AppColors.successSoft, AppColors.success, 'voice_status_completed'),
      'cancelled' => (AppColors.errorSoft, AppColors.error, 'voice_status_cancelled'),
      _ => (AppColors.primarySoft, AppColors.primary, 'voice_status_draft'),
    };
    final label = _vt(context, key);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: fg,
                letterSpacing: 0.2,
              )),
        ],
      ),
    );
  }

  // ─── Job tile ────────────────────────────────────────────────────────────
  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 2),
        child: Text(s.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 0.8,
            )),
      );

  Widget _jobTile(Map<String, dynamic> j) {
    final name = (j['recipient_name'] ?? '').toString();
    final phone = (j['phone_e164'] ?? '').toString();
    final status = (j['status'] ?? 'pending').toString();
    final outcome = (j['ai_outcome'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openJobSheet(j),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? phone : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(_jobSubtitle(status, outcome, phone),
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              _outcomeChip(status, outcome),
            ],
          ),
        ),
      ),
    );
  }

  String _jobSubtitle(String status, String outcome, String phone) {
    if (outcome.isNotEmpty) return '$phone · ${_outcomeLabel(outcome)}';
    return '$phone · ${_statusLabel(status)}';
  }

  String _statusLabel(String s) {
    final key = switch (s) {
      'pending' => 'voice_status_pending',
      'queued' => 'voice_status_queued',
      'in_progress' => 'voice_status_in_progress',
      'completed' => 'voice_status_completed',
      'failed' => 'voice_status_failed',
      'no_answer' => 'voice_status_no_answer',
      'busy' => 'voice_status_busy',
      'opted_out' => 'voice_status_opted_out',
      'blocked' => 'voice_status_blocked',
      'cancelled' => 'voice_status_cancelled',
      _ => '',
    };
    return key.isEmpty ? s : _vt(context, key);
  }

  String _outcomeLabel(String o) {
    final key = switch (o) {
      'confirmed' => 'voice_outcome_confirmed',
      'declined' => 'voice_outcome_declined',
      'maybe' => 'voice_outcome_maybe',
      'call_later' => 'voice_outcome_call_later',
      'wrong_number' => 'voice_outcome_wrong_number',
      _ => '',
    };
    return key.isEmpty ? o : _vt(context, key);
  }

  Widget _outcomeChip(String status, String outcome) {
    final key = outcome.isNotEmpty ? outcome : status;
    final (bg, fg) = switch (key) {
      'confirmed' || 'completed' => (AppColors.successSoft, AppColors.success),
      'declined' || 'failed' || 'wrong_number' => (
          AppColors.errorSoft,
          AppColors.error
        ),
      'maybe' || 'call_later' || 'no_answer' || 'busy' => (
          AppColors.warningSoft,
          AppColors.warning
        ),
      'in_progress' || 'queued' => (AppColors.infoSoft, AppColors.info),
      _ => (AppColors.primarySoft, AppColors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(
        outcome.isNotEmpty ? _outcomeLabel(outcome) : _statusLabel(status),
        style: GoogleFonts.inter(
            fontSize: 10.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  // ─── Job detail bottom sheet ─────────────────────────────────────────────
  void _openJobSheet(Map<String, dynamic> job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JobDetailSheet(jobId: job['id'].toString()),
    );
  }
}

class _JobDetailSheet extends StatefulWidget {
  final String jobId;
  const _JobDetailSheet({required this.jobId});
  @override
  State<_JobDetailSheet> createState() => _JobDetailSheetState();
}

class _JobDetailSheetState extends State<_JobDetailSheet> {
  bool _loading = true;
  Map<String, dynamic>? _job;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await VoiceCallsService.getJob(widget.jobId);
    if (res['success'] == true) {
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      _job = (data['job'] as Map?)?.cast<String, dynamic>();
      _logs = ((data['logs'] as List?) ?? const [])
          .map((l) => Map<String, dynamic>.from(l as Map))
          .toList();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _retry() async {
    setState(() => _loading = true);
    await VoiceCallsService.retryJob(widget.jobId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.92;
    return Container(
      height: h,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: _loading
                ? const _JobSheetSkeleton()
                : _body(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final j = _job;
    if (j == null) {
      return Center(
        child: Text(_vt(context, 'voice_sheet_not_found'),
            style: GoogleFonts.inter(color: AppColors.textSecondary)),
      );
    }
    final name = (j['recipient_name'] ?? '').toString();
    final phone = (j['phone_e164'] ?? '').toString();
    final outcome = (j['ai_outcome'] ?? '').toString();
    final confidence = j['ai_confidence'];
    final summary = (j['summary'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Text(name.isEmpty ? phone : name,
            style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.3)),
        const SizedBox(height: 4),
        Text(phone,
            style: GoogleFonts.inter(
                fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 18),
        if (outcome.isNotEmpty)
          _kvCard(_vt(context, 'voice_sheet_ai_reply'), _humanOutcome(outcome),
              footer: confidence != null
                  ? _vt(context, 'voice_sheet_confidence', {
                      'p': ((confidence as num) * 100).toStringAsFixed(0)
                    })
                  : null),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          _kvCard(_vt(context, 'voice_sheet_summary'), summary),
        ],
        const SizedBox(height: 20),
        Text(_vt(context, 'voice_sheet_attempts'),
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textTertiary,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        if (_logs.isEmpty)
          Text(_vt(context, 'voice_sheet_no_attempts'),
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textTertiary)),
        ..._logs.map(_logCard),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(_vt(context, 'voice_sheet_retry'),
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _kvCard(String label, String value, {String? footer}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.4)),
          if (footer != null) ...[
            const SizedBox(height: 4),
            Text(footer,
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _logCard(Map<String, dynamic> log) {
    final transcript = (log['transcript'] ?? '').toString();
    final status = (log['status'] ?? '').toString();
    final duration = (log['duration_seconds'] ?? 0) as int;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(status.toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.6)),
              const Spacer(),
              Text('${duration}s',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          if (transcript.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(transcript,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.5)),
          ],
        ],
      ),
    );
  }

  String _humanOutcome(String o) {
    final key = switch (o) {
      'confirmed' => 'voice_outcome_confirmed',
      'declined' => 'voice_outcome_declined',
      'maybe' => 'voice_outcome_maybe',
      'call_later' => 'voice_outcome_call_later',
      'wrong_number' => 'voice_outcome_wrong_number',
      _ => '',
    };
    return key.isEmpty ? o : _vt(context, key);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Call one person — quick single-recipient call sheet
// ─────────────────────────────────────────────────────────────────────────

class _CallOneSheet extends StatefulWidget {
  final String eventId;
  final String? eventTitle;
  final List<Map<String, dynamic>> guests;
  final Future<void> Function() onPlaced;

  const _CallOneSheet({
    required this.eventId,
    required this.eventTitle,
    required this.guests,
    required this.onPlaced,
  });

  @override
  State<_CallOneSheet> createState() => _CallOneSheetState();
}

class _CallOneSheetState extends State<_CallOneSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _pickGuest(Map<String, dynamic> g) {
    final phone = (g['phone'] ?? g['phone_number'] ?? '').toString();
    // Toggle: tapping the already-selected guest clears the selection.
    if (_phoneCtrl.text.trim() == phone.trim() && phone.trim().isNotEmpty) {
      _nameCtrl.clear();
      _phoneCtrl.clear();
    } else {
      _nameCtrl.text = (g['name'] ?? g['full_name'] ?? '').toString();
      _phoneCtrl.text = phone;
    }
    setState(() {});
  }


  Future<void> _placeCall() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      AppSnackbar.error(context, _vt(context, 'voice_call_one_phone_required'));
      return;
    }
    setState(() => _busy = true);

    final lang = context.read<LocaleProvider>().isSwahili ? 'sw' : 'en';
    final created = await VoiceCallsService.createCampaign(
      eventId: widget.eventId,
      purpose: 'rsvp',
      language: lang,
      title: 'Single call · ${_nameCtrl.text.trim().isEmpty ? phone : _nameCtrl.text.trim()}',
    );
    if (created['success'] != true) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnackbar.error(context,
            created['message']?.toString() ?? _vt(context, 'voice_create_failed'));
      }
      return;
    }
    final cid = (created['data'] as Map)['id'].toString();
    final added = await VoiceCallsService.addJobs(cid, [
      {
        'recipient_type': 'guest',
        'recipient_name': _nameCtrl.text.trim(),
        'phone': phone,
        'language': lang,
      },
    ], enforceHours: true);
    final data = added['data'];
    final dialable = _itemsOfTopLevel(
      (data is Map ? (data['accepted'] ?? data['jobs']) : null),
    );
    if (dialable.isEmpty) {
      if (mounted) {
        setState(() => _busy = false);
        final rej = _itemsOfTopLevel(data is Map ? data['rejected'] : null);
        final reason = rej.isNotEmpty && rej.first is Map
            ? (rej.first as Map)['reason']?.toString()
            : null;
        AppSnackbar.error(context, reason ?? _vt(context, 'voice_call_one_blocked'));
      }
      return;
    }
    final jobId = (dialable.first as Map)['id'].toString();
    var placed = await VoiceCallsService.placeCall(jobId);
    // Outside-hours: don't block — ask the organiser if they want to dial anyway.
    if (placed['success'] != true) {
      final detail = placed['detail'] ?? placed['error'] ?? placed['message'];
      final code = (detail is Map) ? detail['code']?.toString() : null;
      final reason = (detail is Map)
          ? (detail['message'] ?? detail['detail'] ?? '').toString()
          : (detail?.toString() ?? '');
      final outside = code == 'outside_hours' ||
          reason.toLowerCase().contains('outside') && reason.toLowerCase().contains('hours');
      if (outside && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(_vt(context, 'voice_outside_hours_title')),
            content: Text(reason.isEmpty
                ? _vt(context, 'voice_outside_hours_body')
                : reason),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(_vt(context, 'voice_outside_hours_cancel'))),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(_vt(context, 'voice_outside_hours_call'))),
            ],
          ),
        );
        if (go == true) {
          placed = await VoiceCallsService.placeCall(jobId, force: true);
        } else {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }
    }
    await widget.onPlaced();
    if (mounted) {
      Navigator.pop(context);
      AppSnackbar.success(context,
          placed['success'] == true
              ? _vt(context, 'voice_call_one_dialing')
              : (placed['message']?.toString() ?? _vt(context, 'voice_call_one_queued')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Shrink with the keyboard so the guest list / search results stay
    // visible while typing — the previous fixed 0.9 * screen height hid
    // them behind the IME on phones.
    final keyboard = media.viewInsets.bottom;
    final maxH = media.size.height * 0.9;
    final h = (maxH - keyboard).clamp(280.0, maxH);
    final q = _search.trim().toLowerCase();
    final guests = q.isEmpty
        ? widget.guests
        : widget.guests.where((g) {
            final name = (g['name'] ?? g['full_name'] ?? '').toString().toLowerCase();
            final phone = (g['phone'] ?? g['phone_number'] ?? '').toString().toLowerCase();
            return name.contains(q) || phone.contains(q);
          }).toList();
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
      height: h,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Grabber
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const AppIcon('phone', size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_vt(context, 'voice_call_one_title'),
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3,
                          )),
                      const SizedBox(height: 2),
                      Text(_vt(context, 'voice_call_one_sub'),
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          )),
                    ],
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: AppIcon('close', size: 18, color: Color(0xFF8E8E93)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Compose pill inputs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _PillInput(
                  controller: _nameCtrl,
                  iconName: 'user',
                  hint: _vt(context, 'voice_call_one_name'),
                ),
                const SizedBox(height: 10),
                _PillInput(
                  controller: _phoneCtrl,
                  iconName: 'phone',
                  hint: _vt(context, 'voice_call_one_phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _placeCall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnPrimary,
                      disabledBackgroundColor:
                          AppColors.primary.withOpacity(0.55),
                      disabledForegroundColor:
                          AppColors.textOnPrimary.withOpacity(0.85),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const AppIcon('phone',
                                  size: 18, color: Colors.white),
                              const SizedBox(width: 10),
                              Text(_vt(context, 'voice_call_one_btn'),
                                  style: GoogleFonts.inter(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Or pick a guest — divider label
          if (widget.guests.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: Divider(color: AppColors.borderLight)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      _vt(context, 'voice_call_one_pick'),
                      style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textTertiary,
                          letterSpacing: 0.4),
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.borderLight)),
                ],
              ),
            ),
          if (widget.guests.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: NuruSearchBar(
                controller: _searchCtrl,
                hintText: _vt(context, 'voice_search_guests'),
                debounce: const Duration(milliseconds: 150),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              itemCount: guests.length,
              itemBuilder: (_, i) => _guestPickRow(guests[i]),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _guestPickRow(Map<String, dynamic> g) {
    final name = (g['name'] ?? g['full_name'] ?? '').toString();
    final phone = (g['phone'] ?? g['phone_number'] ?? '').toString();
    final isSelected = _phoneCtrl.text.trim() == phone.trim() &&
        phone.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _pickGuest(g),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primarySoft.withOpacity(0.6)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.5)
                  : const Color(0xFFEDEDEF),
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  (name.isNotEmpty ? name[0] : (phone.isNotEmpty ? '#' : '?'))
                      .toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? phone : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(phone,
                        style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: isSelected
                    ? const AppIcon('check',
                        size: 16, color: Colors.white)
                    : const AppIcon('phone',
                        size: 16, color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillInput extends StatelessWidget {
  final TextEditingController controller;
  final String iconName;
  final String hint;
  final TextInputType? keyboardType;
  const _PillInput({
    required this.controller,
    required this.iconName,
    required this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
      ),
      child: Row(children: [
        AppIcon(iconName, size: 20, color: const Color(0xFF8E8E93)),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            autocorrect: false,
            keyboardType: keyboardType,
            cursorColor: Colors.black,
            textAlignVertical: TextAlignVertical.center,
            style: GoogleFonts.inter(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Colors.black),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF9E9E9E),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}



// ─── Skeleton loaders ───────────────────────────────────────────────────────

class _SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const _SkeletonBox({this.width, required this.height, this.radius = 10});
  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = 0.55 + (_c.value * 0.35);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              const Color(0xFFEFEFEF),
              const Color(0xFFF7F7F7),
              t,
            ),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

class _RsvpCallsSkeleton extends StatelessWidget {
  const _RsvpCallsSkeleton();

  Widget _statTile() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _SkeletonBox(width: 50, height: 22, radius: 6),
            SizedBox(height: 8),
            _SkeletonBox(width: 70, height: 10, radius: 4),
          ],
        ),
      ),
    );
  }

  Widget _row() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            const _SkeletonBox(width: 38, height: 38, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SkeletonBox(width: 140, height: 12, radius: 4),
                  SizedBox(height: 6),
                  _SkeletonBox(width: 100, height: 10, radius: 4),
                ],
              ),
            ),
            const _SkeletonBox(width: 56, height: 22, radius: 11),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Hero card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SkeletonBox(width: 180, height: 14, radius: 5),
              const SizedBox(height: 8),
              const _SkeletonBox(width: 240, height: 10, radius: 4),
              const SizedBox(height: 16),
              Row(children: [
                _statTile(),
                const SizedBox(width: 10),
                _statTile(),
                const SizedBox(width: 10),
                _statTile(),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Call-one CTA
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            children: const [
              _SkeletonBox(width: 38, height: 38, radius: 12),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 160, height: 12, radius: 4),
                    SizedBox(height: 6),
                    _SkeletonBox(width: 200, height: 10, radius: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Runtime panel placeholder
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _SkeletonBox(width: 120, height: 12, radius: 4),
              SizedBox(height: 12),
              _SkeletonBox(height: 38, radius: 10),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SkeletonBox(width: 120, height: 10, radius: 4),
        const SizedBox(height: 10),
        _row(),
        _row(),
        _row(),
      ],
    );
  }
}

class _JobSheetSkeleton extends StatelessWidget {
  const _JobSheetSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: const [
        _SkeletonBox(width: 200, height: 22, radius: 6),
        SizedBox(height: 10),
        _SkeletonBox(width: 140, height: 12, radius: 4),
        SizedBox(height: 24),
        _SkeletonBox(height: 70, radius: 14),
        SizedBox(height: 12),
        _SkeletonBox(height: 70, radius: 14),
        SizedBox(height: 20),
        _SkeletonBox(width: 100, height: 12, radius: 4),
        SizedBox(height: 10),
        _SkeletonBox(height: 60, radius: 12),
        SizedBox(height: 10),
        _SkeletonBox(height: 60, radius: 12),
      ],
    );
  }
}
