import '../../core/widgets/nuru_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/photo_libraries_service.dart';
import '../../core/services/media_transfer_manager.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/video_thumbnail_image.dart';
import '../../core/widgets/nuru_skeleton.dart';
import 'upload_to_library_screen.dart';
import 'media_viewer_screen.dart';
import 'transfers_screen.dart';

/// Photo Library Detail - gallery grouped by date, with action row + tabs.
class PhotoLibraryScreen extends StatefulWidget {
  final String libraryId;
  final String? libraryName;
  const PhotoLibraryScreen({super.key, required this.libraryId, this.libraryName});

  @override
  State<PhotoLibraryScreen> createState() => _PhotoLibraryScreenState();
}

class _PhotoLibraryScreenState extends State<PhotoLibraryScreen> {
  Map<String, dynamic>? _library;
  List<dynamic> _media = [];
  bool _loading = true;
  bool _updatingPrivacy = false;
  int _tabIndex = 0; // 0=All 1=Photos 2=Videos 3=Highlights 4=Albums
  final ScrollController _tabsScrollCtrl = ScrollController();
  final List<GlobalKey> _tabKeys = List.generate(5, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    final cached = PhotoLibrariesService.cached('library:${widget.libraryId}');
    if (cached?['success'] == true && cached?['data'] is Map<String, dynamic>) {
      _library = cached!['data'] as Map<String, dynamic>;
      _media = _library?['photos'] ?? [];
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _tabsScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_library == null) setState(() => _loading = true);
    final res = await PhotoLibrariesService.getLibrary(widget.libraryId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _library = res['data'] is Map<String, dynamic> ? res['data'] : null;
        _media = _library?['photos'] ?? [];
      }
    });
  }

  void _scrollActiveTabIntoView() {
    if (!mounted || !_tabsScrollCtrl.hasClients || _tabIndex >= _tabKeys.length) return;
    final ctx = _tabKeys[_tabIndex].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 260), curve: Curves.easeOut, alignment: 0.5);
  }

  Future<void> _openUpload() async {
    if (_library == null) return;
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => UploadToLibraryScreen(library: _library!),
    ));
    if (changed == true) _load();
  }

  Future<void> _deleteMedia(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete media?', style: appText(size: 16, weight: FontWeight.w700)),
        content: Text('This cannot be undone.', style: appText(size: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: appText(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: appText(size: 13, weight: FontWeight.w700, color: AppColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await PhotoLibrariesService.deletePhoto(widget.libraryId, id);
    if (!mounted) return;
    if (res['success'] == true) {
      AppSnackbar.success(context, 'Deleted');
      _load();
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Unable to delete');
    }
  }

  Future<void> _updatePrivacy(String privacy) async {
    if (_updatingPrivacy) return;
    final previous = _library?['privacy']?.toString();
    setState(() {
      _updatingPrivacy = true;
      if (_library != null) _library!['privacy'] = privacy;
    });
    final res = await PhotoLibrariesService.updateLibrary(widget.libraryId, privacy: privacy);
    if (!mounted) return;
    setState(() => _updatingPrivacy = false);
    if (res['success'] == true) {
      AppSnackbar.success(context, privacy == 'public' ? 'Library set to Public' : 'Library set to Private');
      final data = res['data'];
      if (data is Map && data['share_url'] != null) {
        setState(() => _library?['share_url'] = data['share_url']);
      }
    } else {
      setState(() { if (_library != null) _library!['privacy'] = previous; });
      AppSnackbar.error(context, res['message']?.toString() ?? 'Unable to update');
    }
  }

  void _shareLink() {
    final privacy = (_library?['privacy']?.toString() ?? 'event_creator_only').toLowerCase();
    if (privacy != 'public') {
      AppSnackbar.error(context, 'Set library to Public to share link');
      return;
    }
    final url = _library?['share_url']?.toString() ?? '';
    if (url.isNotEmpty) Share.share('Check out this photo library: $url', sharePositionOrigin: sharePositionOrigin(context));
  }

  void _downloadAll() {
    final media = _media.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    if (media.isEmpty) {
      AppSnackbar.error(context, 'Nothing to download');
      return;
    }
    MediaTransferManager.instance.downloadAll(
      libraryId: widget.libraryId,
      media: media,
      folderName: (_library?['name'] ?? 'Photo Library').toString(),
    );
    AppSnackbar.success(context, 'Downloading ${media.length} files');
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TransfersScreen(libraryId: widget.libraryId),
    ));
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final current = (_library?['privacy']?.toString() ?? 'event_creator_only').toLowerCase();
        return SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Row(children: [
              Text('Library Settings', style: appText(size: 16, weight: FontWeight.w700)),
              const Spacer(),
              if (_updatingPrivacy)
                const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            ]),
            const SizedBox(height: 14),
            _settingTile('assets/icons/earth-icon.svg', 'Public', 'Anyone with the link can view',
                active: current == 'public', activeColor: const Color(0xFF15803D),
                onTap: () async { await _updatePrivacy('public'); setSheet(() {}); }),
            const SizedBox(height: 10),
            _settingTile('assets/icons/lock-icon.svg', 'Private', 'Only owner and event organizer can view',
                active: current != 'public', activeColor: const Color(0xFF7C3AED),
                onTap: () async { await _updatePrivacy('event_creator_only'); setSheet(() {}); }),
          ]),
        ));
      }),
    );
  }

  Widget _settingTile(String iconPath, String title, String subtitle,
      {required bool active, required Color activeColor, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? activeColor : AppColors.border, width: active ? 1.5 : 1),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: active ? activeColor.withOpacity(0.12) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: SvgPicture.asset(iconPath, width: 18, height: 18,
              colorFilter: ColorFilter.mode(active ? activeColor : AppColors.textSecondary, BlendMode.srcIn))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: appText(size: 14, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: appText(size: 11, color: AppColors.textTertiary)),
          ])),
          if (active) Icon(Icons.check_circle, color: activeColor, size: 20),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.libraryName ?? _library?['name'] ?? 'Photo Library';
    final privacy = (_library?['privacy']?.toString() ?? 'event_creator_only').toLowerCase();
    final isOwner = _library?['is_owner'] == true;
    final eventDate = (_library?['event']?['start_date'] ?? _library?['created_at'])?.toString() ?? '';
    final createdByYou = isOwner ? 'Created by You' : 'Created by ${_library?['service']?['title'] ?? 'Service'}';
    final totalSizeMb = _toDouble(_library?['total_size_mb']) > 0
        ? _toDouble(_library?['total_size_mb'])
        : (_toDouble(_library?['total_size_bytes']) / (1024 * 1024));
    final double storageLimitMb = _toDouble(_library?['storage_limit_mb']) > 0 ? _toDouble(_library?['storage_limit_mb']) : 200.0;
    final percent = storageLimitMb > 0 ? (totalSizeMb / storageLimitMb).clamp(0.0, 1.0) : 0.0;
    final coverItem = _firstCoverItem();
    final cover = coverItem?['url'] as String?;
    final coverIsVideo = (coverItem?['media_type']?.toString() ?? 'photo') == 'video';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(children: [
            _header(name),
            Expanded(
              child: _loading
                  ? const NuruSkeletonGrid(itemCount: 9, crossAxisCount: 3, showCaption: false)
                  : NuruRefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        children: [
                          _coverBlock(cover, isOwner, coverIsVideo),
                          const SizedBox(height: 14),
                          Row(children: [
                            Expanded(child: Text(name, style: appText(size: 18, weight: FontWeight.w800))),
                            _privacyBadge(privacy),
                          ]),
                          const SizedBox(height: 6),
                          Row(children: [
                            SvgPicture.asset('assets/icons/calendar-icon.svg', width: 12, height: 12,
                              colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
                            const SizedBox(width: 6),
                            Text(_fmtDate(eventDate), style: appText(size: 11, color: AppColors.textTertiary)),
                            const SizedBox(width: 10),
                            Text('• $createdByYou', style: appText(size: 11, color: AppColors.textTertiary)),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percent, minHeight: 6,
                                backgroundColor: const Color(0xFFF3F4F6),
                                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                              ),
                            )),
                            const SizedBox(width: 10),
                            Text('${_fmtSize(totalSizeMb)} of ${_fmtSize(storageLimitMb)}',
                              style: appText(size: 11, color: AppColors.textSecondary)),
                            const SizedBox(width: 6),
                            Text('${(percent * 100).toStringAsFixed(0)}%',
                              style: appText(size: 11, weight: FontWeight.w700, color: AppColors.textPrimary)),
                          ]),
                          const SizedBox(height: 18),
                          _actionRow(),
                          const SizedBox(height: 18),
                          _tabPills(),
                          const SizedBox(height: 14),
                          ..._buildGroupedMedia(),
                        ],
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header(String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: SvgPicture.asset('assets/icons/arrow-left-icon.svg', width: 22, height: 22,
            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
        ),
        Expanded(child: Center(child: Text(name, style: appText(size: 16, weight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis))),
        IconButton(
          onPressed: _shareLink,
          icon: SvgPicture.asset('assets/icons/link-icon.svg', width: 20, height: 20,
            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
        ),
        IconButton(
          onPressed: _openSettings,
          icon: SvgPicture.asset('assets/icons/more-vertical-icon.svg', width: 20, height: 20,
            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
        ),
      ]),
    );
  }

  Widget _coverBlock(String? cover, bool isOwner, [bool isVideo = false]) {
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Container(
            color: const Color(0xFFF3F4F6),
            child: cover != null
                ? (isVideo
                    ? VideoThumbnailImage(videoUrl: cover, fit: BoxFit.cover)
                    : Image.network(cover, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.image, color: AppColors.textHint, size: 48)))
                : const Center(child: Icon(Icons.image, color: AppColors.textHint, size: 48)),
          ),
        ),
      ),
      if (isOwner)
        Positioned(
          right: 12, bottom: 12,
          child: GestureDetector(
            onTap: _openSettings,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                boxShadow: AppColors.subtleShadow),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SvgPicture.asset('assets/icons/pen-icon.svg', width: 12, height: 12,
                  colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
                const SizedBox(width: 6),
                Text('Edit Library', style: appText(size: 11, weight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _privacyBadge(String privacy) {
    final isPublic = privacy == 'public';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isPublic ? const Color(0xFFDCFCE7) : const Color(0xFFF3E8FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SvgPicture.asset(
          isPublic ? 'assets/icons/earth-icon.svg' : 'assets/icons/lock-icon.svg',
          width: 11, height: 11,
          colorFilter: ColorFilter.mode(
            isPublic ? const Color(0xFF15803D) : const Color(0xFF7C3AED),
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 5),
        Text(isPublic ? 'Public' : 'Private', style: appText(
          size: 10, weight: FontWeight.w700,
          color: isPublic ? const Color(0xFF15803D) : const Color(0xFF7C3AED),
        )),
      ]),
    );
  }

  Widget _actionRow() {
    final actions = <(String, String, VoidCallback)>[
      ('assets/icons/link-icon.svg', 'Share Link', _shareLink),
      ('assets/icons/plus-icon.svg', 'Add Photos/Videos', _openUpload),
      ('assets/icons/download-icon.svg', 'Download', _downloadAll),
      ('assets/icons/settings-icon.svg', 'Settings', _openSettings),
    ];
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _actionTile(actions[i].$1, actions[i].$2, actions[i].$3),
      ),
    );
  }

  Widget _actionTile(String iconPath, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: AppColors.subtleShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SvgPicture.asset(iconPath, width: 16, height: 16,
            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
          const SizedBox(width: 8),
          Text(label, style: appText(size: 12, weight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _tabPills() {
    const labels = ['All', 'Photos', 'Videos', 'Highlights', 'Albums'];
    return SingleChildScrollView(
      controller: _tabsScrollCtrl,
      scrollDirection: Axis.horizontal,
      child: Row(children: List.generate(labels.length, (i) {
        final active = i == _tabIndex;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            key: _tabKeys[i],
            onTap: () {
              setState(() => _tabIndex = i);
              WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveTabIntoView());
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.textPrimary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? AppColors.textPrimary : AppColors.border),
              ),
              child: Text(labels[i], style: appText(
                size: 12, weight: FontWeight.w700,
                color: active ? Colors.white : AppColors.textSecondary,
              )),
            ),
          ),
        );
      })),
    );
  }

  List<Map<String, dynamic>> get _filteredMedia {
    final all = _media.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    List<Map<String, dynamic>> list;
    switch (_tabIndex) {
      case 1: list = all.where((m) => (m['media_type'] ?? 'photo') == 'photo').toList(); break;
      case 2: list = all.where((m) => m['media_type'] == 'video').toList(); break;
      case 3: list = all.where((m) => m['is_highlight'] == true).toList(); break;
      case 4: list = all.where((m) => (m['album_name'] ?? '').toString().trim().isNotEmpty).toList(); break;
      default: list = all;
    }
    // Newest first by created_at (UTC-aware).
    list.sort((a, b) {
      final da = _parseUtcLocal((a['created_at'] ?? '').toString());
      final db = _parseUtcLocal((b['created_at'] ?? '').toString());
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return list;
  }

  List<Widget> _buildGroupedMedia() {
    final list = _filteredMedia;
    if (list.isEmpty) {
      return [Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Column(children: [
          Icon(Icons.photo_library_outlined, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text('No media yet', style: appText(size: 14, weight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Tap Add Photos/Videos to upload', style: appText(size: 12, color: AppColors.textTertiary)),
        ])),
      )];
    }

    // Group by local day; preserve newest-first order from the sorted list
    // by using a LinkedHashMap (default Dart map preserves insertion order).
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final m in list) {
      final date = (m['created_at'] ?? '').toString();
      final key = _dayLabel(date);
      groups.putIfAbsent(key, () => []).add(m);
    }

    final widgets = <Widget>[];
    groups.forEach((label, items) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(label, style: appText(size: 13, weight: FontWeight.w700)),
      ));
      widgets.add(GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, mainAxisSpacing: 4, crossAxisSpacing: 4),
        itemCount: items.length,
        itemBuilder: (_, i) => _mediaTile(items[i]),
      ));
    });
    return widgets;
  }

  Widget _mediaTile(Map<String, dynamic> media) {
    final url = media['url']?.toString() ?? '';
    final isVideo = media['media_type'] == 'video';
    final duration = media['duration_seconds'];
    final list = _filteredMedia;
    final index = list.indexWhere((m) => m['id'] == media['id']);
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => MediaViewerScreen(media: list, initialIndex: index < 0 ? 0 : index, libraryId: widget.libraryId),
          fullscreenDialog: true,
        ));
      },
      onLongPress: () {
        final id = media['id']?.toString();
        if (id != null && _library?['is_owner'] == true) _deleteMedia(id);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(fit: StackFit.expand, children: [
          Container(
            color: const Color(0xFFF3F4F6),
            child: url.isNotEmpty
                ? (isVideo ? VideoThumbnailImage(key: ValueKey('vt-$url'), videoUrl: url, fit: BoxFit.cover, showPlayBadge: false) : Image.network(url, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(child: SvgPicture.asset('assets/icons/image-icon.svg',
                      width: 20, height: 20,
                      colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)))))
                : Center(child: SvgPicture.asset('assets/icons/image-icon.svg', width: 20, height: 20,
                    colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn))),
          ),
          if (isVideo) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                child: SvgPicture.asset('assets/icons/play-icon.svg', width: 16, height: 16,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
              ),
            ),
            if (duration is num)
              Positioned(
                right: 4, bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
                  child: Text(_fmtDuration(duration.toInt()),
                      style: appText(size: 9, weight: FontWeight.w700, color: Colors.white)),
                ),
              ),
          ],
        ]),
      ),
    );
  }

  Map<String, dynamic>? _firstCoverItem() {
    final cover = _library?['cover_image_url'] ?? _library?['cover_url'] ?? _library?['event']?['cover_image'];
    final s = cover?.toString();
    if (s != null && s.isNotEmpty) return {'url': s, 'media_type': 'photo'};
    for (final p in _media) {
      if (p is Map) {
        final u = p['url']?.toString();
        if (u != null && u.isNotEmpty) {
          return {'url': u, 'media_type': p['media_type']?.toString() ?? 'photo'};
        }
      }
    }
    return null;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _fmtSize(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  /// Parse an ISO timestamp from the backend, treating naive (no-offset)
  /// strings as UTC, and return the value converted to the device's local
  /// timezone. This avoids the "uploaded today shows yesterday" bug caused
  /// by `DateTime.parse` reading a naive string as local time.
  DateTime? _parseUtcLocal(String iso) {
    if (iso.isEmpty) return null;
    try {
      final hasTz = iso.endsWith('Z') ||
          RegExp(r'[+\-]\d{2}:?\d{2}$').hasMatch(iso);
      final normalized = hasTz ? iso : '${iso}Z';
      return DateTime.parse(normalized).toLocal();
    } catch (_) { return null; }
  }

  String _fmtDate(String iso) {
    final d = _parseUtcLocal(iso);
    if (d == null) return iso;
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _dayLabel(String iso) {
    final d = _parseUtcLocal(iso);
    if (d == null) return 'Earlier';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _fmtDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
