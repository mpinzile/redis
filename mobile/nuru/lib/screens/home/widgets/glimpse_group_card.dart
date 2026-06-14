import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/video_thumbnail_image.dart';

/// Card that groups all glimpses (moments) of a single author.
/// Shows author header + horizontal preview tiles with view counts (WhatsApp-style).
class GlimpseGroupCard extends StatelessWidget {
  final Map group;
  final void Function(int momentIndex) onOpen;

  const GlimpseGroupCard({super.key, required this.group, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final user = group['user'] is Map ? group['user'] as Map : const {};
    final moments = group['moments'] is List ? group['moments'] as List : const [];
    final isSelf = user['is_self'] == true;
    final name = isSelf ? 'Your Glimpses' : (user['name']?.toString() ?? 'Unknown');
    final isVerified = user['is_verified'] == true || user['is_identity_verified'] == true;
    final avatar = user['avatar']?.toString();
    // Own glimpses don't show the unseen ring.
    final allSeen = isSelf ? true : (group['all_seen'] == true);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: allSeen
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  border: allSeen ? Border.all(color: AppColors.borderLight, width: 1.5) : null,
                ),
                child: ClipOval(
                  child: (avatar != null && avatar.isNotEmpty)
                      ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.surface,
                          alignment: Alignment.center,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                        ),
                        if (isVerified && !isSelf) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded,
                              size: 14, color: AppColors.primary),
                        ],
                      ],
                    ),

                    Text('${moments.length} glimpse${moments.length == 1 ? '' : 's'} • 24h',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: moments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final m = moments[i] is Map ? moments[i] as Map : const {};
                return GestureDetector(
                  onTap: () => onOpen(i),
                  child: _GlimpseTile(moment: m, showViews: isSelf),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GlimpseTile extends StatelessWidget {
  final Map moment;
  final bool showViews;
  const _GlimpseTile({required this.moment, required this.showViews});

  @override
  Widget build(BuildContext context) {
    final type = moment['content_type']?.toString() ?? '';
    final media = moment['media_url']?.toString() ?? '';
    final thumb = moment['thumbnail_url']?.toString() ?? '';
    final caption = (moment['caption'] ?? moment['content'] ?? '').toString();
    final bgRaw = moment['background_color']?.toString() ?? '';
    final viewers = moment['viewer_count'];
    final viewerCount = viewers is num ? viewers.toInt() : int.tryParse('$viewers') ?? 0;

    Color bg = AppColors.primary;
    if (bgRaw.startsWith('#') && bgRaw.length == 7) {
      bg = Color(int.parse('FF${bgRaw.substring(1)}', radix: 16));
    }
    final isText = type == 'text' || (media.isEmpty && caption.isNotEmpty);
    final isVideo = type == 'video';

    return Container(
      width: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isText)
            Container(
              color: bg,
              padding: const EdgeInsets.all(8),
              alignment: Alignment.center,
              child: Text(
                caption.isEmpty ? 'Untitled' : caption,
                maxLines: 5,
                overflow: TextOverflow.fade,
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            )
          else if (isVideo)
            VideoThumbnailImage(
              videoUrl: media,
              posterUrl: thumb.isNotEmpty ? thumb : null,
              showPlayBadge: false,
            )
          else if (media.isNotEmpty)
            CachedNetworkImage(imageUrl: media, fit: BoxFit.cover, filterQuality: FilterQuality.medium, fadeInDuration: Duration.zero, fadeOutDuration: Duration.zero, placeholderFadeInDuration: Duration.zero)
          else
            const SizedBox.shrink(),

          // Bottom gradient
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.transparent, Color(0xCC000000)],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          if (isVideo)
            Positioned(
              top: 6, left: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: SvgPicture.asset('assets/icons/play-icon.svg',
                    width: 10, height: 10,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
              ),
            ),
          if (showViews)
            Positioned(
              left: 6, bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset('assets/icons/view-icon.svg',
                        width: 10, height: 10,
                        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                    const SizedBox(width: 4),
                    Text(_formatViews(viewerCount),
                        style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.0)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatViews(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return '$n';
  }
}
