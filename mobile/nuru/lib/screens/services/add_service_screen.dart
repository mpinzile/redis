import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/user_services_service.dart';
import '../../core/services/api_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../widgets/app_select.dart';

class AddServiceScreen extends StatefulWidget {
  const AddServiceScreen({super.key});

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  static String get _baseUrl => ApiService.baseUrl;
  static const int _maxImageCount = 10;
  static const int _maxImageBytes = 5 * 1024 * 1024;
  static const int _maxSampleBytes = 50 * 1024 * 1024; // videos can be larger
  static const int _maxDocumentBytes = 5 * 1024 * 1024;
  static const List<String> _allowedDocumentExt = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];
  static const List<String> _allowedSampleExt = ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'm4v', '3gp', 'webm'];
  static const List<String> _videoExt = ['mp4', 'mov', 'm4v', '3gp', 'webm'];

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _briefDescCtrl = TextEditingController();
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  List<dynamic> _categories = [];
  List<dynamic> _serviceTypes = [];
  String _selectedCategoryId = '';
  final Set<String> _selectedTypeIds = <String>{};
  bool _loadingCategories = true;
  bool _loadingTypes = false;
  bool _loadingDocuments = false;
  bool _submitting = false;
  String? _yearsInBusiness;

  final List<File> _images = [];
  final Map<String, List<File>> _documentFiles = <String, List<File>>{};
  List<Map<String, dynamic>> _kycRequirements = [];
  int _step = 0; // 0,1,2

  /// The portfolio KYC requirement (filtered out of the documents list and
  /// auto-filled at submit time using the photos/videos uploaded in the
  /// "Portfolio & Samples" section below). We keep it so we can submit those
  /// files against the right kyc_requirement_id rather than dropping it.
  Map<String, dynamic>? _portfolioKycRequirement;

  static const String _draftKey = 'add_service_draft_v2';

  @override
  void initState() {
    super.initState();
    _loadCategories();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefillPersonalInfo();
      _restoreDraft();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _briefDescCtrl.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    _locationCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _prefillPersonalInfo() {
    final user = context.read<AuthProvider>().user ?? <String, dynamic>{};
    if (!mounted) return;
    setState(() {
      _firstNameCtrl.text = (user['first_name'] ?? '').toString();
      _lastNameCtrl.text = (user['last_name'] ?? '').toString();
      _emailCtrl.text = (user['email'] ?? '').toString();
      _phoneCtrl.text = (user['phone'] ?? user['phone_number'] ?? '').toString();
    });
  }

  Future<void> _loadCategories() async {
    final res = await UserServicesService.getServiceCategories();
    if (mounted) {
      setState(() {
        _loadingCategories = false;
        if (res['success'] == true) {
          final d = res['data'];
          _categories = d is List ? d : [];
        }
      });
    }
  }

  Future<void> _loadTypes(String categoryId) async {
    if (categoryId.isEmpty) return;
    setState(() => _loadingTypes = true);
    final res = await UserServicesService.getServiceTypesByCategory(categoryId);
    if (mounted) {
      setState(() {
        _loadingTypes = false;
        _serviceTypes = (res['success'] == true && res['data'] is List) ? res['data'] : [];
      });
    }
  }

  Future<void> _loadDocumentRequirements() async {
    if (_selectedTypeIds.isEmpty) {
      setState(() => _kycRequirements = []);
      return;
    }
    setState(() => _loadingDocuments = true);
    final requirements = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final typeId in _selectedTypeIds) {
      final res = await UserServicesService.getServiceTypeKyc(typeId);
      final data = res['data'];
      if (res['success'] == true && data is List) {
        for (final raw in data) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final id = item['id']?.toString() ?? '';
          if (id.isEmpty || seen.contains(id)) continue;
          seen.add(id);
          requirements.add(item);
        }
      }
    }
    if (!mounted) return;
    // Split out any portfolio/sample-style KYC requirement so it doesn't
    // appear as a duplicate "Business Document" row. The photos uploaded
    // in the Portfolio & Samples section will be submitted against it.
    Map<String, dynamic>? portfolio;
    final filtered = <Map<String, dynamic>>[];
    for (final r in requirements) {
      final name = (r['name'] ?? '').toString().toLowerCase();
      if (portfolio == null &&
          (name.contains('portfolio') ||
           name.contains('sample') ||
           name.contains('work') )) {
        portfolio = r;
      } else {
        filtered.add(r);
      }
    }
    setState(() {
      _kycRequirements = filtered;
      _portfolioKycRequirement = portfolio;
      _documentFiles.removeWhere((key, _) => !seen.contains(key));
      _loadingDocuments = false;
    });
  }

  Future<void> _pickImages() async {
    if (_images.length >= _maxImageCount) {
      AppSnackbar.info(context, 'You can upload up to 10 files');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedSampleExt,
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final remaining = _maxImageCount - _images.length;
      final accepted = <File>[];
      var oversized = 0;
      for (final picked in result.files) {
        if (accepted.length >= remaining) break;
        final path = picked.path;
        if (path == null) continue;
        final ext = (picked.extension ?? '').toLowerCase();
        if (!_allowedSampleExt.contains(ext)) continue;
        final isVideo = _videoExt.contains(ext);
        final limit = isVideo ? _maxSampleBytes : _maxImageBytes;
        if (picked.size > limit) { oversized++; continue; }
        accepted.add(File(path));
      }
      if (accepted.isNotEmpty) setState(() => _images.addAll(accepted));
      if (oversized > 0) AppSnackbar.info(context, 'Some files were skipped (over size limit).');
      if (result.files.length > accepted.length && oversized == 0) AppSnackbar.info(context, 'You can upload up to 10 files');
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to pick files');
    }
  }

  void _removeImage(int i) => setState(() => _images.removeAt(i));

  Future<void> _pickDocument(String requirementId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedDocumentExt,
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final accepted = <File>[];
      for (final picked in result.files) {
        final path = picked.path;
        if (path == null) continue;
        final ext = (picked.extension ?? '').toLowerCase();
        if (!_allowedDocumentExt.contains(ext)) {
          AppSnackbar.error(context, 'Unsupported file: ${picked.name}. Allowed: JPG, PNG, WEBP, PDF.');
          continue;
        }
        if (picked.size > _maxDocumentBytes) {
          AppSnackbar.error(context, '${picked.name} is larger than 5MB.');
          continue;
        }
        accepted.add(File(path));
      }
      if (accepted.isEmpty || !mounted) return;
      setState(() => (_documentFiles[requirementId] ??= <File>[]).addAll(accepted));
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to pick document');
    }
  }

  void _removeDocument(String requirementId, int fileIndex) {
    setState(() {
      final files = _documentFiles[requirementId];
      if (files == null || fileIndex >= files.length) return;
      files.removeAt(fileIndex);
      if (files.isEmpty) _documentFiles.remove(requirementId);
    });
  }

  String _formatPrice(String value) {
    final numbers = value.replaceAll(RegExp(r'[^\d]'), '');
    return numbers.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String? _validateStep(int step) {
    if (step == 1) {
      if (_titleCtrl.text.trim().isEmpty) return 'Service title is required';
      if (_selectedCategoryId.isEmpty) return 'Please select a category';
      if (_descCtrl.text.trim().isEmpty) return 'Description is required';
      if (_selectedTypeIds.isEmpty) return 'Please select at least one service type';
      if (_minPriceCtrl.text.trim().isEmpty) return 'Minimum price is required';
      if (_maxPriceCtrl.text.trim().isEmpty) return 'Maximum price is required';
      final mn = double.tryParse(_minPriceCtrl.text.trim().replaceAll(',', '')) ?? 0;
      final mx = double.tryParse(_maxPriceCtrl.text.trim().replaceAll(',', '')) ?? 0;
      if (mn <= 0) return 'Minimum price must be greater than 0';
      if (mx <= 0) return 'Maximum price must be greater than 0';
      if (mx < mn) return 'Maximum price must be ≥ minimum price';
    }
    if (step == 2) {
      // Portfolio photos are required when a portfolio-style KYC exists.
      if (_portfolioKycRequirement != null && _images.isEmpty) {
        return 'Please add at least one portfolio photo or sample';
      }
      for (final item in _kycRequirements) {
        final id = item['id']?.toString() ?? '';
        final isMandatory = item['is_mandatory'] == true;
        final hasFile = (_documentFiles[id]?.isNotEmpty ?? false);
        if (isMandatory && !hasFile) {
          return 'Please upload ${item['name'] ?? 'all required documents'}';
        }
      }
    }
    return null;
  }

  Future<void> _next() async {
    final err = _validateStep(_step);
    if (err != null) { AppSnackbar.error(context, err); return; }
    if (_step < 2) {
      setState(() => _step++);
      if (_step == 2) await _loadDocumentRequirements();
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
    else Navigator.pop(context);
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Persist file paths so attachments survive a restart (paths only valid until OS evicts the cache).
      final docPaths = <String, List<String>>{};
      _documentFiles.forEach((k, v) {
        docPaths[k] = v.where((f) => f.existsSync()).map((f) => f.path).toList();
      });
      final imagePaths = _images.where((f) => f.existsSync()).map((f) => f.path).toList();
      final data = <String, dynamic>{
        'title': _titleCtrl.text,
        'description': _descCtrl.text,
        'brief_description': _briefDescCtrl.text,
        'years_in_business': _yearsInBusiness,
        'min_price': _minPriceCtrl.text,
        'max_price': _maxPriceCtrl.text,
        'location': _locationCtrl.text,
        'category_id': _selectedCategoryId,
        'type_ids': _selectedTypeIds.toList(),
        'image_paths': imagePaths,
        'document_paths': docPaths,
        'step': _step,
        'saved_at': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_draftKey, jsonEncode(data));
      if (!mounted) return;
      AppSnackbar.success(context, 'Draft saved. You can continue later.');
      Navigator.pop(context);
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to save draft');
    }
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      if (!mounted) return;
      final useIt = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Resume draft?', style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 17)),
          content: Text('You have an unsaved service draft. Continue where you left off?',
              style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () async {
                await prefs.remove(_draftKey);
                if (ctx.mounted) Navigator.pop(ctx, false);
              },
              child: Text('Discard', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.textPrimary, elevation: 0),
              child: Text('Resume', style: GoogleFonts.sora(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (useIt != true) return;
      // Rehydrate images that still exist on disk.
      final restoredImages = <File>[];
      for (final p in (data['image_paths'] as List? ?? [])) {
        final f = File(p.toString());
        if (f.existsSync()) restoredImages.add(f);
      }
      final restoredDocs = <String, List<File>>{};
      final docMap = data['document_paths'];
      if (docMap is Map) {
        docMap.forEach((k, v) {
          final files = <File>[];
          if (v is List) {
            for (final p in v) {
              final f = File(p.toString());
              if (f.existsSync()) files.add(f);
            }
          }
          if (files.isNotEmpty) restoredDocs[k.toString()] = files;
        });
      }
      setState(() {
        _titleCtrl.text = (data['title'] ?? '').toString();
        _descCtrl.text = (data['description'] ?? '').toString();
        _briefDescCtrl.text = (data['brief_description'] ?? '').toString();
        final yib = data['years_in_business'];
        _yearsInBusiness = yib == null ? null : yib.toString();
        _minPriceCtrl.text = (data['min_price'] ?? '').toString();
        _maxPriceCtrl.text = (data['max_price'] ?? '').toString();
        _locationCtrl.text = (data['location'] ?? '').toString();
        _selectedCategoryId = (data['category_id'] ?? '').toString();
        _selectedTypeIds
          ..clear()
          ..addAll((data['type_ids'] as List? ?? []).map((e) => e.toString()));
        _images
          ..clear()
          ..addAll(restoredImages);
        _documentFiles
          ..clear()
          ..addAll(restoredDocs);
        final stp = data['step'];
        if (stp is int && stp >= 0 && stp <= 2) _step = stp;
      });
      if (_selectedCategoryId.isNotEmpty) await _loadTypes(_selectedCategoryId);
      if (_step == 2) await _loadDocumentRequirements();
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }


  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final uri = Uri.parse('$_baseUrl/user-services/');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _headers());
      request.fields['title'] = _titleCtrl.text.trim();
      request.fields['description'] = _descCtrl.text.trim();
      request.fields['category_id'] = _selectedCategoryId;
      // Multi-select: send comma-separated list (backend supports both list & csv)
      final ids = _selectedTypeIds.toList();
      request.fields['service_type_id'] = ids.first;
      request.fields['service_type_ids'] = ids.join(',');
      request.fields['min_price'] = _minPriceCtrl.text.trim().replaceAll(',', '');
      request.fields['max_price'] = _maxPriceCtrl.text.trim().replaceAll(',', '');
      if (_locationCtrl.text.trim().isNotEmpty) {
        request.fields['location'] = _locationCtrl.text.trim();
      }
      if (_yearsInBusiness != null && _yearsInBusiness!.isNotEmpty) {
        // Extract leading integer (e.g. "5 years" → "5")
        final m = RegExp(r'\d+').firstMatch(_yearsInBusiness!);
        if (m != null) request.fields['years_in_business'] = m.group(0)!;
      }
      if (_briefDescCtrl.text.trim().isNotEmpty) {
        // Append the brief description to the main description for now.
        final base = request.fields['description'] ?? '';
        request.fields['description'] = base.isEmpty
            ? _briefDescCtrl.text.trim()
            : '$base\n\n${_briefDescCtrl.text.trim()}';
      }
      for (final img in _images) {
        request.files.add(await http.MultipartFile.fromPath('images', img.path));
      }
      final streamedRes = await request.send();
      final body = await streamedRes.stream.bytesToString();
      final result = jsonDecode(body);
      if (!mounted) return;
      if (result['success'] == true) {
        final serviceId = result['data']?['id']?.toString();
        if (serviceId != null) {
          final docsOk = await _submitDocuments(serviceId);
          if (!mounted) return;
          if (!docsOk) {
            setState(() => _submitting = false);
            return;
          }
          await _clearDraft();
          AppSnackbar.success(context, 'Service submitted for verification.');
          Navigator.pop(context, true);
        } else {
          await _clearDraft();
          AppSnackbar.success(context, result['message'] ?? 'Service created!');
          Navigator.pop(context, true);
        }
      } else {
        AppSnackbar.error(context, result['message']?.toString() ?? 'Failed to create service');
        setState(() => _submitting = false);
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to create service');
        setState(() => _submitting = false);
      }
    }
  }

  Future<bool> _submitDocuments(String serviceId) async {
    final headers = await _headers();
    // Build the list of (requirementId, file) pairs to upload, including the
    // portfolio photos as the portfolio KYC requirement when present.
    final uploads = <MapEntry<String, File>>[];
    _documentFiles.forEach((rid, files) {
      for (final f in files) uploads.add(MapEntry(rid, f));
    });
    final portfolioId = _portfolioKycRequirement?['id']?.toString();
    if (portfolioId != null && portfolioId.isNotEmpty) {
      for (final f in _images) uploads.add(MapEntry(portfolioId, f));
    }
    for (final entry in uploads) {
        final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/user-services/$serviceId/kyc'));
        request.headers.addAll(headers);
        request.fields['kyc_requirement_id'] = entry.key;
        request.files.add(await http.MultipartFile.fromPath('file', entry.value.path));
        final streamed = await request.send();
        final body = await streamed.stream.bytesToString();
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          String msg = 'Service was created, but a document failed to upload.';
          try {
            final parsed = jsonDecode(body);
            if (parsed is Map && parsed['message'] != null) msg = parsed['message'].toString();
          } catch (_) {}
          if (mounted) AppSnackbar.error(context, msg);
          return false;
        }
        try {
          final parsed = jsonDecode(body);
          if (parsed is Map && parsed['success'] == false) {
            if (mounted) AppSnackbar.error(context, parsed['message']?.toString() ?? 'Document upload failed');
            return false;
          }
        } catch (_) {}
    }
    return true;
  }

  TextStyle _f({required double size, FontWeight weight = FontWeight.w500, Color color = AppColors.textPrimary, double height = 1.3}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

  @override
  Widget build(BuildContext context) {
    final stepTitles = ['Personal Info', 'Business Info', 'Documents'];
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
                // ── Top bar ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
                  child: Row(children: [
                    IconButton(
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    ),
                    Expanded(
                      child: Text(
                        context.tr('add_service'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.sora(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                    TextButton(
                      onPressed: _submitting ? null : _saveDraft,
                      child: Text('Save Draft',
                          style: _f(size: 13, weight: FontWeight.w600, color: AppColors.primary)),
                    ),
                  ]),
                ),

                // ── Step indicator ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                  child: Row(children: [
                    for (int i = 0; i < 3; i++) ...[
                      _StepDot(
                        index: i + 1,
                        active: _step == i,
                        completed: _step > i,
                        label: stepTitles[i],
                      ),
                      if (i < 2)
                        Expanded(child: Container(
                          height: 1.5,
                          margin: const EdgeInsets.only(bottom: 22),
                          color: _step > i ? AppColors.primary : const Color(0xFFE5E7EB),
                        )),
                    ],
                  ]),
                ),

                // ── Content ──
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: switch (_step) {
                      0 => _buildStep1(),
                      1 => _buildStep2(),
                      _ => _buildStep3(),
                    },
                  ),
                ),

                // ── CTAs (Back + Continue) ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(children: [
                    if (_step > 0) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting ? null : _back,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text('Back',
                              style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: _step > 0 ? 2 : 1,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _submitting
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(
                                _step < 2 ? 'Continue' : 'Submit for Verification',
                                style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                      ),
                    ),
                  ]),
                ),
              ]),
      ),
    );
  }

  // ── Steps ──

  Widget _buildStep1() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Personal Info',
          style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      const SizedBox(height: 6),
      Text('This is filled from your account so clients know who owns the service.',
          style: _f(size: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 22),
      _sectionCard('Account Details', [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _fieldLabel('First Name'),
            _textField(_firstNameCtrl, 'First name', readOnly: true),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _fieldLabel('Last Name'),
            _textField(_lastNameCtrl, 'Last name', readOnly: true),
          ])),
        ]),
        const SizedBox(height: 14),
        _fieldLabel('Phone Number'),
        _textField(_phoneCtrl, 'Phone number', readOnly: true),
        const SizedBox(height: 14),
        _fieldLabel('Email'),
        _textField(_emailCtrl, 'Email address', readOnly: true),
      ]),
    ]);
  }

  Widget _buildStep2() {
    String currency = 'TZS';
    try { currency = context.watch<WalletProvider>().currency; } catch (_) {}
    if (currency.isEmpty) currency = 'TZS';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Business Info',
          style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      const SizedBox(height: 6),
      Text('Add your service details, types, pricing and location.',
          style: _f(size: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 22),

      // Card 1 - Category & Service Type
      _sectionCard('Category & Service Type', [
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
          Text('Select a category first.',
              style: _f(size: 13, color: AppColors.textTertiary))
        else if (_loadingTypes)
          Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Loading types...', style: _f(size: 13, color: AppColors.textTertiary)),
          ])
        else if (_serviceTypes.isEmpty)
          Text('No service types available for this category.',
              style: _f(size: 13, color: AppColors.textTertiary))
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
      ]),
      const SizedBox(height: 16),

      // Card 2 - Service Title & Description
      _sectionCard('Service Title & Description', [
        _fieldLabel('Service Title *'),
        _textField(_titleCtrl, 'e.g., Professional Wedding Photography'),
        const SizedBox(height: 14),
        _fieldLabel('Description *'),
        _textField(_descCtrl, 'Describe your service, experience, and what makes you unique...', maxLines: 4),
      ]),
      const SizedBox(height: 16),

      // Card 3 - Pricing & Location
      _sectionCard('Pricing & Location', [
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
      ]),
    ]);
  }

  Widget _buildStep3() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Verify Your Business',
          style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      const SizedBox(height: 6),
      Text('Upload required documents to verify your business and gain the trust of customers.',
          style: _f(size: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 28),
      Text('Business Documents', style: _f(size: 16, weight: FontWeight.w600)),
      const SizedBox(height: 14),
      _documentsCard(),
      const SizedBox(height: 22),
      Text('Portfolio & Samples', style: _f(size: 16, weight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(
        _portfolioKycRequirement != null
            ? 'Required · these photos verify your portfolio as part of your service KYC.'
            : 'Showcase your best work to attract more clients.',
        style: _f(size: 13, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 14),
      _portfolioCard(),
      const SizedBox(height: 22),
      Text('Additional Information', style: _f(size: 16, weight: FontWeight.w600)),
      const SizedBox(height: 14),
      _additionalInfoCard(),
    ]);
  }

  Widget _documentsCard() {
    if (_loadingDocuments) {
      return _sectionShell([
        const Center(child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
        )),
      ]);
    }
    if (_kycRequirements.isEmpty) {
      return _sectionShell([
        Text('No required documents for the selected service type.', style: _f(size: 13, color: AppColors.textTertiary)),
      ]);
    }
    final rows = <Widget>[];
    for (var i = 0; i < _kycRequirements.length; i++) {
      final item = _kycRequirements[i];
      final id = item['id']?.toString() ?? '';
      rows.add(_documentUploadRow(
        id: id,
        title: item['name']?.toString() ?? 'Business Document',
        subtitle: item['is_mandatory'] == true ? 'Required' : 'Optional',
        iconAsset: 'assets/icons/file-pdf-icon.svg',
        iconTint: const Color(0xFF22B14C),
        iconBg: const Color(0xFFE9F9EA),
      ));
      if (i < _kycRequirements.length - 1) rows.add(const Divider(height: 1, color: Color(0xFFF1F3F7)));
    }
    return _sectionShell(rows);
  }

  Widget _portfolioCard() {
    return _sectionShell([
      _documentUploadRow(
        id: 'service-images',
        title: 'Sample Photos / Videos',
        subtitle: _portfolioKycRequirement != null
            ? 'Required (Max 10 files, videos up to 50MB)'
            : 'Recommended (Max 10 files, videos up to 50MB)',
        iconAsset: 'assets/icons/gallery-icon.svg',
        iconTint: AppColors.primary,
        iconBg: AppColors.primary.withOpacity(0.10),
        onUpload: _pickImages,
        filesCount: _images.length,
      ),
      if (_images.isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _sampleTile(_images[i], i),
          ),
        ),
      ],
    ]);
  }

  Widget _sampleTile(File file, int i) {
    final ext = file.path.split('.').last.toLowerCase();
    final isVideo = _videoExt.contains(ext);
    return Stack(children: [
      Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        clipBehavior: Clip.antiAlias,
        child: isVideo
            ? Stack(fit: StackFit.expand, children: [
                Container(color: const Color(0xFF111827)),
                Center(
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 22),
                  ),
                ),
                Positioned(
                  left: 6, bottom: 4,
                  child: Text(ext.toUpperCase(),
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ])
            : Image.file(file, fit: BoxFit.cover),
      ),
      Positioned(top: 4, right: 4, child: GestureDetector(
        onTap: () => _removeImage(i),
        child: Container(
          width: 22, height: 22,
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
        ),
      )),
    ]);
  }

  Widget _additionalInfoCard() {
    const years = ['Less than 1 year', '1-2 years', '3-5 years', '6-10 years', '10+ years'];
    return _sectionShell([
      _fieldLabel('Years in Business'),
      _dropdown(
        value: _yearsInBusiness != null && years.contains(_yearsInBusiness) ? _yearsInBusiness : null,
        hint: 'Select years',
        items: years.map((y) => DropdownMenuItem(value: y, child: Text(y, style: _f(size: 14)))).toList(),
        onChanged: (v) => setState(() => _yearsInBusiness = v),
      ),
      const SizedBox(height: 14),
      _fieldLabel('Brief Description of Your Services'),
      _textField(_briefDescCtrl, 'Tell customers about your services, experience and what makes you unique...', maxLines: 4),
    ]);
  }

  // ── UI Helpers ──

  Widget _sectionShell(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEFF4), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _documentUploadRow({
    required String id,
    required String title,
    required String subtitle,
    required String iconAsset,
    required Color iconTint,
    required Color iconBg,
    VoidCallback? onUpload,
    int? filesCount,
  }) {
    final files = _documentFiles[id] ?? const <File>[];
    final count = filesCount ?? files.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Center(
              child: SvgPicture.asset(iconAsset, width: 22, height: 22,
                colorFilter: ColorFilter.mode(iconTint, BlendMode.srcIn)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _f(size: 13.5, weight: FontWeight.w700, height: 1.2)),
            const SizedBox(height: 3),
            Text(count > 0 ? '$count attached' : subtitle,
                style: _f(size: 12, color: count > 0 ? AppColors.success : AppColors.textSecondary)),
          ])),
          OutlinedButton.icon(
            onPressed: onUpload ?? () => _pickDocument(id),
            icon: SvgPicture.asset('assets/icons/upload-icon.svg', width: 14, height: 14,
                colorFilter: const ColorFilter.mode(Color(0xFFC99000), BlendMode.srcIn)),
            label: Text('Upload', style: _f(size: 12, weight: FontWeight.w800, color: const Color(0xFFC99000))),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC99000),
              side: BorderSide(color: AppColors.primary.withOpacity(0.45)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
          ),
        ]),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(files.length, (i) => _documentChip(id, i, files[i])),
          ),
        ],
      ]),
    );
  }

  Widget _documentChip(String requirementId, int index, File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isImg = ['jpg', 'jpeg', 'png', 'webp'].contains(ext);
    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: isImg ? AppColors.primary.withOpacity(0.08) : const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: isImg
              ? Image.file(file, fit: BoxFit.cover)
              : Center(child: SvgPicture.asset('assets/icons/file-pdf-icon.svg', width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(Color(0xFFDC2626), BlendMode.srcIn))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _f(size: 11.5, weight: FontWeight.w700)),
          Text(ext.toUpperCase(), style: _f(size: 10, color: AppColors.textTertiary, weight: FontWeight.w600)),
        ])),
        GestureDetector(
          onTap: () => _removeDocument(requirementId, index),
          child: Container(
            width: 22, height: 22,
            decoration: const BoxDecoration(color: Color(0xFFF1F3F7), shape: BoxShape.circle),
            child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textTertiary),
          ),
        ),
      ]),
    );
  }


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
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _dropdown({String? value, required String hint, required List<DropdownMenuItem<String>> items, ValueChanged<String?>? onChanged}) {
    return AppSelect.fromItems<String>(
      value: value,
      items: items,
      onChanged: onChanged,
      hint: hint,
      title: hint,
      borderRadius: 10,
      borderColor: const Color(0xFFE5E7EB),
      fontSize: 14,
      searchable: items.length > 6,
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 84, child: Text(label, style: _f(size: 12, color: AppColors.textSecondary))),
          Expanded(child: Text(value, style: _f(size: 13, weight: FontWeight.w600))),
        ]),
      );
}

class _StepDot extends StatelessWidget {
  final int index;
  final bool active;
  final bool completed;
  final String label;
  const _StepDot({required this.index, required this.active, required this.completed, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = (active || completed) ? AppColors.primary : AppColors.borderLight;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(
          child: completed
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : Text('$index', style: GoogleFonts.sora(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: active ? AppColors.textPrimary : AppColors.textTertiary)),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? AppColors.textPrimary : AppColors.textTertiary)),
    ]);
  }
}
