import '../../core/widgets/nuru_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/services/user_services_service.dart';
import '../../core/services/social_service.dart';
import '../../core/services/messages_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../messages/messages_screen.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../core/utils/avatar_url.dart';
import '../../core/widgets/nuru_skeleton.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final String? username;
  const PublicProfileScreen({super.key, required this.userId, this.username});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Map<String, dynamic>? _profile;
  List<dynamic> _posts = [];
  bool _loading = true;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Resolve the profile. If userId is empty (e.g. opened from a /u/:username
    // deep link), fall back to the by-username endpoint so the page still
    // renders instead of bouncing the user back home.
    final hasUserId = widget.userId.isNotEmpty;
    final res = hasUserId
        ? await UserServicesService.getUserProfile(widget.userId)
        : await UserServicesService.getPublicProfile(widget.username ?? '');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _profile = res['data'] is Map<String, dynamic> ? res['data'] : null;
        _isFollowing = _profile?['is_following'] == true;
      }
    });
    // Posts load in the background - does not block first paint.
    final resolvedId = (_profile?['id'] ?? widget.userId)?.toString() ?? '';
    if (resolvedId.isNotEmpty) {
      SocialService.getUserPosts(resolvedId).then((postsRes) {
        if (!mounted || postsRes['success'] != true) return;
        final data = postsRes['data'];
        setState(() {
          _posts = data is List
              ? data
              : (data is Map ? (data['posts'] ?? data['items'] ?? []) : []);
        });
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${_profile?['first_name'] ?? ''} ${_profile?['last_name'] ?? ''}'.trim();
    final username = _profile?['username']?.toString() ?? widget.username ?? '';
    final avatar = effectiveAvatarUrl(_profile?['avatar']?.toString());
    final bio = _profile?['bio']?.toString() ?? '';
    final followersCount = _profile?['followers_count'] ?? 0;
    final followingCount = _profile?['following_count'] ?? 0;
    final postsCount = _profile?['posts_count'] ?? _posts.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: NuruSubPageAppBar(
        title: _loading
            ? ''
            : (name.isNotEmpty
                ? name
                : (username.isNotEmpty ? '@$username' : '')),
      ),
      body: _loading
          ? _buildSkeleton()
          : NuruRefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Profile header
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: AppColors.surfaceVariant,
                          backgroundImage: (avatar != null && avatar.isNotEmpty)
                              ? CachedNetworkImageProvider(avatar)
                              : null,
                          child: (avatar == null || avatar.isEmpty)
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: GoogleFonts.inter(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textTertiary),
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(name.isNotEmpty ? name : 'Unknown',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary)),
                            ),
                            if (_profile?['is_verified'] == true ||
                                _profile?['is_identity_verified'] == true) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified_rounded,
                                  size: 18, color: AppColors.primary),
                            ],
                          ],
                        ),
                        if (username.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('@$username', style: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary)),
                        ],
                        if (bio.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(bio, textAlign: TextAlign.center, style: GoogleFonts.inter(
                              fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statItem('$postsCount', 'Posts'),
                      _statItem('$followersCount', 'Followers'),
                      _statItem('$followingCount', 'Following'),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Follow button
                  GestureDetector(
                    onTap: () async {
                      if (_isFollowing) {
                        await SocialService.unfollowUser(widget.userId);
                      } else {
                        await SocialService.followUser(widget.userId);
                      }
                      setState(() => _isFollowing = !_isFollowing);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _isFollowing ? AppColors.surfaceVariant : AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          _isFollowing ? 'Following' : 'Follow',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600,
                              color: _isFollowing ? AppColors.textSecondary : Colors.white),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Message button
                  GestureDetector(
                    onTap: () async {
                      final res = await MessagesService.startConversation(
                        recipientId: widget.userId,
                        message: 'Hello!',
                      );
                      if (!mounted) return;
                      if (res['success'] == true && res['data'] != null) {
                        final convId = res['data']['id']?.toString();
                        if (convId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatDetailScreen(
                                conversationId: convId,
                                name: name.isNotEmpty ? name : '@$username',
                                avatar: avatar,
                              ),
                            ),
                          );
                        }
                      } else {
                        AppSnackbar.error(
                          context,
                          res['message']?.toString() ?? 'Failed to start conversation',
                        );
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              'assets/icons/chat-icon.svg',
                              width: 16,
                              height: 16,
                              colorFilter: const ColorFilter.mode(
                                  AppColors.textSecondary, BlendMode.srcIn),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Message',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Posts
                  Text('Posts', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),

                  if (_posts.isEmpty)
                    Center(child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text('No posts yet', style: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary)),
                    ))
                  else
                    ..._posts.map((p) {
                      final post = p is Map<String, dynamic> ? p : <String, dynamic>{};
                      final content = post['content']?.toString() ?? '';
                      final images = post['images'] is List ? post['images'] as List : [];
                      final createdAt = post['created_at']?.toString() ?? '';
                      final mediaUrl = post['media_url']?.toString() ?? '';
                      final contentType = (post['content_type'] ?? post['media_type'] ?? '').toString().toLowerCase();

                      String? mediaSrc;
                      bool isVideo = false;
                      if (images.isNotEmpty) {
                        final first = images[0];
                        if (first is Map) {
                          mediaSrc = (first['url'] ?? first['image_url'] ?? '').toString();
                          final t = (first['media_type'] ?? first['type'] ?? '').toString().toLowerCase();
                          isVideo = t.contains('video') || _isVideoUrl(mediaSrc ?? '');
                        } else {
                          mediaSrc = first.toString();
                          isVideo = _isVideoUrl(mediaSrc);
                        }
                      } else if (mediaUrl.isNotEmpty && !mediaUrl.startsWith('text:')) {
                        mediaSrc = mediaUrl;
                        isVideo = contentType.contains('video') || _isVideoUrl(mediaUrl);
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (content.isNotEmpty)
                              Text(content, style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
                            if (mediaSrc != null && mediaSrc.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      height: 220,
                                      color: Colors.black,
                                      child: isVideo
                                          ? CachedNetworkImage(
                                              imageUrl: (post['thumbnail_url'] ?? post['thumbnail'] ?? mediaSrc).toString(),
                                              width: double.infinity, height: 220, fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                                            )
                                          : CachedNetworkImage(
                                              imageUrl: mediaSrc,
                                              width: double.infinity, height: 220, fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                                            ),
                                    ),
                                    if (isVideo)
                                      Container(
                                        width: 52, height: 52,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.55),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            if (createdAt.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(SocialService.getTimeAgo(createdAt), style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
                            ],
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
      ],
    );
  }

  Widget _initials(String name) {
    return Center(child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textTertiary),
    ));
  }

  Widget _skel({double? w, double h = 12, double r = 8}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }

  Widget _buildSkeleton() {
    return NuruSkeletonGroup(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                NuruSkeleton.circle(size: 72),
                const SizedBox(height: 14),
                NuruSkeleton.text(width: 160, height: 16),
                const SizedBox(height: 10),
                NuruSkeleton.text(width: 100, height: 12),
                const SizedBox(height: 12),
                NuruSkeleton.text(width: 240, height: 11),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(children: [NuruSkeleton.text(width: 36, height: 16), const SizedBox(height: 6), NuruSkeleton.text(width: 50, height: 10)]),
              Column(children: [NuruSkeleton.text(width: 36, height: 16), const SizedBox(height: 6), NuruSkeleton.text(width: 60, height: 10)]),
              Column(children: [NuruSkeleton.text(width: 36, height: 16), const SizedBox(height: 6), NuruSkeleton.text(width: 60, height: 10)]),
            ],
          ),
          const SizedBox(height: 18),
          NuruSkeleton.box(height: 44, radius: 12),
          const SizedBox(height: 10),
          NuruSkeleton.box(height: 44, radius: 12),
          const SizedBox(height: 24),
          NuruSkeleton.text(width: 60, height: 18),
          const SizedBox(height: 12),
          const NuruSkeletonPostCard(),
          const SizedBox(height: 14),
          const NuruSkeletonPostCard(),
        ],
      ),
    );
  }

  static bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.avi') ||
        lower.endsWith('.webm') || lower.endsWith('.mkv') || lower.endsWith('.m4v') ||
        lower.contains('/video') || lower.contains('video/');
  }
}
