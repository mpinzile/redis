import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/video_thumbnail_image.dart';


/// Horizontal "stories"-style rail showing one circle per author with at least
/// one active moment. The first item is always the "Your Glimpse" composer.
class GlimpsesRail extends StatelessWidget {
  /// Each entry: { user: {id, name, avatar, is_self}, moments: [...], all_seen }
  final List<dynamic> glimpses;
  final bool loading;
  final VoidCallback onCreateTap;
  final void Function(int authorIndex) onAuthorTap;
  final String? myAvatar;
  final VoidCallback? onShareMomentTap;
  final bool shareMomentExpanded;

  const GlimpsesRail({
    super.key,
    required this.glimpses,
    required this.loading,
    required this.onCreateTap,
    required this.onAuthorTap,
    this.myAvatar,
    this.onShareMomentTap,
    this.shareMomentExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasShare = onShareMomentTap != null;
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: 1 + (hasShare ? 1 : 0) + glimpses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          if (i == 0) return _yourGlimpse(context);
          if (hasShare && i == 1) return _shareMomentPill();
          final glimpseIndex = i - 1 - (hasShare ? 1 : 0);
          final r = glimpses[glimpseIndex];
          if (r is! Map) return const SizedBox.shrink();
          final user = (r['user'] is Map) ? r['user'] as Map : const {};
          final moments = r['moments'] is List ? r['moments'] as List : const [];
          final allSeen = r['all_seen'] == true;
          final seenCount = moments.where((m) => m is Map && m['has_seen'] == true).length;
          return _glimpseTile(
            label: user['is_self'] == true
                ? 'You'
                : (user['name']?.toString() ?? '').split(' ').first,
            avatar: user['avatar']?.toString(),
            preview: moments.isNotEmpty ? moments.last : null,
            allSeen: allSeen,
            onTap: () => onAuthorTap(glimpseIndex),
            totalMoments: moments.length,
            seenCount: seenCount,
          );
        },
      ),
    );
  }

  Widget _shareMomentPill() {
    return GestureDetector(
      onTap: onShareMomentTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.08),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.35),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: SvgPicture.asset(
                  shareMomentExpanded
                      ? 'assets/icons/close-circle-icon.svg'
                      : 'assets/icons/pen-icon.svg',
                  width: 26,
                  height: 26,
                  colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              shareMomentExpanded ? 'Hide' : 'Moment',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _yourGlimpse(BuildContext context) {
    return GestureDetector(
      onTap: onCreateTap,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceVariant,
                  border: Border.all(color: AppColors.borderLight, width: 1.5),
                ),
                child: ClipOval(
                  child: myAvatar != null && myAvatar!.isNotEmpty
                      ? CachedNetworkImage(imageUrl: myAvatar!, fit: BoxFit.cover, width: 64, height: 64)
                      : Center(child: SvgPicture.asset('assets/icons/user-icon.svg', width: 26, height: 26, colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn))),
                ),
              ),
              Positioned(
                right: 0, bottom: 0,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  child: Center(child: SvgPicture.asset('assets/icons/plus-icon.svg', width: 12, height: 12, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Your Glimpse',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _glimpseTile({
    required String label,
    String? avatar,
    dynamic preview,
    required bool allSeen,
    required VoidCallback onTap,
    int totalMoments = 1,
    int seenCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            SizedBox(
              width: 64, height: 64,
              child: CustomPaint(
                painter: _SegmentedRingPainter(
                  total: totalMoments < 1 ? 1 : totalMoments,
                  seen: seenCount.clamp(0, totalMoments < 1 ? 1 : totalMoments),
                  unseenColor: AppColors.primary,
                  seenColor: AppColors.borderLight,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceVariant,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _previewFace(label: label, avatar: avatar, preview: preview),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _previewFace({required String label, String? avatar, dynamic preview}) {
    final p = preview is Map ? preview : const {};
    final type = p['content_type']?.toString() ?? '';
    final media = p['media_url']?.toString() ?? '';
    final thumb = p['thumbnail_url']?.toString() ?? '';
    final bg = (p['background_color']?.toString().isNotEmpty == true)
        ? p['background_color'].toString()
        : (media.startsWith('text:') ? media.substring(5) : '');
    final caption = (p['caption'] ?? p['content'] ?? '').toString();

    Widget fallback() {
      if (avatar != null && avatar.isNotEmpty) {
        return CachedNetworkImage(
          imageUrl: avatar, fit: BoxFit.cover, width: 64, height: 64,
          filterQuality: FilterQuality.medium,
          placeholder: (_, __) => Container(color: AppColors.surfaceVariant),
          errorWidget: (_, __, ___) => _initial(label),
        );
      }
      return _initial(label);
    }

    if (type == 'image' && media.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: media, fit: BoxFit.cover, width: 64, height: 64,
        filterQuality: FilterQuality.medium,
        placeholder: (_, __) => Container(color: AppColors.surfaceVariant),
        errorWidget: (_, __, ___) => fallback(),
      );
    }
    if (type == 'video') {
      return Stack(fit: StackFit.expand, children: [
        VideoThumbnailImage(
          videoUrl: media,
          posterUrl: thumb.isNotEmpty ? thumb : null,
          showPlayBadge: false,
        ),
        _playBadge(),
      ]);
    }

    if (type == 'text' || bg.isNotEmpty) {
      Color color = AppColors.primary;
      if (bg.startsWith('#') && bg.length == 7) {
        color = Color(int.parse('FF${bg.substring(1)}', radix: 16));
      }
      final l = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
      final fg = l > 0.65 ? const Color(0xFF111111) : Colors.white;
      return Container(
        color: color,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(7),
        child: Text(
          caption.isNotEmpty ? caption : label,
          maxLines: 3,
          textAlign: TextAlign.center,
          overflow: TextOverflow.fade,
          style: GoogleFonts.sora(color: fg, fontSize: 9.5, fontWeight: FontWeight.w800, height: 1.1),
        ),
      );
    }
    return fallback();
  }

  Widget _initial(String label) => Center(
        child: Text(
          label.isNotEmpty ? label[0].toUpperCase() : '?',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
      );

  Widget _playBadge() => Container(
        color: Colors.black.withOpacity(0.16),
        alignment: Alignment.center,
        child: SvgPicture.asset('assets/icons/play-icon.svg', width: 18, height: 18, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
      );
}

class _SegmentedRingPainter extends CustomPainter {
  final int total;
  final int seen;
  final Color unseenColor;
  final Color seenColor;
  _SegmentedRingPainter({
    required this.total,
    required this.seen,
    required this.unseenColor,
    required this.seenColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.5;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final gap = total > 1 ? 0.10 : 0.0; // radians gap between segments
    final totalGap = gap * total;
    final segSweep = (2 * 3.141592653589793 - totalGap) / total;
    for (int i = 0; i < total; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = i < seen ? seenColor : unseenColor;
      final start = -3.141592653589793 / 2 + i * (segSweep + gap) + gap / 2;
      canvas.drawArc(rect, start, segSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedRingPainter oldDelegate) =>
      oldDelegate.total != total || oldDelegate.seen != seen ||
      oldDelegate.unseenColor != unseenColor || oldDelegate.seenColor != seenColor;
}
