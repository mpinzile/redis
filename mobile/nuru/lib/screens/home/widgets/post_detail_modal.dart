import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/share_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/social_service.dart';
import '../../../core/widgets/nuru_video_player.dart';
import '../../../core/widgets/image_gallery_viewer.dart';
import '../../../core/widgets/event_cover_image.dart';
import '../../../core/l10n/l10n_helper.dart';
import '../../events/event_public_view_screen.dart';

/// Full-screen modal for post detail with scrollable echoes - matches web PostDetail
class PostDetailModal extends StatefulWidget {
  final Map<String, dynamic> post;

  const PostDetailModal({super.key, required this.post});

  static Future<void> show(BuildContext context, Map<String, dynamic> post) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PostDetailModal(post: post),
    );
  }

  @override
  State<PostDetailModal> createState() => _PostDetailModalState();
}

class _PostDetailModalState extends State<PostDetailModal> {
  late Map<String, dynamic> _post;
  List<dynamic> _comments = [];
  bool _commentsLoading = true;
  bool _glowed = false;
  int _glowCount = 0;
  bool _saved = false;
  int _commentCount = 0;
  final _commentController = TextEditingController();
  bool _sending = false;
  String? _replyToId;
  String? _replyToName;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _glowed = _post['has_glowed'] == true;
    _glowCount = (_post['glow_count'] ?? 0) as int;
    _saved = _post['has_saved'] == true;
    _commentCount = (_post['comment_count'] ?? _post['echo_count'] ?? 0) as int;
    _fetchPost();
    _fetchComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _postId => _post['id']?.toString() ?? '';

  Future<void> _fetchPost() async {
    if (_postId.isEmpty) return;
    final res = await SocialService.getPost(_postId);
    if (mounted && res['success'] == true && res['data'] != null) {
      setState(() {
        _post = res['data'] as Map<String, dynamic>;
        _glowed = _post['has_glowed'] == true;
        _glowCount = (_post['glow_count'] ?? 0) as int;
        _saved = _post['has_saved'] == true;
        _commentCount = (_post['comment_count'] ?? _post['echo_count'] ?? 0) as int;
      });
    }
  }

  Future<void> _fetchComments() async {
    if (_postId.isEmpty) return;
    setState(() => _commentsLoading = true);
    final res = await SocialService.getComments(_postId, limit: 50);
    if (mounted) {
      setState(() {
        _commentsLoading = false;
        if (res['success'] == true) {
          final data = res['data'];
          _comments = data is Map ? (data['comments'] ?? data['items'] ?? []) : (data is List ? data : []);
        }
      });
    }
  }

  // Author helpers
  String get _authorName {
    final author = _post['author'];
    final user = _post['user'];
    if (author is Map && (author['name'] ?? '').toString().isNotEmpty) return author['name'];
    if (user is Map) {
      final fn = user['first_name'] ?? '';
      final ln = user['last_name'] ?? '';
      final full = '$fn $ln'.trim();
      if (full.isNotEmpty) return full;
    }
    return 'Anonymous';
  }

  String? get _authorAvatar {
    final author = _post['author'];
    final user = _post['user'];
    return (author is Map ? author['avatar'] : null) ?? (user is Map ? user['avatar'] : null);
  }

  bool get _isVerified {
    final user = _post['user'];
    final author = _post['author'];
    return (user is Map ? user['is_identity_verified'] : false) == true ||
        (author is Map ? author['is_verified'] : false) == true;
  }

  String get _timeAgo => SocialService.getTimeAgo(_post['created_at']?.toString() ?? '');
  String get _title => (_post['title'] ?? '').toString().trim();
  String get _content => (_post['content'] ?? '').toString().trim();

  List<String> get _images {
    final imgs = _post['images'] ?? _post['media'] ?? [];
    if (imgs is! List) return [];
    return imgs.map<String>((img) {
      if (img is String) return img;
      if (img is Map) return (img['image_url'] ?? img['url'] ?? '').toString();
      return '';
    }).where((s) => s.isNotEmpty).toList();
  }

  List<String> get _mediaTypes {
    final imgs = _post['images'] ?? _post['media'] ?? [];
    if (imgs is! List) return [];
    return imgs.map<String>((img) {
      if (img is String) return '';
      if (img is Map) return (img['media_type'] ?? img['type'] ?? '').toString();
      return '';
    }).toList();
  }

  Map<String, dynamic>? get _sharedEvent {
    final se = _post['shared_event'] ?? _post['event'];
    if (se is Map) return Map<String, dynamic>.from(se);
    return null;
  }

  bool get _isEventShare =>
      _post['post_type']?.toString() == 'event_share' && _sharedEvent != null;

  Future<void> _handleGlow() async {
    HapticFeedback.lightImpact();
    final was = _glowed;
    setState(() { _glowed = !was; _glowCount += was ? -1 : 1; });
    try {
      if (was) { await SocialService.unglowPost(_postId); }
      else { await SocialService.glowPost(_postId); }
    } catch (_) {
      if (mounted) setState(() { _glowed = was; _glowCount += was ? 1 : -1; });
    }
  }

  Future<void> _handleSave() async {
    HapticFeedback.lightImpact();
    final was = _saved;
    setState(() => _saved = !was);
    try {
      if (was) { await SocialService.unsavePost(_postId); }
      else { await SocialService.savePost(_postId); }
    } catch (_) {
      if (mounted) setState(() => _saved = was);
    }
  }

  Future<void> _handleShare() async {
    HapticFeedback.lightImpact();
    final shareUrl = 'https://nuru.tz/shared/post/$_postId';
    final shareText = _content.isNotEmpty ? '$_content\n\n$shareUrl' : 'Check out this on Nuru!\n$shareUrl';
    await Share.share(shareText, sharePositionOrigin: sharePositionOrigin(context));
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final res = await SocialService.addComment(_postId, text, parentId: _replyToId);
    if (mounted) {
      setState(() => _sending = false);
      if (res['success'] == true) {
        _commentController.clear();
        setState(() { _replyToId = null; _replyToName = null; _commentCount++; });
        await _fetchComments();
        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(_scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text('Moment', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: SvgPicture.asset('assets/icons/chevron-left-icon.svg', width: 22, height: 22,
                    colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn)),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.borderLight, height: 1),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author row
                  _buildAuthorRow(),
                  const SizedBox(height: 12),

                  // Content
                  if (_title.isNotEmpty)
                    Text(_title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.3)),
                  if (_title.isNotEmpty && _content.isNotEmpty) const SizedBox(height: 6),
                  if (_content.isNotEmpty)
                    Text(_content, style: GoogleFonts.inter(fontSize: 15, color: AppColors.textPrimary, height: 1.6)),

                  // Shared event card (event_share posts)
                  if (_isEventShare) ...[
                    const SizedBox(height: 12),
                    _buildSharedEventCard(),
                  ],

                  // Media
                  if (_images.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildMediaSection(),
                  ],

                  const SizedBox(height: 14),

                  // Actions row
                  _buildActionsRow(),

                  const SizedBox(height: 16),
                  const Divider(color: AppColors.borderLight, height: 1),
                  const SizedBox(height: 16),

                  // Echoes header
                  Text('$_commentCount ${_commentCount == 1 ? 'Echo' : 'Echoes'}',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),

                  // Echoes list
                  if (_commentsLoading)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                  else if (_comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            SvgPicture.asset('assets/icons/echo-icon.svg', width: 32, height: 32,
                              colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
                            const SizedBox(height: 8),
                            Text('No echoes yet', style: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary)),
                            Text('Be the first to share your thoughts', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textHint)),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._comments.map((c) => _EchoItemWidget(
                      comment: c is Map<String, dynamic> ? c : {},
                      postId: _postId,
                      onReply: (id, name) {
                        setState(() { _replyToId = id; _replyToName = name; });
                        _commentController.clear();
                      },
                      onDeleted: () { setState(() => _commentCount--); _fetchComments(); },
                    )),
                ],
              ),
            ),
          ),

          // Comment input bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset > 0 ? bottomInset + 8 : MediaQuery.of(context).padding.bottom + 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.borderLight, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyToName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Text('Replying to ', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
                        Text(_replyToName!, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() { _replyToId = null; _replyToName = null; }),
                          child: SvgPicture.asset('assets/icons/close-icon.svg', width: 14, height: 14,
                            colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
                        ),
                      ],
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
                  ),
                  padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            controller: _commentController,
                            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                            cursorColor: AppColors.primary,
                            decoration: InputDecoration(
                              hintText: _replyToName != null ? 'Write a reply...' : 'Write an echo...',
                              hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textHint),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendComment(),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _sendComment,
                        child: Container(
                          width: 40, height: 40,
                          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          child: Center(
                            child: _sending
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : SvgPicture.asset('assets/icons/send-icon.svg', width: 18, height: 18,
                                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorRow() {
    final avatar = _authorAvatar;
    final hasAvatar = avatar != null && avatar.isNotEmpty;

    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.border, width: 1)),
          child: ClipOval(
            child: SizedBox(
              width: 40, height: 40,
              child: hasAvatar
                  ? CachedNetworkImage(imageUrl: avatar!, fit: BoxFit.cover, errorWidget: (_, __, ___) => _initialsCircle(_authorName))
                  : _initialsCircle(_authorName),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text(_authorName, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (_isVerified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified_rounded, size: 14, color: AppColors.primary),
                ],
              ]),
              Text(_timeAgo, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
            ],
          ),
        ),
        GestureDetector(
          onTap: _handleSave,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: SvgPicture.asset(
              _saved ? 'assets/icons/bookmark-filled-icon.svg' : 'assets/icons/bookmark-icon.svg',
              width: 22, height: 22,
              colorFilter: ColorFilter.mode(_saved ? AppColors.primary : AppColors.textHint, BlendMode.srcIn),
            ),
          ),
        ),
      ],
    );
  }

  Widget _initialsCircle(String name) {
    final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(child: Text(initials, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
    );
  }

  Widget _buildMediaSection() {
    final images = _images;
    final types = _mediaTypes;

    void openAt(int idx) {
      ImageGalleryViewer.open(context, urls: images, mediaTypes: types, initialIndex: idx);
    }

    if (images.length == 1) {
      final isVideo = types.isNotEmpty && (types[0].contains('video') || images[0].endsWith('.mp4') || images[0].endsWith('.mov'));
      if (isVideo) return NuruVideoPlayer(url: images[0], height: 260, borderRadius: BorderRadius.circular(12));
      return GestureDetector(
        onTap: () => openAt(0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: CachedNetworkImage(imageUrl: images[0], width: double.infinity, fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorWidget: (_, __, ___) => Container(height: 200, color: AppColors.surfaceVariant)),
          ),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final isVideo = i < types.length && (types[i].contains('video') || images[i].endsWith('.mp4'));
          if (isVideo) return SizedBox(width: 260, child: NuruVideoPlayer(url: images[i], height: 200, borderRadius: BorderRadius.circular(12)));
          return GestureDetector(
            onTap: () => openAt(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(imageUrl: images[i], width: 200, height: 200, fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorWidget: (_, __, ___) => Container(width: 200, height: 200, color: AppColors.surfaceVariant)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSharedEventCard() {
    final event = _sharedEvent!;
    final title = (event['title'] ?? 'Event').toString();
    final desc = (event['description'] ?? '').toString();
    final date = (event['start_date'] ?? '').toString();
    final loc = (event['location'] ?? '').toString();
    final type = (event['event_type'] ?? '').toString();
    final cover = event['cover_image']?.toString();
    final imgs = (event['images'] as List?)?.cast<dynamic>() ?? const [];
    final heroUrl = imgs.isNotEmpty ? imgs.first.toString() : cover;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          SizedBox(
            height: 180, width: double.infinity,
            child: EventCoverImage(event: event, url: heroUrl, fit: BoxFit.cover),
          ),
          if (type.isNotEmpty)
            Positioned(
              top: 10, left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                child: Text(type, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary, height: 1.4)),
            ],
            const SizedBox(height: 10),
            if (date.isNotEmpty) _evtMeta(Icons.calendar_today_outlined, date),
            if (loc.isNotEmpty) _evtMeta(Icons.place_outlined, loc),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  final id = event['id']?.toString();
                  if (id == null || id.isEmpty) return;
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => EventPublicViewScreen(eventId: id, initialData: event),
                  ));
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Text('View Event Details', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _evtMeta(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary))),
      ]),
    );
  }

  Widget _buildActionsRow() {
    return Row(
      children: [
        _actionBtn(
          svgAsset: _glowed ? 'assets/icons/heart-filled-icon.svg' : 'assets/icons/heart-icon.svg',
          label: '$_glowCount ${_glowCount == 1 ? 'Glow' : 'Glows'}',
          onTap: _handleGlow,
          color: _glowed ? AppColors.error : AppColors.textTertiary,
        ),
        const SizedBox(width: 20),
        _actionBtn(
          svgAsset: 'assets/icons/echo-icon.svg',
          label: '$_commentCount ${_commentCount == 1 ? 'Echo' : 'Echoes'}',
          onTap: () {},
          color: AppColors.textTertiary,
        ),
        const SizedBox(width: 20),
        _actionBtn(
          svgAsset: 'assets/icons/share-icon.svg',
          label: 'Spark',
          onTap: _handleShare,
          color: AppColors.textTertiary,
        ),
      ],
    );
  }

  Widget _actionBtn({required String svgAsset, required String label, required VoidCallback onTap, required Color color}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(svgAsset, width: 20, height: 20, colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

// Single Echo (Comment) Widget - threaded with replies
class _EchoItemWidget extends StatefulWidget {
  final Map<String, dynamic> comment;
  final String postId;
  final void Function(String id, String name) onReply;
  final VoidCallback onDeleted;
  final int depth;

  const _EchoItemWidget({required this.comment, required this.postId, required this.onReply, required this.onDeleted, this.depth = 0});

  @override
  State<_EchoItemWidget> createState() => _EchoItemWidgetState();
}

class _EchoItemWidgetState extends State<_EchoItemWidget> {
  bool _showReplies = false;
  List<dynamic> _replies = [];
  bool _loadingReplies = false;
  bool _repliesLoaded = false;

  String get _name {
    final u = widget.comment['user'] ?? widget.comment['author'] ?? {};
    if (u is! Map) return 'User';
    final fn = u['first_name'] ?? '';
    final ln = u['last_name'] ?? '';
    final full = '$fn $ln'.trim();
    return full.isNotEmpty ? full : (u['name'] ?? u['username'] ?? 'User').toString();
  }

  String? get _avatar {
    final u = widget.comment['user'] ?? widget.comment['author'];
    return u is Map ? u['avatar']?.toString() : null;
  }

  bool get _verified {
    final u = widget.comment['user'] ?? widget.comment['author'];
    return u is Map && (u['is_identity_verified'] == true || u['is_verified'] == true);
  }

  String get _timeAgo => SocialService.getTimeAgo(widget.comment['created_at']?.toString() ?? '');
  String get _content => (widget.comment['content'] ?? widget.comment['text'] ?? '').toString();
  int get _replyCount => (widget.comment['reply_count'] ?? 0) as int;
  int get _glowCount => (widget.comment['glow_count'] ?? 0) as int;

  Future<void> _loadReplies() async {
    if (_repliesLoaded) {
      setState(() => _showReplies = !_showReplies);
      return;
    }
    setState(() => _loadingReplies = true);
    final res = await SocialService.getComments(widget.postId, parentId: widget.comment['id']?.toString());
    if (mounted) {
      final data = res['data'];
      final items = data is Map ? (data['comments'] ?? data['items'] ?? []) : (data is List ? data : []);
      setState(() {
        _replies = items is List ? items : [];
        _repliesLoaded = true;
        _showReplies = true;
        _loadingReplies = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = _avatar != null && _avatar!.isNotEmpty;
    final leftPadding = widget.depth > 0 ? 28.0 * widget.depth.clamp(0, 4) : 0.0;

    return Padding(
      padding: EdgeInsets.only(left: leftPadding, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.borderLight, width: 1)),
                child: ClipOval(
                  child: SizedBox(
                    width: 32, height: 32,
                    child: hasAvatar
                        ? CachedNetworkImage(imageUrl: _avatar!, fit: BoxFit.cover, errorWidget: (_, __, ___) => _initialsFallback())
                        : _initialsFallback(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(_name, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                        // Verification badge removed
                        const SizedBox(width: 6),
                        Text(_timeAgo, style: GoogleFonts.inter(fontSize: 10, color: AppColors.textHint)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(_content, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary, height: 1.5)),
                    const SizedBox(height: 6),
                    // Actions
                    Row(
                      children: [
                        // Match the main Glow action icon so glow visuals stay
                        // consistent across the moment and its replies.
                        SvgPicture.asset(
                          'assets/icons/heart-icon.svg',
                          width: 12,
                          height: 12,
                          colorFilter: const ColorFilter.mode(
                              AppColors.textTertiary, BlendMode.srcIn),
                        ),
                        const SizedBox(width: 4),
                        Text('$_glowCount',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: AppColors.textTertiary)),
                        const SizedBox(width: 16),
                        if (widget.depth < 4)
                          GestureDetector(
                            onTap: () => widget.onReply(widget.comment['id']?.toString() ?? '', _name),
                            child: Text('Reply', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                          ),
                      ],
                    ),
                    // Show replies toggle
                    if (_replyCount > 0 && !_showReplies)
                      GestureDetector(
                        onTap: _loadReplies,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _loadingReplies
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary))
                              : Text('View $_replyCount ${_replyCount == 1 ? 'reply' : 'replies'}',
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                        ),
                      ),
                    if (_showReplies && _replies.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _showReplies = false),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Hide replies', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Nested replies
          if (_showReplies)
            ..._replies.map((r) => _EchoItemWidget(
              comment: r is Map<String, dynamic> ? r : {},
              postId: widget.postId,
              onReply: widget.onReply,
              onDeleted: widget.onDeleted,
              depth: widget.depth + 1,
            )),
        ],
      ),
    );
  }

  Widget _initialsFallback() {
    final initials = _name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(child: Text(initials, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
    );
  }
}
