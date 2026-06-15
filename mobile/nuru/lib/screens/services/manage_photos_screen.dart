import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/services/api_service.dart';
import '../../core/l10n/l10n_helper.dart';

/// Manage service portfolio photos - add/remove images
class ManagePhotosScreen extends StatefulWidget {
  final String serviceId;
  final String serviceName;
  const ManagePhotosScreen({super.key, required this.serviceId, required this.serviceName});

  @override
  State<ManagePhotosScreen> createState() => _ManagePhotosScreenState();
}

class _ManagePhotosScreenState extends State<ManagePhotosScreen> {
  List<dynamic> _images = [];
  bool _loading = true;
  bool _uploading = false;

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
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$_baseUrl/services/${widget.serviceId}'), headers: await _headers());
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final svc = data is Map ? (data['data'] ?? data) : data;
        final imgs = svc is Map ? (svc['images'] ?? []) : [];
        setState(() {
          _images = imgs is List ? imgs : [];
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPhotos() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(maxWidth: 1200, imageQuality: 85);
    if (picked.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final uri = Uri.parse('$_baseUrl/user-services/${widget.serviceId}/images');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authOnlyHeaders());
      for (final f in picked) {
        request.files.add(await http.MultipartFile.fromPath('images', f.path));
      }
      final streamedRes = await request.send();
      if (streamedRes.statusCode >= 200 && streamedRes.statusCode < 300) {
        if (mounted) AppSnackbar.success(context, '${picked.length} photo(s) added');
        _loadImages();
      } else {
        if (mounted) AppSnackbar.error(context, 'Failed to upload photos');
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to upload photos');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteImage(String imageId) async {
    try {
      final res = await http.delete(Uri.parse('$_baseUrl/user-services/${widget.serviceId}/images/$imageId'), headers: await _headers());
      if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
        AppSnackbar.success(context, 'Photo removed');
        _loadImages();
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to remove photo');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: NuruSubPageAppBar(title: '${widget.serviceName} · Photos'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _addPhotos,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: _uploading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : SvgPicture.asset('assets/icons/photos-icon.svg', width: 18, height: 18, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
        label: Text(_uploading ? 'Uploading...' : 'Add Photos', style: _f(size: 13, weight: FontWeight.w700, color: Colors.white)),
      ),
      body: _loading
          ? const SkeletonGrid(count: 9, crossAxisCount: 3, spacing: 6, padding: EdgeInsets.all(12))
          : _images.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SvgPicture.asset('assets/icons/photos-icon.svg', width: 48, height: 48, colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
                  const SizedBox(height: 16),
                  Text('No photos yet', style: _f(size: 16, weight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Add portfolio photos to showcase your work', style: _f(size: 13, color: AppColors.textTertiary)),
                ]))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                  itemCount: _images.length,
                  itemBuilder: (_, i) {
                    final img = _images[i];
                    final url = img is String ? img : (img is Map ? (img['url']?.toString() ?? img['image_url']?.toString() ?? '') : '');
                    final imageId = img is Map ? (img['id']?.toString() ?? '') : '';
                    return Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(imageUrl: url, width: double.infinity, height: double.infinity, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant)),
                      ),
                      if (imageId.isNotEmpty)
                        Positioned(top: 4, right: 4, child: GestureDetector(
                          onTap: () => _deleteImage(imageId),
                          child: Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(13)),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        )),
                    ]);
                  },
                ),
    );
  }
}
