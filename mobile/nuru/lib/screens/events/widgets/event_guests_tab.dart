import '../../../core/widgets/nuru_refresh_indicator.dart';
import '../../../widgets/app_action_sheet.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/nuru_search_bar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/events_service.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/l10n/l10n_helper.dart';
import 'register_missing_member_form.dart';


class EventGuestsTab extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic>? permissions;
  const EventGuestsTab({super.key, required this.eventId, this.permissions});

  @override
  State<EventGuestsTab> createState() => _EventGuestsTabState();
}

class _EventGuestsTabState extends State<EventGuestsTab> with AutomaticKeepAliveClientMixin {
  /// Master guest list - fetched once. Filtering & search run client-side
  /// so tab/search interactions are instant (no round-trip).
  List<dynamic> _allGuests = [];
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  String _filter = 'all';
  final _searchCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load({bool background = false}) async {
    if (!background) setState(() => _loading = true);
    final List<dynamic> all = [];
    Map<String, dynamic> summary = {};
    String? lastError;
    int page = 1;
    while (true) {
      final res = await EventsService.getGuests(widget.eventId,
          page: page, limit: 200);
      if (res['success'] != true) {
        lastError = res['message']?.toString();
        break;
      }
      final data = res['data'];
      final list = (data?['guests'] as List?) ?? const [];
      all.addAll(list);
      if (page == 1) {
        summary = (data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
      }
      final pagination = (data?['pagination'] as Map?) ?? const {};
      final totalPages = (pagination['total_pages'] ?? pagination['totalPages'] ?? 1) as int;
      if (list.isEmpty || page >= totalPages) break;
      page++;
      if (page > 200) break;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _allGuests = all;
      if (summary.isNotEmpty) _summary = summary;
    });
    if (lastError != null && !background && mounted) {
      AppSnackbar.error(context, lastError);
    }
  }

  /// Client-side filter + search applied to [_allGuests].
  List<dynamic> get _guests {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allGuests.where((g) {
      if (g is! Map) return false;
      final status = (g['rsvp_status'] ?? 'pending').toString();
      if (_filter != 'all' && status != _filter) return false;
      if (q.isEmpty) return true;
      final hay = [
        g['name'], g['full_name'], g['phone'], g['phone_number'], g['email'],
      ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final canManage = widget.permissions?['can_manage_guests'] == true || widget.permissions?['is_creator'] == true;

    if (_loading && _guests.isEmpty) return _buildSkeleton();

    return NuruRefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // 4 KPI cards
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              Expanded(child: _kpiTile(
                iconName: 'users',
                iconBg: const Color(0xFFEDE9FE), iconColor: const Color(0xFF7C3AED),
                value: '${_summary['total'] ?? _guests.length}',
                label: 'Total',
              )),
              Expanded(child: _kpiTile(
                iconName: 'double-check',
                iconBg: const Color(0xFFDCFCE7), iconColor: const Color(0xFF16A34A),
                value: '${_summary['confirmed'] ?? 0}',
                label: 'Confirmed',
              )),
              Expanded(child: _kpiTile(
                iconName: 'clock',
                iconBg: const Color(0xFFFEF3C7), iconColor: const Color(0xFFCA8A04),
                value: '${_summary['pending'] ?? 0}',
                label: 'Pending',
              )),
              Expanded(child: _kpiTile(
                iconName: 'close',
                iconBg: const Color(0xFFFEE2E2), iconColor: const Color(0xFFDC2626),
                value: '${_summary['declined'] ?? 0}',
                label: 'Declined',
              )),
            ]),
          ),

          const SizedBox(height: 16),

          // Search + Invite
          Row(children: [
            Expanded(
              child: NuruSearchBar(
                controller: _searchCtrl,
                hintText: 'Search guests...',
                debounce: const Duration(milliseconds: 300),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _showAddGuestSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const AppIcon('user-add', size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text('Invite Guest', style: appText(size: 13, weight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ],
          ]),

          const SizedBox(height: 12),

          // Filter pills
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterPill('All', 'all', null),
                _filterPill('Confirmed', 'confirmed', const Color(0xFF16A34A)),
                _filterPill('Pending', 'pending', const Color(0xFFCA8A04)),
                _filterPill('Declined', 'declined', const Color(0xFFDC2626)),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Guest cards
          if (_guests.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(18)),
                  child: const AppIcon('users', size: 26, color: AppColors.primary),
                ),
                const SizedBox(height: 14),
                Text('No guests yet', style: appText(size: 15, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Invite people to be part of your special day', style: appText(size: 12, color: AppColors.textTertiary), textAlign: TextAlign.center),
              ]),
            )
          else
            ..._guests.map((g) => _guestCard(g as Map<String, dynamic>, canManage)),

          if (_guests.isNotEmpty) ...[
            const SizedBox(height: 14),
            // Celebratory bottom card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E6),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                  child: const AppIcon('love', size: 22, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Your guest list is looking great', style: appText(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('All confirmed guests are set to celebrate your special day.', style: appText(size: 11, color: AppColors.textSecondary), maxLines: 2),
                ])),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpiTile({required String iconName, required Color iconBg, required Color iconColor, required String value, required String label}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
        child: Center(child: AppIcon(iconName, size: 18, color: iconColor)),
      ),
      const SizedBox(height: 8),
      Text(value, style: appText(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary)),
      const SizedBox(height: 2),
      Text(label, style: appText(size: 11, weight: FontWeight.w500, color: AppColors.textTertiary)),
    ]);
  }

  Widget _filterPill(String label, String value, Color? dotColor) {
    final active = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? AppColors.primary.withOpacity(0.4) : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dotColor != null) ...[
              Container(width: 7, height: 7, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(label, style: appText(size: 12, weight: FontWeight.w700, color: active ? AppColors.primaryDark : AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }

  Widget _avatarCircle({required String name, required String url, required Color bg, required Color fg}) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final fallback = Container(
      width: 48, height: 48,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initial, style: appText(size: 18, weight: FontWeight.w800, color: fg)),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: 48, height: 48,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: bg),
          errorWidget: (_, __, ___) => fallback,
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    Widget bar(double w, double h, {double r = 8}) => Container(
      width: w, height: h,
      decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(r)),
    );
    Widget tile() => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: const BoxDecoration(color: Color(0xFFF1F1F4), shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          bar(140, 14),
          const SizedBox(height: 8),
          bar(80, 12),
          const SizedBox(height: 6),
          bar(110, 10),
        ])),
        const SizedBox(width: 8),
        Container(width: 36, height: 36, decoration: const BoxDecoration(color: Color(0xFFF1F1F4), shape: BoxShape.circle)),
      ]),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Row(children: List.generate(4, (_) => Expanded(child: Column(children: [
            Container(width: 38, height: 38, decoration: const BoxDecoration(color: Color(0xFFF1F1F4), shape: BoxShape.circle)),
            const SizedBox(height: 8), bar(30, 16), const SizedBox(height: 6), bar(46, 10),
          ])))),
        ),
        const SizedBox(height: 16),
        Row(children: [Expanded(child: bar(double.infinity, 48, r: 16)), const SizedBox(width: 10), bar(120, 48, r: 16)]),
        const SizedBox(height: 12),
        SizedBox(height: 36, child: Row(children: List.generate(4, (_) => Padding(padding: const EdgeInsets.only(right: 8), child: bar(78, 32, r: 999))))),
        const SizedBox(height: 14),
        ...List.generate(5, (_) => tile()),
      ],
    );
  }

  Widget _guestCard(Map<String, dynamic> g, bool canManage) {
    final name = g['name']?.toString() ?? g['full_name']?.toString() ?? 'Guest';
    final rsvp = (g['rsvp_status'] ?? 'pending').toString();
    final phone = g['phone']?.toString() ?? '';

    final Color statusColor;
    final Color statusBg;
    final String statusIcon;
    switch (rsvp) {
      case 'confirmed':
        statusColor = const Color(0xFF16A34A); statusBg = const Color(0xFFDCFCE7); statusIcon = 'verified'; break;
      case 'declined':
        statusColor = const Color(0xFFDC2626); statusBg = const Color(0xFFFEE2E2); statusIcon = 'close-circle'; break;
      case 'maybe':
        statusColor = const Color(0xFF2563EB); statusBg = const Color(0xFFDBEAFE); statusIcon = 'info'; break;
      default:
        statusColor = const Color(0xFFCA8A04); statusBg = const Color(0xFFFEF3C7); statusIcon = 'clock';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        _avatarCircle(
          name: name,
          url: (g['avatar'] ?? g['avatar_url'] ?? g['profile_picture_url'] ?? '').toString(),
          bg: statusBg,
          fg: statusColor,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: appText(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(statusIcon, size: 11, color: statusColor),
              const SizedBox(width: 4),
              Text(rsvp[0].toUpperCase() + rsvp.substring(1), style: appText(size: 10, weight: FontWeight.w700, color: statusColor)),
            ]),
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              AppIcon('phone', size: 12, color: AppColors.textTertiary),
              const SizedBox(width: 5),
              Text(phone, style: appText(size: 11, color: AppColors.textTertiary)),
            ]),
          ],
        ])),
        if (canManage)
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.white, shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const AppIcon('menu', size: 16, color: AppColors.textSecondary),
              onPressed: () async {
                final checkedIn = g['checked_in'] == true;
                final v = await AppActionSheet.show<String>(
                  context: context,
                  title: 'Guest actions',
                  actions: [
                    if (!checkedIn)
                      const MenuAction(value: 'checkin', label: 'Check In', icon: 'double-check'),
                    if (checkedIn)
                      const MenuAction(value: 'undo_checkin', label: 'Undo Check-in', icon: 'close'),
                    const MenuAction(value: 'invite', label: 'Send Invitation', icon: 'send'),
                    const MenuAction(value: 'delete', label: 'Remove', icon: 'delete', destructive: true),
                  ],
                );
                if (v != null) _handleGuestAction(v, g);
              },
            ),
          ),
      ]),
    );
  }

  Future<void> _handleGuestAction(String action, Map<String, dynamic> guest) async {
    final guestId = guest['id']?.toString() ?? '';
    if (guestId.isEmpty) return;

    Map<String, dynamic> res;
    switch (action) {
      case 'checkin':
        res = await EventsService.checkinGuest(widget.eventId, guestId); break;
      case 'undo_checkin':
        res = await EventsService.undoCheckin(widget.eventId, guestId); break;
      case 'invite':
        res = await EventsService.sendInvitation(widget.eventId, guestId); break;
      case 'delete':
        res = await EventsService.deleteGuest(widget.eventId, guestId); break;
      default:
        return;
    }
    if (mounted) {
      if (res['success'] == true) {
        AppSnackbar.success(context, action == 'checkin' ? 'Checked in' : action == 'invite' ? 'Invitation sent' : 'Done');
        _load();
      } else {
        AppSnackbar.error(context, res['message'] ?? 'Failed');
      }
    }
  }

  void _showAddGuestSheet() {
    final searchCtrl = TextEditingController();
    List<dynamic> searchResults = [];
    bool searching = false;
    Map<String, dynamic>? selectedUser;
    bool submitting = false;
    bool showRegisterForm = false;
    Timer? debounce;


    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text(showRegisterForm ? 'Register a new guest' : 'Invite Guest', style: appText(size: 18, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(showRegisterForm
                    ? 'Add someone who is not yet on Nuru'
                    : 'Search for a Nuru user to add as guest',
                  style: appText(size: 13, color: AppColors.textTertiary)),

                const SizedBox(height: 16),
                if (showRegisterForm)
                  RegisterMissingMemberForm(
                    submitLabel: 'Register guest',
                    onCancel: () => setModalState(() => showRegisterForm = false),
                    onRegistered: (user) => setModalState(() {
                      selectedUser = user;
                      showRegisterForm = false;
                      searchResults = [];
                      searchCtrl.clear();
                    }),
                  )
                else ...[
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    autocorrect: false,
                    style: appText(size: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by name, email, or phone...',
                      hintStyle: appText(size: 13, color: AppColors.textHint),
                      prefixIcon: const Padding(padding: EdgeInsets.all(14), child: AppIcon('search', size: 18, color: AppColors.textHint)),
                      filled: true, fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: const Color(0xFFE5E7EB), width: 1)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (q) {
                      debounce?.cancel();
                      if (q.trim().length < 2) { setModalState(() { searchResults = []; selectedUser = null; }); return; }
                      debounce = Timer(const Duration(milliseconds: 400), () async {
                        setModalState(() => searching = true);
                        final res = await EventsService.searchUsers(q.trim());
                        if (ctx.mounted) {
                          setModalState(() {
                            searching = false;
                            if (res['success'] == true) {
                              final data = res['data'];
                              final rawList = data is List ? data : (data is Map ? (data['items'] ?? data['users'] ?? []) : []);
                              searchResults = (rawList is List ? rawList : []).map((u) {
                                if (u is! Map) return u;
                                final m = Map<String, dynamic>.from(u);
                                if ((m['first_name'] == null || m['first_name'] == '') && m['full_name'] != null) {
                                  final parts = (m['full_name'] as String).split(' ');
                                  m['first_name'] = parts.first;
                                  m['last_name'] = parts.length > 1 ? parts.sublist(1).join(' ') : '';
                                }
                                return m;
                              }).toList();
                            }
                          });
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (searching)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
                  if (!searching && searchResults.isEmpty && searchCtrl.text.length >= 2)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text('No users found', style: appText(size: 13, color: AppColors.textTertiary))),
                    ),
                  if (selectedUser == null)
                    InkWell(
                      onTap: () => setModalState(() => showRegisterForm = true),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withOpacity(0.18)),
                        ),
                        child: Row(children: [
                          const AppIcon('user-add', size: 16, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text("Can't find them?", style: appText(size: 12, color: AppColors.textTertiary)),
                              Text('Register missing guest', style: appText(size: 13, weight: FontWeight.w700, color: AppColors.primary)),
                            ]),
                          ),
                          const AppIcon('arrow-right', size: 14, color: AppColors.primary),
                        ]),
                      ),
                    ),
                ],
                const SizedBox(height: 12),

                if (selectedUser != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Builder(builder: (_) {
                        final avatar = selectedUser!['avatar']?.toString();
                        final hasAvatar = avatar != null && avatar.isNotEmpty;
                        return CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.primary.withOpacity(0.15),
                          backgroundImage: hasAvatar ? NetworkImage(avatar) : null,
                          child: hasAvatar
                              ? null
                              : Text(
                                  '${selectedUser!['first_name']?.toString() ?? ''}'.isNotEmpty
                                      ? selectedUser!['first_name'].toString()[0].toUpperCase()
                                      : '?',
                                  style: appText(size: 14, weight: FontWeight.w700, color: AppColors.primary),
                                ),
                        );
                      }),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${selectedUser!['first_name'] ?? ''} ${selectedUser!['last_name'] ?? ''}'.trim(), style: appText(size: 14, weight: FontWeight.w600)),
                        if (selectedUser!['email'] != null) Text(selectedUser!['email'].toString(), style: appText(size: 11, color: AppColors.textTertiary)),
                      ])),
                      GestureDetector(
                        onTap: () => setModalState(() => selectedUser = null),
                        child: const AppIcon('close', size: 16, color: AppColors.textHint),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      onPressed: submitting ? null : () async {
                        setModalState(() => submitting = true);
                        final data = <String, dynamic>{
                          'guest_type': 'user',
                          'user_id': selectedUser!['id'].toString(),
                          'name': '${selectedUser!['first_name'] ?? ''} ${selectedUser!['last_name'] ?? ''}'.trim(),
                          'rsvp_status': 'pending',
                        };
                        if (selectedUser!['email'] != null) data['email'] = selectedUser!['email'].toString();
                        if (selectedUser!['phone'] != null) data['phone'] = selectedUser!['phone'].toString();
                        final res = await EventsService.addGuest(widget.eventId, data);
                        if (!mounted) return;
                        if (res['success'] == true) {
                          Navigator.pop(ctx);
                          AppSnackbar.success(context, 'Guest added');
                          _load();
                        } else {
                          setModalState(() => submitting = false);
                          AppSnackbar.error(context, res['message'] ?? 'Failed');
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                      child: submitting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                          : Text('Add as Guest', style: appText(size: 15, weight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
                if (selectedUser == null && searchResults.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: searchResults.length,
                      itemBuilder: (_, i) {
                        final user = searchResults[i] as Map<String, dynamic>;
                        final fullName = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                        final name = user['full_name']?.toString() ?? (fullName.isNotEmpty ? fullName : user['username']?.toString() ?? 'Unknown');
                        final subtitleParts = <String>[
                          if (user['username'] != null && user['username'] != '') '@${user['username']}',
                          if (user['email'] != null && user['email'] != '') user['email'].toString(),
                          if (user['phone'] != null && user['phone'] != '') user['phone'].toString(),
                        ];
                        final subtitle = subtitleParts.join(' · ');
                        final avatar = user['avatar']?.toString();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 20, backgroundColor: AppColors.surfaceVariant,
                            backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
                            child: (avatar == null || avatar.isEmpty) ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: appText(size: 14, weight: FontWeight.w700, color: AppColors.textTertiary)) : null,
                          ),
                          title: Text(name, style: appText(size: 14, weight: FontWeight.w600)),
                          subtitle: subtitle.isNotEmpty ? Text(subtitle, style: appText(size: 11, color: AppColors.textTertiary)) : null,
                          onTap: () => setModalState(() => selectedUser = user),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
