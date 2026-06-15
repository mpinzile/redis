import 'dart:io';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/moments_service.dart';
import '../../../core/theme/app_colors.dart';

/// Full-screen glimpses viewer. Tap left/right to navigate, swipe down to close.
/// Auto-advances after 5s for text/image. Marks each moment as seen.
class GlimpseViewerScreen extends StatefulWidget {
  /// All grouped glimpses from the home feed.
  final List<dynamic> glimpses;
  final int initialAuthorIndex;
  const GlimpseViewerScreen({
    super.key,
    required this.glimpses,
    required this.initialAuthorIndex,
  });

  @override
  State<GlimpseViewerScreen> createState() => _GlimpseViewerScreenState();
}

class _GlimpseViewerScreenState extends State<GlimpseViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _authorIdx;
  int _momentIdx = 0;
  VideoPlayerController? _vc;
  late final AnimationController _progress;
  static const _defaultDuration = Duration(seconds: 5);
  bool _captionHidden = false;
  // Persists for the lifetime of the session — WhatsApp-style sticky mute.
  static bool _muted = false;

  @override
  void initState() {
    super.initState();
    _authorIdx = widget.initialAuthorIndex;
    _momentIdx = _firstUnseenIndex(_authorIdx);
    _progress = AnimationController(vsync: this, duration: _defaultDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    _start();
  }

  /// Returns the index of the first not-yet-seen moment for the given author,
  /// or 0 when every moment has already been seen.
  int _firstUnseenIndex(int authorIndex) {
    if (authorIndex < 0 || authorIndex >= widget.glimpses.length) return 0;
    final group = widget.glimpses[authorIndex];
    if (group is! Map) return 0;
    final user = group['user'] is Map ? group['user'] as Map : const {};
    // For your own glimpses always start from the beginning.
    if (user['is_self'] == true) return 0;
    final moments = group['moments'] is List ? group['moments'] as List : const [];
    for (var i = 0; i < moments.length; i++) {
      final m = moments[i];
      if (m is Map && m['has_seen'] != true) return i;
    }
    return 0;
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    final c = _vc;
    if (c != null && c.value.isInitialized) {
      await c.setVolume(_muted ? 0.0 : 1.0);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _vc?.dispose();
    super.dispose();
  }

  Map get _author => (widget.glimpses[_authorIdx] as Map);
  List get _moments => (_author['moments'] as List? ?? const []);
  Map get _moment => _moments[_momentIdx] as Map;

  Future<void> _start() async {
    _progress.stop();
    _progress.value = 0;
    _vc?.dispose();
    _vc = null;
    if (mounted) setState(() {});
    final id = _moment['id']?.toString();
    if (id != null) {
      MomentsService.markSeen(id);
      // Optimistically mark this moment as seen locally so the rail ring and
      // viewer's next-unseen logic reflect it immediately, even before the
      // next /moments fetch returns. Cross-device freshness still comes from
      // the server's has_seen flag on the next refresh.
      if (_moment['has_seen'] != true) {
        _moment['has_seen'] = true;
      }
      _loadViewers(id);
    }

    final type = _moment['content_type']?.toString() ?? 'image';
    final url = _moment['media_url']?.toString() ?? '';
    if (type == 'video' && url.isNotEmpty) {
      try {
        final file = await DefaultCacheManager().getSingleFile(url);
        if (!mounted) return;
        final c = VideoPlayerController.file(File(file.path));
        _vc = c;
        await c.initialize();
        if (!mounted || _vc != c) return;
        c.setLooping(false);
        await c.setVolume(_muted ? 0.0 : 1.0);
        c.play();
        _progress.duration = c.value.duration > Duration.zero
            ? c.value.duration
            : _defaultDuration;
        _progress.forward(from: 0);
        setState(() {});
      } catch (_) {
        _progress.duration = _defaultDuration;
        _progress.forward(from: 0);
      }
    } else {
      _progress.duration = _defaultDuration;
      _progress.forward(from: 0);
    }
  }

  // ── Viewers (WhatsApp-style "Seen by" for the author's own glimpse) ──
  List<Map<String, dynamic>> _viewers = const [];
  bool _viewersLoading = false;
  String? _viewersForMomentId;
  // In-memory cache: viewers persist across moments within the session so
  // we never re-show a "Loading viewers…" spinner for a glimpse we've
  // already fetched. Refresh happens silently in the background.
  static final Map<String, List<Map<String, dynamic>>> _viewersCache = {};

  bool get _isOwnGlimpse => (_author['user'] is Map) && (_author['user']['is_self'] == true);

  Future<void> _loadViewers(String momentId) async {
    if (!_isOwnGlimpse) return;
    final cached = _viewersCache[momentId];
    setState(() {
      _viewersForMomentId = momentId;
      _viewers = cached ?? const [];
      // Only show the spinner the very first time we fetch this moment.
      _viewersLoading = cached == null;
    });
    final res = await MomentsService.getViewers(momentId);
    if (!mounted || _viewersForMomentId != momentId) return;
    final data = res['data'];
    final list = data is List
        ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    _viewersCache[momentId] = list;
    setState(() {
      _viewers = list;
      _viewersLoading = false;
    });
  }

  void _openViewersSheet() {
    _progress.stop();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ViewersSheet(viewers: _viewers, loading: _viewersLoading),
    ).whenComplete(() {
      if (mounted) _progress.forward();
    });
  }

  // ── Delete (WhatsApp-style: confirm sheet, then remove from feed) ──
  Future<void> _confirmDelete() async {
    _progress.stop();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFDC2626), size: 26),
              ),
              const SizedBox(height: 14),
              Text('Delete this glimpse?',
                  style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'It will be removed for you and everyone who follows you. This can\u2019t be undone.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.borderLight),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Cancel',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Delete',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _progress.forward();
      return;
    }
    await _deleteCurrentGlimpse();
  }

  Future<void> _deleteCurrentGlimpse() async {
    final id = _moment['id']?.toString();
    if (id == null || id.isEmpty) return;
    // Optimistic: drop the moment from the local group, advance or close.
    _viewersCache.remove(id);
    final moments = _moments;
    final wasLast = moments.length <= 1;
    setState(() {
      moments.removeAt(_momentIdx);
      if (!wasLast && _momentIdx >= moments.length) {
        _momentIdx = moments.length - 1;
      }
    });
    // Fire-and-forget; backend will return success or 404.
    MomentsService.deleteMoment(id);
    if (!mounted) return;
    if (wasLast) {
      Navigator.of(context).pop({'deleted': true});
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        content: Text('Glimpse deleted',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        duration: const Duration(seconds: 2),
      ),
    );
    _start();
  }

  void _next() {
    if (_momentIdx < _moments.length - 1) {
      setState(() => _momentIdx++);
      _start();
    } else if (_authorIdx < widget.glimpses.length - 1) {
      final nextAuthor = _authorIdx + 1;
      setState(() {
        _authorIdx = nextAuthor;
        _momentIdx = _firstUnseenIndex(nextAuthor);
      });
      _start();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_momentIdx > 0) {
      setState(() => _momentIdx--);
      _start();
    } else if (_authorIdx > 0) {
      setState(() {
        _authorIdx--;
        _momentIdx = (widget.glimpses[_authorIdx] as Map)['moments'].length - 1;
      });
      _start();
    }
  }

  /// WhatsApp-style relative timestamp using the device's local time.
  /// "Today, 14:32" / "Yesterday, 09:05" / "Mon, 09:05" / "12 Mar, 09:05".
  String _formatPostedAt(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    DateTime? dt;
    try {
      // Backend often returns naive ISO strings (no Z / offset). Treat
      // those as UTC so toLocal() correctly shifts to the device timezone.
      final hasTz = iso.endsWith('Z') ||
          RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso);
      dt = DateTime.parse(hasTz ? iso : '${iso}Z');
    } catch (_) {
      return '';
    }
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(that).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (diffDays == 0) return 'Today, $hh:$mm';
    if (diffDays == 1) return 'Yesterday, $hh:$mm';
    if (diffDays > 1 && diffDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[local.weekday - 1]}, $hh:$mm';
    }
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${local.day} ${months[local.month - 1]}, $hh:$mm';
  }


  @override
  Widget build(BuildContext context) {
    final user = (_author['user'] as Map? ?? const {});
    final m = _moment;
    final type = m['content_type']?.toString() ?? 'image';
    final mediaUrl = m['media_url']?.toString() ?? '';
    final caption = m['content']?.toString() ?? m['caption']?.toString() ?? '';

    String? bg;
    String? imageUrl;
    if (type == 'text') {
      // Backend stores text bg as "text:#RRGGBB"
      if (mediaUrl.startsWith('text:')) {
        bg = mediaUrl.substring(5);
      } else {
        bg = m['background_color']?.toString();
      }
    } else {
      imageUrl = mediaUrl;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 200) Navigator.of(context).pop();
        },
        onLongPress: () {
          if (type != 'text' && caption.isNotEmpty) {
            setState(() => _captionHidden = !_captionHidden);
          }
        },
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx < w / 3) {
            _prev();
          } else {
            _next();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: _canvas(type, bg, imageUrl, caption)),
            // Progress bars
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  Row(
                    children: List.generate(_moments.length, (i) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: Container(
                              height: 2.5,
                              color: Colors.white24,
                              alignment: Alignment.centerLeft,
                              child: i < _momentIdx
                                  ? Container(color: Colors.white)
                                  : i == _momentIdx
                                      ? AnimatedBuilder(
                                          animation: _progress,
                                          builder: (_, __) => FractionallySizedBox(
                                            widthFactor: _progress.value.clamp(0.0, 1.0),
                                            child: Container(color: Colors.white),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Avatar(name: user['name']?.toString() ?? '', url: user['avatar']?.toString()),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              user['is_self'] == true
                                  ? 'My Glimpse'
                                  : (user['name']?.toString() ?? 'Unknown'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            if (_formatPostedAt(_moment['created_at']?.toString()).isNotEmpty)
                              Text(
                                _formatPostedAt(_moment['created_at']?.toString()),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withOpacity(0.75),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (type == 'video')
                        GestureDetector(
                          onTap: _toggleMute,
                          child: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      if (_isOwnGlimpse)
                        GestureDetector(
                          onTap: _confirmDelete,
                          child: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.more_vert_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                    ],
                  ),

                ],
              ),
            ),
            // Premium caption block for media moments (hidden via long-press)
            if (type != 'text' && caption.isNotEmpty && !_captionHidden)
              Positioned(
                left: 0,
                right: 0,
                bottom: _isOwnGlimpse ? 64 : 0,
                child: _CaptionBlock(caption: caption),
              ),
            if (_isOwnGlimpse)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: _SeenByBar(
                    viewers: _viewers,
                    loading: _viewersLoading,
                    onTap: _openViewersSheet,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _canvas(String type, String? bg, String? imageUrl, String caption) {
    if (type == 'text') {
      Color color = AppColors.primary;
      if (bg != null && bg.startsWith('#') && bg.length == 7) {
        color = Color(int.parse('FF${bg.substring(1)}', radix: 16));
      }
      final l =
          (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
      final fg = l > 0.65 ? const Color(0xFF111111) : Colors.white;
      return Container(
        color: color,
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        child: Text(
          caption,
          textAlign: TextAlign.center,
          style: GoogleFonts.sora(
            color: fg,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      );
    }
    if (type == 'video') {
      final c = _vc;
      if (c != null && c.value.isInitialized) {
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
        );
      }
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: Colors.white70),
        ),
      );
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      // Show full image (BoxFit.contain) over a blurred copy of itself so
      // portrait/landscape photos are never cropped or zoomed.
      return Stack(
        fit: StackFit.expand,
        children: [
          // Blurred backdrop to fill the dead space around the contained image.
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (_, __) => Container(color: Colors.black),
            errorWidget: (_, __, ___) => Container(color: Colors.black),
          ),
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(color: Colors.black.withOpacity(0.55)),
          ),
          Center(
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 48),
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

/// Premium caption block shown at the bottom of media glimpses. Includes a
/// gradient scrim, expandable text, and a subtle glass background so the
/// caption is always legible regardless of the underlying media.
class _CaptionBlock extends StatefulWidget {
  final String caption;
  const _CaptionBlock({required this.caption});

  @override
  State<_CaptionBlock> createState() => _CaptionBlockState();
}

class _CaptionBlockState extends State<_CaptionBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.caption.length > 110;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // White text + dark gradient scrim guarantees legibility even on
    // bright/white media. Subtle text shadow adds an extra safety net.
    const shadows = <Shadow>[
      Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 1)),
      Shadow(color: Color(0x66000000), blurRadius: 18),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isLong ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, 36, 20, 24 + bottomInset),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.55),
              Colors.black.withOpacity(0.92),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.topCenter,
                child: Text(
                  widget.caption,
                  textAlign: TextAlign.center,
                  maxLines: _expanded ? 14 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    height: 1.45,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                    shadows: shadows,
                  ),
                ),
              ),
            ),
            if (isLong) ...[
              const SizedBox(height: 8),
              Text(
                _expanded ? 'Tap to collapse' : 'Tap to read more',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.3,
                  shadows: shadows,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? url;
  const _Avatar({required this.name, this.url});
  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white12,
      ),
      clipBehavior: Clip.antiAlias,
      child: (url != null && url!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_, __) => Container(color: Colors.white12),
              errorWidget: (_, __, ___) => Container(
                color: Colors.white12,
                alignment: Alignment.center,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: GoogleFonts.sora(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            )
          : Container(
              alignment: Alignment.center,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.sora(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
                ),
      ),
    );
  }
}

/// Bottom strip on the author's own glimpse showing a quick preview of who has
/// seen this moment. Tapping opens the full viewer sheet.
class _SeenByBar extends StatelessWidget {
  final List<Map<String, dynamic>> viewers;
  final bool loading;
  final VoidCallback onTap;
  const _SeenByBar({
    required this.viewers,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 28,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int i = 0; i < viewers.take(3).length; i++)
                    Positioned(
                      left: i * 18.0,
                      child: _MiniAvatar(
                        url: viewers[i]['avatar']?.toString(),
                        name: viewers[i]['name']?.toString() ?? '',
                      ),
                    ),
                  if (viewers.isEmpty)
                    Positioned(
                      left: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.remove_red_eye_rounded,
                            color: Colors.white70, size: 14),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                viewers.isEmpty
                    ? (loading ? 'Seen by' : 'No views yet')
                    : '${viewers.length} ${viewers.length == 1 ? 'view' : 'views'}',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_up_rounded,
                color: Colors.white.withOpacity(0.85)),
          ],
        ),
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final String? url;
  final String name;
  const _MiniAvatar({this.url, required this.name});
  @override
  Widget build(BuildContext context) {
    const size = 28.0;
    final fallback = Container(
      width: size,
      height: size,
      color: Colors.white12,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: GoogleFonts.sora(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 1.5),
        color: Colors.white12,
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: (url != null && url!.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  errorWidget: (_, __, ___) => fallback,
                )
              : fallback,
        ),
      ),
    );
  }
}

class _ViewersSheet extends StatelessWidget {
  final List<Map<String, dynamic>> viewers;
  final bool loading;
  const _ViewersSheet({required this.viewers, required this.loading});

  String _rel(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    var s = iso.trim();
    final hasTz = s.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasTz) s = '${s}Z';
    final dt = DateTime.tryParse(s);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.7),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Row(
              children: [
                Icon(Icons.remove_red_eye_rounded,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Viewed by ${viewers.length}',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (loading)
            const _ViewerSkeleton()
          else if (viewers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
              child: Column(
                children: [
                  Icon(Icons.visibility_off_outlined,
                      size: 36, color: AppColors.textTertiary),
                  const SizedBox(height: 10),
                  Text(
                    'No one has viewed this glimpse yet',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: viewers.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 70),
                itemBuilder: (_, i) {
                  final v = viewers[i];
                  return ListTile(
                    leading: _SheetAvatar(
                      url: v['avatar']?.toString(),
                      name: v['name']?.toString() ?? '',
                    ),
                    title: Text(
                      v['name']?.toString() ?? 'Unknown',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      _rel(v['viewed_at']?.toString()),
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetAvatar extends StatelessWidget {
  final String? url;
  final String name;
  const _SheetAvatar({this.url, required this.name});
  @override
  Widget build(BuildContext context) {
    const size = 42.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceVariant,
      ),
      clipBehavior: Clip.antiAlias,
      child: (url != null && url!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: GoogleFonts.sora(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800),
                ),
              ),
            )
          : Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.sora(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800),
              ),
            ),
    );
  }
}

/// Subtle shimmer-free skeleton used while viewers load in the background.
/// Matches the row layout of the real list so there's no layout jump.
class _ViewerSkeleton extends StatelessWidget {
  const _ViewerSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF1F4),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    Widget row() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Color(0xFFEFF1F4),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(140, 11),
                    const SizedBox(height: 7),
                    bar(72, 9),
                  ],
                ),
              ),
            ],
          ),
        );
    return Column(
      children: [row(), row(), row()],
    );
  }
}
