/// Standalone, deep-linkable post details screen for /post/:id.
///
/// Public endpoint: GET /api/v1/posts/{id}/public - renders without a session.
/// Falls back to friendly states for private / deleted / not-found. Protected
/// actions (comment, react, follow, message) show a sign-in CTA only when the
/// user tries to use them.
///
/// Existing in-app bottom-sheet behaviour from the feed remains untouched; this
/// is the dedicated standalone surface for deep links.
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import '../../core/services/api_base.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/date_formatters.dart';
import '../../core/widgets/nuru_logo.dart';
import '../auth/login_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _post;
  int _mediaIndex = 0;
  late final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    debugPrint('[PostDetail] loading id=${widget.postId}');
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ApiBase.get('/posts/${widget.postId}/public', auth: false);
    debugPrint('[PostDetail] response success=${res['success']}');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true && res['data'] is Map) {
        _post = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = (res['message'] ?? 'This post is not available.').toString();
      }
    });
  }

  void _share() {
    Share.share('https://nuru.tz/post/${widget.postId}', subject: 'Check this out on Nuru', sharePositionOrigin: sharePositionOrigin(context));
  }

  void _requireSignIn(String action) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
          ),
          const NuruLogo(size: 38),
          const SizedBox(height: 14),
          Text('Sign in to $action',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('Create an account or log in to keep enjoying Nuru.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Sign in'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Post', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share, color: AppColors.textPrimary, size: 20),
            onPressed: _share,
          ),
        ],
      ),
      body: SafeArea(child: _build()),
    );
  }

  Widget _build() {
    if (_loading) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          NuruLogo(size: 36),
          SizedBox(height: 18),
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary)),
        ]),
      );
    }
    if (_error != null) {
      return _PostUnavailable(message: _error!, onRetry: _load);
    }
    final p = _post!;
    final author = (p['user'] is Map ? p['user'] as Map : const {});
    final authorName = ((author['first_name'] ?? '').toString() + ' ' + (author['last_name'] ?? '').toString()).trim();
    final username = (author['username'] ?? '').toString();
    final verified = author['verified'] == true || author['is_verified'] == true;
    final avatar = (author['avatar'] ?? author['avatar_url'] ?? '').toString();
    final text = (p['caption'] ?? p['text'] ?? p['content'] ?? '').toString();
    final createdAt = (p['created_at'] ?? p['posted_at'] ?? '').toString();
    final reactions = (p['reactions_count'] ?? p['likes_count'] ?? 0);
    final comments = (p['comments_count'] ?? 0);
    final reactionsN = reactions is num ? reactions.toInt() : 0;
    final commentsN = comments is num ? comments.toInt() : 0;
    final media = (p['media'] is List ? p['media'] as List : const []);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _AuthorRow(
            avatar: avatar,
            name: authorName.isEmpty ? 'Nuru user' : authorName,
            username: username,
            verified: verified,
            createdAt: createdAt,
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(text, style: const TextStyle(fontSize: 15.5, color: AppColors.textPrimary, height: 1.55)),
          ],
          if (media.isNotEmpty) ...[
            const SizedBox(height: 14),
            _MediaCarousel(
              media: media,
              pageController: _pageController,
              currentIndex: _mediaIndex,
              onChanged: (i) => setState(() => _mediaIndex = i),
            ),
          ],
          const SizedBox(height: 18),
          _ReactionsBar(reactions: reactionsN, comments: commentsN, onTap: _requireSignIn),
          const SizedBox(height: 20),
          _SignInCard(onSignIn: () => _requireSignIn('react or comment')),
        ],
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  final String avatar;
  final String name;
  final String username;
  final bool verified;
  final String createdAt;
  const _AuthorRow({
    required this.avatar,
    required this.name,
    required this.username,
    required this.verified,
    required this.createdAt,
  });
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primarySoft,
        backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
        child: avatar.isEmpty
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 18))
            : null,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            if (verified) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified, color: AppColors.primary, size: 16),
            ],
          ]),
          if (username.isNotEmpty || createdAt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (username.isNotEmpty) '@$username',
                  if (createdAt.isNotEmpty) getTimeAgo(createdAt),
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ),
        ]),
      ),
    ]);
  }
}

class _MediaCarousel extends StatelessWidget {
  final List media;
  final PageController pageController;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  const _MediaCarousel({
    required this.media,
    required this.pageController,
    required this.currentIndex,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      AspectRatio(
        aspectRatio: 4 / 5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: PageView.builder(
            controller: pageController,
            onPageChanged: onChanged,
            itemCount: media.length,
            itemBuilder: (_, i) {
              final m = media[i];
              final url = (m is Map ? (m['url'] ?? m['file_url'] ?? '') : m).toString();
              if (url.isEmpty) return Container(color: AppColors.borderLight);
              return CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                placeholder: (_, __) => Container(color: AppColors.borderLight),
                errorWidget: (_, __, ___) => Container(color: AppColors.borderLight),
              );
            },
          ),
        ),
      ),
      if (media.length > 1) ...[
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            media.length,
            (i) => Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == currentIndex ? AppColors.primary : AppColors.border,
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

class _ReactionsBar extends StatelessWidget {
  final int reactions;
  final int comments;
  final void Function(String action) onTap;
  const _ReactionsBar({required this.reactions, required this.comments, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        _ReactionBtn(icon: Icons.favorite_border, label: '$reactions', onPressed: () => onTap('react to this post')),
        const SizedBox(width: 6),
        _ReactionBtn(icon: Icons.mode_comment_outlined, label: '$comments', onPressed: () => onTap('comment on this post')),
        const Spacer(),
        _ReactionBtn(icon: Icons.bookmark_border, label: 'Save', onPressed: () => onTap('save this post')),
      ]),
    );
  }
}

class _ReactionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _ReactionBtn({required this.icon, required this.label, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: AppColors.textSecondary),
      label: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
    );
  }
}

class _SignInCard extends StatelessWidget {
  final VoidCallback onSignIn;
  const _SignInCard({required this.onSignIn});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.10), AppColors.primary.withOpacity(0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Join the conversation', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Sign in to react, comment, follow, or message.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: onSignIn,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
          child: const Text('Sign in'),
        ),
      ]),
    );
  }
}

class _PostUnavailable extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _PostUnavailable({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(24)),
          child: const Icon(Icons.visibility_off_outlined, size: 30, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 18),
        const Text('Post not available', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: onRetry,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          child: const Text('Try again'),
        ),
      ]),
    );
  }
}
