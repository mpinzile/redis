import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/photo_libraries_service.dart';
import '../../core/services/media_transfer_manager.dart';
import '../../core/widgets/app_snackbar.dart';

/// Add to Library - upload files (photos/videos), create album, from cloud.
///
/// Uses [MediaTransferManager] so uploads continue in the background while
/// the user navigates away.
class UploadToLibraryScreen extends StatefulWidget {
  final Map<String, dynamic> library;
  const UploadToLibraryScreen({super.key, required this.library});

  @override
  State<UploadToLibraryScreen> createState() => _UploadToLibraryScreenState();
}

class _UploadToLibraryScreenState extends State<UploadToLibraryScreen> {
  int _tabIndex = 0;
  String _privacy = 'event_creator_only';
  bool _notify = true;
  // Files the user has picked but NOT yet uploaded - uploads only start
  // when they tap the bottom "Upload Files (N)" button.
  final List<_PendingFile> _pending = [];
  // Active/finished upload tasks tracked by the manager.
  final List<TransferTask> _items = [];
  bool _privacyDirty = false;
  late final VoidCallback _transferListener;

  static const int _maxLibraryBytes = 200 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _privacy = (widget.library['privacy']?.toString() ?? 'event_creator_only').toLowerCase();
    // Re-attach any existing in-flight tasks for this library.
    _items.addAll(MediaTransferManager.instance
        .tasksForLibrary(widget.library['id']?.toString() ?? '')
        .where((t) => t.kind == TransferKind.upload &&
            t.status != TransferStatus.done &&
            t.status != TransferStatus.cancelled));
    _transferListener = () { if (mounted) setState(() {}); };
    MediaTransferManager.instance.addListener(_transferListener);
  }

  @override
  void dispose() {
    MediaTransferManager.instance.removeListener(_transferListener);
    super.dispose();
  }

  int get _usedBytes {
    final lib = widget.library;
    final used = lib['total_size_bytes'];
    if (used is num) return used.toInt();
    final mb = lib['total_size_mb'];
    if (mb is num) return (mb * 1024 * 1024).toInt();
    return 0;
  }

  int get _libLimitBytes {
    final mb = widget.library['storage_limit_mb'];
    if (mb is num) return (mb * 1024 * 1024).toInt();
    return _maxLibraryBytes;
  }

  int get _pendingBytes =>
      _pending.fold<int>(0, (s, f) => s + f.size) +
      _items
          .where((i) => i.status != TransferStatus.done)
          .fold<int>(0, (s, i) => s + i.sizeBytes);

  Future<void> _pickFiles() async {
    try {
      print('[LibraryUploadUI] opening file picker for library=${widget.library['id']}');
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'avif', 'heic', 'heif', 'gif', 'mp4', 'mov', 'm4v', '3gp', 'avi', 'mkv', 'webm'],
      );
      if (res == null) {
        print('[LibraryUploadUI] file picker cancelled');
        return;
      }
      print('[LibraryUploadUI] picked ${res.files.length} file(s)');
      final remaining = _libLimitBytes - _usedBytes - _pendingBytes;
      int overflow = 0;
      int budget = remaining;
      for (final f in res.files) {
        print('[LibraryUploadUI] candidate name=${f.name} size=${f.size} path=${f.path}');
        if (f.path == null) {
          print('[LibraryUploadUI] skipped ${f.name}: picker returned null path');
          continue;
        }
        // Skip duplicates already queued/picked.
        if (_pending.any((p) => p.path == f.path)) {
          print('[LibraryUploadUI] skipped ${f.name}: duplicate pending file');
          continue;
        }
        if (_items.any((t) => t.sourcePath == f.path)) {
          print('[LibraryUploadUI] skipped ${f.name}: already queued task');
          continue;
        }
        final lower = f.name.toLowerCase();
        final isVideo = _isVideoName(lower);
        final perItemLimit = 10 * 1024 * 1024;
        if (f.size > perItemLimit) {
          print('[LibraryUploadUI] skipped ${f.name}: size ${f.size} exceeds $perItemLimit');
          overflow += f.size;
          continue;
        }
        if (f.size > budget) {
          print('[LibraryUploadUI] skipped ${f.name}: size ${f.size} exceeds remaining budget $budget');
          overflow += f.size;
          continue;
        }
        budget -= f.size;
        _pending.add(_PendingFile(
          path: f.path!,
          name: f.name,
          size: f.size,
          isVideo: isVideo,
        ));
        print('[LibraryUploadUI] accepted ${f.name} isVideo=$isVideo pending=${_pending.length}');
      }
      setState(() {});
      if (overflow > 0 && mounted) {
        AppSnackbar.error(context, 'Some files skipped · photos and videos must be 10MB or less');
      }
    } catch (e) {
      print('[LibraryUploadUI] file picker error: ${e.runtimeType}: $e');
      if (mounted) AppSnackbar.error(context, 'Unable to pick files');
    }
  }

  /// Move all pending files into the manager and start their uploads.
  void _startUploads() {
    if (_pending.isEmpty) {
      print('[LibraryUploadUI] upload pressed with no pending files');
      return;
    }
    final libId = widget.library['id']?.toString() ?? '';
    print('[LibraryUploadUI] starting ${_pending.length} upload(s) for library=$libId');
    final batch = List<_PendingFile>.from(_pending);
    for (final f in batch) {
      print('[LibraryUploadUI] queue upload name=${f.name} path=${f.path} size=${f.size} isVideo=${f.isVideo}');
      final task = MediaTransferManager.instance
          .queueUpload(libraryId: libId, filePath: f.path);
      _items.add(task);
    }
    setState(() => _pending.clear());
  }

  Future<void> _finish() async {
    final libId = widget.library['id']?.toString() ?? '';
    final currentPrivacy = (widget.library['privacy']?.toString() ?? 'event_creator_only').toLowerCase();
    if (_privacyDirty && _privacy != currentPrivacy) {
      await PhotoLibrariesService.updateLibrary(libId, privacy: _privacy);
    }
    final anyDone = _items.any((t) => t.status == TransferStatus.done);
    MediaTransferManager.instance.clearCompleted(libraryId: libId);
    if (mounted) Navigator.pop(context, anyDone);
  }

  void _togglePauseAll() {
    final allPaused = _items.every((t) => t.status == TransferStatus.paused || !t.isActive);
    for (final t in _items) {
      if (allPaused) {
        MediaTransferManager.instance.resume(t);
      } else if (t.isActive) {
        t.pause();
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _libraryCard(),
                  const SizedBox(height: 16),
                  _tabs(),
                  const SizedBox(height: 14),
                  if (_tabIndex == 0) ..._uploadTab(),
                  if (_tabIndex == 1) _comingSoon('Create Album', 'Group your media into albums'),
                  if (_tabIndex == 2) _comingSoon('From Cloud', 'Google Drive & Dropbox · coming soon'),
                ],
              ),
            ),
            if (_tabIndex == 0) _bottomBar(),
          ]),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(children: [
        IconButton(
          onPressed: _finish,
          icon: SvgPicture.asset('assets/icons/arrow-left-icon.svg', width: 22, height: 22,
            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
        ),
        Expanded(child: Center(child: Text('Add to Library', style: appText(size: 16, weight: FontWeight.w700)))),
        const SizedBox(width: 48),
      ]),
    );
  }

  Widget _libraryCard() {
    final lib = widget.library;
    final name = lib['name']?.toString() ?? 'Library';
    final privacy = (lib['privacy']?.toString() ?? 'event_creator_only').toLowerCase();
    final used = _usedBytes;
    final limit = _libLimitBytes;
    final percent = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    // Prefer library cover/first photo, then event cover image.
    final cover = (lib['cover_image_url'] ?? lib['cover_url']) ??
        (lib['photos'] is List && (lib['photos'] as List).isNotEmpty
            ? (lib['photos'] as List).first['url']
            : null) ??
        lib['event']?['cover_image_url'] ??
        lib['event']?['cover_image'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 64, height: 64, color: const Color(0xFFF3F4F6),
            child: cover != null
                ? Image.network(cover.toString(), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(child: SvgPicture.asset(
                      'assets/icons/image-icon.svg', width: 22, height: 22,
                      colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn))))
                : Center(child: SvgPicture.asset('assets/icons/image-icon.svg', width: 22, height: 22,
                    colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn))),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: appText(size: 14, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            SvgPicture.asset(
              privacy == 'public' ? 'assets/icons/earth-icon.svg' : 'assets/icons/lock-icon.svg',
              width: 12, height: 12,
              colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn),
            ),
            const SizedBox(width: 5),
            Text(privacy == 'public' ? 'Public Library' : 'Private Library',
                style: appText(size: 11, color: AppColors.textTertiary)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent, minHeight: 5,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            )),
            const SizedBox(width: 8),
            Text('${(percent * 100).toStringAsFixed(0)}%',
                style: appText(size: 11, weight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text('${_fmtBytes(used)} of ${_fmtBytes(limit)} Used',
              style: appText(size: 10, color: AppColors.textTertiary)),
        ])),
      ]),
    );
  }

  Widget _tabs() {
    const labels = ['Upload Files', 'Create Album', 'From Cloud'];
    return Row(children: List.generate(labels.length, (i) {
      final active = i == _tabIndex;
      return Expanded(child: Padding(
        padding: EdgeInsets.only(right: i < labels.length - 1 ? 8 : 0),
        child: GestureDetector(
          onTap: () => setState(() => _tabIndex = i),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppColors.textPrimary : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? AppColors.textPrimary : AppColors.border),
            ),
            child: Center(child: Text(labels[i], style: appText(
              size: 12, weight: FontWeight.w500,
              color: active ? Colors.white : AppColors.textSecondary,
            ))),
          ),
        ),
      ));
    }));
  }

  List<Widget> _uploadTab() {
    return [
      _dropZone(),
      if (_pending.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('Selected (${_pending.length})',
            style: appText(size: 13, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        ..._pending.map(_pendingRow),
      ],
      if (_items.isNotEmpty) ...[
        const SizedBox(height: 18),
        Row(children: [
          Text('Uploading (${_items.length})', style: appText(size: 13, weight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: _togglePauseAll,
            child: Text(
              _items.every((t) => t.status == TransferStatus.paused || !t.isActive) ? 'Resume All' : 'Pause All',
              style: appText(size: 12, weight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ..._items.map((t) => AnimatedBuilder(
          animation: t, builder: (_, __) => _uploadRow(t),
        )),
      ],
      const SizedBox(height: 18),
      _settingsRow(),
    ];
  }

  Widget _pendingRow(_PendingFile f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40, height: 40, color: const Color(0xFFF3F4F6),
            child: _mediaPreview(f.path, f.isVideo),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.name, style: appText(size: 12, weight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${_fmtBytes(f.size)} · Ready to upload',
              style: appText(size: 10, color: AppColors.textTertiary)),
        ])),
        IconButton(
          onPressed: () => setState(() => _pending.remove(f)),
          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
        ),
      ]),
    );
  }

  Widget _dropZone() {
    return DottedBorderBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(children: [
          Container(
            width: 60, height: 60,
            decoration: const BoxDecoration(color: Color(0xFFF5F5F7), shape: BoxShape.circle),
            child: Center(child: SvgPicture.asset('assets/icons/upload-icon.svg', width: 28, height: 28,
              colorFilter: const ColorFilter.mode(Color(0xFF6B7280), BlendMode.srcIn))),
          ),
          const SizedBox(height: 14),
          Text('Drag and drop photos or videos here',
              style: appText(size: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text('or', style: appText(size: 11, color: AppColors.textTertiary)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _pickFiles,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
              child: Text('Select Files', style: appText(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
          ),
          const SizedBox(height: 12),
          Text('Supports: JPG, PNG, MP4, MOV (Max 10MB per file)',
              style: appText(size: 10, color: AppColors.textTertiary), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _uploadRow(TransferTask t) {
    final isVideo = (t.mediaType == 'video');
    final percent = (t.progress * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        // Thumbnail preview from local file (image only). Video → icon placeholder.
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40, height: 40, color: const Color(0xFFF3F4F6),
            child: t.sourcePath != null ? _mediaPreview(t.sourcePath!, isVideo) : _filePlaceholder(isVideo),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.name, style: appText(size: 12, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(_fmtBytes(t.sizeBytes), style: appText(size: 10, color: AppColors.textTertiary)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: t.progress, minHeight: 4,
              backgroundColor: const Color(0xFFF3F4F6),
              valueColor: AlwaysStoppedAnimation(
                t.status == TransferStatus.error ? AppColors.error
                  : t.status == TransferStatus.done ? AppColors.accent
                  : AppColors.primary,
              ),
            ),
          ),
          if (t.status == TransferStatus.error && t.error != null) ...[
            const SizedBox(height: 3),
            Text(t.error!, style: appText(size: 10, color: AppColors.error), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ])),
        const SizedBox(width: 6),
        SizedBox(
          width: 48,
          child: Text(
            t.status == TransferStatus.done ? '100%'
              : t.status == TransferStatus.error ? 'Failed'
              : t.status == TransferStatus.paused ? 'Paused'
              : '$percent%',
            textAlign: TextAlign.right,
            style: appText(
              size: 11, weight: FontWeight.w700,
              color: t.status == TransferStatus.error ? AppColors.error
                : t.status == TransferStatus.done ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ),
        // Action button: tick / pause / play / retry / close
        _rowAction(t),
      ]),
    );
  }

  Widget _filePlaceholder(bool isVideo) => Center(
    child: Icon(isVideo ? Icons.play_arrow_rounded : Icons.image_rounded,
        size: 20, color: AppColors.textSecondary),
  );

  Widget _mediaPreview(String path, bool isVideo) {
    if (!File(path).existsSync()) return _filePlaceholder(isVideo);
    if (isVideo) return _LocalVideoThumb(path: path);
    return Image.file(File(path), fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _filePlaceholder(false));
  }

  bool _isVideoName(String name) => name.endsWith('.mp4') || name.endsWith('.mov') ||
      name.endsWith('.m4v') || name.endsWith('.3gp') || name.endsWith('.avi') ||
      name.endsWith('.mkv') || name.endsWith('.webm');

  Widget _rowAction(TransferTask t) {
    if (t.status == TransferStatus.done) {
      return const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.check_circle, color: AppColors.accent, size: 20),
      );
    }
    if (t.status == TransferStatus.error) {
      return IconButton(
        onPressed: () => MediaTransferManager.instance.retry(t),
        icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.error),
      );
    }
    if (t.status == TransferStatus.paused) {
      return IconButton(
        onPressed: () => MediaTransferManager.instance.resume(t),
        icon: const Icon(Icons.play_circle_outline_rounded, size: 20, color: AppColors.textPrimary),
      );
    }
    if (t.isActive) {
      return IconButton(
        onPressed: () => t.pause(),
        icon: const Icon(Icons.pause_circle_outline_rounded, size: 20, color: AppColors.textPrimary),
      );
    }
    return IconButton(
      onPressed: () { t.cancel(); setState(() => _items.remove(t)); MediaTransferManager.instance.remove(t); },
      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
    );
  }

  Widget _settingsRow() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Make Library', style: appText(size: 12, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          _privacyPill('Private', 'event_creator_only', 'assets/icons/lock-icon.svg',
              const Color(0xFFF3E8FF), const Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          _privacyPill('Public', 'public', 'assets/icons/earth-icon.svg',
              const Color(0xFFDCFCE7), const Color(0xFF15803D)),
        ]),
      ])),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Notify People', style: appText(size: 12, weight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('Send notification to people with the link',
              style: appText(size: 10, color: AppColors.textTertiary))),
          Switch(
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
            activeColor: AppColors.primary,
          ),
        ]),
      ])),
    ]);
  }

  Widget _privacyPill(String label, String value, String iconPath, Color bg, Color fg) {
    final active = _privacy == value;
    return GestureDetector(
      onTap: () => setState(() { _privacy = value; _privacyDirty = true; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? bg : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? fg : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SvgPicture.asset(iconPath, width: 12, height: 12,
            colorFilter: ColorFilter.mode(active ? fg : AppColors.textTertiary, BlendMode.srcIn)),
          const SizedBox(width: 6),
          Text(label, style: appText(size: 11, weight: FontWeight.w700,
              color: active ? fg : AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _bottomBar() {
    final inFlight = _items.where((i) =>
      i.status != TransferStatus.done && i.status != TransferStatus.error &&
      i.status != TransferStatus.cancelled).length;
    final hasPending = _pending.isNotEmpty;
    final hasItems = _items.isNotEmpty;
    final enabled = hasPending || hasItems;

    String label;
    VoidCallback? action;
    if (hasPending) {
      label = 'Upload Files (${_pending.length})';
      action = _startUploads;
    } else if (inFlight > 0) {
      label = 'Uploading… ($inFlight)';
      action = _finish; // allow user to leave; uploads continue in background
    } else if (hasItems) {
      label = 'Done';
      action = _finish;
    } else {
      label = 'Upload Files';
      action = null;
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: enabled ? action : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: const Color(0xFFE5E5EA),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: Text(
              label,
              style: appText(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }




  Widget _comingSoon(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(child: Column(children: [
        Icon(Icons.hourglass_empty_rounded, size: 48, color: AppColors.textHint),
        const SizedBox(height: 12),
        Text(title, style: appText(size: 15, weight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(subtitle, style: appText(size: 12, color: AppColors.textTertiary)),
      ])),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

class _PendingFile {
  final String path;
  final String name;
  final int size;
  final bool isVideo;
  _PendingFile({required this.path, required this.name, required this.size, required this.isVideo});
}


class _LocalVideoThumb extends StatefulWidget {
  final String path;
  const _LocalVideoThumb({required this.path});

  @override
  State<_LocalVideoThumb> createState() => _LocalVideoThumbState();
}

class _LocalVideoThumbState extends State<_LocalVideoThumb> {
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dir = await getTemporaryDirectory();
      final path = await vt.VideoThumbnail.thumbnailFile(
        video: widget.path,
        thumbnailPath: dir.path,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 240,
        quality: 70,
      );
      if (mounted) setState(() => _thumbPath = path);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbPath == null || !File(_thumbPath!).existsSync()) {
      return const Center(child: Icon(Icons.play_arrow_rounded, size: 20, color: AppColors.textSecondary));
    }
    return Stack(fit: StackFit.expand, children: [
      Image.file(File(_thumbPath!), fit: BoxFit.cover),
      Container(color: Colors.black.withOpacity(0.12)),
      const Center(child: Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white)),
    ]);
  }
}



/// Dashed-border container used by the drop zone.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(14),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const radius = Radius.circular(14);
    final rect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    final path = Path()..addRRect(rect);
    final dashed = Path();
    const dashWidth = 6.0;
    const dashSpace = 5.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0, metric.length).toDouble();
        dashed.addPath(metric.extractPath(distance, end), Offset.zero);
        distance += dashWidth + dashSpace;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
