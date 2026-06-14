import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/audio_file_cache.dart';

/// Inline voice-note player. Plays audio in-app instead of opening it as an
/// external link. Designed to look like the WhatsApp-style waveform chip.
class InlineVoicePlayer extends StatefulWidget {
  final String url;
  final bool isMine;
  const InlineVoicePlayer({super.key, required this.url, this.isMine = false});

  @override
  State<InlineVoicePlayer> createState() => _InlineVoicePlayerState();
}

class _InlineVoicePlayerState extends State<InlineVoicePlayer> {
  late final AudioPlayer _player;
  bool _playing = false;
  bool _loading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _playing = false; _position = Duration.zero; });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    setState(() => _loading = true);
    try {
      if (_position == Duration.zero) {
        // Cache the audio locally so re-opens are instant - without this,
        // every time the chat is opened the file would be re-downloaded.
        final localPath = await AudioFileCache.getLocalPath(widget.url);
        if (localPath != null && File(localPath).existsSync()) {
          await _player.play(DeviceFileSource(localPath));
        } else {
          await _player.play(UrlSource(widget.url));
        }
      } else {
        await _player.resume();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_duration.inMilliseconds == 0)
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(7),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 20, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          // Animated waveform reflecting playback progress
          ...List.generate(18, (i) {
            final h = (5 + (i * 1.7) % 14).toDouble();
            final played = (i / 18) <= progress;
            return Container(
              width: 2.5,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              decoration: BoxDecoration(
                color: played ? AppColors.primary : AppColors.textTertiary.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
          const SizedBox(width: 10),
          Text(
            _fmt(_duration == Duration.zero ? _position : (_playing ? _position : _duration)),
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
