import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/share_helpers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/social_service.dart';
import '../../../core/services/feed_interaction_tracker.dart';
import '../../../core/widgets/nuru_video_player.dart';
import '../../../core/widgets/image_gallery_viewer.dart';
import '../../../core/widgets/video_thumbnail_image.dart';
import '../../events/event_public_view_screen.dart';
import '../../../core/widgets/event_cover_image.dart';
import '../../../core/l10n/l10n_helper.dart';
import '../../../widgets/nuru_emoji_picker.dart';

/// Feed post card - clean, modern white card with subtle border
class MomentCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTap;
  final VoidCallback? onAuthorTap;

  const MomentCard({super.key, required this.post, this.onTap, this.onAuthorTap});

  @override
  State<MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends State<MomentCard> {
  late bool _glowed;
  late int _glowCount;
  late bool _saved;
  late String _glowEmoji;
  bool _glowing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _glowed = widget.post['has_glowed'] == true;
    _glowCount = (widget.post['glow_count'] ?? 0) as int;
    _saved = widget.post['has_saved'] == true;
    _glowEmoji = NuruEmojiPicker.normalizeEmoji(
      (widget.post['glow_emoji']?.toString().isNotEmpty == true)
          ? widget.post['glow_emoji'].toString()
          : '❤️',
    );
  }

  @override
  void didUpdateWidget(covariant MomentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent passes refreshed post data (e.g. after a silent feed
    // refresh that re-hydrates `has_glowed` / `has_saved` from the server),
    // sync the local optimistic state - but never overwrite an in-flight
    // glow/save toggle.
    if (_glowing || _saving) return;
    final newGlowed = widget.post['has_glowed'] == true;
    final newGlowCount = (widget.post['glow_count'] ?? _glowCount) as int;
    final newSaved = widget.post['has_saved'] == true;
    if (newGlowed != _glowed || newGlowCount != _glowCount || newSaved != _saved) {
      setState(() {
        _glowed = newGlowed;
        _glowCount = newGlowCount;
        _saved = newSaved;
      });
    }
  }

  String get _authorName {
    final author = widget.post['author'];
    final user = widget.post['user'];
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
    final author = widget.post['author'];
    final user = widget.post['user'];
    return (author is Map ? author['avatar'] : null) ?? (user is Map ? user['avatar'] : null);
  }

  bool get _isVerified {
    final user = widget.post['user'];
    final author = widget.post['author'];
    return (user is Map ? user['is_identity_verified'] : false) == true ||
        (author is Map ? author['is_verified'] : false) == true;
  }

  String get _timeAgo {
    final created = widget.post['created_at']?.toString() ?? '';
    return created.isEmpty ? 'Recently' : SocialService.getTimeAgo(created);
  }

  int get _commentCount => (widget.post['comment_count'] ?? widget.post['echo_count'] ?? 0) as int;

  List<String> get _images {
    final imgs = widget.post['images'] ?? widget.post['media'] ?? [];
    if (imgs is! List) return [];
    return imgs.map<String>((img) {
      if (img is String) return img;
      if (img is Map) return (img['image_url'] ?? img['url'] ?? '').toString();
      return '';
    }).where((s) => s.isNotEmpty).toList();
  }

  List<String> get _mediaTypes {
    final imgs = widget.post['images'] ?? widget.post['media'] ?? [];
    if (imgs is! List) return [];
    return imgs.map<String>((img) {
      if (img is String) return '';
      if (img is Map) return (img['media_type'] ?? img['type'] ?? '').toString();
      return '';
    }).toList();
  }

  String get _title => (widget.post['title'] ?? '').toString().trim();
  String get _content => (widget.post['content'] ?? '').toString().trim();

  Map<String, dynamic>? get _sharedEvent => widget.post['shared_event'] as Map<String, dynamic>?;
  bool get _isEventShare => widget.post['post_type'] == 'event_share' && _sharedEvent != null;

  Future<void> _handleGlow({String? emoji}) async {
    if (_glowing) return;
    _glowing = true;
    HapticFeedback.lightImpact();
    final wasGlowed = _glowed;
    final willGlow = emoji != null ? true : !wasGlowed;
    setState(() {
      _glowed = willGlow;
      if (emoji != null) _glowEmoji = NuruEmojiPicker.normalizeEmoji(emoji);
      if (emoji != null) {
        if (!wasGlowed) _glowCount += 1;
      } else {
        _glowCount += wasGlowed ? -1 : 1;
      }
    });
    try {
      final postId = widget.post['id'].toString();
      Map<String, dynamic> res;
      if (!willGlow) {
        res = await SocialService.unglowPost(postId);
        FeedInteractionTracker.log(postId, 'unglow');
      } else {
        res = await SocialService.glowPost(postId, emoji: emoji);
        FeedInteractionTracker.log(postId, 'glow');
      }
      final data = res['data'];
      if (res['success'] == true && data is Map) {
        final serverGlowed = data['has_glowed'] == true;
        final serverCount = (data['glow_count'] ?? _glowCount) as int;
        if (mounted && (serverGlowed != _glowed || serverCount != _glowCount)) {
          setState(() {
            _glowed = serverGlowed;
            _glowCount = serverCount;
          });
        }
        widget.post['has_glowed'] = serverGlowed;
        widget.post['glow_count'] = serverCount;
        if (emoji != null) widget.post['glow_emoji'] = emoji;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _glowed = wasGlowed;
          if (emoji == null) _glowCount += wasGlowed ? 1 : -1;
        });
      }
    }
    _glowing = false;
  }

  Future<void> _pickReaction() async {
    HapticFeedback.selectionClick();
    final picked = await NuruEmojiPicker.show(context);
    if (picked != null) {
      await _handleGlow(emoji: picked);
    }
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    _saving = true;
    HapticFeedback.lightImpact();
    final wasSaved = _saved;
    setState(() => _saved = !wasSaved);
    try {
      final postId = widget.post['id'].toString();
      if (wasSaved) {
        await SocialService.unsavePost(postId);
      } else {
        await SocialService.savePost(postId);
      }
    } catch (_) {
      if (mounted) setState(() => _saved = wasSaved);
    }
    _saving = false;
  }

  Future<void> _handleShare() async {
    HapticFeedback.lightImpact();
    final postId = widget.post['id']?.toString() ?? '';
    final shareUrl = 'https://nuru.tz/shared/post/$postId';
    final shareText = _content.isNotEmpty
        ? '$_content\n\n$shareUrl'
        : 'Check out this moment on Nuru!\n$shareUrl';
    await Share.share(shareText, sharePositionOrigin: sharePositionOrigin(context));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            if (_isEventShare)
              _buildEventShareCard()
            else ...[
              if (_images.isNotEmpty) _buildMedia(),
              if (_title.isNotEmpty || _content.isNotEmpty) _buildText(),
            ],
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final avatar = _authorAvatar;
    final hasAvatar = avatar != null && avatar.isNotEmpty && !avatar.contains('unsplash.com');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onAuthorTap,
            child: hasAvatar
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: CachedNetworkImage(imageUrl: avatar!, width: 36, height: 36, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _initialsAvatar()),
                  )
                : _initialsAvatar(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _authorName,
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.3),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded, size: 14, color: AppColors.primary),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(_timeAgo, style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary, height: 1.2)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _handleSave,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: SvgPicture.asset(
                _saved ? 'assets/icons/bookmark-filled-icon.svg' : 'assets/icons/bookmark-icon.svg',
                width: 20, height: 20,
                colorFilter: ColorFilter.mode(
                  _saved ? AppColors.primary : AppColors.textHint,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initialsAvatar() {
    final initials = _authorName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Text(initials, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary, height: 1.0)),
      ),
    );
  }

  void _openGallery(int index) {
    ImageGalleryViewer.open(
      context,
      urls: _images,
      mediaTypes: _mediaTypes,
      initialIndex: index,
    );
  }

  Widget _buildMedia() {
    final images = _images;
    final types = _mediaTypes;

    if (images.length == 1) {
      final isVideo = types.isNotEmpty && (types[0].contains('video') || images[0].endsWith('.mp4') || images[0].endsWith('.mov'));

      if (isVideo) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: NuruVideoPlayer(url: images[0], height: 220, borderRadius: BorderRadius.circular(12)),
        );
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: GestureDetector(
          onTap: () => _openGallery(0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: CachedNetworkImage(imageUrl: images[0], width: double.infinity, fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                fadeInDuration: Duration.zero, fadeOutDuration: Duration.zero, placeholderFadeInDuration: Duration.zero,
                useOldImageOnUrlChange: true,
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => Container(height: 200, color: AppColors.surfaceVariant,
                  child: Center(child: SvgPicture.asset('assets/icons/broken-image-icon.svg', width: 24, height: 24,
                    colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn))))),
            ),
          ),
        ),
      );
    }

    // Multi-image grid: big left + stacked right with +N overlay (matches web)
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 220,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: () => _openGallery(0),
                  child: _gridTile(images[0], types.isNotEmpty ? types[0] : ''),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openGallery(1),
                        child: _gridTile(images[1], types.length > 1 ? types[1] : ''),
                      ),
                    ),
                    if (images.length > 2) const SizedBox(height: 2),
                    if (images.length > 2)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _openGallery(2),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _gridTile(images[2], types.length > 2 ? types[2] : ''),
                              if (images.length > 3)
                                Container(
                                  color: Colors.black.withOpacity(0.55),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '+${images.length - 3}',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
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

  Widget _gridTile(String url, String type) {
    final isVideo = type.contains('video') || url.endsWith('.mp4') || url.endsWith('.mov');
    if (isVideo) {
      return VideoThumbnailImage(videoUrl: url, showPlayBadge: true);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.medium,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
    );
  }

  Widget _buildText() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_title.isNotEmpty)
            Text(_title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.3)),
          if (_title.isNotEmpty && _content.isNotEmpty) const SizedBox(height: 4),
          if (_content.isNotEmpty)
            Text(_content, style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary, height: 1.5),
              maxLines: 6, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildEventShareCard() {
    final event = _sharedEvent!;
    final eventTitle = event['title'] ?? 'Event';
    final eventDesc = event['description'] ?? '';
    final eventDate = event['start_date'] ?? '';
    final eventLocation = event['location'] ?? '';
    final eventType = event['event_type'] ?? '';
    final coverImage = event['cover_image'] as String?;
    final eventImages = (event['images'] as List?)?.cast<String>() ?? (coverImage != null ? [coverImage] : <String>[]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_content, style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
            ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(11), topRight: Radius.circular(11)),
                      child: SizedBox(
                        height: 160,
                        width: double.infinity,
                        child: EventCoverImage(
                          event: event,
                          url: eventImages.isNotEmpty ? eventImages[0] : null,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    if (eventType.isNotEmpty)
                      Positioned(
                        top: 10, left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                          child: Text(eventType.toString(), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white, height: 1.0)),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(eventTitle.toString(), style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.3)),
                      if (eventDesc.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(eventDesc.toString(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 10),
                      if (eventDate.isNotEmpty)
                        _eventMetaRow('assets/icons/calendar-icon.svg', _formatDate(eventDate.toString())),
                      if (eventLocation.isNotEmpty)
                        _eventMetaRow('assets/icons/location-icon.svg', eventLocation.toString()),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            final eventId = event['id']?.toString();
                            if (eventId != null && eventId.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EventPublicViewScreen(eventId: eventId, initialData: event),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            side: const BorderSide(color: AppColors.border),
                          ),
                          child: Text('View Event Details', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.2)),
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

  Widget _eventMetaRow(String svgAsset, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SvgPicture.asset(svgAsset, width: 14, height: 14,
            colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary, height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderLight, width: 1)),
      ),
      child: Row(
        children: [
          _glowButton(),
          const SizedBox(width: 16),
          _svgActionButton(
            onTap: widget.onTap ?? () {},
            svgAsset: 'assets/icons/echo-icon.svg',
            label: 'Echo',
          ),
          const SizedBox(width: 16),
          // Spark = Share using SVG share icon + native share
          _sparkButton(),
          const Spacer(),
          Flexible(
            child: Text(
              '$_glowCount ${_glowCount == 1 ? 'Glow' : 'Glows'}',
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary, height: 1.0),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$_commentCount ${_commentCount == 1 ? 'Echo' : 'Echoes'}',
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary, height: 1.0),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sparkButton() {
    return GestureDetector(
      onTap: _handleShare,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/icons/share-icon.svg',
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn),
          ),
          const SizedBox(width: 4),
          Text('Spark', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textTertiary, height: 1.2)),
        ],
      ),
    );
  }

  Widget _glowButton() {
    final color = _glowed ? AppColors.error : AppColors.textTertiary;
    return GestureDetector(
      onTap: () => _handleGlow(),
      onLongPress: _pickReaction,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_glowed)
            EmojiText(_glowEmoji, size: 16)
          else
            SvgPicture.asset(
              'assets/icons/heart-icon.svg',
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
          const SizedBox(width: 4),
          Text('Glow',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
                height: 1.2,
              )),
        ],
      ),
    );
  }

  Widget _svgActionButton({
    required VoidCallback onTap,
    required String svgAsset,
    required String label,
    bool isActive = false,
    Color? activeColor,
  }) {
    final color = isActive ? (activeColor ?? AppColors.primary) : AppColors.textTertiary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(svgAsset, width: 18, height: 18,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: color, height: 1.2)),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dateStr);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return dateStr;
    }
  }
}