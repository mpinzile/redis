import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/services/api_service.dart';
import '../../core/l10n/l10n_helper.dart';

/// Manage intro clip (video/audio) for a service
class ManageIntroClipScreen extends StatefulWidget {
  final String serviceId;
  final String serviceName;
  const ManageIntroClipScreen({super.key, required this.serviceId, required this.serviceName});

  @override
  State<ManageIntroClipScreen> createState() => _ManageIntroClipScreenState();
}

class _ManageIntroClipScreenState extends State<ManageIntroClipScreen> {
  List<dynamic> _media = [];
  bool _loading = true;
  bool _uploading = false;

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordPath;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  static String get _baseUrl => ApiService.baseUrl;

  TextStyle _f({required double size, FontWeight weight = FontWeight.w500, Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color);

  Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {'Content-Type': 'application/json', 'Accept': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<Map<String, String>> _authOnlyHeaders() async {
    final token = await SecureTokenStorage.getToken();
    return {'Accept': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$_baseUrl/user-services/${widget.serviceId}/intro-media'), headers: await _headers());
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final media = data is Map ? (data['data'] ?? data['intro_media'] ?? []) : (data is List ? data : []);
        setState(() { _media = media is List ? media : []; _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadClip({String source = 'video'}) async {
    String? filePath;
    String mediaType = 'video';
    if (source == 'video') {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      filePath = picked.path;
    } else {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.audio, allowMultiple: false, withData: false,
      );
      if (res == null || res.files.isEmpty) return;
      filePath = res.files.single.path;
      mediaType = 'audio';
    }
    if (filePath == null) return;
    await _doUpload(filePath, mediaType);
  }

  Future<void> _doUpload(String filePath, String mediaType) async {
    setState(() => _uploading = true);
    try {
      final uri = Uri.parse('$_baseUrl/user-services/${widget.serviceId}/intro-media');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authOnlyHeaders());
      request.fields['media_type'] = mediaType;
      request.files.add(await http.MultipartFile.fromPath('media', filePath));
      final streamedRes = await request.send();
      if (streamedRes.statusCode >= 200 && streamedRes.statusCode < 300) {
        if (mounted) AppSnackbar.success(context, 'Intro clip uploaded');
        _loadMedia();
      } else {
        if (mounted) AppSnackbar.error(context, 'Failed to upload clip');
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to upload clip');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) AppSnackbar.error(context, 'Microphone permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/intro_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: path,
      );
      _recordPath = path;
      _recordDuration = Duration.zero;
      setState(() => _isRecording = true);
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordDuration += const Duration(seconds: 1));
      });
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Could not start recording');
    }
  }

  Future<void> _cancelRecording() async {
    try { await _recorder.stop(); } catch (_) {}
    _recordTimer?.cancel();
    if (_recordPath != null) {
      try { File(_recordPath!).deleteSync(); } catch (_) {}
    }
    _recordPath = null;
    if (mounted) setState(() { _isRecording = false; _recordDuration = Duration.zero; });
  }

  Future<void> _stopAndUpload() async {
    String? p;
    try { p = await _recorder.stop(); } catch (_) {}
    _recordTimer?.cancel();
    if (mounted) setState(() { _isRecording = false; _recordDuration = Duration.zero; });
    final filePath = p ?? _recordPath;
    _recordPath = null;
    if (filePath == null || filePath.isEmpty) return;
    await _doUpload(filePath, 'audio');
  }

  Future<void> _deleteClip(String mediaId) async {
    try {
      final res = await http.delete(Uri.parse('$_baseUrl/user-services/${widget.serviceId}/intro-media/$mediaId'), headers: await _headers());
      if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
        AppSnackbar.success(context, 'Clip removed');
        _loadMedia();
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to remove clip');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: NuruSubPageAppBar(title: '${widget.serviceName} · Intro Clip'),
      body: _loading
          ? SkeletonGroup(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  SkeletonBox(height: 56, radius: 14),
                  SizedBox(height: 16),
                  SkeletonBox(height: 200, radius: 16),
                  SizedBox(height: 16),
                  SkeletonLine(widthFactor: 0.5, height: 12),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Info box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    SvgPicture.asset('assets/icons/video-icon.svg', width: 20, height: 20, colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Upload a short video, audio clip, or record a voice intro to introduce your service.', style: _f(size: 12, color: AppColors.primary))),
                  ]),
                ),
                const SizedBox(height: 20),

                // Existing clips
                if (_media.isNotEmpty)
                  ..._media.map((m) {
                    final mediaId = m is Map ? m['id']?.toString() ?? '' : '';
                    final mediaType = m is Map ? (m['media_type']?.toString() ?? 'video') : 'video';
                    final mediaUrl = m is Map ? (m['media_url']?.toString() ?? '') : '';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                          child: Center(child: SvgPicture.asset('assets/icons/video-icon.svg', width: 22, height: 22,
                            colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn))),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(mediaType == 'video' ? 'Video Clip' : 'Audio Clip', style: _f(size: 14, weight: FontWeight.w600)),
                          if (mediaUrl.isNotEmpty)
                            Text(mediaUrl.split('/').last, style: _f(size: 11, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                        GestureDetector(
                          onTap: () => _deleteClip(mediaId),
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                          ),
                        ),
                      ]),
                    );
                  }),

                if (_isRecording) _buildRecordingBar() else _buildActions(),
              ],
            ),
    );
  }

  Widget _buildActions() {
    Widget btn(String label, IconData icon, VoidCallback? onTap) => Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: AppColors.primary),
        label: Text(label, style: _f(size: 12, weight: FontWeight.w600, color: AppColors.primary)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.primary.withOpacity(0.45)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
    return Row(children: [
      btn('Video', Icons.videocam_rounded, _uploading ? null : () => _uploadClip(source: 'video')),
      const SizedBox(width: 8),
      btn('Audio file', Icons.audiotrack_rounded, _uploading ? null : () => _uploadClip(source: 'audio')),
      const SizedBox(width: 8),
      btn('Record', Icons.mic_rounded, _uploading ? null : _startRecording),
    ]);
  }

  Widget _buildRecordingBar() {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(_recordDuration.inMinutes.remainder(60));
    final s = two(_recordDuration.inSeconds.remainder(60));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withOpacity(0.30)),
      ),
      child: Row(children: [
        const Icon(Icons.fiber_manual_record_rounded, size: 16, color: AppColors.error),
        const SizedBox(width: 8),
        Text('Recording  $m:$s', style: _f(size: 14, weight: FontWeight.w600, color: AppColors.error)),
        const Spacer(),
        TextButton(onPressed: _cancelRecording, child: Text('Cancel', style: _f(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary))),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: _stopAndUpload,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('Stop & upload', style: _f(size: 12, weight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
