import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/nuru_refresh_indicator.dart';
import '../../core/widgets/nuru_scrollable_tabs.dart';

import '../../core/widgets/nuru_skeleton.dart';
import '../../core/services/social_service.dart';
import '../../core/services/events_service.dart';
import '../../core/services/event_extras_service.dart';
import '../../core/services/messages_service.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../providers/auth_provider.dart';
import '../../core/widgets/nuru_search_bar.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_snackbar.dart';
import '../messages/messages_screen.dart';

/// My Circle - pixel match to mockup.
/// Black hero with circular avatar arrangement, underline tabs
/// (Members / Requests / Invitations), borderless rows, privacy notice
/// and a full-width "Invite to Circle" CTA.
class CircleScreen extends StatefulWidget {
  const CircleScreen({super.key});

  @override
  State<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends State<CircleScreen> {
  static const _tabs = ['Members', 'Requests', 'Invitations'];
  int _activeTab = 0;
  bool _privacyDismissed = false;

  Map<String, dynamic>? _me;
  List<dynamic> _circles = [];
  List<dynamic> _requests = [];
  List<dynamic> _invitations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Seed _me from AuthProvider so avatar/name show immediately even if
    // the profile endpoint is slow or fails.
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.user != null) _me = Map<String, dynamic>.from(auth.user!);
    } catch (_) {}

    final results = await Future.wait([
      SocialService.getCircles(),
      SocialService.getCircleRequests(),
      SocialService.getCircleInvitations(),
      EventsService.getProfile(),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (results[0]['success'] == true) {
        final data = results[0]['data'];
        _circles = data is List ? data : (data is Map ? (data['circles'] ?? []) : []);
      }
      if (results[1]['success'] == true) {
        final data = results[1]['data'];
        _requests = data is List ? data : (data is Map ? (data['requests'] ?? []) : []);
      }
      if (results[2]['success'] == true) {
        final data = results[2]['data'];
        _invitations = data is List ? data : (data is Map ? (data['invitations'] ?? []) : []);
      }
      if (results[3]['success'] == true) {
        final data = results[3]['data'];
        final fresh = data is Map<String, dynamic>
            ? (data['user'] is Map ? Map<String, dynamic>.from(data['user']) : data)
            : null;
        if (fresh != null) _me = {...?_me, ...fresh};
      }
    });
  }

  List<dynamic> get _members {
    if (_circles.isEmpty) return [];
    final circle = _circles[0] is Map ? _circles[0] : {};
    final members = circle['members'];
    return members is List ? members : [];
  }

  Future<void> _removeMember(String memberId) async {
    if (_circles.isEmpty) return;
    final circleId = _circles[0]['id']?.toString() ?? '';
    if (circleId.isEmpty) return;
    final res = await SocialService.removeCircleMember(circleId, memberId);
    if (res['success'] == true) _load();
  }

  Future<void> _acceptRequest(String requestId) async {
    await SocialService.acceptCircleRequest(requestId);
    _load();
  }

  Future<void> _rejectRequest(String requestId) async {
    await SocialService.rejectCircleRequest(requestId);
    _load();
  }

  Future<void> _cancelInvitation(String invitationId) async {
    await SocialService.cancelCircleInvitation(invitationId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: NuruSubPageAppBar(
        title: context.trw('my_circle'),
        actions: [
          IconButton(
            icon: SvgPicture.asset('assets/icons/plus-icon.svg',
                width: 22, height: 22,
                colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
            onPressed: _showInviteSheet,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? _CircleSkeleton()
          : Column(children: [
              Expanded(
                child: NuruRefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
                    children: [
                      _heroCard(),
                      const SizedBox(height: 18),
                      _underlineTabs(),
                      const SizedBox(height: 8),
                      const Divider(height: 1, color: Color(0xFFEDEDF2)),
                      const SizedBox(height: 8),
                      if (_activeTab == 0) ..._buildMembersTab(),
                      if (_activeTab == 1) ..._buildRequestsTab(),
                      if (_activeTab == 2) ..._buildInvitationsTab(),
                      const SizedBox(height: 14),
                      if (!_privacyDismissed) _privacyNotice(),
                    ],
                  ),
                ),
              ),
              _bottomCta(),
            ]),
    );
  }

  // ─── Hero card (black, with circular avatar arrangement) ──────────────────

  Widget _heroCard() {
    final memberCount = _members.length;
    final me = _me ?? {};
    final myAvatar = me['avatar']?.toString() ?? me['profile_picture_url']?.toString() ?? me['avatar_url']?.toString();
    final myName = '${me['first_name'] ?? ''} ${me['last_name'] ?? ''}'.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF111114),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
            width: 150,
            height: 150,
            child: _circleAvatarConstellation(myName, myAvatar),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('My Circle',
                  style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$memberCount Members',
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(height: 10),
              Text('My closest people. My\ncircle, my trust.',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.7), height: 1.4)),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  // Show a focused management action sheet (Invite, switch to
                  // Requests, Invitations) instead of the previous no-op
                  // that just re-set the already-active Members tab.
                  _showManageCircleSheet();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(11)),
                  child: Text('Manage Circle',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF111114))),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _circleAvatarConstellation(String myName, String? myAvatar) {
    // Center avatar + up to 8 small avatars arranged on a ring around it.
    final orbiters = _members.take(8).toList();
    return LayoutBuilder(builder: (ctx, constraints) {
      final size = math.min(constraints.maxWidth, constraints.maxHeight);
      final center = Offset(size / 2, size / 2);
      const orbitCount = 8;
      final orbitRadius = size * 0.40;
      const small = 26.0;
      const big = 56.0;

      final widgets = <Widget>[
        // connectors (lines + diamond beads between adjacent orbiters)
        Positioned.fill(
          child: CustomPaint(
            painter: _ConstellationPainter(
              center: center,
              radius: orbitRadius,
              count: orbitCount,
              lineColor: AppColors.primary.withOpacity(0.55),
              beadColor: AppColors.primary,
            ),
          ),
        ),
        // crown above center
        Positioned(
          left: center.dx - 9,
          top: center.dy - big / 2 - 14,
          child: SvgPicture.asset('assets/icons/crown-icon.svg',
              width: 16, height: 16,
              colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
        ),
        // center avatar
        Positioned(
          left: center.dx - big / 2,
          top: center.dy - big / 2,
          child: Container(
            width: big,
            height: big,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            padding: const EdgeInsets.all(2),
            child: ClipOval(child: _avatarImg(myAvatar, myName, big - 4)),
          ),
        ),
      ];

      for (int i = 0; i < orbitCount; i++) {
        final angle = (math.pi * 2) * (i / orbitCount) - math.pi / 2;
        final dx = center.dx + orbitRadius * math.cos(angle) - small / 2;
        final dy = center.dy + orbitRadius * math.sin(angle) - small / 2;
        Map<String, dynamic>? m;
        if (i < orbiters.length && orbiters[i] is Map) {
          m = Map<String, dynamic>.from(orbiters[i]);
        }
        final n = m == null ? '' : '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
        final av = m == null ? null : m['avatar']?.toString();
        widgets.add(Positioned(
          left: dx,
          top: dy,
          child: Container(
            width: small,
            height: small,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A1A1F),
              border: Border.all(color: const Color(0xFF111114), width: 2),
            ),
            child: ClipOval(
              child: m == null
                  ? Container(color: Colors.white.withOpacity(0.06))
                  : _avatarImg(av, n, small - 4),
            ),
          ),
        ));
      }
      return Stack(children: widgets);
    });
  }

  Widget _avatarImg(String? url, String name, double size) {
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _initials(name, size),
        placeholder: (_, __) => Container(color: Colors.white.withOpacity(0.06)),
      );
    }
    return _initials(name, size);
  }

  Widget _initials(String name, double size) => Container(
        width: size,
        height: size,
        color: AppColors.primary.withOpacity(0.18),
        alignment: Alignment.center,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: GoogleFonts.inter(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
      );

  // ─── Underline tabs ───────────────────────────────────────────────────────

  Widget _underlineTabs() {
    final labels = <String>[];
    for (int i = 0; i < _tabs.length; i++) {
      int? badge;
      if (i == 1 && _requests.isNotEmpty) badge = _requests.length;
      if (i == 2 && _invitations.isNotEmpty) badge = _invitations.length;
      labels.add(badge != null ? '${_tabs[i]} ($badge)' : _tabs[i]);
    }
    return NuruScrollableTabs(
      labels: labels,
      activeIndex: _activeTab,
      onChanged: (i) => setState(() => _activeTab = i),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }


  // ─── Tab content ──────────────────────────────────────────────────────────

  List<Widget> _buildMembersTab() {
    final widgets = <Widget>[];
    // Always show "You" first (Circle Owner)
    widgets.add(_youRow());
    if (_members.isEmpty) {
      widgets.add(const SizedBox(height: 30));
      widgets.add(_empty('users', 'No members yet', 'Invite friends to your circle'));
    } else {
      for (final m in _members) {
        widgets.add(_memberRow(m is Map<String, dynamic> ? m : <String, dynamic>{}));
      }
    }
    return widgets;
  }

  List<Widget> _buildRequestsTab() {
    if (_requests.isEmpty) {
      return [const SizedBox(height: 30), _empty('bell', 'No pending requests', 'New requests will appear here')];
    }
    return _requests
        .map((r) => _requestRow(r is Map<String, dynamic> ? r : <String, dynamic>{}))
        .toList();
  }

  List<Widget> _buildInvitationsTab() {
    if (_invitations.isEmpty) {
      return [const SizedBox(height: 30), _empty('email', 'No invitations sent', 'People you invite show up here')];
    }
    return _invitations
        .map((r) => _invitationRow(r is Map<String, dynamic> ? r : <String, dynamic>{}))
        .toList();
  }

  Widget _youRow() {
    final me = _me ?? {};
    final myAvatar = me['avatar']?.toString() ?? me['profile_picture_url']?.toString() ?? me['avatar_url']?.toString();
    final myName = '${me['first_name'] ?? ''} ${me['last_name'] ?? ''}'.trim();
    final username = me['username']?.toString() ?? '';
    final subtitle = username.isNotEmpty
        ? '@$username'
        : (me['email']?.toString() ?? '');

    return _row(
      avatarUrl: myAvatar,
      name: myName.isNotEmpty ? myName : 'You',
      titleSuffix: _ownerBadge(),
      subtitle: subtitle,
      onlineDot: true,
      trailing: _moreDots(onTap: () {}),
      youLabel: false,
    );
  }

  Widget _ownerBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEFE7FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('Circle Owner',
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF6E3DD1))),
    );
  }

  Widget _memberRow(Map<String, dynamic> m) {
    final name = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
    final avatar = m['avatar']?.toString();
    final id = m['id']?.toString() ?? '';
    final addedAt = m['added_at']?.toString();
    final subtitle = addedAt != null && addedAt.isNotEmpty
        ? 'Joined ${SocialService.getTimeAgo(addedAt)}'
        : (m['username'] != null ? '@${m['username']}' : '');

    return _row(
      avatarUrl: avatar,
      name: name.isNotEmpty ? name : 'Unknown',
      subtitle: subtitle,
      trailing: _moreDots(onTap: () => _showMemberMenu(id, name.isNotEmpty ? name : 'Unknown', avatar)),
    );
  }

  Widget _requestRow(Map<String, dynamic> r) {
    final name = '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
    final avatar = r['avatar']?.toString();
    final reqId = r['request_id']?.toString() ?? r['id']?.toString() ?? '';
    return _row(
      avatarUrl: avatar,
      name: name.isNotEmpty ? name : 'Unknown',
      subtitle: 'Wants to join your circle',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _miniBtn('Accept', AppColors.primary, Colors.white, () => _acceptRequest(reqId)),
        const SizedBox(width: 6),
        _miniBtn('Decline', Colors.white, AppColors.textSecondary, () => _rejectRequest(reqId), bordered: true),
      ]),
    );
  }

  Widget _invitationRow(Map<String, dynamic> r) {
    final name = '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
    final avatar = r['avatar']?.toString();
    final invId = r['invitation_id']?.toString() ?? '';
    final sentAt = r['sent_at']?.toString();
    return _row(
      avatarUrl: avatar,
      name: name.isNotEmpty ? name : 'Unknown',
      subtitle: sentAt != null && sentAt.isNotEmpty
          ? 'Invited ${SocialService.getTimeAgo(sentAt)}'
          : 'Invitation pending',
      trailing: _miniBtn('Cancel', Colors.white, AppColors.textSecondary,
          () => _cancelInvitation(invId), bordered: true),
    );
  }

  Widget _row({
    required String? avatarUrl,
    required String name,
    String? subtitle,
    Widget? titleSuffix,
    Widget? trailing,
    bool onlineDot = false,
    bool youLabel = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(children: [
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(children: [
            ClipOval(child: _avatarImg(avatarUrl, name, 44)),
            if (onlineDot)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(
                  name.isEmpty ? 'You' : name,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              if (titleSuffix != null) titleSuffix,
            ]),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
            ],
          ]),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget _miniBtn(String label, Color bg, Color fg, VoidCallback onTap, {bool bordered = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9),
          border: bordered ? Border.all(color: const Color(0xFFEDEDF2)) : null,
        ),
        child: Text(label,
            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }

  Widget _moreDots({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: SvgPicture.asset('assets/icons/more-vertical-icon.svg',
            width: 18, height: 18,
            colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
      ),
    );
  }

  void _showMemberMenu(String id, String name, [String? avatar]) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(name, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
            const SizedBox(height: 8),
            _menuTile('user', 'View profile', () => Navigator.pop(ctx)),
            _menuTile('chat', 'Send a message', () { Navigator.pop(ctx); if (id.isNotEmpty) _showComposeSheet(id, name, avatar); }),
            _menuTile('delete', 'Remove from circle', () { Navigator.pop(ctx); if (id.isNotEmpty) _removeMember(id); }, danger: true),
          ]),
        ),
      ),
    );
  }

  // ─── Compose & start conversation ────────────────────────────────────────
  void _showComposeSheet(String userId, String name, String? avatar) {
    final ctrl = TextEditingController();
    final focus = FocusNode();
    bool sending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> doSend() async {
            final text = ctrl.text.trim();
            if (text.isEmpty || sending) return;
            setSheet(() => sending = true);
            // Always start (or fetch existing) conversation first, then send
            // the message explicitly so it works both for brand-new and
            // existing conversations (the backend only persists `message` for
            // newly created ones).
            final res = await MessagesService.startConversation(
              recipientId: userId,
            );
            if (!mounted) return;
            if (res['success'] != true || res['data'] == null) {
              setSheet(() => sending = false);
              AppSnackbar.error(context, res['message']?.toString() ?? 'Failed to send message');
              return;
            }
            final convId = res['data']['id']?.toString();
            if (convId == null) {
              setSheet(() => sending = false);
              AppSnackbar.error(context, 'Failed to send message');
              return;
            }
            final sendRes = await MessagesService.sendMessage(
              convId,
              content: text,
            );
            if (!mounted) return;
            if (sendRes['success'] != true) {
              setSheet(() => sending = false);
              AppSnackbar.error(context, sendRes['message']?.toString() ?? 'Failed to send message');
              return;
            }
            Navigator.pop(ctx);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatDetailScreen(
                  conversationId: convId,
                  name: name,
                  avatar: avatar,
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                      clipBehavior: Clip.antiAlias,
                      child: (avatar != null && avatar.isNotEmpty)
                          ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Center(child: Text(
                                name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.primary))))
                          : Center(child: Text(
                              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.primary))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Message $name',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text('Starts a private chat',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
                    ])),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(color: const Color(0xFFF2F2F4), borderRadius: BorderRadius.circular(10)),
                        child: const Center(child: AppIcon('close', size: 14, color: AppColors.textSecondary)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  TextField(
                    controller: ctrl,
                    focusNode: focus,
                    autofocus: true,
                    autocorrect: true,
                    enableSuggestions: true,
                    maxLines: 6,
                    minLines: 4,
                    textInputAction: TextInputAction.newline,
                    style: GoogleFonts.inter(fontSize: 14.5, color: AppColors.textPrimary, height: 1.45),
                    decoration: InputDecoration(
                      hintText: 'Write a message…',
                      hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textHint),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border, width: 1)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border, width: 1)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                    onChanged: (_) => setSheet(() {}),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Text(
                      'Be kind. Your message starts a new chat with $name.',
                      style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textTertiary),
                    )),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: ctrl.text.trim().isEmpty || sending ? null : doSend,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: ctrl.text.trim().isEmpty || sending
                              ? AppColors.primary.withOpacity(0.35)
                              : AppColors.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (sending)
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                          else
                            const AppIcon('send', size: 14, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(sending ? 'Sending…' : 'Send',
                              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
                        ]),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          );
        });
      },
    );
  }

  Widget _menuTile(String icon, String label, VoidCallback onTap, {bool danger = false}) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: danger ? AppColors.error.withOpacity(0.08) : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: SvgPicture.asset('assets/icons/$icon-icon.svg',
                width: 18, height: 18,
                colorFilter: ColorFilter.mode(danger ? AppColors.error : AppColors.primary, BlendMode.srcIn))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(label,
              style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: color))),
          SvgPicture.asset('assets/icons/chevron-right-icon.svg',
              width: 14, height: 14,
              colorFilter: ColorFilter.mode(color.withOpacity(0.4), BlendMode.srcIn)),
        ]),
      ),
    );
  }

  // ─── Privacy notice + bottom CTA ─────────────────────────────────────────

  Widget _privacyNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFCE7A8)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
            child: const Center(
              child: AppIcon('shield', size: 16, color: AppColors.primaryDark),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your circle is private',
                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text("Only members can see who's in the circle and what's shared.",
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
          ])),
          GestureDetector(
            onTap: () => setState(() => _privacyDismissed = true),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: AppIcon('close', size: 14, color: AppColors.textSecondary),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _bottomCta() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: GestureDetector(
          onTap: _showInviteSheet,
          child: Container(
            height: 52,
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const AppIcon('plus', size: 18, color: Color(0xFF111114)),
              const SizedBox(width: 6),
              Text('Invite to Circle',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF111114))),
            ]),
          ),
        ),
      ),
    );
  }

  void _showInviteSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _InviteToCircleSheet(onInvited: _load),
    );
  }

  /// Bottom sheet shown when the user taps the "Manage Circle" CTA on the
  /// hero card. Provides quick access to the three management surfaces
  /// already implemented in this screen (Members tab, Requests tab,
  /// Invitations tab) plus the existing invite flow.
  void _showManageCircleSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: const Color(0xFFE5E5EA),
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Manage Circle',
                  style: GoogleFonts.inter(
                      fontSize: 17, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Quick actions for your inner circle.',
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: AppColors.textTertiary)),
              const SizedBox(height: 14),
              _manageRow(ctx,
                  iconAsset: 'assets/icons/contributors-icon.svg',
                  label: 'View members',
                  subtitle: '${_members.length} in your circle',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _activeTab = 0);
                  }),
              _manageRow(ctx,
                  iconAsset: 'assets/icons/plus-icon.svg',
                  label: 'Invite someone',
                  subtitle: 'Send a circle invitation',
                  onTap: () { Navigator.pop(ctx); _showInviteSheet(); }),
              _manageRow(ctx,
                  iconAsset: 'assets/icons/bell-icon.svg',
                  label: 'Requests',
                  subtitle: 'People asking to join',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _activeTab = 1);
                  }),
              _manageRow(ctx,
                  iconAsset: 'assets/icons/send-icon.svg',
                  label: 'Sent invitations',
                  subtitle: 'Track invites you sent',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _activeTab = 2);
                  }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _manageRow(BuildContext ctx, {
    required String iconAsset,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: SvgPicture.asset(iconAsset,
                  width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(
                      AppColors.primary, BlendMode.srcIn)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
          ),
          SvgPicture.asset('assets/icons/chevron-right-icon.svg',
              width: 16, height: 16,
              colorFilter: const ColorFilter.mode(
                  AppColors.textTertiary, BlendMode.srcIn)),
        ]),
      ),
    );
  }

  Widget _empty(String icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(18)),
          child: Center(child: AppIcon(icon, size: 24, color: AppColors.primary)),
        ),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textTertiary)),
      ]),
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final int count;
  final Color lineColor;
  final Color beadColor;

  _ConstellationPainter({
    required this.center,
    required this.radius,
    required this.count,
    required this.lineColor,
    required this.beadColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final points = <Offset>[];
    for (int i = 0; i < count; i++) {
      final angle = (math.pi * 2) * (i / count) - math.pi / 2;
      points.add(Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      ));
    }

    canvas.drawCircle(center, radius, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter old) =>
      old.center != center || old.radius != radius || old.count != count;
}

/// Bottom sheet with a real, live user search input for inviting people to
/// the user's circle. Mirrors the look & feel of the global search screen.
class _InviteToCircleSheet extends StatefulWidget {
  final VoidCallback onInvited;
  const _InviteToCircleSheet({required this.onInvited});

  @override
  State<_InviteToCircleSheet> createState() => _InviteToCircleSheetState();
}

class _InviteToCircleSheetState extends State<_InviteToCircleSheet> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<dynamic> _results = [];
  bool _loading = false;
  String _query = '';
  final Set<String> _sending = {};
  final Set<String> _invited = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() => _query = q);
    if (q.isEmpty) {
      setState(() { _results = []; _loading = false; });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final res = await EventExtrasService.searchUsers(q, limit: 20);
    if (!mounted || _query != q) return;
    List<dynamic> items = const [];
    final data = res['data'];
    if (data is List) {
      items = data;
    } else if (data is Map) {
      for (final k in ['items', 'users', 'results']) {
        final v = data[k];
        if (v is List) { items = v; break; }
      }
    } else {
      for (final k in ['items', 'users', 'results']) {
        final v = res[k];
        if (v is List) { items = v; break; }
      }
    }
    setState(() { _results = items; _loading = false; });
  }

  Future<void> _invite(Map<String, dynamic> user) async {
    final id = user['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _sending.add(id));
    final res = await SocialService.addCircleMember('me', id);
    if (!mounted) return;
    setState(() => _sending.remove(id));
    final ok = res['success'] == true;
    if (ok) {
      setState(() => _invited.add(id));
      widget.onInvited();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['message']?.toString() ?? (ok ? 'Invitation sent' : 'Unable to send invite')),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxH = media.size.height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Text('Invite to Circle', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Search a friend by name or username.',
                style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            NuruSearchBar(
              controller: _ctrl,
              focusNode: _focus,
              hintText: 'Find a friend',
              debounce: const Duration(milliseconds: 300),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 12),
            Flexible(child: _buildResults()),
          ]),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_query.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Start typing to search people',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary)),
        ),
      );
    }
    if (_loading && _results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No people match "$_query"',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary)),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F2)),
      itemBuilder: (_, i) {
        final u = (_results[i] as Map).cast<String, dynamic>();
        final id = u['id']?.toString() ?? '';
        final rawName = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
        final name = u['full_name']?.toString() ?? (rawName.isNotEmpty ? rawName : (u['username']?.toString() ?? 'Unknown'));
        final username = u['username']?.toString() ?? '';
        final avatar = (u['avatar'] ?? u['profile_picture_url'])?.toString();
        final sending = _sending.contains(id);
        final invited = _invited.contains(id);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFF1F1F3),
            backgroundImage: (avatar != null && avatar.isNotEmpty) ? CachedNetworkImageProvider(avatar) : null,
            child: (avatar == null || avatar.isEmpty)
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary))
                : null,
          ),
          title: Text(name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          subtitle: username.isNotEmpty
              ? Text('@$username', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary))
              : null,
          trailing: SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: (sending || invited) ? null : () => _invite(u),
              style: ElevatedButton.styleFrom(
                backgroundColor: invited ? const Color(0xFFE9F8EE) : Colors.black,
                foregroundColor: invited ? const Color(0xFF1E8E3E) : Colors.white,
                disabledBackgroundColor: invited ? const Color(0xFFE9F8EE) : const Color(0xFFE5E5EA),
                disabledForegroundColor: invited ? const Color(0xFF1E8E3E) : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                textStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              child: sending
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(invited ? 'Invited' : 'Invite'),
            ),
          ),
        );
      },
    );
  }
}

// ─── Skeleton mirroring the Circle screen layout ─────────────────────
class _CircleSkeleton extends StatefulWidget {
  @override
  State<_CircleSkeleton> createState() => _CircleSkeletonState();
}

class _CircleSkeletonState extends State<_CircleSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _box(double w, double h, {double r = 6}) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Color.lerp(
              const Color(0xFFEDEEF1), const Color(0xFFF6F7F9), _ctrl.value)!,
          borderRadius: BorderRadius.circular(r),
        ),
      ),
    );
  }

  Widget _circle(double d) => _box(d, d, r: d / 2);

  Widget _memberRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _circle(44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _box(140, 13),
                  const SizedBox(height: 8),
                  _box(90, 11),
                ],
              ),
            ),
            _box(22, 22, r: 6),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Hero card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.borderLight),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _circle(56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _box(160, 16),
                        const SizedBox(height: 8),
                        _box(110, 12),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _box(double.infinity, 44, r: 12)),
                  const SizedBox(width: 10),
                  _box(44, 44, r: 12),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Tabs
        Row(
          children: [
            _box(80, 28, r: 14),
            const SizedBox(width: 10),
            _box(96, 28, r: 14),
            const SizedBox(width: 10),
            _box(72, 28, r: 14),
          ],
        ),
        const SizedBox(height: 12),
        // Member rows
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.borderLight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: List.generate(
              6,
              (i) => Column(
                children: [
                  if (i > 0)
                    Divider(height: 1, color: AppColors.borderLight),
                  _memberRow(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
