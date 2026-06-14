import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/social_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/l10n/l10n_helper.dart';

/// Create post box - modern card composer
class CreatePostBox extends StatefulWidget {
  final VoidCallback? onPostCreated;

  const CreatePostBox({super.key, this.onPostCreated});

  @override
  State<CreatePostBox> createState() => _CreatePostBoxState();
}

class _CreatePostBoxState extends State<CreatePostBox> {
  static const int _maxMediaCount = 10;
  static const int _maxImageBytes = 10 * 1024 * 1024;

  final _textController = TextEditingController();
  final _picker = ImagePicker();
  List<XFile> _mediaFiles = [];
  bool _isSubmitting = false;
  String _visibility = 'public';
  String? _locationName;
  bool _isExpanded = false;
  bool _fetchingLocation = false;

  int get _charCount => _textController.text.length;
  bool get _isOverLimit => _charCount > 2000;
  bool get _canSubmit =>
      (_textController.text.trim().isNotEmpty || _mediaFiles.isNotEmpty) &&
      !_isOverLimit &&
      !_isSubmitting;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    if (_mediaFiles.length >= _maxMediaCount) {
      AppSnackbar.info(context, 'You can upload up to 10 images');
      return;
    }

    try {
      final files = await _picker.pickMultipleMedia(
        limit: _maxMediaCount - _mediaFiles.length,
      );
      if (!mounted || files.isEmpty) return;
      await _addPickedMedia(files);
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to pick images');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (file != null && mounted) {
        await _addPickedMedia([file]);
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to open camera');
    }
  }

  Future<void> _addPickedMedia(List<XFile> files) async {
    final accepted = <XFile>[];
    var skippedVideos = 0;
    var oversized = 0;

    for (final file in files) {
      if (_isVideoFile(file.path)) {
        skippedVideos++;
        continue;
      }

      final bytes = await File(file.path).length();
      if (bytes > _maxImageBytes) {
        oversized++;
        continue;
      }

      accepted.add(file);
    }

    if (!mounted) return;

    if (accepted.isNotEmpty) {
      setState(() {
        _mediaFiles = [..._mediaFiles, ...accepted].take(_maxMediaCount).toList();
        _isExpanded = true;
      });
    }

    if (skippedVideos > 0) {
      AppSnackbar.info(
        context,
        'Some videos were skipped. Mobile moment uploads currently support images only.',
      );
    }

    if (oversized > 0) {
      AppSnackbar.error(
        context,
        'Some images were skipped because they exceed 10MB.',
      );
    }
  }

  void _removeMedia(int index) {
    setState(() => _mediaFiles.removeAt(index));
  }

  Future<void> _toggleLocation() async {
    if (_locationName != null) {
      setState(() => _locationName = null);
      return;
    }

    setState(() => _fetchingLocation = true);

    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() => _fetchingLocation = false);
        _showLocationPermissionDialog();
      }
      return;
    }

    try {
      final position = await LocationService.getCurrentPosition();
      if (mounted) {
        setState(() {
          _fetchingLocation = false;
          if (position != null) {
            _locationName = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
          } else {
            _locationName = 'Current location';
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _fetchingLocation = false;
        _locationName = 'Current location';
      });
    }
  }

  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Location Permission Required', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Text(
          'To tag your moment with a location, please allow Nuru to access your location.',
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Not Now', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await LocationService.openSettings();
            },
            child: Text('Open Settings', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);

    try {
      final result = await SocialService.createPost(
        content: _textController.text.trim(),
        visibility: _visibility,
        location: _locationName,
        imagePaths: _mediaFiles.map((f) => f.path).toList(),
      );

      if (mounted) {
        if (result['success'] == true) {
          _textController.clear();
          setState(() {
            _mediaFiles.clear();
            _locationName = null;
            _visibility = 'public';
            _isExpanded = false;
          });
          widget.onPostCreated?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Moment shared!',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              backgroundColor: AppColors.accent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? 'Failed to share moment',
                style: GoogleFonts.inter(height: 1.3),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Composer area
          GestureDetector(
            onTap: () => setState(() => _isExpanded = true),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: TextField(
                controller: _textController,
                maxLines: _isExpanded ? null : 2,
                minLines: _isExpanded ? 3 : 2,
                maxLength: 2000,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                onChanged: (_) => setState(() {}),
                onTap: () => setState(() => _isExpanded = true),
                decoration: InputDecoration(
                  hintText: 'Share a moment...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 15,
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                    decoration: TextDecoration.none,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  height: 1.5,
                  decoration: TextDecoration.none,
                  decorationThickness: 0,
                ),
              ),
            ),
          ),

          // Media previews
          if (_mediaFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: _mediaFiles.length == 1 ? 160 : 90,
                child: _mediaFiles.length == 1
                    ? Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _isVideoFile(_mediaFiles[0].path)
                                ? Container(
                                    width: double.infinity, height: 160,
                                    color: Colors.black87,
                                    child: const Center(child: Icon(Icons.play_circle_fill_rounded, size: 48, color: Colors.white70)),
                                  )
                                : Image.file(
                                    File(_mediaFiles[0].path),
                                    width: double.infinity,
                                    height: 160,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () => _removeMedia(0),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _mediaFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _isVideoFile(_mediaFiles[i].path)
                                  ? Container(
                                      width: 100, height: 90,
                                      color: Colors.black87,
                                      child: const Center(child: Icon(Icons.play_circle_fill_rounded, size: 32, color: Colors.white70)),
                                    )
                                  : Image.file(
                                      File(_mediaFiles[i].path),
                                      width: 100,
                                      height: 90,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => _removeMedia(i),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],

          // Location badge
          if (_locationName != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/location-icon.svg',
                      width: 12,
                      height: 12,
                      colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _locationName!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() => _locationName = null),
                      child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Bottom action bar
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderLight, width: 1)),
            ),
            child: Row(
              children: [
                _svgIconBtn('assets/icons/camera-icon.svg', _takePhoto),
                _svgIconBtn('assets/icons/image-icon.svg', _pickFromGallery),
                _fetchingLocation
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                      )
                    : _svgIconBtn(
                        'assets/icons/location-icon.svg',
                        _toggleLocation,
                        isActive: _locationName != null,
                      ),

                const Spacer(),

                // Visibility toggle
                GestureDetector(
                  onTap: () => setState(() => _visibility = _visibility == 'public' ? 'circle' : 'public'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _visibility == 'public' ? Icons.public_rounded : Icons.people_rounded,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _visibility == 'public' ? 'Public' : 'Circle',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Share Moment button
                GestureDetector(
                  onTap: _canSubmit ? _submit : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _canSubmit ? AppColors.primary : AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Share Moment',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _canSubmit ? Colors.white : AppColors.textHint,
                              height: 1.2,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isVideoFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext);
  }

  Widget _svgIconBtn(String assetPath, VoidCallback onTap, {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SvgPicture.asset(
          assetPath,
          width: 20,
          height: 20,
          colorFilter: ColorFilter.mode(
            isActive ? AppColors.primary : AppColors.textTertiary,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
