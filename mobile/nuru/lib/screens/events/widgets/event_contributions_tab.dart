import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../widgets/app_action_sheet.dart';
import '../../../core/widgets/nuru_search_bar.dart';
import '../../../core/utils/money_format.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import 'package:csv/csv.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/events_service.dart';
import '../../../core/services/event_contributors_service.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/share_helpers.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../../core/services/report_generator.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../report_preview_screen.dart';
import '../../../core/widgets/deleting_overlay.dart';
import '../../../core/theme/text_styles.dart';
import '../../contributors/verify_contribution_scanner_screen.dart';
import '../../../core/l10n/l10n_helper.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_checkbox.dart';

const _kPaymentMethods = [
  {'id': 'cash', 'name': 'Cash'},
  {'id': 'mobile', 'name': 'Mobile Money'},
  {'id': 'bank_transfer', 'name': 'Bank Transfer'},
  {'id': 'card', 'name': 'Card'},
  {'id': 'cheque', 'name': 'Cheque'},
  {'id': 'other', 'name': 'Other'},
];

class EventContributionsTab extends StatefulWidget {
  final String eventId;
  final String? eventTitle;
  final double? eventBudget;
  final bool isCreator;
  final Map<String, dynamic>? permissions;
  const EventContributionsTab({
    super.key,
    required this.eventId,
    this.eventTitle,
    this.eventBudget,
    this.isCreator = false,
    this.permissions,
  });

  @override
  State<EventContributionsTab> createState() => _EventContributionsTabState();
}

class _EventContributionsTabState extends State<EventContributionsTab>
    with AutomaticKeepAliveClientMixin {
  List<dynamic> _eventContributors = [];
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  bool _actionLoading = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  // Pending contributions
  List<dynamic> _pendingContributions = [];
  final Set<String> _selectedPending = {};

  // Messaging state
  bool _messagingExpanded = false;
  String _messagingCase = 'no_contribution';
  String _messageTemplate = '';
  String _paymentInfo = '';
  String _reminderContactOverride = '';
  final Set<String> _messagingSelected = {};
  bool _sendingMessages = false;
  bool _savingTemplate = false;
  // Per-case persisted customisations: {message_template, payment_info, contact_phone}
  final Map<String, Map<String, String?>> _savedTemplates = {};

  @override
  bool get wantKeepAlive => true;

  bool get _canManage =>
      widget.permissions?['can_manage_contributions'] == true ||
      widget.permissions?['is_creator'] == true;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.isCreator) _loadPending();
    _setDefaultTemplate();
    if (widget.isCreator) _loadSavedTemplates();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setDefaultTemplate() {
    _messageTemplate = _getDefaultTemplate(_messagingCase);
  }

  /// Pull the organiser's saved per-case messaging customisations and
  /// apply the entry for the currently active case.
  Future<void> _loadSavedTemplates() async {
    final res = await EventsService.getMessagingTemplates(widget.eventId);
    if (!mounted || res['success'] != true) return;
    final tpls = res['data']?['templates'];
    if (tpls is! Map) return;
    setState(() {
      _savedTemplates.clear();
      tpls.forEach((k, v) {
        if (v is Map) {
          _savedTemplates[k.toString()] = {
            'message_template': v['message_template']?.toString(),
            'payment_info': v['payment_info']?.toString(),
            'contact_phone': v['contact_phone']?.toString(),
          };
        }
      });
      _applySavedForCase(_messagingCase);
    });
  }

  /// Apply saved values (or defaults) for [caseKey] to the form fields.
  void _applySavedForCase(String caseKey) {
    final s = _savedTemplates[caseKey];
    _messageTemplate = s?['message_template']?.isNotEmpty == true
        ? s!['message_template']!
        : _getDefaultTemplate(caseKey);
    if (s?['payment_info'] != null) _paymentInfo = s!['payment_info']!;
    if (s?['contact_phone'] != null) _reminderContactOverride = s!['contact_phone']!;
  }

  Future<void> _saveCurrentTemplate() async {
    if (_messageTemplate.trim().isEmpty) return;
    setState(() => _savingTemplate = true);
    final res = await EventsService.saveMessagingTemplate(
      widget.eventId,
      _messagingCase,
      {
        'message_template': _messageTemplate,
        'payment_info': _paymentInfo,
        'contact_phone': _reminderContactOverride.trim(),
      },
    );
    if (!mounted) return;
    setState(() {
      _savingTemplate = false;
      if (res['success'] == true) {
        _savedTemplates[_messagingCase] = {
          'message_template': _messageTemplate,
          'payment_info': _paymentInfo,
          'contact_phone': _reminderContactOverride.trim(),
        };
      }
    });
    if (res['success'] == true) {
      AppSnackbar.success(context, 'Template saved for this event');
    } else {
      AppSnackbar.error(context, res['message'] ?? 'Failed to save template');
    }
  }

  String _getDefaultTemplate(String caseType) {
    switch (caseType) {
      case 'not_pledged':
        return '{event_title}\nHabari {name},\nTunakukaribisha kushiriki katika {event_name}. Tafadhali toa ahadi yako ya mchango.\nNamba ya malipo: {payment}';
      case 'no_contribution':
        return '{event_title}\nHabari {name},\nTunakukumbusha kutoa mchango wako kwa ajili ya {event_name}.\nNamba ya malipo: {payment}';
      case 'partial':
        return '{event_title}\nHabari {name},\nTunakukumbusha kumalizia mchango wako kwa ajili ya {event_name}.\nNamba ya malipo: {payment}';
      case 'completed':
        return '{event_title}\nHabari {name},\nAsante kwa kukamilisha mchango wako kwa ajili ya {event_name}. Tunathamini sana ushiriki wako.';
      default:
        return '';
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await EventsService.getEventContributors(widget.eventId);
    if (mounted)
      setState(() {
        _loading = false;
        if (res['success'] == true) {
          _eventContributors = res['data']?['event_contributors'] ?? [];
          _summary = res['data']?['summary'] ?? {};
        }
      });
  }

  Future<void> _loadPending() async {
    final res = await EventsService.getPendingContributions(widget.eventId);
    if (mounted && res['success'] == true) {
      setState(
        () => _pendingContributions = res['data']?['contributions'] ?? [],
      );
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '${getActiveCurrency()} 0';
    final n =
        (amount is String ? double.tryParse(amount) : amount.toDouble()) ?? 0.0;
    return '${getActiveCurrency()} ${n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  double _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  List<dynamic> get _filteredContributors {
    if (_searchQuery.isEmpty) return _eventContributors;
    final q = _searchQuery.toLowerCase();
    return _eventContributors.where((ec) {
      final c = ec['contributor'] as Map<String, dynamic>?;
      return (c?['name']?.toString().toLowerCase().contains(q) ?? false) ||
          (c?['phone']?.toString().contains(q) ?? false) ||
          (c?['email']?.toString().toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return _skeleton();

    final totalPledged = _toNum(
      _summary['total_pledged'] ?? _summary['total_amount'],
    );
    final totalPaid = _toNum(
      _summary['total_paid'] ?? _summary['total_confirmed'],
    );
    final totalBalance = _eventContributors.fold<double>(0, (sum, entry) {
      final ec = entry is Map ? entry : const {};
      // Match the contributors report logic: clamp each contributor's
      // outstanding at 0 so overpayments don't cancel out others' debts.
      final pledged = _toNum(ec['pledge_amount']);
      final paid = _toNum(ec['total_paid'] ?? ec['amount']);
      final fallback = (pledged - paid).clamp(0, double.infinity).toDouble();
      final bal = ec['balance'] != null ? _toNum(ec['balance']) : fallback;
      return sum + (bal < 0 ? 0.0 : bal);
    });
    final budget = widget.eventBudget ?? 0;
    final goal = budget > 0 ? budget : totalPledged;
    final filtered = _filteredContributors;

    return Stack(
      children: [
        NuruRefreshIndicator(
          onRefresh: () async {
            await _load();
            if (widget.isCreator) await _loadPending();
          },
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              // ── Goal header (ring + total goal + linear progress) ──
              _buildGoalHeader(goal: goal, collected: totalPaid),
              const SizedBox(height: 12),

              // ── 4-stat strip ──
              _buildStatStrip(
                pledged: totalPledged,
                collected: totalPaid,
                outstanding: totalBalance,
                contributors: _eventContributors.length,
              ),
              const SizedBox(height: 14),

              // ── Quick actions (horizontal scroll) ──
              _buildQuickActions(),
              const SizedBox(height: 14),

              // ── Messaging Section (expanded) ──
              if (widget.isCreator &&
                  _messagingExpanded &&
                  _eventContributors.isNotEmpty) ...[
                _buildMessagingSection(),
                const SizedBox(height: 12),
              ],

              // ── Pending Contributions ──
              if (widget.isCreator && _pendingContributions.isNotEmpty) ...[
                _buildPendingSection(),
                const SizedBox(height: 12),
              ],

              // ── Search Bar ──
              _buildSearchBar(),
              const SizedBox(height: 12),

              // ── Contributors header line ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(children: [
                  Text(
                    '${filtered.length} contributor${filtered.length != 1 ? 's' : ''}',
                    style: appText(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),

              if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Center(
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? 'No contributors match your search.'
                          : 'No contributors added yet.\nTap the + button to add one.',
                      textAlign: TextAlign.center,
                      style: appText(size: 13, color: AppColors.textTertiary),
                    ),
                  ),
                )
              else
                ...filtered.map((ec) => _contributorTile(ec, _canManage)),
            ],
          ),
        ),
        // (Floating Add Contributor FAB removed - Add Contributor action lives in the header.)
        DeletingOverlay(visible: _actionLoading, label: 'Processing...'),
      ],
    );
  }


  // ════════════════════════════════════════════════════
  // GOAL HEADER  (circular ring + total goal + linear progress)
  // ════════════════════════════════════════════════════

  Widget _buildGoalHeader({required double goal, required double collected}) {
    final pct = goal > 0 ? (collected / goal).clamp(0.0, 1.0) : 0.0;
    final pctLabel = '${(pct * 100).round()}%';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Circular ring
          SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 112,
                  height: 112,
                  child: CircularProgressIndicator(
                    value: pct == 0 ? 0.001 : pct,
                    strokeWidth: 9,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor:
                        const AlwaysStoppedAnimation(Color(0xFFEA580C)),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(pctLabel,
                        style: appText(
                            size: 22,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text('of goal',
                        style: appText(
                            size: 10,
                            color: AppColors.textTertiary,
                            weight: FontWeight.w500)),
                    Text('collected',
                        style: appText(
                            size: 10,
                            color: AppColors.textTertiary,
                            weight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          // Right column: goal + bar + collected
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total goal',
                    style: appText(
                        size: 11,
                        color: AppColors.textTertiary,
                        weight: FontWeight.w500)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_formatAmount(goal),
                      style: appText(
                          size: 22,
                          weight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                const SizedBox(height: 10),
                Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: pct == 0 ? 0.02 : pct,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEA580C),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Collected',
                    style: appText(
                        size: 11,
                        color: AppColors.textTertiary,
                        weight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(_formatAmount(collected),
                    style: appText(
                        size: 17,
                        weight: FontWeight.w700,
                        color: const Color(0xFF16A34A))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════
  // STAT STRIP (4 columns: Pledged / Collected / Outstanding / Contributors)
  // ════════════════════════════════════════════════════

  Widget _buildStatStrip({
    required double pledged,
    required double collected,
    required double outstanding,
    required int contributors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 44,
          ),
          child: Row(children: [
            SizedBox(width: 104, child: _statColumn(
              icon: 'event-calendar-check',
              iconColor: const Color(0xFFEA580C),
              label: 'Pledged',
              value: _formatAmount(pledged),
            )),
            const SizedBox(width: 12),
            SizedBox(width: 104, child: _statColumn(
              icon: 'double-check',
              iconColor: const Color(0xFF16A34A),
              label: 'Collected',
              value: _formatAmount(collected),
            )),
            const SizedBox(width: 12),
            SizedBox(width: 104, child: _statColumn(
              icon: 'calendar',
              iconColor: const Color(0xFFDC2626),
              label: 'Outstanding',
              value: _formatAmount(outstanding),
            )),
            const SizedBox(width: 12),
            SizedBox(width: 104, child: _statColumn(
              icon: 'users',
              iconColor: const Color(0xFF475569),
              label: 'Contributors',
              value: '$contributors',
            )),
          ]),
        ),
      ),
    );
  }

  Widget _statColumn({
    required String icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: 18, color: iconColor),
        const SizedBox(height: 5),
        Text(label,
            style: appText(
                size: 9.5,
                weight: FontWeight.w500,
                color: AppColors.textTertiary)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: appText(
                  size: 11,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════
  // QUICK ACTIONS (horizontal scroll)
  // ════════════════════════════════════════════════════

  Widget _buildQuickActions() {
    final actions = <_QuickAction>[
      if (_canManage)
        _QuickAction(
          icon: 'user-add',
          label: 'Add\nContributor',
          tint: const Color(0xFFEA580C),
          tintBg: const Color(0xFFFFEDD5),
          onTap: _showAddContributorSheet,
        ),
      if (widget.isCreator)
        _QuickAction(
          icon: 'upload',
          label: 'Bulk\nUpload',
          tint: const Color(0xFF7C3AED),
          tintBg: const Color(0xFFEDE9FE),
          onTap: _showBulkUploadSheet,
        ),
      _QuickAction(
        icon: 'print',
        label: 'Report',
        tint: const Color(0xFF2563EB),
        tintBg: const Color(0xFFDBEAFE),
        onTap: _showReportOptions,
      ),
      if (widget.isCreator && _eventContributors.isNotEmpty)
        _QuickAction(
          icon: _messagingExpanded ? 'close' : 'chat',
          label: 'Messaging',
          tint: const Color(0xFF16A34A),
          tintBg: const Color(0xFFDCFCE7),
          onTap: () => setState(() {
            _messagingExpanded = !_messagingExpanded;
            if (_messagingExpanded) {
              _messagingSelected.clear();
              _messagingSelected.addAll(_eventContributors.where((ec) {
                final pledge = _toNum(ec['pledge_amount']);
                final paid = _toNum(ec['total_paid']);
                final phone = ec['contributor']?['phone']?.toString() ?? '';
                if (phone.isEmpty) return false;
                switch (_messagingCase) {
                  case 'not_pledged':
                    return pledge == 0 && paid == 0;
                  case 'no_contribution':
                    return pledge > 0 && paid == 0;
                  case 'partial':
                    return pledge > 0 && paid > 0 && paid < pledge;
                  case 'completed':
                    return pledge > 0 && paid >= pledge;
                  default:
                    return false;
                }
              }).map((ec) => ec['id']?.toString() ?? ''));
            }
          }),
        ),
      if (_canManage)
        _QuickAction(
          icon: null,
          materialIcon: Icons.qr_code_scanner_rounded,
          label: 'Verify\nQR',
          tint: const Color(0xFF475569),
          tintBg: const Color(0xFFF1F5F9),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const VerifyContributionScannerScreen(),
            ),
          ),
        ),
    ];

    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _quickActionCard(actions[i]),
      ),
    );
  }

  Widget _quickActionCard(_QuickAction a) {
    return GestureDetector(
      onTap: a.onTap,
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: a.tintBg,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: a.icon != null
                  ? AppIcon(a.icon!, size: 20, color: a.tint)
                  : Icon(a.materialIcon, size: 20, color: a.tint),
            ),
            const SizedBox(height: 8),
            Text(
              a.label,
              textAlign: TextAlign.center,
              style: appText(
                size: 11,
                weight: FontWeight.w700,
                height: 1.2,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }




  // ════════════════════════════════════════════════════
  // SEARCH BAR
  // ════════════════════════════════════════════════════

  Widget _buildSearchBar() {
    return NuruSearchBar(
      controller: _searchCtrl,
      hintText: 'Search contributors',
      debounce: const Duration(milliseconds: 200),
      onChanged: (v) => setState(() => _searchQuery = v.trim()),
      onClear: () => setState(() => _searchQuery = ''),
    );
  }

  // ════════════════════════════════════════════════════
  // CONTRIBUTOR TILE (with full action menu)
  // ════════════════════════════════════════════════════

  Widget _contributorTile(Map<String, dynamic> ec, bool canManage) {
    final contributor = ec['contributor'] as Map<String, dynamic>?;
    final name = (contributor?['name']?.toString() ?? 'Unknown');
    final phone = contributor?['phone']?.toString() ?? '';
    final email = contributor?['email']?.toString() ?? '';
    final avatarUrl = contributor?['avatar_url']?.toString() ??
        contributor?['profile_image']?.toString() ??
        '';
    final pledged = _toNum(ec['pledge_amount']);
    final paid = _toNum(ec['total_paid']);
    final balance = ec['balance'] != null
        ? _toNum(ec['balance'])
        : (pledged - paid).clamp(0, double.infinity).toDouble();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: avatar + name/phone + kebab
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                  image: avatarUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(avatarUrl), fit: BoxFit.cover)
                      : null,
                ),
                alignment: Alignment.center,
                child: avatarUrl.isEmpty
                    ? Text(initial,
                        style: appText(
                            size: 16,
                            weight: FontWeight.w700,
                            color: AppColors.primary))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appText(
                            size: 14,
                            weight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(phone.isNotEmpty ? phone : email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appText(
                            size: 11.5,
                            weight: FontWeight.w500,
                            color: AppColors.textTertiary)),
                  ],
                ),
              ),
              if (canManage)
                IconButton(
                  padding: EdgeInsets.zero,
                  icon: const AppIcon('more-vertical',
                      size: 20, color: AppColors.textHint),
                  onPressed: () async {
                    final action = await AppActionSheet.show<String>(
                      context: context,
                      title: 'Contributor',
                      actions: [
                        const MenuAction(value: 'payment', label: 'Record payment', icon: 'money'),
                        const MenuAction(value: 'pledge', label: 'Update pledge', icon: 'pen'),
                        const MenuAction(value: 'history', label: 'Payment history', icon: 'time-fast'),
                        const MenuAction(value: 'share_link', label: 'Share payment link', icon: 'link'),
                        if (paid > 0)
                          const MenuAction(value: 'thankyou', label: 'Send thank you', icon: 'heart'),
                        const MenuAction(value: 'guest', label: 'Add as guest', icon: 'user-add'),
                        const MenuAction(value: 'remove', label: 'Remove contributor', icon: 'delete', destructive: true),
                      ],
                    );
                    if (action != null) _handleContributorAction(action, ec);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 3-column footer: Pledged / Paid / Balance
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Expanded(
                child: _tileStat(
                    'Pledged', _formatAmount(pledged), AppColors.textPrimary),
              ),
              _vDivider(),
              Expanded(
                child: _tileStat(
                    'Paid',
                    _formatAmount(paid),
                    paid > 0
                        ? const Color(0xFF16A34A)
                        : AppColors.textTertiary),
              ),
              _vDivider(),
              Expanded(
                child: _tileStat(
                    'Balance',
                    _formatAmount(balance),
                    balance > 0
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF16A34A)),
              ),
            ]),
          ),
        ],
      ),
    );
  }


  Widget _tileStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: appText(
                size: 10,
                weight: FontWeight.w500,
                color: AppColors.textTertiary)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style:
                  appText(size: 13, weight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 28,
        color: AppColors.borderLight,
      );



  // ════════════════════════════════════════════════════
  // CONTRIBUTOR ACTIONS
  // ════════════════════════════════════════════════════

  void _handleContributorAction(String action, Map<String, dynamic> ec) async {
    final ecId = ec['id']?.toString() ?? '';
    switch (action) {
      case 'payment':
        _showRecordPaymentSheet(ec);
        break;
      case 'pledge':
        _showUpdatePledgeSheet(ec);
        break;
      case 'history':
        _showPaymentHistory(ec);
        break;
      case 'thankyou':
        _showSendThankYou(ec);
        break;
      case 'guest':
        _addAsGuest(ecId);
        break;
      case 'share_link':
        _showShareLinkSheet(ec);
        break;
      case 'remove':
        _removeContributor(ecId);
        break;
    }
  }

  /// Bottom sheet that lets the host generate / share / SMS / revoke a guest
  /// payment link for ONE contributor. The plain token is returned by the
  /// server only once per generation - if the host closes the sheet without
  /// sharing, regenerating rotates the token (the previous URL stops working).
  Future<void> _showShareLinkSheet(Map<String, dynamic> ec) async {
    final ecId = ec['id']?.toString() ?? '';
    if (ecId.isEmpty) return;
    final contributor = (ec['contributor'] as Map?) ?? const {};
    final name = (contributor['name'] ?? 'Contributor').toString();
    final phone = (contributor['phone'] ?? '').toString();
    final balance = (ec['balance'] as num?)?.toDouble() ?? 0;
    final currency = (ec['currency'] ?? '').toString();
    final hasExisting = ec['has_share_link'] == true;

    String? url;
    String? host;
    bool smsSupported = false;
    bool busy = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> generate({bool regenerate = false}) async {
              setSheetState(() => busy = true);
              final res = await EventContributorsService.generateShareLink(
                widget.eventId, ecId, regenerate: regenerate,
              );
              if (!mounted) return;
              setSheetState(() => busy = false);
              if (res['success'] == true) {
                final data = (res['data'] as Map?) ?? {};
                setSheetState(() {
                  url = data['url']?.toString();
                  host = data['host']?.toString();
                  smsSupported = data['sms_supported'] == true;
                });
                if (regenerate) {
                  AppSnackbar.success(
                    context,
                    'New link generated. The previous one no longer works.',
                  );
                }
              } else {
                AppSnackbar.error(
                  context, res['message']?.toString() ?? 'Could not generate link',
                );
              }
            }

            Future<void> sendSms() async {
              setSheetState(() => busy = true);
              final res = await EventContributorsService.sendShareLinkSms(
                widget.eventId, ecId,
              );
              if (!mounted) return;
              setSheetState(() => busy = false);
              if (res['success'] == true) {
                AppSnackbar.success(context, 'SMS sent to $name');
              } else {
                AppSnackbar.error(
                  context, res['message']?.toString() ?? 'Could not send SMS',
                );
              }
            }

            Future<void> revoke() async {
              setSheetState(() => busy = true);
              final res = await EventContributorsService.revokeShareLink(
                widget.eventId, ecId,
              );
              if (!mounted) return;
              setSheetState(() => busy = false);
              if (res['success'] == true) {
                AppSnackbar.success(context, 'Link disabled');
                Navigator.of(ctx).pop();
                _load();
              } else {
                AppSnackbar.error(
                  context, res['message']?.toString() ?? 'Could not revoke',
                );
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textHint.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Icon(Icons.link, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Share payment link',
                      style: appText(size: 16, weight: FontWeight.w700),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'Generate a secure one-tap link for $name to pay without signing up.',
                    style: appText(size: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: appText(size: 14, weight: FontWeight.w600)),
                        if (phone.isNotEmpty)
                          Text(phone, style: appText(size: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Outstanding balance',
                              style: appText(size: 12, color: AppColors.textSecondary),
                            ),
                            Text(
                              '$currency ${balance.toStringAsFixed(0)}',
                              style: appText(size: 13, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (url == null) ...[
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: busy ? null : () => generate(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: busy
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.link),
                        label: Text(busy ? 'Generating…' : 'Generate payment link'),
                      ),
                    ),
                    if (hasExisting) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: busy ? null : revoke,
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text(
                          'Disable existing link',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.divider),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            url!,
                            style: appText(size: 11, weight: FontWeight.w500),
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy',
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: url!));
                            if (mounted) AppSnackbar.success(context, 'Link copied');
                          },
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : () {
                            final text =
                              'Hi $name, please use this secure link to pay your contribution'
                              '${balance > 0 ? " ($currency ${balance.toStringAsFixed(0)})" : ""}'
                              ': ${url!}';
                            Share.share(text, subject: 'Payment link', sharePositionOrigin: sharePositionOrigin(context));
                          },
                          icon: const Icon(Icons.ios_share),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (busy || !smsSupported || phone.isEmpty)
                            ? null : sendSms,
                          icon: const Icon(Icons.sms_outlined),
                          label: Text(smsSupported ? 'Send SMS' : 'SMS N/A'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: busy ? null : () => generate(regenerate: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Regenerate'),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: busy ? null : revoke,
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          label: const Text('Disable', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ]),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Remove Contributor ──
  Future<void> _removeContributor(String ecId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Contributor'),
        content: const Text(
          'Are you sure you want to remove this contributor from the event? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _actionLoading = true);
    final res = await EventsService.removeContributorFromEvent(
      widget.eventId,
      ecId,
    );
    if (mounted) {
      setState(() => _actionLoading = false);
      if (res['success'] == true) {
        AppSnackbar.success(context, 'Removed');
        _load();
      } else
        AppSnackbar.error(context, res['message'] ?? 'Failed');
    }
  }

  // ── Add as Guest ──
  Future<void> _addAsGuest(String ecId) async {
    setState(() => _actionLoading = true);
    final res = await EventsService.addContributorsAsGuests(widget.eventId, {
      'contributor_ids': [ecId],
      'send_sms': true,
    });
    if (mounted) {
      setState(() => _actionLoading = false);
      if (res['success'] == true) {
        final skipped = res['data']?['skipped'] ?? 0;
        if (skipped > 0)
          AppSnackbar.info(context, 'Already on guest list');
        else
          AppSnackbar.success(context, 'Added as guest');
      } else {
        AppSnackbar.error(context, res['message'] ?? 'Failed');
      }
    }
  }

  // ════════════════════════════════════════════════════
  // PAYMENT HISTORY
  // ════════════════════════════════════════════════════

  void _showPaymentHistory(Map<String, dynamic> ec) async {
    final ecId = ec['id']?.toString() ?? '';
    final name = ec['contributor']?['name'] ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return FutureBuilder<Map<String, dynamic>>(
              future: EventsService.getPaymentHistory(widget.eventId, ecId),
              builder: (ctx, snapshot) {
                final loading = !snapshot.hasData;
                final data = snapshot.data;
                final success = data?['success'] == true;
                final historyData = data?['data'];
                final pledgeAmt = _toNum(historyData?['pledge_amount']);
                final totalPaid = _toNum(historyData?['total_paid']);
                final payments = (historyData?['payments'] as List?) ?? [];

                return Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.8,
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '$name · Payment History',
                        style: appText(size: 17, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      if (loading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(30),
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      else if (!success)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(30),
                            child: Text('Failed to load history'),
                          ),
                        )
                      else ...[
                        // Summary row
                        Row(
                          children: [
                            Expanded(
                              child: _historyStatCard(
                                _formatAmount(pledgeAmt),
                                'Pledged',
                                const Color(0xFFd97706),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _historyStatCard(
                                _formatAmount(totalPaid),
                                'Paid',
                                AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _historyStatCard(
                                _formatAmount(
                                  (pledgeAmt - totalPaid).clamp(
                                    0,
                                    double.infinity,
                                  ),
                                ),
                                'Balance',
                                AppColors.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Payments list
                        if (payments.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'No payments recorded yet',
                                style: appText(
                                  size: 13,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          )
                        else
                          Flexible(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: payments.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final p = payments[i] as Map<String, dynamic>;
                                  final isPending =
                                      p['confirmation_status'] == 'pending';
                                  return Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isPending
                                                          ? const Color(
                                                              0xFFFEF3C7,
                                                            )
                                                          : const Color(
                                                              0xFFD1FAE5,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      isPending
                                                          ? 'Pending'
                                                          : 'Payment',
                                                      style: appText(
                                                        size: 10,
                                                        weight: FontWeight.w600,
                                                        color: isPending
                                                            ? const Color(
                                                                0xFF92400E,
                                                              )
                                                            : const Color(
                                                                0xFF065F46,
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (p['payment_method'] !=
                                                      null) ...[
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      (p['payment_method']
                                                              as String)
                                                          .replaceAll('_', ' '),
                                                      style: appText(
                                                        size: 10,
                                                        color: AppColors
                                                            .textTertiary,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              if (p['created_at'] != null)
                                                Text(
                                                  _formatDate(p['created_at']),
                                                  style: appText(
                                                    size: 11,
                                                    color:
                                                        AppColors.textTertiary,
                                                  ),
                                                ),
                                              if (p['payment_reference'] !=
                                                      null &&
                                                  p['payment_reference']
                                                      .toString()
                                                      .isNotEmpty)
                                                Text(
                                                  'Ref: ${p['payment_reference']}',
                                                  style: appText(
                                                    size: 11,
                                                    color:
                                                        AppColors.textTertiary,
                                                  ),
                                                ),
                                              if (p['recorded_by_name'] != null)
                                                Text(
                                                  'By: ${p['recorded_by_name']}',
                                                  style: appText(
                                                    size: 11,
                                                    color:
                                                        AppColors.textTertiary,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              _formatAmount(p['amount']),
                                              style: appText(
                                                size: 14,
                                                weight: FontWeight.w700,
                                                color: AppColors.accent,
                                              ),
                                            ),
                                            if (widget.isCreator) ...[
                                              const SizedBox(width: 4),
                                              GestureDetector(
                                                onTap: () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: ctx,
                                                    builder: (c) => AlertDialog(
                                                      title: const Text(
                                                        'Delete Transaction',
                                                      ),
                                                      content: const Text(
                                                        'Are you sure? This cannot be undone.',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                c,
                                                                false,
                                                              ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                c,
                                                                true,
                                                              ),
                                                          style:
                                                              TextButton.styleFrom(
                                                                foregroundColor:
                                                                    Colors.red,
                                                              ),
                                                          child: const Text(
                                                            'Delete',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm != true) return;
                                                  final delRes =
                                                      await EventsService.deleteTransaction(
                                                        widget.eventId,
                                                        ecId,
                                                        p['id'].toString(),
                                                      );
                                                  if (delRes['success'] ==
                                                      true) {
                                                    AppSnackbar.success(
                                                      context,
                                                      'Transaction deleted',
                                                    );
                                                    Navigator.pop(ctx);
                                                    _load();
                                                  } else {
                                                    AppSnackbar.error(
                                                      context,
                                                      delRes['message'] ??
                                                          'Failed',
                                                    );
                                                  }
                                                },
                                                child: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _historyStatCard(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: appText(size: 13, weight: FontWeight.w700, color: color),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: appText(size: 10, color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(
        dateStr.endsWith('Z') || dateStr.contains('+')
            ? dateStr
            : '${dateStr}Z',
      ).toLocal();
      final months = [
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
        'Dec',
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  // ════════════════════════════════════════════════════
  // SEND THANK YOU
  // ════════════════════════════════════════════════════

  void _showSendThankYou(Map<String, dynamic> ec) {
    final name = ec['contributor']?['name'] ?? 'Unknown';
    final phone = ec['contributor']?['phone'] ?? '';
    final ecId = ec['id']?.toString() ?? '';
    final msgCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          bool sending = false;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Send Thank You',
                  style: appText(size: 18, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'A thank you SMS will be sent to ${phone.isNotEmpty ? phone : name}.',
                  style: appText(size: 13, color: AppColors.textTertiary),
                ),
                const SizedBox(height: 16),
                _label('Custom Message (optional)'),
                _input(
                  msgCtrl,
                  'Add a personal thank you message...',
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: sending
                        ? null
                        : () async {
                            setSheetState(() => sending = true);
                            final res = await EventsService.sendThankYou(
                              widget.eventId,
                              ecId,
                              {
                                if (msgCtrl.text.trim().isNotEmpty)
                                  'custom_message': msgCtrl.text.trim(),
                              },
                            );
                            if (mounted) {
                              Navigator.pop(ctx);
                              if (res['success'] == true)
                                AppSnackbar.success(context, 'Thank you sent!');
                              else
                                AppSnackbar.error(
                                  context,
                                  res['message'] ?? 'Failed to send',
                                );
                            }
                          },
                    icon: sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.favorite, size: 18),
                    label: Text(
                      sending ? 'Sending...' : 'Send Thank You',
                      style: appText(
                        size: 15,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pinkAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════
  // PENDING CONTRIBUTIONS
  // ════════════════════════════════════════════════════

  Widget _buildPendingSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.hourglass_top_rounded, size: 16, color: Color(0xFF6B7280)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Awaiting Confirmation',
                      style: appText(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    Text(
                      '${_pendingContributions.length} payment${_pendingContributions.length == 1 ? '' : 's'} need your review',
                      style: appText(size: 10.5, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Select All
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  if (_selectedPending.length == _pendingContributions.length)
                    _selectedPending.clear();
                  else
                    _selectedPending.addAll(
                      _pendingContributions.map((p) => p['id'].toString()),
                    );
                }),
                child: Text(
                  _selectedPending.length == _pendingContributions.length
                      ? 'Deselect All'
                      : 'Select All',
                  style: appText(
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (_selectedPending.isNotEmpty) ...[
                _pendingActionButton('Reject', Colors.red, _rejectPending),
                const SizedBox(width: 8),
                _pendingActionButton(
                  'Confirm (${_selectedPending.length})',
                  AppColors.accent,
                  _confirmPending,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ..._pendingContributions.map((pc) {
            final id = pc['id'].toString();
            final selected = _selectedPending.contains(id);
            final name = (pc['contributor_name'] ?? 'Unknown').toString();
            final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
            return GestureDetector(
              onTap: () => setState(() {
                if (selected)
                  _selectedPending.remove(id);
                else
                  _selectedPending.add(id);
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFF8FAFC) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.borderLight,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Selection check
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: selected ? AppColors.primary : const Color(0xFFE5E7EB),
                          width: 1.5,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    // Avatar
                    Container(
                      width: 36, height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF3F4F6),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(initial,
                          style: appText(size: 14, weight: FontWeight.w800, color: AppColors.textSecondary)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              style: appText(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.schedule_rounded, size: 9, color: Color(0xFFB45309)),
                                const SizedBox(width: 3),
                                Text('Pending',
                                    style: appText(size: 9, weight: FontWeight.w700, color: const Color(0xFFB45309))),
                              ]),
                            ),
                            if (pc['created_at'] != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _formatDate(pc['created_at']),
                                  style: appText(size: 10, color: AppColors.textTertiary),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_formatAmount(pc['amount']),
                            style: appText(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                        if (pc['payment_method'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              pc['payment_method'].toString().replaceAll('_', ' '),
                              style: appText(size: 10, weight: FontWeight.w500, color: AppColors.textTertiary),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _pendingActionButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: appText(
            size: 11,
            weight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPending() async {
    if (_selectedPending.isEmpty) return;
    setState(() => _actionLoading = true);
    final res = await EventsService.confirmContributions(
      widget.eventId,
      _selectedPending.toList(),
    );
    if (mounted) {
      setState(() => _actionLoading = false);
      if (res['success'] == true) {
        AppSnackbar.success(
          context,
          '${res['data']?['confirmed'] ?? 0} confirmed',
        );
        _selectedPending.clear();
        _loadPending();
        _load();
      } else {
        AppSnackbar.error(context, res['message'] ?? 'Failed');
      }
    }
  }

  Future<void> _rejectPending() async {
    if (_selectedPending.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Contributions'),
        content: Text(
          'Reject ${_selectedPending.length} pending contribution(s)? Contributors will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _actionLoading = true);
    final res = await EventsService.rejectContributions(
      widget.eventId,
      _selectedPending.toList(),
    );
    if (mounted) {
      setState(() => _actionLoading = false);
      if (res['success'] == true) {
        AppSnackbar.success(
          context,
          '${res['data']?['rejected'] ?? 0} rejected',
        );
        _selectedPending.clear();
        _loadPending();
        _load();
      } else {
        AppSnackbar.error(context, res['message'] ?? 'Failed');
      }
    }
  }

  // ════════════════════════════════════════════════════
  // MESSAGING SECTION (matches web ContributorMessaging)
  // ════════════════════════════════════════════════════

  String _resolveTemplate(String template, Map<String, dynamic> ec) {
    final name = ec['contributor']?['name'] ?? 'Contributor';
    var resolved = template
        .replaceAll('{name}', name)
        .replaceAll('{event_name}', widget.eventTitle ?? '')
        .replaceAll('{event_title}', (widget.eventTitle ?? '').toUpperCase());
    if (resolved.contains('{payment}')) {
      if (_paymentInfo.isNotEmpty) {
        resolved = resolved.replaceAll('{payment}', _paymentInfo);
      } else {
        resolved = resolved.split('\n').where((l) => !l.contains('{payment}')).join('\n');
      }
    }
    return resolved.trim();
  }

  Widget _buildMessagingSection() {
    final cases = {
      'not_pledged': {
        'label': 'Not Pledged',
        'desc': 'No pledge yet',
        'svgIcon': 'assets/icons/users-icon.svg',
        'color': const Color(0xFF6B7280),
      },
      'no_contribution': {
        'label': 'No Contribution',
        'desc': 'Pledged but no payment',
        'svgIcon': 'assets/icons/info-icon.svg',
        'color': AppColors.error,
      },
      'partial': {
        'label': 'Partial',
        'desc': 'Paid partially',
        'svgIcon': 'assets/icons/clock-icon.svg',
        'color': const Color(0xFFD97706),
      },
      'completed': {
        'label': 'Completed',
        'desc': 'Fully paid',
        'svgIcon': 'assets/icons/circle-icon.svg',
        'color': AppColors.accent,
      },
    };

    // Filter contributors by case
    final caseContributors = _eventContributors.where((ec) {
      final pledge = _toNum(ec['pledge_amount']);
      final paid = _toNum(ec['total_paid']);
      final phone = ec['contributor']?['phone']?.toString() ?? '';
      if (phone.isEmpty) return false;
      switch (_messagingCase) {
        case 'not_pledged':
          return pledge == 0 && paid == 0;
        case 'no_contribution':
          return pledge > 0 && paid == 0;
        case 'partial':
          return pledge > 0 && paid > 0 && paid < pledge;
        case 'completed':
          return pledge > 0 && paid >= pledge;
        default:
          return false;
      }
    }).toList();

    final selectedTargets = caseContributors
        .where((ec) => _messagingSelected.contains(ec['id']?.toString()))
        .toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with SVG chat icon (matching web)
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/chat-icon.svg',
                    width: 18, height: 18,
                    colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contributor Messaging', style: appText(size: 15, weight: FontWeight.w700)),
                    Text('Send targeted reminders based on contribution status',
                        style: appText(size: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Case selector - 4 chips, horizontally scrollable to fit the
          // extra "Not Pledged" target without crushing the layout.
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: cases.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final entry = cases.entries.elementAt(i);
                final key = entry.key;
                final cfg = entry.value;
                final color = cfg['color'] as Color;
                final count = _eventContributors.where((ec) {
                  final pledge = _toNum(ec['pledge_amount']);
                  final paid = _toNum(ec['total_paid']);
                  final phone = ec['contributor']?['phone']?.toString() ?? '';
                  if (phone.isEmpty) return false;
                  if (key == 'not_pledged') return pledge == 0 && paid == 0;
                  if (key == 'no_contribution') return pledge > 0 && paid == 0;
                  if (key == 'partial') return pledge > 0 && paid > 0 && paid < pledge;
                  if (key == 'completed') return pledge > 0 && paid >= pledge;
                  return false;
                }).length;
                final isActive = _messagingCase == key;

                return GestureDetector(
                  onTap: () => setState(() {
                    _messagingCase = key;
                    _applySavedForCase(key);
                    _messagingSelected.clear();
                    final matching = _eventContributors.where((ec) {
                      final pledge = _toNum(ec['pledge_amount']);
                      final paid = _toNum(ec['total_paid']);
                      final phone = ec['contributor']?['phone']?.toString() ?? '';
                      if (phone.isEmpty) return false;
                      if (key == 'not_pledged') return pledge == 0 && paid == 0;
                      if (key == 'no_contribution') return pledge > 0 && paid == 0;
                      if (key == 'partial') return pledge > 0 && paid > 0 && paid < pledge;
                      if (key == 'completed') return pledge > 0 && paid >= pledge;
                      return false;
                    });
                    _messagingSelected.addAll(matching.map((ec) => ec['id']?.toString() ?? ''));
                  }),
                  child: Container(
                    width: 96,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isActive ? color.withOpacity(0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive ? color : const Color(0xFFE5E7EB),
                        width: isActive ? 1.5 : 1,
                      ),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SvgPicture.asset(
                        cfg['svgIcon'] as String,
                        width: 16, height: 16,
                        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                      ),
                      const SizedBox(height: 4),
                      Text(cfg['label'] as String,
                          style: appText(size: 9.5, weight: FontWeight.w700, color: AppColors.textPrimary),
                          maxLines: 1, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('$count',
                          style: appText(size: 13, weight: FontWeight.w800, color: color)),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Recipients
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recipients (${selectedTargets.length} of ${caseContributors.length})',
                  style: appText(size: 12, weight: FontWeight.w600)),
              if (caseContributors.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() {
                    if (_messagingSelected.length == caseContributors.length) {
                      _messagingSelected.clear();
                    } else {
                      _messagingSelected.clear();
                      _messagingSelected.addAll(caseContributors.map((ec) => ec['id']?.toString() ?? ''));
                    }
                  }),
                  child: Text(
                    _messagingSelected.length == caseContributors.length ? 'Deselect All' : 'Select All',
                    style: appText(size: 11, weight: FontWeight.w600, color: AppColors.primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (caseContributors.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: caseContributors.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final ec = caseContributors[i];
                  final ecId = ec['id']?.toString() ?? '';
                  final isSelected = _messagingSelected.contains(ecId);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (_messagingSelected.contains(ecId))
                        _messagingSelected.remove(ecId);
                      else
                        _messagingSelected.add(ecId);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      color: isSelected
                          ? AppColors.primary.withOpacity(0.06) : Colors.transparent,
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.check_circle : Icons.circle_outlined,
                            size: 18,
                            color: isSelected ? AppColors.primary : AppColors.textHint,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ec['contributor']?['name'] ?? '',
                                    style: appText(size: 12, weight: FontWeight.w600)),
                                Text(ec['contributor']?['phone'] ?? '',
                                    style: appText(size: 10, color: AppColors.textTertiary)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Pledged: ${_formatAmount(ec['pledge_amount'])}',
                                  style: appText(size: 10, color: AppColors.textTertiary)),
                              Text('Paid: ${_formatAmount(ec['total_paid'])}',
                                  style: appText(size: 10, color: AppColors.textTertiary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('No contributors with phone numbers match this category.',
                  style: appText(size: 12, color: AppColors.textTertiary)),
            ),
          const SizedBox(height: 12),

          // Payment info
          _label('Payment Info (for {payment} variable)'),
          _input(
            TextEditingController(text: _paymentInfo),
            'e.g. M-Pesa: 0712345678 (John Doe)',
            onChanged: (v) => _paymentInfo = v,
          ),
          Text('Leave empty to omit the payment line from the message entirely.',
              style: appText(size: 10, color: AppColors.textTertiary)),
          const SizedBox(height: 12),

          // Reminder contact phone override
          _label('Contact phone for this send (optional)'),
          _input(
            TextEditingController(text: _reminderContactOverride),
            'Defaults to event reminder contact, then your number',
            onChanged: (v) => _reminderContactOverride = v,
          ),
          Text("Recipients will see this number if they need to reach you about their contribution.",
              style: appText(size: 10, color: AppColors.textTertiary)),
          const SizedBox(height: 12),

          // Message template (editable)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label('Message Template'),
              GestureDetector(
                onTap: () => setState(() {
                  _messageTemplate = _getDefaultTemplate(_messagingCase);
                }),
                child: Text('Reset', style: appText(size: 11, weight: FontWeight.w600, color: AppColors.primary)),
              ),
            ],
          ),
          TextField(
            controller: TextEditingController(text: _messageTemplate),
            onChanged: (v) => _messageTemplate = v,
            maxLines: 5,
            minLines: 3,
            style: appText(size: 12, color: AppColors.textPrimary, height: 1.5),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.primary)),
              contentPadding: const EdgeInsets.all(12),
              hintText: 'Edit your message template...',
              hintStyle: appText(size: 12, color: AppColors.textHint),
            ),
          ),
          Text('Variables: {name}, {event_name}, {event_title}, {payment}',
              style: appText(size: 10, color: AppColors.textTertiary)),
          const SizedBox(height: 8),

          // Save-for-this-event row (mirrors web persistent save block).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border, style: BorderStyle.solid),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _savedTemplates[_messagingCase] != null
                        ? 'Saved customisation in use for this case.'
                        : 'Save these values so you do not have to retype them next time.',
                    style: appText(size: 10, color: AppColors.textTertiary, height: 1.4),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (_savingTemplate || _messageTemplate.trim().isEmpty)
                      ? null
                      : _saveCurrentTemplate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    minimumSize: const Size(0, 32),
                  ),
                  child: _savingTemplate
                      ? const SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Save', style: appText(size: 11, weight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Preview + Send buttons (matching web layout)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: selectedTargets.isEmpty ? null : () => _showMessagePreview(selectedTargets),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: Text('Preview (${selectedTargets.length})',
                      style: appText(size: 12, weight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (selectedTargets.isEmpty || _sendingMessages)
                      ? null
                      : () => _sendBulkMessage(selectedTargets),
                  icon: _sendingMessages
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : SvgPicture.asset('assets/icons/send-icon.svg', width: 16, height: 16,
                          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                  label: Text(
                    _sendingMessages ? 'Sending...' : 'Send (${selectedTargets.length})',
                    style: appText(size: 12, weight: FontWeight.w700, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Message Preview (matching web's preview dialog) ──
  void _showMessagePreview(List<dynamic> targets) {
    final sampleEc = targets.isNotEmpty ? targets.first : null;
    final sampleMessage = sampleEc != null ? _resolveTemplate(_messageTemplate, sampleEc) : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF7F8FA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE3E5EA), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Row(children: [
              Text('Message Preview', style: appText(size: 18, weight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${targets.length} recipient${targets.length != 1 ? 's' : ''}',
                    style: appText(size: 11, weight: FontWeight.w700, color: AppColors.primary)),
              ),
            ]),
            const SizedBox(height: 14),
            if (sampleEc != null) ...[
              Text('Sample for ${sampleEc['contributor']?['name'] ?? 'contributor'}',
                  style: appText(size: 11, weight: FontWeight.w600, color: AppColors.textTertiary)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.82),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCF8C6),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: Text(sampleMessage,
                        style: appText(size: 13, color: AppColors.textPrimary, height: 1.45)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text('Recipients', style: appText(size: 11, weight: FontWeight.w600, color: AppColors.textTertiary)),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: targets.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.borderLight),
                  itemBuilder: (_, i) {
                    final ec = targets[i];
                    final name = (ec['contributor']?['name'] ?? '').toString();
                    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.10),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(initial,
                              style: appText(size: 12, weight: FontWeight.w800, color: AppColors.primary)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(name,
                                style: appText(size: 12.5, weight: FontWeight.w700)),
                            Text(ec['contributor']?['phone'] ?? '',
                                style: appText(size: 10.5, color: AppColors.textTertiary)),
                          ],
                        )),
                      ]),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Close', style: appText(size: 13, weight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendBulkMessage(targets);
                  },
                  icon: SvgPicture.asset('assets/icons/send-icon.svg', width: 16, height: 16,
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                  label: Text('Confirm & Send', style: appText(size: 13, weight: FontWeight.w700, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _sendBulkMessage(List<dynamic> targets) async {
    setState(() => _sendingMessages = true);
    final res = await EventsService.sendBulkReminder(widget.eventId, {
      'case_type': _messagingCase,
      'message_template': _messageTemplate,
      if (_paymentInfo.isNotEmpty) 'payment_info': _paymentInfo,
      if (_reminderContactOverride.trim().isNotEmpty)
        'contact_phone': _reminderContactOverride.trim(),
      'contributor_ids': targets
          .map((ec) => ec['id']?.toString())
          .where((id) => id != null)
          .toList(),
    });
    if (mounted) {
      setState(() => _sendingMessages = false);
      if (res['success'] == true) {
        final data = (res['data'] as Map?) ?? {};
        final sent = (data['sent'] ?? 0) as int;
        final failed = (data['failed'] ?? 0) as int;
        final queued = (data['queued'] ?? 0) as int;
        final errors = (data['errors'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (queued > 0 && sent == 0 && failed == 0) {
          AppSnackbar.success(context, 'Queued $queued message${queued == 1 ? '' : 's'} for delivery');
        } else {
          _showSendResults(sent, failed, errors);
        }
      } else {
        AppSnackbar.error(context, res['message'] ?? 'Failed to send');
      }
    }
  }

  // ── Send Results Dialog (matching web's result dialog) ──
  void _showSendResults(int sent, int failed, List<String> errors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Send Results', style: appText(size: 17, weight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(children: [
                    Text('$sent', style: appText(size: 22, weight: FontWeight.w800, color: AppColors.accent)),
                    Text('Sent', style: appText(size: 11, color: AppColors.textTertiary)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(children: [
                    Text('$failed', style: appText(size: 22, weight: FontWeight.w800, color: AppColors.error)),
                    Text('Failed', style: appText(size: 11, color: AppColors.textTertiary)),
                  ]),
                ),
              ),
            ]),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.error.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Errors:', style: appText(size: 11, weight: FontWeight.w600, color: AppColors.error)),
                    const SizedBox(height: 4),
                    ...errors.take(5).map((e) => Text(e,
                        style: appText(size: 10, color: AppColors.error.withOpacity(0.8)))),
                    if (errors.length > 5)
                      Text('...and ${errors.length - 5} more',
                          style: appText(size: 10, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: appText(size: 13, weight: FontWeight.w600, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════
  // ADD CONTRIBUTOR (New + Address Book)
  // ════════════════════════════════════════════════════
  // BULK UPLOAD (matches web version)
  // ════════════════════════════════════════════════════

  String _formatTanzanianPhone(String raw) {
    String phone = raw.replaceAll(RegExp(r'[\s\-\+]'), '');
    if (phone.startsWith('0') && phone.length == 10) phone = phone.substring(1);
    if (RegExp(r'^[67]').hasMatch(phone)) phone = '255$phone';
    if (RegExp(r'^255[67]\d{8}$').hasMatch(phone)) return phone;
    throw Exception('Invalid phone: $raw');
  }

  void _showBulkUploadSheet() {
    String bulkMode = 'targets';
    List<Map<String, dynamic>> bulkRows = [];
    String bulkFileName = '';
    List<String> bulkErrors = [];
    bool bulkUploading = false;
    bool bulkSendSms = false;
    Map<String, dynamic>? bulkResult;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> pickAndParseFile() async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['xlsx', 'xls', 'csv'],
            );
            if (result == null || result.files.isEmpty) return;
            final file = result.files.first;
            setSheetState(() {
              bulkFileName = file.name;
              bulkErrors = [];
              bulkRows = [];
              bulkResult = null;
            });

            try {
              final bytes = file.path != null ? File(file.path!).readAsBytesSync() : file.bytes;
              if (bytes == null) {
                setSheetState(() => bulkErrors = ['Could not read file']);
                return;
              }

              List<List<dynamic>> rows = [];
              if (file.name.endsWith('.csv')) {
                final csvString = String.fromCharCodes(bytes);
                rows = const CsvToListConverter().convert(csvString);
              } else {
                final excel = xl.Excel.decodeBytes(bytes as List<int>);
                final sheet = excel.tables[excel.tables.keys.first];
                if (sheet == null) {
                  setSheetState(() => bulkErrors = ['No sheet found in file']);
                  return;
                }
                for (final row in sheet.rows) {
                  rows.add(row.map((cell) => cell?.value?.toString() ?? '').toList());
                }
              }

              if (rows.length < 2) {
                setSheetState(() => bulkErrors = ['File must have a header row and at least one data row']);
                return;
              }

              final parsed = <Map<String, dynamic>>[];
              final parseErrors = <String>[];
              final headers = rows.first.map((v) => v.toString().trim().toLowerCase()).toList();
              int col(List<String> names, int fallback) {
                final idx = headers.indexWhere((h) => names.any((n) => h.contains(n)));
                return idx >= 0 ? idx : fallback;
              }
              final nameCol = col(['name', 'contributor'], 1);
              final phoneCol = col(['phone', 'mobile', 'contact'], 2);
              final amountCol = col(['amount', 'pledge', 'target', 'contribution', 'paid'], 3);

              for (int i = 1; i < rows.length; i++) {
                final row = rows[i];
                final name = row.length > nameCol ? row[nameCol].toString().trim() : '';
                final phoneRaw = row.length > phoneCol ? row[phoneCol].toString().trim() : '';
                final amountRaw = row.length > amountCol ? row[amountCol].toString().trim() : '0';

                if (name.isEmpty && phoneRaw.isEmpty) continue;
                if (name.isEmpty) { parseErrors.add('Row ${i + 1}: Name is missing'); continue; }

                String phone = '';
                if (phoneRaw.isNotEmpty) {
                  try {
                    phone = _formatTanzanianPhone(phoneRaw);
                  } catch (_) {
                    parseErrors.add('Row ${i + 1}: Invalid phone "$phoneRaw" for $name');
                    continue;
                  }
                }

                final amount = double.tryParse(amountRaw.replaceAll(',', '')) ?? 0;
                if (amount < 0) { parseErrors.add('Row ${i + 1}: Invalid amount for $name'); continue; }

                parsed.add({'name': name, 'phone': phone, 'amount': amount});
              }

              setSheetState(() {
                bulkRows = parsed;
                if (parseErrors.isNotEmpty) bulkErrors = parseErrors;
              });
            } catch (_) {
              setSheetState(() => bulkErrors = ['We couldn\'t parse this file. Please use a valid .xlsx or .csv file.']);
            }
          }

          Future<void> uploadBulk() async {
            if (bulkRows.isEmpty) return;
            setSheetState(() { bulkUploading = true; bulkResult = null; });
            final res = await EventsService.bulkAddContributors(widget.eventId, {
              'contributors': bulkRows,
              'send_sms': bulkSendSms,
              'mode': bulkMode,
            });
            if (res['success'] != true) {
              if (ctx.mounted) {
                setSheetState(() => bulkUploading = false);
                AppSnackbar.error(context, res['message'] ?? 'We couldn\'t process the upload. Please try again.');
              }
              return;
            }
            final data = res['data'] is Map ? (res['data'] as Map).cast<String, dynamic>() : <String, dynamic>{};
            final jobId = data['job_id']?.toString();
            if (jobId != null && jobId.isNotEmpty) {
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                AppSnackbar.success(context, 'Upload accepted. Contributors are processing in the background.');
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) _load();
                });
              }
              return;
            }
            if (jobId == null || jobId.isEmpty) {
              // Legacy sync response (no background worker available).
              if (ctx.mounted) {
                setSheetState(() {
                  bulkUploading = false;
                  bulkResult = data.isNotEmpty ? data : {'processed': 0, 'errors_count': 0};
                  bulkRows = [];
                  bulkFileName = '';
                  bulkErrors = [];
                });
                AppSnackbar.success(context, '${bulkResult?['processed'] ?? 0} contributors processed');
                _load();
              }
              return;
            }

          }

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),
                  Text('Bulk Upload Contributors', style: appText(size: 18, weight: FontWeight.w700)),
                  const SizedBox(height: 16),

                  // Mode selector
                  _label('Upload Mode'),
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(3),
                    child: Row(children: [
                      _tabButton('Set Pledge Targets', bulkMode == 'targets', () => setSheetState(() => bulkMode = 'targets')),
                      const SizedBox(width: 4),
                      _tabButton('Record Contributions', bulkMode == 'contributions', () => setSheetState(() => bulkMode = 'contributions')),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bulkMode == 'targets'
                        ? 'Set or update pledge targets for multiple contributors at once.'
                        : 'Record actual payments for multiple contributors at once.',
                    style: appText(size: 11, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 14),

                  // Template info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                      color: Colors.white,
                    ),
                    child: Row(children: [
                      const AppIcon('excel-document', size: 28),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('File Format', style: appText(size: 13, weight: FontWeight.w600)),
                        Text('Columns: S/N, Name, Phone (255 format), Amount', style: appText(size: 10, color: AppColors.textTertiary)),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 14),

                  // File picker - drop-zone style
                  InkWell(
                    onTap: pickAndParseFile,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                      decoration: BoxDecoration(
                        color: (bulkFileName.isEmpty ? AppColors.primary : const Color(0xFF16A34A))
                            .withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (bulkFileName.isEmpty ? AppColors.primary : const Color(0xFF16A34A))
                              .withOpacity(0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Column(children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: (bulkFileName.isEmpty ? AppColors.primary : const Color(0xFF16A34A))
                                  .withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              bulkFileName.isEmpty ? Icons.cloud_upload_rounded : Icons.insert_drive_file_rounded,
                              size: 24,
                              color: bulkFileName.isEmpty ? AppColors.primary : const Color(0xFF16A34A),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            bulkFileName.isEmpty ? 'Tap to select a file' : bulkFileName,
                            style: appText(size: 14, weight: FontWeight.w700),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bulkFileName.isEmpty ? 'XLSX or CSV · up to a few thousand rows' : 'Tap to choose a different file',
                            style: appText(size: 11, color: AppColors.textTertiary),
                          ),
                        ]),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Parsed rows preview
                  if (bulkRows.isNotEmpty) ...[
                    Row(children: [
                      const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF16A34A)),
                      const SizedBox(width: 6),
                      Text('${bulkRows.length} valid rows', style: appText(size: 13, weight: FontWeight.w600, color: const Color(0xFF16A34A))),
                    ]),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: bulkRows.length > 20 ? 21 : bulkRows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          if (i == 20) {
                            return Padding(
                              padding: const EdgeInsets.all(8),
                              child: Center(child: Text('...and ${bulkRows.length - 20} more', style: appText(size: 11, color: AppColors.textTertiary))),
                            );
                          }
                          final r = bulkRows[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(children: [
                              SizedBox(width: 24, child: Text('${i + 1}', style: appText(size: 10, color: AppColors.textTertiary))),
                              Expanded(child: Text(r['name'] ?? '', style: appText(size: 11, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 6),
                              Text(r['phone'] ?? '', style: appText(size: 10, color: AppColors.textTertiary)),
                              const SizedBox(width: 6),
                              Text(_formatAmount(r['amount']), style: appText(size: 10, weight: FontWeight.w600, color: AppColors.primary)),
                            ]),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Parse errors
                  if (bulkErrors.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.error.withOpacity(0.2)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.warning_rounded, size: 14, color: AppColors.error),
                          const SizedBox(width: 4),
                          Text('Parsing Issues', style: appText(size: 11, weight: FontWeight.w600, color: AppColors.error)),
                        ]),
                        const SizedBox(height: 4),
                        ...bulkErrors.take(5).map((e) => Text('◈ $e', style: appText(size: 10, color: AppColors.error.withOpacity(0.8)))),
                        if (bulkErrors.length > 5)
                          Text('...and ${bulkErrors.length - 5} more', style: appText(size: 10, color: AppColors.textTertiary)),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // SMS toggle
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border), color: Colors.white),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: AppCheckbox.box(
                          value: bulkSendSms,
                          onChanged: (v) => setSheetState(() => bulkSendSms = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Send notifications', style: appText(size: 13, weight: FontWeight.w600)),
                        Text(
                          bulkSendSms
                              ? 'WhatsApp/SMS will be sent to each contributor.'
                              : 'No messages will be sent. You can notify them later.',
                          style: appText(size: 10, color: AppColors.textTertiary),
                        ),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 14),

                  // Upload result
                  if (bulkResult != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF16A34A)),
                          const SizedBox(width: 6),
                          Text('Upload Complete', style: appText(size: 13, weight: FontWeight.w600, color: const Color(0xFF16A34A))),
                        ]),
                        const SizedBox(height: 4),
                        Text('${bulkResult!['processed'] ?? 0} contributors processed, ${bulkResult!['errors_count'] ?? 0} errors',
                            style: appText(size: 11, color: const Color(0xFF16A34A))),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Buttons
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(bulkResult != null ? 'Close' : 'Cancel', style: appText(size: 13, weight: FontWeight.w600)),
                      ),
                    ),
                    if (bulkResult == null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (bulkUploading || bulkRows.isEmpty) ? null : () => uploadBulk(),
                          icon: bulkUploading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.upload_rounded, size: 16),
                          label: Text(
                            bulkUploading ? 'Uploading...' : 'Upload ${bulkRows.length} Contributors',
                            style: appText(size: 12, weight: FontWeight.w700, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════
  // ADD CONTRIBUTOR (New + Address Book)
  // ════════════════════════════════════════════════════

  void _showAddContributorSheet() {
    int tabIndex = 1;
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final pledgeCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    List<dynamic> searchResults = [];
    bool searchLoading = false;
    bool initialLoadDone = false;
    String? selectedExistingId;
    final searchCtrl = TextEditingController();
    final existPledgeCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> searchAddressBook(String query) async {
            setSheetState(() => searchLoading = true);
            final res = await EventsService.getUserContributors(search: query);
            if (res['success'] == true) {
              setSheetState(() {
                searchResults = res['data']?['contributors'] ?? [];
                searchLoading = false;
              });
            } else {
              setSheetState(() => searchLoading = false);
            }
          }

          if (!initialLoadDone) {
            initialLoadDone = true;
            searchAddressBook('');
          }

          Future<void> submit() async {
            Map<String, dynamic> data;
            if (tabIndex == 0) {
              if (nameCtrl.text.trim().isEmpty) {
                AppSnackbar.error(ctx, 'Name is required');
                return;
              }
              if (phoneCtrl.text.trim().isEmpty) {
                AppSnackbar.error(ctx, 'Phone is required');
                return;
              }
              data = {
                'name': nameCtrl.text.trim(),
                'email': emailCtrl.text.trim().isEmpty
                    ? null
                    : emailCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
                'pledge_amount': double.tryParse(pledgeCtrl.text.trim()) ?? 0,
                'notes': notesCtrl.text.trim().isEmpty
                    ? null
                    : notesCtrl.text.trim(),
              };
            } else {
              if (selectedExistingId == null) {
                AppSnackbar.error(ctx, 'Select a contributor');
                return;
              }
              data = {
                'contributor_id': selectedExistingId,
                'pledge_amount':
                    double.tryParse(existPledgeCtrl.text.trim()) ?? 0,
              };
            }
            Navigator.pop(ctx);
            setState(() => _actionLoading = true);
            final res = await EventsService.addContributorToEvent(
              widget.eventId,
              data,
            );
            if (mounted) {
              setState(() => _actionLoading = false);
              if (res['success'] == true) {
                AppSnackbar.success(context, 'Contributor added');
                _load();
              } else
                AppSnackbar.error(
                  context,
                  res['message'] ?? 'Failed to add contributor',
                );
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Add Contributor',
                    style: appText(size: 18, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  // Tab selector
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        _tabButton(
                          'New Contributor',
                          tabIndex == 0,
                          () => setSheetState(() => tabIndex = 0),
                        ),
                        const SizedBox(width: 4),
                        _tabButton('Address Book', tabIndex == 1, () {
                          setSheetState(() => tabIndex = 1);
                          if (searchResults.isEmpty) searchAddressBook('');
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (tabIndex == 0) ...[
                    _label('Name *'),
                    _input(nameCtrl, 'Full name'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('Email'),
                              _input(
                                emailCtrl,
                                'email@example.com',
                                keyboard: TextInputType.emailAddress,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('Phone *'),
                              _input(
                                phoneCtrl,
                                '+255...',
                                keyboard: TextInputType.phone,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _label('Pledge Amount (TZS)'),
                    _input(
                      pledgeCtrl,
                      'e.g. 20,000',
                      keyboard: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    _label('Notes'),
                    _input(notesCtrl, 'Optional notes...', maxLines: 2),
                  ] else ...[
                    _label('Search Your Contributors'),
                    TextField(
                      controller: searchCtrl,
                      onChanged: (v) => searchAddressBook(v),
                      style: appText(size: 14),
                      decoration: InputDecoration(
                        hintText: 'Search by name, email, or phone...',
                        hintStyle: appText(size: 13, color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (searchLoading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    else if (searchResults.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final c = searchResults[i];
                            final isSelected = selectedExistingId == c['id'];
                            return GestureDetector(
                              onTap: () => setSheetState(
                                () => selectedExistingId = c['id'],
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                color: isSelected
                                    ? AppColors.primary.withOpacity(0.08)
                                    : Colors.transparent,
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      size: 18,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textHint,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c['name'] ?? '',
                                            style: appText(
                                              size: 14,
                                              weight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            [c['email'], c['phone']]
                                                .where(
                                                  (e) =>
                                                      e != null &&
                                                      e.toString().isNotEmpty,
                                                )
                                                .join(' · '),
                                            style: appText(
                                              size: 11,
                                              color: AppColors.textTertiary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'No contributors found',
                          style: appText(
                            size: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    if (selectedExistingId != null) ...[
                      const SizedBox(height: 14),
                      _label('Pledge Amount (TZS)'),
                      _input(
                        existPledgeCtrl,
                        'e.g. 20,000',
                        keyboard: TextInputType.number,
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: Text(
                        'Add Contributor',
                        style: appText(
                          size: 15,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tabButton(String text, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              text,
              style: appText(
                size: 13,
                weight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════
  // RECORD PAYMENT
  // ════════════════════════════════════════════════════

  void _showRecordPaymentSheet(Map<String, dynamic> ec) {
    final amtCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    String method = 'cash';
    final name = ec['contributor']?['name'] ?? 'Unknown';
    final pledged = _toNum(ec['pledge_amount']);
    final paid = _toNum(ec['total_paid']);
    final balance = (pledged - paid).clamp(0, double.infinity);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Record Payment',
                style: appText(size: 18, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: appText(size: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'Pledge: ${_formatAmount(pledged)} · Paid: ${_formatAmount(paid)} · Balance: ${_formatAmount(balance)}',
                style: appText(size: 12, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Amount (TZS) *'),
                        _input(amtCtrl, '0', keyboard: TextInputType.number),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Payment Method'),
                        AppSelect.fromItems<String>(
                          value: method,
                          hint: 'Payment Method',
                          title: 'Payment Method',
                          borderRadius: 12,
                          fontSize: 14,
                          items: _kPaymentMethods
                              .map(
                                (m) => DropdownMenuItem<String>(
                                  value: m['id'] as String,
                                  child: Text(
                                    m['name'] as String,
                                    style: appText(size: 14),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setSheetState(() => method = v);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _label('Payment Reference'),
              _input(refCtrl, 'Transaction ID...'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    if (amtCtrl.text.trim().isEmpty ||
                        (double.tryParse(amtCtrl.text.trim()) ?? 0) <= 0) {
                      AppSnackbar.error(ctx, 'Enter a valid amount');
                      return;
                    }
                    Navigator.pop(ctx);
                    setState(() => _actionLoading = true);
                    final res = await EventsService.recordContributorPayment(
                      widget.eventId,
                      ec['id'].toString(),
                      {
                        'amount': double.tryParse(amtCtrl.text.trim()) ?? 0,
                        'payment_method': method,
                        if (refCtrl.text.trim().isNotEmpty)
                          'payment_reference': refCtrl.text.trim(),
                      },
                    );
                    if (mounted) {
                      setState(() => _actionLoading = false);
                      if (res['success'] == true) {
                        AppSnackbar.success(context, 'Payment recorded');
                        _load();
                      } else
                        AppSnackbar.error(context, res['message'] ?? 'Failed');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(
                    'Record Payment',
                    style: appText(
                      size: 15,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════
  // UPDATE PLEDGE
  // ════════════════════════════════════════════════════

  void _showUpdatePledgeSheet(Map<String, dynamic> ec) {
    final pledgeCtrl = TextEditingController(
      text: _toNum(ec['pledge_amount']).toStringAsFixed(0),
    );
    final name = ec['contributor']?['name'] ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Update Pledge',
              style: appText(size: 18, weight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: appText(size: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            _label('Pledge Amount (TZS)'),
            _input(pledgeCtrl, '0', keyboard: TextInputType.number),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  setState(() => _actionLoading = true);
                  final res = await EventsService.updateEventContributor(
                    widget.eventId,
                    ec['id'].toString(),
                    {
                      'pledge_amount':
                          double.tryParse(pledgeCtrl.text.trim()) ?? 0,
                    },
                  );
                  if (mounted) {
                    setState(() => _actionLoading = false);
                    if (res['success'] == true) {
                      AppSnackbar.success(context, 'Pledge updated');
                      _load();
                    } else
                      AppSnackbar.error(context, res['message'] ?? 'Failed');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  'Update Pledge',
                  style: appText(
                    size: 15,
                    weight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════
  // DOWNLOAD REPORT
  // ════════════════════════════════════════════════════

  void _showReportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Download Report',
              style: appText(size: 18, weight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _downloadReport('pdf');
                    },
                    icon: const AppIcon('pdf-file-type', size: 18),
                    label: Text(
                      'PDF',
                      style: appText(size: 13, weight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.borderLight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _downloadReport('xlsx');
                    },
                    icon: const AppIcon('excel-document', size: 18),
                    label: Text(
                      'Excel',
                      style: appText(size: 13, weight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.borderLight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadReport(String format) async {
    AppSnackbar.success(
      context,
      'Generating ${format == 'xlsx' ? 'Excel' : 'PDF'} report...',
    );
    try {
      final res = await ReportGenerator.generateContributionsReport(
        widget.eventId,
        format: format,
        contributions: _eventContributors,
        summary: _summary,
        eventBudget: widget.eventBudget,
        eventTitle: widget.eventTitle,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        if (format == 'pdf' && res['bytes'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportPreviewScreen(
                title: 'Contribution Report',
                pdfBytes: res['bytes'] as Uint8List,
                filePath: res['path'] as String,
              ),
            ),
          );
        } else if (res['path'] != null) {
          await OpenFilex.open(res['path'] as String);
          if (mounted) AppSnackbar.success(context, 'Report opened');
        }
      } else {
        AppSnackbar.error(
          context,
          res['message'] ?? 'Failed to generate report',
        );
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to generate report');
    }
  }

  // ════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ════════════════════════════════════════════════════

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: appText(
        size: 12,
        weight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    ),
  );

  Widget _input(
    TextEditingController ctrl,
    String hint, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      onChanged: onChanged,
      style: appText(size: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: appText(size: 13, color: AppColors.textHint),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _skeleton() {
    Widget box({double? w, required double h, double r = 12}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AppColors.borderLight,
            borderRadius: BorderRadius.circular(r),
          ),
        );
    Widget goalHeader() => Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(
              width: 112,
              height: 112,
              child: Stack(alignment: Alignment.center, children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 9),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  box(w: 44, h: 22, r: 5),
                  const SizedBox(height: 6),
                  box(w: 46, h: 10, r: 4),
                  const SizedBox(height: 4),
                  box(w: 58, h: 10, r: 4),
                ]),
              ]),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                box(w: 66, h: 11, r: 4),
                const SizedBox(height: 8),
                box(w: 154, h: 22, r: 5),
                const SizedBox(height: 12),
                box(h: 6, r: 999),
                const SizedBox(height: 12),
                box(w: 58, h: 11, r: 4),
                const SizedBox(height: 7),
                box(w: 126, h: 17, r: 4),
              ]),
            ),
          ]),
        );
    Widget statStrip() => Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(children: List.generate(4, (_) => Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  box(w: 22, h: 22, r: 6),
                  const SizedBox(height: 6),
                  box(w: 58, h: 10, r: 4),
                  const SizedBox(height: 5),
                  box(w: 66, h: 13, r: 4),
                ]),
              ))),
        );
    Widget quickAction() => Container(
          width: 92,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            box(w: 40, h: 40, r: 12),
            const SizedBox(height: 8),
            box(w: 58, h: 11, r: 4),
            const SizedBox(height: 5),
            box(w: 46, h: 11, r: 4),
          ]),
        );
    Widget searchBar() => Container(
          height: 50,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            box(w: 20, h: 20, r: 5),
            const SizedBox(width: 12),
            box(w: 150, h: 13, r: 4),
          ]),
        );
    Widget contributorTile() => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              box(w: 44, h: 44, r: 999),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                box(w: 136, h: 14, r: 4),
                const SizedBox(height: 7),
                box(w: 112, h: 11.5, r: 4),
              ])),
              box(w: 20, h: 20, r: 5),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(child: _contributionTileStatSkeleton(box)),
                Container(width: 1, height: 28, color: AppColors.borderLight),
                Expanded(child: _contributionTileStatSkeleton(box)),
                Container(width: 1, height: 28, color: AppColors.borderLight),
                Expanded(child: _contributionTileStatSkeleton(box)),
              ]),
            ),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        goalHeader(),
        const SizedBox(height: 12),
        statStrip(),
        const SizedBox(height: 14),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, __) => quickAction(),
          ),
        ),
        const SizedBox(height: 14),
        searchBar(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: box(w: 92, h: 12, r: 4),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < 5; i++) ...[
          contributorTile(),
        ],
      ],
    );
  }

  Widget _contributionTileStatSkeleton(
    Widget Function({required double h, double r, double? w}) box,
  ) => Column(mainAxisSize: MainAxisSize.min, children: [
        box(w: 48, h: 10, r: 4),
        const SizedBox(height: 6),
        box(w: 64, h: 13, r: 4),
      ]);
}

class _QuickAction {
  final String? icon;
  final IconData? materialIcon;
  final String label;
  final VoidCallback onTap;
  final Color tint;
  final Color tintBg;
  const _QuickAction({
    this.icon,
    this.materialIcon,
    required this.label,
    required this.onTap,
    required this.tint,
    required this.tintBg,
  });
}


