import '../../core/widgets/nuru_refresh_indicator.dart';
import '../../core/widgets/nuru_skeleton.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/event_groups_service.dart';
import '../../core/utils/event_groups_cache.dart';
import '../../core/widgets/event_cover_image.dart';
import '../home/widgets/pill_tabs.dart';
import 'event_group_workspace_screen.dart';
import '../../core/widgets/nuru_search_bar.dart';

class MyGroupsScreen extends StatefulWidget {
  const MyGroupsScreen({super.key});

  @override
  State<MyGroupsScreen> createState() => _MyGroupsScreenState();
}

class _MyGroupsScreenState extends State<MyGroupsScreen> {
  List<dynamic> _groups = [];
  bool _loading = true;
  String _search = '';
  Timer? _poll;
  Timer? _searchDebounce;
  int _tab = 0; // 0 All, 1 My Groups, 2 Joined, 3 Invites
  bool _showAllPinned = false;
  static const _tabs = ['All Groups', 'My Groups', 'Joined', 'Invites'];

  @override
  void initState() {
    super.initState();
    // Seed instantly from cache to avoid skeleton flicker (WhatsApp-style).
    final cached = EventGroupsCache.groups;
    if (cached != null) {
      _groups = cached;
      _loading = false;
    }
    // Always refresh in background.
    _load(silent: cached != null);
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await EventGroupsService.listMyGroups(search: _search.isEmpty ? null : _search);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        _groups = data is Map ? (data['groups'] ?? []) : [];
        if (_search.isEmpty) EventGroupsCache.groups = _groups;
      }
    });
  }

  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    // Backend returns naive UTC ISO strings - coerce to UTC then convert to local.
    var s = iso;
    if (!s.endsWith('Z') && !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s)) {
      if (s.contains('T')) {
        s = '${s}Z';
      } else if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}').hasMatch(s)) {
        s = '${s.replaceFirst(' ', 'T')}Z';
      }
    }
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return '';
    final d = parsed.toLocal();
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${d.day}/${d.month}';
  }

  bool _isAdmin(Map g) =>
      g['viewer']?['is_admin'] == true ||
      (g['viewer']?['role']?.toString().toLowerCase() == 'admin');

  String _gid(dynamic g) => (g is Map ? g['id']?.toString() : null) ?? '';

  bool _isPinned(dynamic g) => EventGroupsCache.isPinned(_gid(g));

  void _togglePin(dynamic g) {
    final id = _gid(g);
    if (id.isEmpty) return;
    setState(() => EventGroupsCache.togglePin(id));
  }

  List<dynamic> _filtered() {
    Iterable<dynamic> src = _groups;
    switch (_tab) {
      case 1:
        src = src.where((g) => g is Map && _isAdmin(g));
        break;
      case 2:
        src = src.where((g) => g is Map && !_isAdmin(g));
        break;
      case 3:
        src = const [];
        break;
    }
    return src.toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    final pinnedAll = filtered.where(_isPinned).toList();
    final pinned = _showAllPinned ? pinnedAll : pinnedAll.take(2).toList();
    final others = filtered.where((g) => !pinnedAll.contains(g)).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset(
            'assets/icons/arrow-left-icon.svg',
            width: 22,
            height: 22,
            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
        centerTitle: true,
        title: Text(
          'Event Groups',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: NuruSearchBar(
              hintText: 'Search groups',
              onChanged: (v) {
                _search = v;
                _load(silent: true);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: PillTabs(
              tabs: _tabs,
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: NuruRefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _loading && _groups.isEmpty
                  ? const NuruSkeletonEventList(itemCount: 5)
                  : filtered.isEmpty
                      ? _emptyState(
                          // True empty only when there's no DB data AND no
                          // search/filter is active. Otherwise we're showing
                          // a "no matches" state, not "no data".
                          isFiltered: _search.trim().isNotEmpty || _tab != 0,
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          children: [
                            if (pinnedAll.isNotEmpty) ...[
                              _sectionHeader(
                                'Pinned Groups',
                                onSeeAll: pinnedAll.length > 2
                                    ? () => setState(() => _showAllPinned = !_showAllPinned)
                                    : null,
                                seeAllLabel: _showAllPinned ? 'Show less' : 'See all',
                              ),
                              const SizedBox(height: 8),
                              ...pinned.map((g) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _groupCard(g),
                                  )),
                              const SizedBox(height: 12),
                            ],
                            if (others.isNotEmpty) ...[
                              _sectionHeader('Your Groups'),
                              const SizedBox(height: 8),
                              ...others.map((g) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _groupCard(g),
                                  )),
                            ],
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, {VoidCallback? onSeeAll, String seeAllLabel = 'See all'}) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.1,
          ),
        ),
        const Spacer(),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Text(
              seeAllLabel,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _emptyState({bool isFiltered = false}) => ListView(
        children: [
          const SizedBox(height: 100),
          Icon(
            isFiltered ? Icons.search_off_rounded : Icons.chat_bubble_outline_rounded,
            size: 64,
            color: AppColors.textTertiary.withOpacity(0.4),
          ),
          const SizedBox(height: 14),
          Center(
              child: Text(
                  isFiltered ? 'No results found' : 'No groups here yet',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontSize: 15))),
          const SizedBox(height: 6),
          Center(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
                isFiltered
                    ? 'No groups match your search or filters. Try a different keyword or clear the filter.'
                    : (_tab == 3
                        ? 'You will see invitations to event groups here'
                        : 'Join an event to start chatting with the team'),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
          )),
        ],
      );

  Widget _groupCard(Map g) {
    final lastMsg = g['last_message'] as Map?;
    final preview = lastMsg == null
        ? 'No messages yet'
        : (lastMsg['message_type'] == 'image' ? '📷 Image' : (lastMsg['content'] ?? '').toString());
    final unread = (g['unread_count'] ?? 0) as int;
    // Live closed status - derived from the event date so reschedules
    // immediately reopen the chat instead of staying locked.
    final endIso = (g['event_end_date'] ?? g['event_start_date'])?.toString();
    DateTime? endAt;
    if (endIso != null && endIso.isNotEmpty) {
      try { endAt = DateTime.parse(endIso).toLocal(); } catch (_) {}
    }
    final eventEnded = endAt != null && endAt.isBefore(DateTime.now());
    final closed = eventEnded || (g['is_closed'] == true && endAt == null);
    final imageUrl = (g['image_url'] ?? g['event_image_url'] ?? g['cover_image_url'])?.toString();
    final isAdmin = _isAdmin(g);
    final eventName = g['event_name']?.toString() ?? '';
    final senderHint = lastMsg?['sender_name'] ?? lastMsg?['sender']?['name'];
    final pinned = _isPinned(g);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EventGroupWorkspaceScreen(groupId: g['id'])),
          ).then((_) => _load(silent: true));
        },
        onLongPress: () => _togglePin(g),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              EventCoverImage(
                event: {
                  if (imageUrl != null) 'image_url': imageUrl,
                  ...g.cast<String, dynamic>(),
                },
                url: imageUrl,
                width: 52,
                height: 52,
                borderRadius: BorderRadius.circular(14),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title row: name + admin badge + lock + time aligned right (same baseline)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            g['name'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.1),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _roleBadge(isAdmin),
                        if (closed) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.lock_outline_rounded, size: 12, color: AppColors.textTertiary),
                        ],
                        const Spacer(),
                        const SizedBox(width: 8),
                        Text(
                          _timeAgo(lastMsg?['created_at'] ?? g['created_at']),
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: unread > 0 ? AppColors.primary : AppColors.textTertiary,
                              fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500),
                        ),
                      ],
                    ),
                    if (eventName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        eventName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Preview row + unread badge or pin (right-aligned)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                              children: [
                                if (senderHint != null)
                                  TextSpan(
                                    text: '$senderHint: ',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                TextSpan(text: preview),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (unread > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                            constraints: const BoxConstraints(minWidth: 20),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                  color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                            ),
                          )
                        else
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _togglePin(g),
                            onLongPress: () => _togglePin(g),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              child: SvgPicture.asset(
                                'assets/icons/pin-icon.svg',
                                width: 16,
                                height: 16,
                                colorFilter: ColorFilter.mode(
                                  pinned ? AppColors.primary : AppColors.textTertiary,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleBadge(bool isAdmin) {
    final label = isAdmin ? 'Admin' : 'Member';
    final fg = isAdmin ? AppColors.primary : AppColors.textSecondary;
    final bg = isAdmin ? AppColors.primary.withOpacity(0.12) : AppColors.borderLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 9.5, color: fg, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    );
  }
}
