import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import '../../../core/theme/app_colors.dart';

/// Modern, Instagram/WhatsApp-style video trimmer with a filmstrip scrubber,
/// dual handles, live playhead, and free range selection between
/// [minDurationSeconds] and [maxDurationSeconds].
class GlimpseTrimScreen extends StatefulWidget {
  final File source;
  final double maxDurationSeconds;
  final double minDurationSeconds;

  const GlimpseTrimScreen({
    super.key,
    required this.source,
    this.maxDurationSeconds = 30.0,
    this.minDurationSeconds = 1.0,
  });

  @override
  State<GlimpseTrimScreen> createState() => _GlimpseTrimScreenState();
}

class _GlimpseTrimScreenState extends State<GlimpseTrimScreen> {
  static const MethodChannel _nativeTrimmerChannel =
      MethodChannel('flutter_native_video_trimmer');

  static const int _thumbCount = 10;
  static const double _stripHeight = 56;
  static const double _handleWidth = 14;

  VideoPlayerController? _controller;
  double _start = 0.0;
  double _end = 0.0;
  double _duration = 0.0;
  bool _playing = false;
  bool _loading = true;
  bool _saving = false;
  List<Uint8List?> _thumbs = const [];
  _Drag _drag = _Drag.none;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final controller = VideoPlayerController.file(widget.source);
      await Future.wait([
        _nativeTrimmerChannel.invokeMethod<void>(
          'loadVideo',
          {'path': widget.source.path},
        ),
        controller.initialize(),
      ]);
      if (!mounted) return;
      controller.addListener(_syncPlaybackWindow);
      final durationSeconds = controller.value.duration.inMilliseconds / 1000;
      setState(() {
        _controller = controller;
        _duration = durationSeconds;
        _start = 0;
        _end = durationSeconds < widget.maxDurationSeconds
            ? durationSeconds
            : widget.maxDurationSeconds;
        _loading = false;
      });
      _generateThumbs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load video: $e')),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _generateThumbs() async {
    final dur = _duration;
    if (dur <= 0) return;
    final results = List<Uint8List?>.filled(_thumbCount, null);
    if (mounted) setState(() => _thumbs = results);
    for (int i = 0; i < _thumbCount; i++) {
      final t = (dur * (i + 0.5) / _thumbCount * 1000).round();
      try {
        final data = await vt.VideoThumbnail.thumbnailData(
          video: widget.source.path,
          imageFormat: vt.ImageFormat.JPEG,
          timeMs: t,
          maxWidth: 120,
          quality: 60,
        );
        if (!mounted) return;
        results[i] = data;
        setState(() => _thumbs = List<Uint8List?>.from(results));
      } catch (_) {/* skip a single frame */}
    }
  }

  void _syncPlaybackWindow() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final position = controller.value.position.inMilliseconds / 1000;
    final isPlaying = controller.value.isPlaying;
    if (isPlaying && position >= _end) {
      controller.pause();
      controller.seekTo(Duration(milliseconds: (_start * 1000).round()));
    }
    if (mounted) {
      if (_playing != isPlaying) {
        setState(() => _playing = isPlaying);
      } else {
        // Just trigger a rebuild for the moving playhead.
        setState(() {});
      }
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      final position = controller.value.position.inMilliseconds / 1000;
      if (position < _start || position >= _end) {
        await controller.seekTo(Duration(milliseconds: (_start * 1000).round()));
      }
      await controller.play();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final outputPath = await _nativeTrimmerChannel.invokeMethod<String>(
        'trimVideo',
        {
          'startTimeMs': (_start * 1000).round(),
          'endTimeMs': (_end * 1000).round(),
          'includeAudio': true,
        },
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (outputPath != null) {
        Navigator.of(context).pop(File(outputPath));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to trim video')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to trim video: $e')),
      );
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_syncPlaybackWindow);
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(double seconds) {
    final s = seconds.clamp(0.0, double.infinity);
    final m = (s ~/ 60);
    final r = (s - m * 60);
    return '${m.toString().padLeft(2, '0')}:${r.toStringAsFixed(1).padLeft(4, '0')}';
  }

  void _applyDrag(double dx, double trackWidth) {
    if (_duration <= 0) return;
    final perPx = _duration / trackWidth;
    final deltaSec = dx * perPx;
    double s = _start, e = _end;
    final minW = widget.minDurationSeconds;
    final maxW = widget.maxDurationSeconds;
    switch (_drag) {
      case _Drag.start:
        s = (s + deltaSec).clamp(0.0, (e - minW)).toDouble();
        if (e - s > maxW) s = e - maxW;
        break;
      case _Drag.end:
        e = (e + deltaSec).clamp(s + minW, _duration).toDouble();
        if (e - s > maxW) e = s + maxW;
        break;
      case _Drag.window:
        final w = e - s;
        s = (s + deltaSec).clamp(0.0, _duration - w).toDouble();
        e = s + w;
        break;
      case _Drag.none:
        return;
    }
    setState(() {
      _start = s;
      _end = e;
    });
    final seekSec = _drag == _Drag.end ? e : s;
    _controller?.seekTo(Duration(milliseconds: (seekSec * 1000).round()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  _topBar(),
                  Expanded(child: _player()),
                  _controlsCard(),
                ],
              ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              'Trim Glimpse',
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB300), Color(0xFFFFD54F)],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB300).withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : Text('Done',
                      style: GoogleFonts.sora(
                          color: Colors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _player() {
    return GestureDetector(
      onTap: _togglePlayback,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_controller != null)
              AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            AnimatedOpacity(
              opacity: _playing ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlsCard() {
    final selected = (_end - _start);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
      decoration: const BoxDecoration(
        color: Color(0xFF111118),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _timeChip(_fmt(_start), label: 'Start'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB300).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.4)),
                ),
                child: Text(
                  '${selected.toStringAsFixed(1)}s selected',
                  style: GoogleFonts.inter(
                    color: const Color(0xFFFFD54F),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              _timeChip(_fmt(_end), label: 'End'),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final trackWidth = c.maxWidth;
              final startX = (_start / (_duration == 0 ? 1 : _duration)) * trackWidth;
              final endX = (_end / (_duration == 0 ? 1 : _duration)) * trackWidth;
              final playheadX = _controller == null
                  ? startX
                  : (_controller!.value.position.inMilliseconds /
                          1000 /
                          (_duration == 0 ? 1 : _duration)) *
                      trackWidth;
              return SizedBox(
                height: _stripHeight + 16,
                child: Stack(
                  children: [
                    // Filmstrip
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Row(
                            children: List.generate(_thumbCount, (i) {
                              final t = _thumbs.length > i ? _thumbs[i] : null;
                              return Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(right: i == _thumbCount - 1 ? 0 : 1),
                                  color: const Color(0xFF1E1E27),
                                  child: t == null
                                      ? const SizedBox.shrink()
                                      : Image.memory(t, fit: BoxFit.cover, gaplessPlayback: true),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                    // Left dim
                    Positioned(
                      left: 0,
                      top: 8,
                      bottom: 8,
                      width: startX.clamp(0.0, trackWidth),
                      child: Container(color: Colors.black.withOpacity(0.55)),
                    ),
                    // Right dim
                    Positioned(
                      left: endX.clamp(0.0, trackWidth),
                      top: 8,
                      bottom: 8,
                      right: 0,
                      child: Container(color: Colors.black.withOpacity(0.55)),
                    ),
                    // Selection frame
                    Positioned(
                      left: startX,
                      top: 4,
                      width: (endX - startX).clamp(0.0, trackWidth),
                      bottom: 4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) => _drag = _Drag.window,
                        onHorizontalDragUpdate: (d) => _applyDrag(d.delta.dx, trackWidth),
                        onHorizontalDragEnd: (_) => _drag = _Drag.none,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.symmetric(
                              horizontal: BorderSide(color: const Color(0xFFFFB300), width: 3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Playhead
                    if (playheadX >= startX - 1 && playheadX <= endX + 1)
                      Positioned(
                        left: (playheadX - 1).clamp(0.0, trackWidth - 2),
                        top: 4,
                        bottom: 4,
                        width: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(1),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.white.withOpacity(0.5),
                                  blurRadius: 8),
                            ],
                          ),
                        ),
                      ),
                    // Left handle
                    Positioned(
                      left: (startX - _handleWidth / 2)
                          .clamp(-_handleWidth / 2, trackWidth - _handleWidth / 2),
                      top: 0,
                      bottom: 0,
                      width: _handleWidth + 12,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) => _drag = _Drag.start,
                        onHorizontalDragUpdate: (d) => _applyDrag(d.delta.dx, trackWidth),
                        onHorizontalDragEnd: (_) => _drag = _Drag.none,
                        child: Center(child: _handle()),
                      ),
                    ),
                    // Right handle
                    Positioned(
                      left: (endX - _handleWidth / 2 - 6)
                          .clamp(-_handleWidth / 2, trackWidth - _handleWidth / 2),
                      top: 0,
                      bottom: 0,
                      width: _handleWidth + 12,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) => _drag = _Drag.end,
                        onHorizontalDragUpdate: (d) => _applyDrag(d.delta.dx, trackWidth),
                        onHorizontalDragEnd: (_) => _drag = _Drag.none,
                        child: Center(child: _handle()),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: Colors.white.withOpacity(0.5)),
              const SizedBox(width: 6),
              Text(
                'Drag handles • ${widget.minDurationSeconds.toInt()}s min · ${widget.maxDurationSeconds.toInt()}s max',
                style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _togglePlayback,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(_playing ? 'Pause' : 'Preview',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _handle() {
    return Container(
      width: _handleWidth,
      decoration: BoxDecoration(
        color: const Color(0xFFFFB300),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB300).withOpacity(0.45),
            blurRadius: 12,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _timeChip(String text, {required String label}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
              color: Colors.white.withOpacity(0.45),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            )),
        const SizedBox(height: 2),
        Text(text,
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}

enum _Drag { none, start, end, window }
