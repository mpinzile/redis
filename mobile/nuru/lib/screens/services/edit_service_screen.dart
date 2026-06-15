import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import 'service_verification_screen.dart';
import '../../core/services/api_service.dart';
import '../../core/services/user_services_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../providers/wallet_provider.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../widgets/app_select.dart';

/// Full-page Edit Service screen - matches Add Service card styling.
class EditServiceScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  const EditServiceScreen({super.key, required this.service});

  @override
  State<EditServiceScreen> createState() => _EditServiceScreenState();
}

class _EditServiceScreenState extends State<EditServiceScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _minPriceCtrl;
  late TextEditingController _maxPriceCtrl;
  late TextEditingController _locationCtrl;

  String _status = 'active';
  bool _submitting = false;

  List<dynamic> _categories = [];
  List<dynamic> _serviceTypes = [];
  String _selectedCategoryId = '';
  final Set<String> _selectedTypeIds = <String>{};
  bool _loadingRefs = true;
  bool _loadingTypes = false;

  // Images
  final List<String> _existingImages = [];
  final List<File> _newImages = [];

  // Intro media
  List<dynamic> _introMedia = [];
  bool _uploadingMedia = false;

  // Voice recording (intro audio)
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordPath;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  // Track original values for re-verification detection
  late String _originalCategoryId;
  late Set<String> _originalTypeIds;

  static String get _baseUrl => ApiService.baseUrl;

  TextStyle _f({double size = 14, FontWeight weight = FontWeight.w500, Color color = AppColors.textPrimary, double height = 1.3}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _titleCtrl = TextEditingController(text: (s['title'] ?? s['name'] ?? '').toString());
    _descCtrl = TextEditingController(text: (s['description'] ?? '').toString());
    _minPriceCtrl = TextEditingController(text: _initPrice(s['min_price'] ?? s['starting_price'] ?? s['price']));
    _maxPriceCtrl = TextEditingController(text: _initPrice(s['max_price']));
    _locationCtrl = TextEditingController(text: (s['location'] ?? '').toString());
    _status = (s['status']?.toString() ?? 'active').toLowerCase();
    // Treat anything that isn't a known "live" status as paused for the UI
    // toggle. The backend still controls draft/pending/approved.
    if (_status != 'active' && _status != 'paused') _status = 'active';
    _selectedCategoryId = (s['service_category_id'] ?? s['service_category']?['id'] ?? '').toString();

    // Initialise multi-type selection
    final typeIds = s['service_type_ids'];
    if (typeIds is List) {
      for (final t in typeIds) {
        final id = t?.toString() ?? '';
        if (id.isNotEmpty) _selectedTypeIds.add(id);
      }
    }
    if (_selectedTypeIds.isEmpty) {
      final legacy = (s['service_type_id'] ?? s['service_type']?['id'] ?? '').toString();
      if (legacy.isNotEmpty) _selectedTypeIds.add(legacy);
    }

    _originalCategoryId = _selectedCategoryId;
    _originalTypeIds = Set<String>.from(_selectedTypeIds);
    _existingImages.addAll(_extractImages(s));
    _loadReferences();
    _loadIntroMedia();
  }

  String _initPrice(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.isEmpty) return '';
    final n = num.tryParse(s);
    if (n == null) return s;
    return n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    _locationCtrl.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  List<String> _extractImages(Map<String, dynamic> s) {
    final result = <String>[];
    final images = s['images'];
    if (images is List) {
      for (final img in images) {
        if (img is String && img.isNotEmpty) result.add(img);
        if (img is Map) {
          final url = img['url']?.toString() ?? img['image_url']?.toString() ?? img['file_url']?.toString() ?? '';
          if (url.isNotEmpty) result.add(url);
        }
      }
    }
    if (result.isEmpty) {
      final primary = s['primary_image'];
      if (primary is String && primary.isNotEmpty) result.add(primary);
      if (primary is Map) {
        final url = primary['thumbnail_url']?.toString() ?? primary['url']?.toString() ?? '';
        if (url.isNotEmpty) result.add(url);
      }
    }
    return result;
  }

  Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, String>> _authOnlyHeaders() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _loadReferences() async {
    setState(() => _loadingRefs = true);
    final catRes = await UserServicesService.getServiceCategories();
    if (catRes['success'] == true) {
      final d = catRes['data'];
      _categories = d is List ? d : (d is Map ? (d['categories'] ?? []) : []);
    }
    if (_selectedCategoryId.isNotEmpty) {
      await _loadTypes(_selectedCategoryId);
    }
    if (mounted) setState(() => _loadingRefs = false);
  }

  Future<void> _loadTypes(String catId) async {
    if (catId.isEmpty) {
      setState(() => _serviceTypes = []);
      return;
    }
    setState(() => _loadingTypes = true);
    final res = await UserServicesService.getServiceTypesByCategory(catId);
    if (!mounted) return;
    setState(() {
      _loadingTypes = false;
      _serviceTypes = (res['success'] == true && res['data'] is List) ? res['data'] : [];
    });
  }

  Future<void> _loadIntroMedia() async {
    final serviceId = widget.service['id']?.toString() ?? '';
    if (serviceId.isEmpty) return;
    try {
      final res = await http.get(Uri.parse('$_baseUrl/user-services/$serviceId/intro-media'), headers: await _headers());
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final media = data is Map ? (data['data'] ?? data['intro_media'] ?? []) : (data is List ? data : []);
        setState(() => _introMedia = media is List ? media : []);
      }
    } catch (_) {}
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(maxWidth: 1200, imageQuality: 85);
    if (picked.isNotEmpty && mounted) {
      final accepted = <File>[];
      for (final f in picked) {
        final file = File(f.path);
        final bytes = await file.length();
        if (bytes > 5 * 1024 * 1024) continue;
        accepted.add(file);
      }
      if (accepted.isEmpty && picked.isNotEmpty && mounted) {
        AppSnackbar.info(context, 'Images must be 5MB or smaller');
      }
      if (accepted.isNotEmpty && mounted) {
        setState(() => _newImages.addAll(accepted));
      }
    }
  }

  Future<void> _uploadIntroMedia({String source = 'video'}) async {
    final serviceId = widget.service['id']?.toString() ?? '';
    String? filePath;
    String mediaType = 'video';
    if (source == 'video') {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      filePath = picked.path;
      mediaType = 'video';
    } else if (source == 'audio') {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.audio, allowMultiple: false, withData: false,
      );
      if (res == null || res.files.isEmpty) return;
      filePath = res.files.single.path;
      mediaType = 'audio';
    }
    if (filePath == null) return;

    setState(() => _uploadingMedia = true);
    try {
      final uri = Uri.parse('$_baseUrl/user-services/$serviceId/intro-media');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authOnlyHeaders());
      request.fields['media_type'] = mediaType;
      request.files.add(await http.MultipartFile.fromPath('media', filePath));
      final streamedRes = await request.send();
      await streamedRes.stream.bytesToString();
      if (streamedRes.statusCode >= 200 && streamedRes.statusCode < 300) {
        if (mounted) {
          AppSnackbar.success(context, 'Intro clip uploaded');
          _loadIntroMedia();
        }
      } else {
        if (mounted) AppSnackbar.error(context, 'Failed to upload intro clip');
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to upload intro clip');
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _startVoiceRecording() async {
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

  Future<void> _cancelVoiceRecording() async {
    try { await _recorder.stop(); } catch (_) {}
    _recordTimer?.cancel();
    if (_recordPath != null) {
      try { File(_recordPath!).deleteSync(); } catch (_) {}
    }
    _recordPath = null;
    if (mounted) setState(() { _isRecording = false; _recordDuration = Duration.zero; });
  }

  Future<void> _stopAndUploadVoiceRecording() async {
    final serviceId = widget.service['id']?.toString() ?? '';
    String? path;
    try { path = await _recorder.stop(); } catch (_) {}
    _recordTimer?.cancel();
    if (mounted) setState(() { _isRecording = false; _recordDuration = Duration.zero; });
    final filePath = path ?? _recordPath;
    _recordPath = null;
    if (filePath == null || filePath.isEmpty) return;

    setState(() => _uploadingMedia = true);
    try {
      final uri = Uri.parse('$_baseUrl/user-services/$serviceId/intro-media');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authOnlyHeaders());
      request.fields['media_type'] = 'audio';
      request.files.add(await http.MultipartFile.fromPath('media', filePath));
      final res = await request.send();
      await res.stream.bytesToString();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (mounted) { AppSnackbar.success(context, 'Voice clip uploaded'); _loadIntroMedia(); }
      } else if (mounted) {
        AppSnackbar.error(context, 'Failed to upload voice clip');
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to upload voice clip');
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _deleteIntroMedia(String mediaId) async {
    final serviceId = widget.service['id']?.toString() ?? '';
    try {
      final res = await http.delete(Uri.parse('$_baseUrl/user-services/$serviceId/intro-media/$mediaId'), headers: await _headers());
      if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
        AppSnackbar.success(context, 'Intro clip removed');
        _loadIntroMedia();
      }
    } catch (_) {}
  }

  String _formatPrice(String value) {
    final numbers = value.replaceAll(RegExp(r'[^\d]'), '');
    if (numbers.isEmpty) return '';
    return numbers.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  Future<void> _save() async {
    final serviceId = widget.service['id']?.toString() ?? '';
    if (serviceId.isEmpty) return;

    if (_titleCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Service title is required');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Description is required');
      return;
    }
    if (_selectedCategoryId.isEmpty) {
      AppSnackbar.error(context, 'Please select a category');
      return;
    }
    if (_selectedTypeIds.isEmpty) {
      AppSnackbar.error(context, 'Please select at least one service type');
      return;
    }

    final minNum = num.tryParse(_minPriceCtrl.text.trim().replaceAll(',', ''));
    final maxNum = num.tryParse(_maxPriceCtrl.text.trim().replaceAll(',', ''));
    if (minNum != null && maxNum != null && maxNum < minNum) {
      AppSnackbar.error(context, 'Max price must be ≥ min price');
      return;
    }

    setState(() => _submitting = true);

    try {
      final uri = Uri.parse('$_baseUrl/user-services/$serviceId');
      final request = http.MultipartRequest('PUT', uri);
      request.headers.addAll(await _authOnlyHeaders());
      request.fields['title'] = _titleCtrl.text.trim();
      request.fields['description'] = _descCtrl.text.trim();
      request.fields['status'] = _status;
      // Mirror the simple Active/Paused toggle onto the availability field
      // so legacy clients/back-office stay in sync.
      request.fields['availability'] = _status == 'paused' ? 'unavailable' : 'available';
      request.fields['location'] = _locationCtrl.text.trim();

      if (minNum != null) request.fields['min_price'] = '$minNum';
      if (maxNum != null) request.fields['max_price'] = '$maxNum';
      if (_selectedCategoryId.isNotEmpty) request.fields['service_category_id'] = _selectedCategoryId;
      final ids = _selectedTypeIds.toList();
      if (ids.isNotEmpty) {
        request.fields['service_type_id'] = ids.first;
        request.fields['service_type_ids'] = ids.join(',');
      }

      // Detect key changes that require re-verification.
      final keyChanged = _selectedCategoryId != _originalCategoryId ||
          !_setEquals(_selectedTypeIds, _originalTypeIds);
      if (keyChanged) request.fields['reset_verification'] = 'true';

      for (final img in _newImages) {
        request.files.add(await http.MultipartFile.fromPath('images', img.path));
      }

      final streamedRes = await request.send();
      final body = await streamedRes.stream.bytesToString();
      Map<String, dynamic> resData = const {};
      try { resData = jsonDecode(body) as Map<String, dynamic>; } catch (_) {}

      if (!mounted) return;
      final ok = streamedRes.statusCode >= 200 && streamedRes.statusCode < 300 && (resData['success'] != false);
      if (ok) {
        AppSnackbar.success(
          context,
          keyChanged ? 'Service updated · please upload KYC to re-verify' : 'Service updated',
        );
        if (keyChanged) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => ServiceVerificationScreen(serviceId: serviceId)),
          );
        } else {
          Navigator.pop(context, true);
        }
      } else {
        AppSnackbar.error(context, resData['message']?.toString() ?? 'Unable to update service');
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Unable to update service');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final x in a) { if (!b.contains(x)) return false; }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: NuruSubPageAppBar(title: context.tr('edit_service')),
      body: _loadingRefs
          ? SkeletonGroup(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: const [
                  SkeletonBox(height: 110, radius: 16),
                  SizedBox(height: 16),
                  SkeletonBox(height: 160, radius: 16),
                  SizedBox(height: 16),
                  SkeletonBox(height: 140, radius: 16),
                  SizedBox(height: 16),
                  SkeletonBox(height: 100, radius: 16),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _categoryTypeCard(),
                      const SizedBox(height: 16),
                      _titleDescCard(),
                      const SizedBox(height: 16),
                      _pricingLocationCard(),
                      const SizedBox(height: 16),
                      _statusCard(),
                      const SizedBox(height: 16),
                      _imagesCard(),
                      const SizedBox(height: 16),
                      _introClipCard(),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Save Changes', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Cards ──────────────────────────────────────────────────────────

  Widget _categoryTypeCard() => _sectionCard('Category & Service Type', [
    _fieldLabel('Category *'),
    _dropdown(
      value: _categories.any((c) => c['id']?.toString() == _selectedCategoryId) ? _selectedCategoryId : null,
      hint: 'Select a category',
      items: _categories.map<DropdownMenuItem<String>>((c) => DropdownMenuItem(
        value: c['id']?.toString() ?? '',
        child: Text(c['name']?.toString() ?? '', style: _f(size: 14)),
      )).toList(),
      onChanged: (v) {
        setState(() {
          _selectedCategoryId = v ?? '';
          _selectedTypeIds.clear();
          _serviceTypes = [];
        });
        _loadTypes(v ?? '');
      },
    ),
    const SizedBox(height: 16),
    _fieldLabel('Service Types *'),
    if (_selectedCategoryId.isEmpty)
      Text('Select a category first.', style: _f(size: 13, color: AppColors.textTertiary))
    else if (_loadingTypes)
      Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
        const SizedBox(width: 10),
        Text('Loading types...', style: _f(size: 13, color: AppColors.textTertiary)),
      ])
    else if (_serviceTypes.isEmpty)
      Text('No service types available for this category.', style: _f(size: 13, color: AppColors.textTertiary))
    else ...[
      Text('Tap to select one or more', style: _f(size: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: _serviceTypes.map<Widget>((t) {
        final id = t['id']?.toString() ?? '';
        final name = t['name']?.toString() ?? '';
        final selected = _selectedTypeIds.contains(id);
        return GestureDetector(
          onTap: () => setState(() {
            if (selected) _selectedTypeIds.remove(id); else _selectedTypeIds.add(id);
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? AppColors.primary : AppColors.borderLight),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 14, color: AppColors.textPrimary),
                const SizedBox(width: 6),
              ],
              Text(name, style: _f(size: 13, weight: FontWeight.w600,
                  color: selected ? AppColors.textPrimary : AppColors.textSecondary)),
            ]),
          ),
        );
      }).toList()),
    ],
  ]);

  Widget _titleDescCard() => _sectionCard('Service Title & Description', [
    _fieldLabel('Service Title *'),
    _textField(_titleCtrl, 'e.g., Professional Wedding Photography'),
    const SizedBox(height: 14),
    _fieldLabel('Description *'),
    _textField(_descCtrl, 'Describe your service, experience, and what makes you unique...', maxLines: 4),
  ]);

  Widget _pricingLocationCard() => _sectionCard('Pricing & Location', [
    Builder(builder: (ctx) {
      String currency = 'TZS';
      try { currency = ctx.watch<WalletProvider>().currency; } catch (_) {}
      if (currency.isEmpty) currency = 'TZS';
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _fieldLabel('Min Price ($currency) *'),
        _textField(_minPriceCtrl, 'e.g., 300,000', keyboardType: TextInputType.number, onChanged: (v) {
          final f = _formatPrice(v);
          if (f != v) _minPriceCtrl.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
        }),
      ])),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _fieldLabel('Max Price ($currency) *'),
        _textField(_maxPriceCtrl, 'e.g., 2,500,000', keyboardType: TextInputType.number, onChanged: (v) {
          final f = _formatPrice(v);
          if (f != v) _maxPriceCtrl.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
        }),
      ])),
    ]),
    const SizedBox(height: 14),
    _fieldLabel('Service Location'),
    _textField(_locationCtrl, 'e.g., Mikocheni, Dar es Salaam'),
      ]);
    }),
  ]);

  Widget _statusCard() {
    Widget pill(String value, String label, IconData icon) {
      final selected = _status == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _status = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : const Color(0xFFE5E7EB),
              ),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: selected ? AppColors.textPrimary : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: _f(size: 13, weight: FontWeight.w600,
                color: selected ? AppColors.textPrimary : AppColors.textSecondary)),
            ]),
          ),
        ),
      );
    }
    return _sectionCard('Service Status', [
      Text('Pause your service to stop receiving new bookings. Existing bookings are unaffected.',
          style: _f(size: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 12),
      Row(children: [
        pill('active', 'Active', Icons.check_circle_rounded),
        const SizedBox(width: 10),
        pill('paused', 'Paused', Icons.pause_circle_filled_rounded),
      ]),
    ]);
  }

  Widget _imagesCard() => _sectionCard('Service Images', [
    Row(children: [
      SvgPicture.asset('assets/icons/gallery-icon.svg', width: 16, height: 16,
        colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn)),
      const SizedBox(width: 8),
      Text('Add or remove gallery images', style: _f(size: 12, color: AppColors.textSecondary)),
    ]),
    const SizedBox(height: 12),
    if (_existingImages.isNotEmpty || _newImages.isNotEmpty)
      SizedBox(
        height: 100,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            ..._existingImages.map((url) => _imageThumb(networkUrl: url)),
            ..._newImages.map((file) => _imageThumb(file: file, onRemove: () => setState(() => _newImages.remove(file)))),
            _addImageBtn(),
          ],
        ),
      )
    else
      _addImageBtn(),
  ]);

  Widget _introClipCard() => _sectionCard('Intro Clip', [
    Row(children: [
      SvgPicture.asset('assets/icons/video-icon.svg', width: 16, height: 16,
        colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn)),
      const SizedBox(width: 8),
      Expanded(child: Text('A short video or voice intro shown on your service page', style: _f(size: 12, color: AppColors.textSecondary))),
    ]),
    const SizedBox(height: 12),
    if (_introMedia.isNotEmpty)
      ..._introMedia.map((m) {
        final mediaId = m is Map ? m['id']?.toString() ?? '' : '';
        final mediaType = m is Map ? (m['media_type']?.toString() ?? 'video') : 'video';
        final mediaUrl = m is Map ? (m['media_url']?.toString() ?? '') : '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
              child: Center(child: SvgPicture.asset(mediaType == 'audio' ? 'assets/icons/headset-icon.svg' : 'assets/icons/video-icon.svg', width: 18, height: 18,
                colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mediaType == 'video' ? 'Video Clip' : 'Audio Clip', style: _f(size: 13, weight: FontWeight.w600)),
              if (mediaUrl.isNotEmpty)
                Text(mediaUrl.split('/').last, style: _f(size: 11, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            GestureDetector(
              onTap: () => _deleteIntroMedia(mediaId),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
              ),
            ),
          ]),
        );
      }),
    if (_isRecording) _recordingBar() else _introUploadActions(),
  ]);

  Widget _introUploadActions() {
    Widget btn(String label, IconData icon, VoidCallback? onTap) => Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: AppColors.primary),
        label: Text(label, style: _f(size: 12, weight: FontWeight.w600, color: AppColors.primary)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.primary.withOpacity(0.45)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
    return Row(children: [
      btn('Video', Icons.videocam_rounded, _uploadingMedia ? null : () => _uploadIntroMedia(source: 'video')),
      const SizedBox(width: 8),
      btn('Audio file', Icons.audiotrack_rounded, _uploadingMedia ? null : () => _uploadIntroMedia(source: 'audio')),
      const SizedBox(width: 8),
      btn('Record', Icons.mic_rounded, _uploadingMedia ? null : _startVoiceRecording),
    ]);
  }

  Widget _recordingBar() {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(_recordDuration.inMinutes.remainder(60));
    final s = two(_recordDuration.inSeconds.remainder(60));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.30)),
      ),
      child: Row(children: [
        const Icon(Icons.fiber_manual_record_rounded, size: 14, color: AppColors.error),
        const SizedBox(width: 8),
        Text('Recording  $m:$s', style: _f(size: 13, weight: FontWeight.w600, color: AppColors.error)),
        const Spacer(),
        TextButton(
          onPressed: _cancelVoiceRecording,
          child: Text('Cancel', style: _f(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: _stopAndUploadVoiceRecording,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          child: Text('Stop & upload', style: _f(size: 12, weight: FontWeight.w700)),
        ),
      ]),
    );
  }

  // ── UI Helpers (mirrors add_service_screen) ────────────────────────

  Widget _sectionCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: _f(size: 15, weight: FontWeight.w600)),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  Widget _fieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label, style: _f(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary)),
      );

  Widget _textField(TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType keyboardType = TextInputType.text, ValueChanged<String>? onChanged, bool readOnly = false}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      readOnly: readOnly,
      style: _f(size: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _f(size: 14, color: AppColors.textHint),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.4)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _dropdown({String? value, required String hint, required List<DropdownMenuItem<String>> items, ValueChanged<String?>? onChanged}) {
    return AppSelect.fromItems<String>(
      value: value,
      items: items,
      onChanged: _submitting ? null : onChanged,
      hint: hint,
      title: hint,
      borderRadius: 10,
      borderColor: const Color(0xFFE5E7EB),
      fontSize: 14,
      enabled: !_submitting,
      searchable: items.length > 6,
    );
  }

  Widget _imageThumb({String? networkUrl, File? file, VoidCallback? onRemove}) {
    return Container(
      width: 90, height: 90,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderLight)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (networkUrl != null)
          Image.network(networkUrl, width: 90, height: 90, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceVariant)),
        if (file != null)
          Image.file(file, width: 90, height: 90, fit: BoxFit.cover),
        if (onRemove != null)
          Positioned(top: 4, right: 4, child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22, height: 22,
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          )),
      ]),
    );
  }

  Widget _addImageBtn() {
    return GestureDetector(
      onTap: _pickImages,
      child: Container(
        width: 90, height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SvgPicture.asset('assets/icons/photos-icon.svg', width: 22, height: 22,
            colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
          const SizedBox(height: 4),
          Text('Add', style: _f(size: 10, weight: FontWeight.w600, color: AppColors.primary)),
        ]),
      ),
    );
  }
}
