import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/moments_service.dart';
import '../../../core/theme/app_colors.dart';
import 'glimpse_trim_screen.dart';
import '../../../widgets/nuru_emoji_picker.dart';

/// Modern full-screen Glimpse composer.
/// Layout (top→bottom):
///   • Top bar: Close (left)  ·  Share (right)
///   • Canvas: text or media
///   • Tool dock (text mode): font / align / keyboard
///   • Color rail (text mode, horizontal)
///   • Mode switcher: Text · Photo · Video
class GlimpseComposerScreen extends StatefulWidget {
  const GlimpseComposerScreen({super.key});

  @override
  State<GlimpseComposerScreen> createState() => _GlimpseComposerScreenState();
}

enum _Mode { text, photo, video }

class _Bg {
  final String hex;
  final List<Color> gradient;
  const _Bg(this.hex, this.gradient);
}

class _GlimpseComposerScreenState extends State<GlimpseComposerScreen> {
  static final List<_Bg> _bgs = [
    _Bg('#0F172A', [const Color(0xFF0F172A), const Color(0xFF1E293B)]),
    _Bg('#7C3AED', [const Color(0xFF7C3AED), const Color(0xFFEC4899)]),
    _Bg('#0EA5E9', [const Color(0xFF0EA5E9), const Color(0xFF22D3EE)]),
    _Bg('#10B981', [const Color(0xFF059669), const Color(0xFF34D399)]),
    _Bg('#F59E0B', [const Color(0xFFF59E0B), const Color(0xFFEF4444)]),
    _Bg('#EC4899', [const Color(0xFFEC4899), const Color(0xFFF43F5E)]),
    _Bg('#1E1B4B', [const Color(0xFF1E1B4B), const Color(0xFF7C3AED)]),
    _Bg('#FECA08', [const Color(0xFFFECA08), const Color(0xFFF59E0B)]),
  ];

  /// Pick black or white text depending on background luminance for legibility.
  Color get _fg {
    final c = _bg.gradient.first;
    final l = (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) / 255;
    return l > 0.65 ? const Color(0xFF111111) : Colors.white;
  }

  static const _fonts = ['Sora', 'Playfair', 'Mono'];

  _Mode _mode = _Mode.text;
  final _textCtrl = TextEditingController();
  final _captionCtrl = TextEditingController();
  _Bg _bg = _bgs.first;
  String _font = 'Sora';
  TextAlign _align = TextAlign.center;
  File? _media;
  bool _submitting = false;
  double _uploadProgress = 0.0;
  bool _editingText = false;
  bool _editingCaption = false;
  bool _toolsCollapsed = false;
  final _picker = ImagePicker();
  final _focus = FocusNode();
  final _captionFocus = FocusNode();
  VideoPlayerController? _videoPreview;
  bool _videoPreviewReady = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _focus.addListener(() {
      if (mounted) setState(() => _editingText = _focus.hasFocus);
    });
    _captionFocus.addListener(() {
      if (mounted) setState(() => _editingCaption = _captionFocus.hasFocus);
    });
    _textCtrl.addListener(_refreshInputs);
    _captionCtrl.addListener(_refreshInputs);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _captionCtrl.dispose();
    _focus.dispose();
    _captionFocus.dispose();
    _videoPreview?.dispose();
    super.dispose();
  }

  void _refreshInputs() {
    if (mounted) setState(() {});
  }

  bool _videoMuted = false;

  Future<bool> _prepareVideoPreview(File file) async {
    _videoPreview?.dispose();
    final controller = VideoPlayerController.file(file);
    _videoPreview = controller;
    _videoPreviewReady = false;
    try {
      await controller.initialize();
      if (!mounted || _videoPreview != controller) return false;
      if (controller.value.duration > const Duration(seconds: 30)) {
        controller.dispose();
        if (_videoPreview == controller) _videoPreview = null;
        if (mounted) {
          setState(() {
            _media = null;
            _videoPreviewReady = false;
          });
          _toast('Video must be 30 seconds or less');
        }
        return false;
      }
      await controller.setLooping(true);
      // Allow the user to listen to the video while composing.
      await controller.setVolume(_videoMuted ? 0.0 : 1.0);
      await controller.play();
      if (mounted) setState(() => _videoPreviewReady = true);
      return true;
    } catch (_) {
      if (mounted && _videoPreview == controller) {
        setState(() => _videoPreviewReady = false);
      }
      return false;
    }
  }

  void _toggleVideoMute() {
    final c = _videoPreview;
    if (c == null || !c.value.isInitialized) return;
    setState(() => _videoMuted = !_videoMuted);
    c.setVolume(_videoMuted ? 0.0 : 1.0);
  }

  void _clearVideoPreview() {
    _videoPreview?.dispose();
    _videoPreview = null;
    _videoPreviewReady = false;
  }

  Future<void> _pickMedia() async {
    final picked = _mode == _Mode.photo
        ? await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90)
        : await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    File file = File(picked.path);

    if (_mode == _Mode.video) {
      // Probe duration; if > 30s, push the WhatsApp-style trim screen.
      final probe = VideoPlayerController.file(file);
      try {
        await probe.initialize();
        final durSec = probe.value.duration.inMilliseconds / 1000.0;
        await probe.dispose();
        if (durSec > 30.0 && mounted) {
          final trimmed = await Navigator.of(context).push<File>(
            MaterialPageRoute(
              builder: (_) => GlimpseTrimScreen(source: file, maxDurationSeconds: 30),
            ),
          );
          if (trimmed == null) return;
          file = trimmed;
        }
      } catch (_) {
        await probe.dispose();
      }

      setState(() => _media = file);
      final ok = await _prepareVideoPreview(file);
      if (!ok && mounted) setState(() => _media = null);
    } else {
      setState(() => _media = file);
      _clearVideoPreview();
    }
  }

  void _toggleVideoPreview() {
    final c = _videoPreview;
    if (c == null || !c.value.isInitialized) return;
    c.value.isPlaying ? c.pause() : c.play();
    setState(() {});
  }

  TextStyle _textStyle(double size) {
    final c = _fg;
    switch (_font) {
      case 'Playfair':
        return GoogleFonts.playfairDisplay(
            color: c, fontSize: size, fontWeight: FontWeight.w700, height: 1.25);
      case 'Mono':
        return GoogleFonts.jetBrainsMono(
            color: c, fontSize: size - 2, fontWeight: FontWeight.w600, height: 1.4);
      default:
        return GoogleFonts.sora(
            color: c, fontSize: size, fontWeight: FontWeight.w700, height: 1.3);
    }
  }

  Future<void> _publish() async {
    if (_submitting) return;
    if (_mode == _Mode.text && _textCtrl.text.trim().isEmpty) {
      _toast('Type something first');
      return;
    }
    if (_mode != _Mode.text && _media == null) {
      _toast('Pick a ${_mode == _Mode.photo ? 'photo' : 'video'} first');
      return;
    }
    setState(() {
      _submitting = true;
      _uploadProgress = 0.0;
    });
    HapticFeedback.lightImpact();
    final res = await MomentsService.createMoment(
      contentType: _mode == _Mode.text
          ? 'text'
          : (_mode == _Mode.photo ? 'image' : 'video'),
      caption: _mode == _Mode.text
          ? _textCtrl.text.trim()
          : _captionCtrl.text.trim(),
      backgroundColor: _mode == _Mode.text ? _bg.hex : null,
      mediaPath: _media?.path,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _uploadProgress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _uploadProgress = 0.0;
    });
    if (res['success'] == true) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res['message']?.toString() ?? 'Failed to publish');
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m, style: GoogleFonts.inter(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: _canvas()),

            // ── TOP BAR ─────────────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      _circleBtn(
                        svg: 'assets/icons/close-icon.svg',
                        onTap: _submitting ? null : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      // "Hold to replace" lives next to Share at the top so it
                      // doesn't get covered by the caption bar at the bottom.
                      if (_mode != _Mode.text && _media != null) ...[
                        Expanded(child: _replaceHintChip()),
                        const SizedBox(width: 8),
                      ] else
                        const Spacer(),
                      if (_mode == _Mode.video && _videoPreviewReady) ...[
                        _circleMaterialBtn(
                          icon: _videoMuted ? Icons.volume_off : Icons.volume_up,
                          onTap: _toggleVideoMute,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _shareBtn(),
                    ],
                  ),
                ),
              ),
            ),

            // ── BOTTOM CONTROLS ─────────────────────────────────
          if (_mode != _Mode.text && _media != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: _editingCaption
                  ? mq.viewInsets.bottom + mq.padding.bottom + 10
                  : mq.padding.bottom + 78,
              child: _captionField(),
            ),

          // ── BOTTOM CONTROLS ─────────────────────────────────
          // Text mode: keep tools accessible but allow collapse so they
          // don't overlap the typing area. Media mode: caption owns the
          // bottom while editing.
          if (_mode == _Mode.text || (!_editingText && !_editingCaption))
            Positioned(
              left: 0, right: 0,
              bottom: _editingText
                  ? mq.viewInsets.bottom + 8
                  : 0,
              child: SafeArea(
                top: false,
                bottom: !_editingText,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: (_mode == _Mode.text && _editingText && _toolsCollapsed)
                      ? _collapsedToolsHandle()
                      : Container(
                          key: const ValueKey('tools-expanded'),
                          padding:
                              const EdgeInsets.fromLTRB(14, 8, 14, 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.55),
                              ],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_mode == _Mode.text && _editingText)
                                _toolsCollapseHandle(),
                              if (_mode == _Mode.text) ...[
                                _textToolbar(),
                                const SizedBox(height: 10),
                                _colorRailHorizontal(),
                                const SizedBox(height: 12),
                              ],
                              if (!_editingText) _modeSwitcher(),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          // ── UPLOAD OVERLAY ──────────────────────────────────
          if (_submitting)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withOpacity(0.45),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 220,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: (_uploadProgress > 0 && _uploadProgress < 1)
                                  ? _uploadProgress
                                  : null,
                              minHeight: 6,
                              backgroundColor: Colors.white.withOpacity(0.15),
                              valueColor:
                                  const AlwaysStoppedAnimation(AppColors.primary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _uploadProgress >= 1.0
                              ? 'Finishing up…'
                              : (_uploadProgress > 0
                                  ? 'Uploading ${(_uploadProgress * 100).round()}%'
                                  : 'Preparing…'),
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Canvas ────────────────────────────────────────────────────
  Widget _canvas() {
    if (_mode == _Mode.text) return _textCanvas();
    return _mediaCanvas();
  }

  Widget _textCanvas() {
    final size = _textCtrl.text.length > 150
        ? 22.0
        : (_textCtrl.text.length > 80 ? 24.0 : 28.0);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _bg.gradient,
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focusTextField,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 110, 28, 210),
            child: SizedBox(
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_textCtrl.text.isEmpty)
                    IgnorePointer(
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          'Type a status',
                          textAlign: _align,
                          style: _textStyle(size).copyWith(
                            color: _fg.withOpacity(0.45),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  EditableText(
                    controller: _textCtrl,
                    focusNode: _focus,
                    style: _textStyle(size),
                    cursorColor: _fg,
                    backgroundCursorColor: _fg.withOpacity(0.25),
                    textAlign: _align,
                    textDirection: TextDirection.ltr,
                    maxLines: null,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    keyboardAppearance: Brightness.dark,
                    textCapitalization: TextCapitalization.sentences,
                    autocorrect: false,
                    enableSuggestions: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    inputFormatters: [LengthLimitingTextInputFormatter(280)],
                    selectionColor: _fg.withOpacity(0.22),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mediaCanvas() {
    if (_media == null) {
      return GestureDetector(
        onTap: _pickMedia,
        child: Container(
          color: const Color(0xFF111114),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    _mode == _Mode.photo
                        ? 'assets/icons/image-icon.svg'
                        : 'assets/icons/video-icon.svg',
                    width: 30, height: 30,
                    colorFilter: const ColorFilter.mode(
                        Colors.white, BlendMode.srcIn),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _mode == _Mode.photo ? 'Add a photo' : 'Add a video',
                style: GoogleFonts.sora(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text('Tap to browse your library',
                  style: GoogleFonts.inter(
                      color: Colors.white60,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    }
    if (_mode == _Mode.photo) {
      return GestureDetector(
        onTap: _pickMedia,
        child: Container(
          color: const Color(0xFF0A0A0C),
          alignment: Alignment.center,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Centered, contained image so the full photo is visible inside
              // a clean black container instead of being cropped edge-to-edge.
              Center(
                child: Image.file(_media!, fit: BoxFit.contain),
              ),
              _mediaShade(),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _toggleVideoPreview,
      onLongPress: _pickMedia,
      child: Container(
        color: const Color(0xFF0A0A0C),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_videoPreviewReady && _videoPreview != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _videoPreview!.value.aspectRatio == 0
                      ? 9 / 16
                      : _videoPreview!.value.aspectRatio,
                  child: VideoPlayer(_videoPreview!),
                ),
              )
            else
              Center(
                child: SvgPicture.asset(
                  'assets/icons/video-icon.svg',
                  width: 34,
                  height: 34,
                  colorFilter:
                      const ColorFilter.mode(Colors.white70, BlendMode.srcIn),
                ),
              ),
            _mediaShade(),
            if (_videoPreviewReady &&
                _videoPreview != null &&
                !_videoPreview!.value.isPlaying)
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/icons/play-icon.svg',
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(
                          Colors.white, BlendMode.srcIn),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mediaShade() {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.34),
              Colors.transparent,
              Colors.black.withOpacity(0.42),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
      ),
    );
  }

  // ─── Top bar pieces ────────────────────────────────────────────
  Widget _circleBtn({required String svg, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Center(
          child: SvgPicture.asset(svg,
              width: 18, height: 18,
              colorFilter:
                  const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
        ),
      ),
    );
  }

  Widget _circleMaterialBtn({required IconData icon, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  /// "Hold to replace" hint that lives in the top bar (next to Share)
  /// so it never gets covered by the caption field at the bottom.
  Widget _replaceHintChip() {
    return GestureDetector(
      onTap: _pickMedia,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Tap to replace',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareBtn() {
    return GestureDetector(
      onTap: _submitting ? null : _publish,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: _submitting
              ? AppColors.primary.withOpacity(0.6)
              : AppColors.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.4),
              blurRadius: 14,
              spreadRadius: 0.5,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_submitting)
              const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation(Colors.black)))
            else
              SvgPicture.asset('assets/icons/send-icon.svg',
                  width: 16, height: 16,
                  colorFilter: const ColorFilter.mode(
                      Colors.black, BlendMode.srcIn)),
            const SizedBox(width: 8),
            Text(
                _submitting
                    ? (_uploadProgress > 0 && _uploadProgress < 1
                        ? 'Uploading ${(_uploadProgress * 100).round()}%'
                        : 'Sharing…')
                    : 'Share',
                style: GoogleFonts.inter(
                    color: Colors.black,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }

  // Reliably opens the keyboard even after font/align toggles steal focus.
  void _focusTextField() {
    if (!_focus.hasFocus) {
      FocusScope.of(context).requestFocus(_focus);
    }
    // Re-attach the platform input connection so the OS keyboard appears.
    SystemChannels.textInput.invokeMethod('TextInput.show');
    setState(() => _toolsCollapsed = false);
  }

  // Tiny pull-tab to expand the toolbar after the user collapsed it.
  Widget _collapsedToolsHandle() {
    return GestureDetector(
      key: const ValueKey('tools-collapsed'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _toolsCollapsed = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white70,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Show tools',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Small grab-handle above the toolbar to collapse it out of the typing area.
  Widget _toolsCollapseHandle() {
    return GestureDetector(
      onTap: () => setState(() => _toolsCollapsed = true),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(bottom: 6),
        alignment: Alignment.center,
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white54,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  // ─── Text mode toolbar (font · align · keyboard) ───────────────
  Widget _textToolbar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolPill(
            label: _font,
            onTap: () {
              final i = _fonts.indexOf(_font);
              setState(() => _font = _fonts[(i + 1) % _fonts.length]);
              if (_editingText) {
                SystemChannels.textInput.invokeMethod('TextInput.show');
              }
            },
          ),
          const SizedBox(width: 4),
          _alignButton(),
          const SizedBox(width: 4),
          _toolSvg(
            svg: 'assets/icons/keyboard-icon.svg',
            onTap: _focusTextField,
          ),
        ],
      ),
    );
  }

  Widget _toolPill({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3)),
      ),
    );
  }

  Widget _alignButton() {
    final align = _align == TextAlign.left
        ? Alignment.centerLeft
        : (_align == TextAlign.right ? Alignment.centerRight : Alignment.center);
    return GestureDetector(
      onTap: () {
        const next = {
          TextAlign.center: TextAlign.left,
          TextAlign.left: TextAlign.right,
          TextAlign.right: TextAlign.center,
        };
        setState(() => _align = next[_align]!);
        if (_editingText) {
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      },
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Align(alignment: align, child: _alignLine(15)),
            Align(alignment: align, child: _alignLine(11)),
            Align(alignment: align, child: _alignLine(15)),
          ],
        ),
      ),
    );
  }

  Widget _alignLine(double width) => Container(
        width: width,
        height: 2,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _toolSvg({required String svg, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: SvgPicture.asset(svg,
              width: 16, height: 16,
              colorFilter: const ColorFilter.mode(
                  Colors.white, BlendMode.srcIn)),
        ),
      ),
    );
  }

  // ─── Horizontal color rail ─────────────────────────────────────
  Widget _colorRailHorizontal() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: _bgs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final b = _bgs[i];
          final selected = b.hex == _bg.hex;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _bg = b);
            },
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: b.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Colors.white : Colors.white30,
                  width: selected ? 2.5 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.25),
                          blurRadius: 8,
                        )
                      ]
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Caption field for media modes ─────────────────────────────
  Widget _captionField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.58),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 22, maxHeight: 86),
              child: Stack(
                children: [
                  if (_captionCtrl.text.isEmpty)
                    IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          'Add a caption',
                          style: GoogleFonts.inter(
                            color: Colors.white.withOpacity(0.58),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: EditableText(
                      controller: _captionCtrl,
                      focusNode: _captionFocus,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                      cursorColor: Colors.white,
                      backgroundCursorColor: Colors.white24,
                      selectionColor: Colors.white.withOpacity(0.22),
                      keyboardAppearance: Brightness.dark,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 3,
                      minLines: 1,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      inputFormatters: [LengthLimitingTextInputFormatter(160)],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              HapticFeedback.selectionClick();
              FocusScope.of(context).unfocus();
              final picked = await NuruEmojiPicker.show(context);
              if (picked == null) return;
              final sel = _captionCtrl.selection;
              final text = _captionCtrl.text;
              final start = sel.isValid ? sel.start : text.length;
              final end = sel.isValid ? sel.end : text.length;
              final next = text.replaceRange(start, end, picked);
              _captionCtrl.value = TextEditingValue(
                text: next,
                selection: TextSelection.collapsed(
                    offset: start + picked.length),
              );
            },
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Text('😊', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }


  // ─── Mode switcher ─────────────────────────────────────────────
  Widget _modeSwitcher() {
    Widget pill(_Mode m, String icon, String label) {
      final selected = _mode == m;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            FocusScope.of(context).unfocus();
            if (_mode == _Mode.video && m != _Mode.video) _clearVideoPreview();
            setState(() {
              _mode = m;
              _media = null;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 44,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  icon,
                  width: 16, height: 16,
                  colorFilter: ColorFilter.mode(
                      selected ? Colors.black : Colors.white,
                      BlendMode.srcIn),
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: GoogleFonts.inter(
                      color: selected ? Colors.black : Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        children: [
          pill(_Mode.text, 'assets/icons/echo-icon.svg', 'Text'),
          pill(_Mode.photo, 'assets/icons/image-icon.svg', 'Photo'),
          pill(_Mode.video, 'assets/icons/video-icon.svg', 'Video'),
        ],
      ),
    );
  }
}
