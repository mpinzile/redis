import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/nuru_refresh_indicator.dart';
import '../../core/widgets/nuru_scrollable_tabs.dart';
import '../../core/services/social_service.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../providers/auth_provider.dart';

/// Community detail - pixel match to "Decorators Hub" mockup.
/// Cover image with overlapping circular avatar, verified badge,
/// underline tabs (Feed / Discussions / Resources / Events / Members / About),
/// compose row + quick actions + post stream.
class CommunityDetailScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? coverImage;

  const CommunityDetailScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.coverImage,
  });

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  static const _tabs = ['Feed', 'Discussions', 'Resources', 'Events', 'Members', 'About'];
  int _activeTab = 0;

  Map<String, dynamic>? _community;
  List<dynamic> _posts = [];
  List<dynamic> _members = [];
  bool _loading = true;
  bool _postsLoading = true;
  bool _membersLoading = true;

  // Compose state
  final TextEditingController _composeCtl = TextEditingController();
  final List<File> _composeImages = [];
  bool _posting = false;

  // Per-post optimistic state for glow / save
  final Map<String, bool> _glowed = {};
  final Map<String, int> _glowCount = {};
  final Map<String, bool> _saved = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await SocialService.getCommunityDetail(widget.communityId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final d = res['data'];
        _community = d is Map<String, dynamic>
            ? d
            : (d is Map ? Map<String, dynamic>.from(d) : null);
      }
    });
    _loadPosts();
    _loadMembers();
  }

  /// Pull-to-refresh from inside the community now only reloads the data
  /// the current tab depends on, instead of remounting the whole screen.
  Future<void> _refreshActiveTab() async {
    switch (_activeTab) {
      case 4: // Members
        await _loadMembers();
        return;
      case 5: // About - uses _community
        final res = await SocialService.getCommunityDetail(widget.communityId);
        if (!mounted) return;
        if (res['success'] == true) {
          setState(() {
            final d = res['data'];
            _community = d is Map<String, dynamic>
                ? d
                : (d is Map ? Map<String, dynamic>.from(d) : null);
          });
        }
        return;
      default: // Feed / Discussions / Resources / Events → posts stream
        await _loadPosts();
        return;
    }
  }

  @override
  void dispose() {
    _composeCtl.dispose();
    super.dispose();
  }

  // ─── Compose & interactions ────────────────────────────────────────────────

  bool get _isCreator {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final myId = auth.user?['id']?.toString();
      final creatorId = (_community?['created_by'] ?? _community?['creator_id'])?.toString();
      return myId != null && creatorId != null && myId == creatorId;
    } catch (_) {
      return false;
    }
  }

  bool get _canPost => _isCreator || (_community?['is_member'] == true);

  String? get _myUserId {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      return auth.user?['id']?.toString();
    } catch (_) {
      return null;
    }
  }

  bool _muted = false;

  Future<void> _pickComposeImages() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage(imageQuality: 85);
      if (files.isEmpty) return;
      setState(() {
        _composeImages.addAll(files.map((x) => File(x.path)));
      });
    } catch (_) {}
  }

  Future<void> _submitPost() async {
    final text = _composeCtl.text.trim();
    if (text.isEmpty && _composeImages.isEmpty) return;
    setState(() => _posting = true);

    // Backend route: POST /communities/{id}/posts (creator only).
    // SocialService doesn't expose this directly, so we call the generic
    // createPost when not the creator (falls back to global feed); use a
    // dedicated multipart for creator-only community posts.
    final ok = await SocialService.createCommunityPost(
      communityId: widget.communityId,
      content: text,
      imagePaths: _composeImages.map((f) => f.path).toList(),
    );

    if (!mounted) return;
    setState(() {
      _posting = false;
      if (ok['success'] == true) {
        _composeCtl.clear();
        _composeImages.clear();
      }
    });
    if (ok['success'] == true) {
      _loadPosts();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok['message']?.toString() ?? 'Could not post',
            style: GoogleFonts.inter(fontSize: 13)),
      ));
    }
  }

  Future<void> _toggleGlow(String postId, bool currentlyGlowed, int currentCount) async {
    setState(() {
      _glowed[postId] = !currentlyGlowed;
      _glowCount[postId] = currentlyGlowed ? (currentCount - 1).clamp(0, 999999) : currentCount + 1;
    });
    final res = currentlyGlowed
        ? await SocialService.unglowCommunityPost(widget.communityId, postId)
        : await SocialService.glowCommunityPost(widget.communityId, postId);
    if (res['success'] != true && mounted) {
      setState(() {
        _glowed[postId] = currentlyGlowed;
        _glowCount[postId] = currentCount;
      });
    }
  }

  Future<void> _toggleSave(String postId, bool currentlySaved) async {
    setState(() => _saved[postId] = !currentlySaved);
    final res = currentlySaved
        ? await SocialService.unsaveCommunityPost(widget.communityId, postId)
        : await SocialService.saveCommunityPost(widget.communityId, postId);
    if (res['success'] != true && mounted) {
      setState(() => _saved[postId] = currentlySaved);
    }
  }

  Future<void> _sharePost(Map<String, dynamic> p) async {
    final id = (p['id'] ?? '').toString();
    if (id.isEmpty) return;
    final content = (p['content']?.toString() ?? '').trim();
    final name = _community?['name']?.toString() ?? widget.communityName;
    final shareText = content.isEmpty
        ? 'Check out this post from $name on Nuru'
        : '$content\n\nShared from $name on Nuru';
    try {
      await Share.share(shareText, subject: 'Post from $name');
    } catch (_) {}
    // Record share count in background - don't reload feed (keeps post visible).
    SocialService.shareCommunityPost(widget.communityId, id);
  }

  void _showPostMenu(Map<String, dynamic> p, {required bool canEdit, required bool canDelete}) {
    final id = (p['id'] ?? '').toString();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          if (canEdit)
            _sheetTile('assets/icons/pen-icon.svg', 'Edit post', () {
              Navigator.pop(ctx);
              _editPost(p);
            }),
          _sheetTile('assets/icons/share-icon.svg', 'Share post', () {
            Navigator.pop(ctx);
            _sharePost(p);
          }),
          _sheetTile('assets/icons/bookmark-icon.svg', 'Save post', () async {
            Navigator.pop(ctx);
            await SocialService.saveCommunityPost(widget.communityId, id);
            if (mounted) setState(() => _saved[id] = true);
          }),
          if (canDelete)
            _sheetTile('assets/icons/delete-icon.svg', 'Delete post', () async {
              Navigator.pop(ctx);
              final res = await SocialService.deleteCommunityPost(widget.communityId, id);
              if (res['success'] == true) _loadPosts();
            }, danger: true),
          if (!canDelete)
            _sheetTile('assets/icons/issue-icon.svg', 'Report post', () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reported')));
            }, danger: true),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _editPost(Map<String, dynamic> p) {
    final id = (p['id'] ?? '').toString();
    final ctl = TextEditingController(text: p['content']?.toString() ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Edit post', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: ctl, maxLines: 6, autofocus: true,
            decoration: InputDecoration(
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              final newContent = ctl.text.trim();
              if (newContent.isEmpty) return;
              final res = await SocialService.updateCommunityPost(widget.communityId, id, newContent);
              if (!mounted) return;
              if (res['success'] == true) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post updated')));
                _loadPosts();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(res['message']?.toString() ?? 'Could not update post'),
                ));
              }
            },
            child: Text('Save changes', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }

  void _openCommentsSheet(Map<String, dynamic> p) {
    final id = (p['id'] ?? '').toString();
    if (id.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _CommentsSheet(
        communityId: widget.communityId,
        postId: id,
        onChanged: _loadPosts,
      ),
    );
  }
  Future<void> _loadPosts() async {
    setState(() => _postsLoading = true);
    final res = await SocialService.getCommunityPosts(widget.communityId);
    if (!mounted) return;
    setState(() {
      _postsLoading = false;
      if (res['success'] == true) {
        final d = res['data'];
        _posts = d is List ? d : (d is Map ? (d['posts'] ?? []) : []);
      }
    });
  }

  Future<void> _loadMembers() async {
    setState(() => _membersLoading = true);
    final res = await SocialService.getCommunityMembers(widget.communityId);
    if (!mounted) return;
    setState(() {
      _membersLoading = false;
      if (res['success'] == true) {
        final d = res['data'];
        _members = d is List ? d : (d is Map ? (d['members'] ?? []) : []);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _community ?? <String, dynamic>{};
    final name = c['name']?.toString() ?? widget.communityName;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: NuruSubPageAppBar(
        title: name,
        actions: [
          IconButton(
            icon: SvgPicture.asset('assets/icons/menu-icon.svg',
                width: 22, height: 22,
                colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
            onPressed: _showActionsMenu,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const NuruSkeletonList(itemCount: 6, showTrailing: true)
          : NuruRefreshIndicator(
              onRefresh: _refreshActiveTab,
              color: AppColors.primary,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _coverWithAvatar(c),
                  _headerInfo(c),
                  const SizedBox(height: 14),
                  NuruScrollableTabs(
                    labels: _tabs,
                    activeIndex: _activeTab,
                    onChanged: (i) => setState(() => _activeTab = i),
                  ),
                  const SizedBox(height: 8),
                  _tabContent(c),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ─── Cover + avatar ──────────────────────────────────────────────────────

  Widget _coverWithAvatar(Map<String, dynamic> c) {
    final cover = c['image']?.toString() ?? c['cover_image']?.toString() ?? widget.coverImage;
    return SizedBox(
      height: 188,
      child: Stack(clipBehavior: Clip.none, children: [
        // cover
        Positioned.fill(
          bottom: 38,
          child: cover != null && cover.isNotEmpty
              ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover, errorWidget: (_, __, ___) => _coverFallback())
              : _coverFallback(),
        ),
        // play badge over cover
        Positioned(
          right: 0, left: 0, top: 50,
          child: Center(
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF111114), size: 28),
            ),
          ),
        ),
        // avatar overlapping bottom-left
        Positioned(
          left: 16, bottom: 0,
          child: Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: ClipOval(
              child: cover != null && cover.isNotEmpty
                  ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover, errorWidget: (_, __, ___) => _coverFallback())
                  : _coverFallback(),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _coverFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppColors.primary.withOpacity(0.55), AppColors.primary.withOpacity(0.25)],
        ),
      ),
      child: const Center(child: Icon(Icons.groups_2_outlined, size: 36, color: Colors.white)),
    );
  }

  // ─── Header info row ─────────────────────────────────────────────────────

  Widget _headerInfo(Map<String, dynamic> c) {
    final name = c['name']?.toString() ?? widget.communityName;
    final description = c['description']?.toString() ?? '';
    final memberCount = c['member_count'] ?? c['members_count'] ?? _members.length;
    final onlineCount = c['online_count'] ?? 0;
    final isVerified = c['is_verified'] == true;
    final isMember = c['is_member'] == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                ),
                if (isVerified) ...[
                  const SizedBox(width: 8),
                  _verifiedChip(),
                ],
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(_formatMembers(memberCount) + ' Members',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(width: 6),
                Text('•', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
                const SizedBox(width: 6),
                Text('$onlineCount Online',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          _joinButton(isMember),
        ]),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(description,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
        ],
      ]),
    );
  }

  Widget _verifiedChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE8FBE9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.verified_rounded, size: 12, color: AppColors.success),
        const SizedBox(width: 4),
        Text('Verified Community',
            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.success)),
      ]),
    );
  }

  Widget _joinButton(bool isMember) {
    return GestureDetector(
      onTap: () async {
        if (isMember) {
          _showJoinedMenu();
        } else {
          await SocialService.joinCommunity(widget.communityId);
          _load();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isMember ? const Color(0xFFEFE7FF) : AppColors.primary,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(isMember ? 'Joined' : 'Join',
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: isMember ? const Color(0xFF6E3DD1) : Colors.white)),
          const SizedBox(width: 4),
          Icon(isMember ? Icons.keyboard_arrow_down_rounded : Icons.add_rounded,
              size: 16, color: isMember ? const Color(0xFF6E3DD1) : Colors.white),
        ]),
      ),
    );
  }

  void _showJoinedMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          _sheetTile('assets/icons/bell-icon.svg', _muted ? 'Unmute notifications' : 'Mute notifications', () async {
            Navigator.pop(ctx);
            final res = await SocialService.muteCommunity(widget.communityId);
            if (res['success'] == true && mounted) {
              setState(() => _muted = (res['data']?['muted'] == true));
            }
          }),
          _sheetTile('assets/icons/share-icon.svg', 'Share community', () {
            Navigator.pop(ctx);
            _shareCommunity();
          }),
          if (!_isCreator)
            _sheetTile('assets/icons/logout-icon.svg', 'Leave community', () async {
              Navigator.pop(ctx);
              final res = await SocialService.leaveCommunity(widget.communityId);
              if (!mounted) return;
              if (res['success'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Left community')));
                Navigator.of(context).maybePop();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(res['message']?.toString() ?? 'Could not leave community'),
                ));
              }
            }, danger: true),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _sheetTile(String svg, String label, VoidCallback onTap, {bool danger = false}) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return ListTile(
      leading: SvgPicture.asset(svg, width: 22, height: 22,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
      title: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      onTap: onTap,
    );
  }

  void _shareCommunity() {
    final name = _community?['name']?.toString() ?? widget.communityName;
    try {
      // ignore: avoid_print
      print('Share community: $name (${widget.communityId})');
    } catch (_) {}
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sharing $name…')));
  }

  String _formatMembers(dynamic count) {
    final n = (count is int) ? count : int.tryParse(count.toString()) ?? 0;
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return '$n';
  }

  // ─── Underline tabs ──────────────────────────────────────────────────────

  Widget _underlineTabs() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (_, i) {
          final active = _activeTab == i;
          return GestureDetector(
            onTap: () => setState(() => _activeTab = i),
            child: IntrinsicWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 12),
                Text(_tabs[i],
                    style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active ? AppColors.primary : AppColors.textTertiary)),
                const SizedBox(height: 8),
                Container(
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ─── Tab content ─────────────────────────────────────────────────────────

  Widget _tabContent(Map<String, dynamic> c) {
    switch (_activeTab) {
      case 0: return _feedTab();
      case 1: return _feedTab();  // Discussions reuses post stream + comments
      case 2: return _comingSoon('Resources', 'Files & links shared by admins.');
      case 3: return _comingSoon('Events', 'Community gatherings will appear here.');
      case 4: return _membersTab();
      case 5: return _aboutTab(c);
      default: return const SizedBox.shrink();
    }
  }

  Widget _comingSoon(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 36, 16, 24),
      child: Column(children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.auto_awesome_rounded, size: 26, color: AppColors.primary),
        ),
        const SizedBox(height: 12),
        Text(title, style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(subtitle, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textTertiary), textAlign: TextAlign.center),
      ]),
    );
  }

  // ─── Feed ───────────────────────────────────────────────────────────────

  Widget _feedTab() {
    return Column(children: [
      _composeRow(),
      const SizedBox(height: 12),
      if (_postsLoading)
        const NuruSkeletonPostList(itemCount: 3, padding: EdgeInsets.symmetric(horizontal: 16))
      else if (_posts.isEmpty)
        _comingSoon('No posts yet', 'Be the first to share with the community.')
      else
        ..._posts.map((p) => _postCard(p is Map<String, dynamic> ? p : Map<String, dynamic>.from(p as Map))),
    ]);
  }

  Widget _composeRow() {
    if (!_canPost) return const SizedBox.shrink();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final me = auth.user ?? const {};
    final myAvatar = me['avatar']?.toString() ?? me['profile_picture_url']?.toString();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEDEDF2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipOval(
              child: myAvatar != null && myAvatar.isNotEmpty
                  ? CachedNetworkImage(imageUrl: myAvatar, width: 36, height: 36, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _initials('${me['first_name'] ?? ''}', 36))
                  : _initials('${me['first_name'] ?? ''}', 36),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _composeCtl,
                minLines: 1,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                cursorColor: Colors.black,
                style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Share something with the community…',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary),
                ),
              ),
            ),
          ]),
          if (_composeImages.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _composeImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(_composeImages[i], width: 70, height: 70, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 2, top: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _composeImages.removeAt(i)),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(2),
                        child: SvgPicture.asset('assets/icons/close-icon.svg',
                            width: 12, height: 12,
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            _composeIconButton('assets/icons/image-icon.svg', 'Photo', _pickComposeImages),
            const SizedBox(width: 6),
            _composeIconButton('assets/icons/attach-icon.svg', 'Attach', _pickComposeImages),
            const Spacer(),
            GestureDetector(
              onTap: _posting ? null : _submitPost,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (_composeCtl.text.trim().isEmpty && _composeImages.isEmpty)
                      ? AppColors.primary.withOpacity(0.4)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SvgPicture.asset('assets/icons/send-icon.svg',
                      width: 14, height: 14,
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                  const SizedBox(width: 6),
                  Text(_posting ? 'Posting…' : 'Post',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _composeIconButton(String svg, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SvgPicture.asset(svg, width: 16, height: 16,
              colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn)),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _postCard(Map<String, dynamic> p) {
    final author = p['author'] is Map ? p['author'] : (p['user'] is Map ? p['user'] : {});
    final authorMap = Map<String, dynamic>.from(author as Map);
    final authorFromName = authorMap['name']?.toString().trim() ?? '';
    final authorComposed = '${authorMap['first_name'] ?? ''} ${authorMap['last_name'] ?? ''}'.trim();
    final authorName = authorFromName.isNotEmpty ? authorFromName : authorComposed;
    final authorVerified = authorMap['is_verified'] == true;
    final authorId = authorMap['id']?.toString();
    final avatar = authorMap['avatar']?.toString();
    final content = p['content']?.toString() ?? '';
    final createdAt = p['created_at']?.toString() ?? '';
    final editedAt = p['edited_at']?.toString();
    final glow = p['glow_count'] ?? p['likes_count'] ?? 0;
    final comments = p['comment_count'] ?? p['comments_count'] ?? 0;
    final shares = p['share_count'] ?? p['shares_count'] ?? 0;
    final postId = (p['id'] ?? '').toString();
    final canEdit = authorId != null && authorId == _myUserId;
    final canDelete = canEdit || _isCreator;
    final images = (p['images'] is List ? p['images'] as List : [])
        .map((i) => i is Map ? (i['url'] ?? i['image_url'] ?? '').toString() : i.toString())
        .where((u) => u.isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEDEDF2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 4, 10),
            child: Row(children: [
              ClipOval(
                child: avatar != null && avatar.isNotEmpty
                    ? CachedNetworkImage(imageUrl: avatar, width: 36, height: 36, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _initials(authorName, 36))
                    : _initials(authorName, 36),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(authorName.isNotEmpty ? authorName : 'Member',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ),
                  if (authorVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified_rounded, size: 14, color: AppColors.primary),
                  ],
                ]),
                if (createdAt.isNotEmpty)
                  Row(children: [
                    Text(SocialService.getTimeAgo(createdAt),
                        style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textTertiary)),
                    if (editedAt != null && editedAt.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('• edited',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary, fontStyle: FontStyle.italic)),
                    ],
                  ]),
              ])),
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textTertiary),
                onPressed: postId.isEmpty ? null : () => _showPostMenu(p, canEdit: canEdit, canDelete: canDelete),
              ),
            ]),
          ),
          if (content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(content,
                  style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textPrimary, height: 1.5)),
            ),
          if (images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _imageGallery(images),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Builder(builder: (_) {
              final initialGlowed = p['is_glowed'] == true || p['has_glowed'] == true;
              final glowedNow = _glowed[postId] ?? initialGlowed;
              final glowCountNow = _glowCount[postId] ?? (glow is int ? glow : int.tryParse(glow.toString()) ?? 0);
              final initialSaved = p['is_saved'] == true || p['has_saved'] == true;
              final savedNow = _saved[postId] ?? initialSaved;
              return Row(children: [
                _reactionBtn(
                  svg: glowedNow ? 'assets/icons/heart-filled-icon.svg' : 'assets/icons/heart-icon.svg',
                  value: '$glowCountNow',
                  color: glowedNow ? const Color(0xFFE53935) : AppColors.textSecondary,
                  onTap: postId.isEmpty ? null : () => _toggleGlow(postId, glowedNow, glowCountNow),
                ),
                _reactionBtn(
                  svg: 'assets/icons/echo-icon.svg',
                  value: '$comments',
                  onTap: postId.isEmpty ? null : () => _openCommentsSheet(p),
                ),
                _reactionBtn(
                  svg: 'assets/icons/share-icon.svg',
                  value: '$shares',
                  onTap: postId.isEmpty ? null : () => _sharePost(p),
                ),
                const Spacer(),
                IconButton(
                  icon: SvgPicture.asset(
                    savedNow ? 'assets/icons/bookmark-filled-icon.svg' : 'assets/icons/bookmark-icon.svg',
                    width: 20, height: 20,
                    colorFilter: ColorFilter.mode(
                        savedNow ? AppColors.primary : AppColors.textTertiary, BlendMode.srcIn),
                  ),
                  onPressed: postId.isEmpty ? null : () => _toggleSave(postId, savedNow),
                ),
              ]);
            }),
          ),
        ]),
      ),
    );
  }

  Widget _imageGallery(List<String> urls) {
    if (urls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(imageUrl: urls.first, width: double.infinity, height: 220, fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink()),
      );
    }
    final hero = urls.first;
    final rest = urls.sublist(1).take(3).toList();
    return SizedBox(
      height: 200,
      child: Row(children: [
        Expanded(
          flex: 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(imageUrl: hero, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox.shrink()),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 1,
          child: Column(children: [
            for (int i = 0; i < rest.length; i++) ...[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(imageUrl: rest[i], width: double.infinity, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox.shrink()),
                ),
              ),
              if (i < rest.length - 1) const SizedBox(height: 6),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _reactionBtn({required String svg, required String value, Color? color, VoidCallback? onTap}) {
    final c = color ?? AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TextButton.icon(
        style: TextButton.styleFrom(
            foregroundColor: c,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        onPressed: onTap ?? () {},
        icon: SvgPicture.asset(svg,
            width: 18, height: 18,
            colorFilter: ColorFilter.mode(c, BlendMode.srcIn)),
        label: Text(value, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: c)),
      ),
    );
  }

  // ─── Members ────────────────────────────────────────────────────────────

  Widget _membersTab() {
    if (_membersLoading) {
      return const NuruSkeletonList(itemCount: 6);
    }
    if (_members.isEmpty) {
      return _comingSoon('No members yet', 'Members will appear here.');
    }
    return Column(children: [
      for (final m in _members)
        _memberRow(m is Map<String, dynamic> ? m : Map<String, dynamic>.from(m as Map)),
    ]);
  }

  Widget _memberRow(Map<String, dynamic> m) {
    final name = (m['name']?.toString().trim().isNotEmpty == true)
        ? m['name'].toString()
        : '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
    final username = m['username']?.toString() ?? '';
    final avatar = m['avatar']?.toString();
    final isVerified = m['is_verified'] == true;
    final role = m['role']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        ClipOval(
          child: avatar != null && avatar.isNotEmpty
              ? CachedNetworkImage(imageUrl: avatar, width: 42, height: 42, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _initials(name, 42))
              : _initials(name, 42),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
              child: Text(name.isNotEmpty ? name : 'Member',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
            if (isVerified) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified_rounded, size: 14, color: AppColors.primary),
            ],
          ]),
          if (username.isNotEmpty)
            Text('@$username', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
        ])),
        if (role == 'admin')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
            child: Text('Admin',
                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 0.4)),
          ),
      ]),
    );
  }

  // ─── About ──────────────────────────────────────────────────────────────

  Widget _aboutTab(Map<String, dynamic> c) {
    final description = c['description']?.toString() ?? 'No description';
    final createdAt = c['created_at']?.toString() ?? '';
    final visibility = c['is_public'] == false ? 'Private' : 'Public';
    final category = c['category']?.toString() ?? '-';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _aboutCard('About', description),
        _aboutCard('Visibility', visibility),
        _aboutCard('Category', category),
        if (createdAt.isNotEmpty) _aboutCard('Created', SocialService.getTimeAgo(createdAt)),
      ]),
    );
  }

  Widget _aboutCard(String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEDF2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Text(value, style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textPrimary, height: 1.5)),
      ]),
    );
  }

  Widget _initials(String name, double size) => Container(
        width: size, height: size,
        color: AppColors.primary.withOpacity(0.18),
        alignment: Alignment.center,
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: GoogleFonts.inter(fontSize: size * 0.36, fontWeight: FontWeight.w800, color: AppColors.primary)),
      );

  void _showActionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          _sheetTile('assets/icons/share-icon.svg', 'Share community', () {
            Navigator.pop(ctx);
            _shareCommunity();
          }),
          _sheetTile('assets/icons/bell-icon.svg', _muted ? 'Unmute notifications' : 'Mute notifications', () async {
            Navigator.pop(ctx);
            final res = await SocialService.muteCommunity(widget.communityId);
            if (res['success'] == true && mounted) {
              setState(() => _muted = (res['data']?['muted'] == true));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_muted ? 'Notifications muted' : 'Notifications unmuted')),
              );
            }
          }),
          _sheetTile('assets/icons/issue-icon.svg', 'Report', () {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reported. Thank you.')));
          }, danger: true),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Comments bottom sheet
// ─────────────────────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  final String communityId;
  final String postId;
  final VoidCallback? onChanged;
  const _CommentsSheet({required this.communityId, required this.postId, this.onChanged});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  List<dynamic> _comments = [];
  bool _loading = true;
  bool _sending = false;
  final TextEditingController _ctl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await SocialService.getCommunityPostComments(widget.communityId, widget.postId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final d = res['data'];
        _comments = d is List ? d : (d is Map ? (d['comments'] ?? []) : []);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final res = await SocialService.addCommunityPostComment(widget.communityId, widget.postId, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (res['success'] == true) {
      _ctl.clear();
      await _load();
      widget.onChanged?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['message']?.toString() ?? 'Could not post comment'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text('Comments', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${_comments.length}',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textTertiary)),
            ]),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFEDEDF2)),
          Expanded(
            child: _loading
                ? const NuruSkeletonList(itemCount: 5)
                : (_comments.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          SvgPicture.asset('assets/icons/echo-icon.svg', width: 36, height: 36,
                              colorFilter: ColorFilter.mode(AppColors.textTertiary.withOpacity(0.6), BlendMode.srcIn)),
                          const SizedBox(height: 10),
                          Text('Be the first to comment',
                              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                        ]),
                      )
                    : ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _comments.length,
                        itemBuilder: (_, i) => _commentRow(Map<String, dynamic>.from(_comments[i] as Map)),
                      )),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEDEDF2))),
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ctl,
                    minLines: 1, maxLines: 4,
                    cursorColor: Colors.black,
                    style: GoogleFonts.inter(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Add a comment…',
                      hintStyle: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textTertiary),
                      filled: true, fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sending ? null : _send,
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: _sending
                        ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : Center(
                            child: SvgPicture.asset('assets/icons/send-icon.svg', width: 18, height: 18,
                                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                          ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _commentRow(Map<String, dynamic> c) {
    final user = (c['user'] is Map) ? Map<String, dynamic>.from(c['user'] as Map) : <String, dynamic>{};
    final name = (user['name']?.toString().trim().isNotEmpty == true)
        ? user['name'].toString()
        : '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
    final avatar = user['avatar']?.toString();
    final verified = user['is_verified'] == true;
    final content = c['content']?.toString() ?? '';
    final ts = c['created_at']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipOval(
          child: avatar != null && avatar.isNotEmpty
              ? CachedNetworkImage(imageUrl: avatar, width: 34, height: 34, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _initial(name))
              : _initial(name),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(name.isNotEmpty ? name : 'Member',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
                if (verified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified_rounded, size: 12, color: AppColors.primary),
                ],
                const Spacer(),
                if (ts.isNotEmpty)
                  Text(SocialService.getTimeAgo(ts),
                      style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textTertiary)),
              ]),
              const SizedBox(height: 3),
              Text(content,
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary, height: 1.4)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _initial(String name) => Container(
        width: 34, height: 34,
        color: AppColors.primary.withOpacity(0.18),
        alignment: Alignment.center,
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
      );
}
