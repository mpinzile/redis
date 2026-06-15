import '../../core/widgets/nuru_refresh_indicator.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/services/api_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/l10n/l10n_helper.dart';

/// Service Verification / KYC document upload - matches web ServiceVerification.tsx
class ServiceVerificationScreen extends StatefulWidget {
  final String serviceId;
  final String serviceType;
  const ServiceVerificationScreen({super.key, required this.serviceId, this.serviceType = ''});

  @override
  State<ServiceVerificationScreen> createState() => _ServiceVerificationScreenState();
}

const int _maxFileBytes = 5 * 1024 * 1024; // 5 MB
const List<String> _allowedExt = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];

class _ServiceVerificationScreenState extends State<ServiceVerificationScreen> {
  static String get _baseUrl => ApiService.baseUrl;
  bool _loading = true;
  bool _submitting = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadKyc();
  }

  Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _loadKyc() async {
    setState(() => _loading = true);
    try {
      final headers = await _headers();
      headers['Content-Type'] = 'application/json';
      final res = await http.get(Uri.parse('$_baseUrl/user-services/${widget.serviceId}/kyc'), headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body);
        final data = body['data'] ?? body;
        final list = data is List ? data : (data is Map ? (data['requirements'] ?? data['items'] ?? []) : []);
        setState(() {
          _items = (list as List).map((k) {
            final kyc = k is Map<String, dynamic> ? k : <String, dynamic>{};
            return <String, dynamic>{
              'id': kyc['id']?.toString() ?? '',
              'name': kyc['name']?.toString() ?? 'Document',
              'description': kyc['description']?.toString() ?? '',
              'is_mandatory': kyc['is_mandatory'] == true,
              'status': kyc['status']?.toString(),
              'remarks': kyc['remarks']?.toString(),
              'files': <File>[],
            };
          }).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  int get _verifiedCount => _items.where((i) => i['status'] == 'verified').length;
  double get _progress => _items.isNotEmpty ? (_verifiedCount / _items.length) * 100 : 0;

  Future<void> _pickFile(int index) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExt,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final accepted = <File>[];
    for (final pf in result.files) {
      final path = pf.path;
      if (path == null) continue;
      final ext = (pf.extension ?? '').toLowerCase();
      if (!_allowedExt.contains(ext)) {
        AppSnackbar.error(context, 'Unsupported file: ${pf.name}. Allowed: JPG, PNG, PDF.');
        continue;
      }
      final size = pf.size;
      if (size > _maxFileBytes) {
        AppSnackbar.error(context, '${pf.name} is larger than 5MB.');
        continue;
      }
      accepted.add(File(path));
    }
    if (accepted.isEmpty) return;
    setState(() {
      (_items[index]['files'] as List<File>).addAll(accepted);
    });
    AppSnackbar.success(context, '${accepted.length} file${accepted.length == 1 ? '' : 's'} added');
  }

  void _removeFile(int itemIdx, int fileIdx) {
    setState(() {
      (_items[itemIdx]['files'] as List<File>).removeAt(fileIdx);
    });
  }

  bool get _hasEditable => _items.any((i) => i['status'] == null || i['status'] == 'rejected');

  Future<void> _submit({bool partial = false}) async {
    if (_submitting) return;

    final itemsToSubmit = partial
        ? _items.where((i) => (i['files'] as List<File>).isNotEmpty).toList()
        : _items.where((i) => i['status'] != 'verified' && i['status'] != 'pending').toList();

    if (!partial) {
      // Required items must have an existing approved/pending status OR newly attached files
      for (final i in _items) {
        final isMandatory = i['is_mandatory'] == true;
        final status = i['status']?.toString();
        final hasFiles = (i['files'] as List<File>).isNotEmpty;
        final alreadyDone = status == 'verified' || status == 'pending';
        if (isMandatory && !alreadyDone && !hasFiles) {
          AppSnackbar.error(context, 'Please attach files for "${i['name']}" before submitting.');
          return;
        }
      }
    }

    if (partial && itemsToSubmit.isEmpty) {
      AppSnackbar.success(context, 'Progress saved.');
      return;
    }
    if (!partial && itemsToSubmit.isEmpty) {
      AppSnackbar.error(context, 'No files to submit.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final headers = await _headers();
      for (final item in itemsToSubmit) {
        final files = item['files'] as List<File>;
        if (files.isEmpty) continue;

        for (final file in files) {
          final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/user-services/${widget.serviceId}/kyc'));
          headers.forEach((k, v) => req.headers[k] = v);
          req.fields['kyc_requirement_id'] = item['id'].toString();
          req.files.add(await http.MultipartFile.fromPath('file', file.path));
          final streamed = await req.send();
          final resBody = await streamed.stream.bytesToString();
          if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
            String msg = 'Failed to upload ${item['name']}';
            try {
              final j = jsonDecode(resBody);
              if (j is Map && j['message'] is String) msg = j['message'];
            } catch (_) {}
            if (mounted) AppSnackbar.error(context, msg);
            setState(() => _submitting = false);
            return;
          }
        }
      }
      if (mounted) {
        AppSnackbar.success(context, 'Documents submitted! Your service will be activated once reviewed.');
      }
      await _loadKyc();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Upload failed');
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: NuruSubPageAppBar(title: context.tr('service_verification')),
      body: _loading
          ? SkeletonGroup(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  SkeletonBox(height: 64, radius: 14),
                  SizedBox(height: 14),
                  SkeletonBox(height: 110, radius: 16),
                  SizedBox(height: 14),
                  SkeletonListTile(padding: EdgeInsets.zero, trailing: true),
                  SkeletonListTile(padding: EdgeInsets.zero, trailing: true),
                  SkeletonListTile(padding: EdgeInsets.zero, trailing: true),
                  SkeletonListTile(padding: EdgeInsets.zero, trailing: true),
                ],
              ),
            )
          : NuruRefreshIndicator(
              onRefresh: _loadKyc,
              color: AppColors.primary,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _infoBanner(),
                const SizedBox(height: 14),
                _progressCard(),
                const SizedBox(height: 14),
                ..._items.asMap().entries.map((e) => _kycItemCard(e.key, e.value)),
                if (_hasEditable) _submitButtons(),
                const SizedBox(height: 80),
              ]),
            ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SvgPicture.asset('assets/icons/info-icon.svg', width: 18, height: 18,
          colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Why is this needed?', style: appText(size: 13, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Nuru holds money in escrow, handles disputes, and pays vendors after confirmation. Business verification ensures your service meets the standards required for payouts and bookings.',
            style: appText(size: 12, color: AppColors.textSecondary, height: 1.4),
          ),
        ])),
      ]),
    );
  }

  Widget _progressCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Verification Progress', style: appText(size: 13, weight: FontWeight.w700)),
          Text('$_verifiedCount of ${_items.length} verified',
              style: appText(size: 11, color: AppColors.textTertiary)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progress / 100,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: _verifiedCount == _items.length && _items.isNotEmpty
              ? Row(children: [
                  const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text('All items verified!',
                      style: appText(size: 11, weight: FontWeight.w600, color: AppColors.success)),
                ])
              : Text('${_progress.round()}% verified', style: appText(size: 11, color: AppColors.textTertiary)),
        ),
      ]),
    );
  }

  Widget _submitButtons() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => _submit(partial: true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_submitting ? 'Saving…' : 'Save Progress',
                        style: appText(size: 13, weight: FontWeight.w700, color: AppColors.primary)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : () => _submit(partial: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Submit for Review',
                              style: appText(size: 13, weight: FontWeight.w700, color: Colors.white)),
                        ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            'You can save your progress and return later. Our team typically reviews submissions within 24–48 hours. Once approved, your service goes live.',
            textAlign: TextAlign.center,
            style: appText(size: 11, color: AppColors.textTertiary, height: 1.4),
          ),
        ]),
      ),
    );
  }

  Widget _kycItemCard(int index, Map<String, dynamic> item) {
    final status = item['status']?.toString();
    final isVerified = status == 'verified';
    final isPending = status == 'pending';
    final isRejected = status == 'rejected';
    final isMandatory = item['is_mandatory'] == true;
    final files = item['files'] as List<File>;
    final remarks = item['remarks']?.toString();

    Color statusColor = AppColors.textTertiary;
    String statusLabel = 'Not submitted';
    if (isVerified) { statusColor = AppColors.success; statusLabel = 'Verified'; }
    else if (isPending) { statusColor = AppColors.warning; statusLabel = 'Pending review'; }
    else if (isRejected) { statusColor = AppColors.error; statusLabel = 'Rejected'; }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isVerified
            ? AppColors.success.withOpacity(0.3)
            : isRejected ? AppColors.error.withOpacity(0.3) : AppColors.borderLight),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Leading document icon tile
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isVerified
                  ? AppColors.success.withOpacity(0.1)
                  : isPending
                      ? AppColors.warning.withOpacity(0.1)
                      : AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: SvgPicture.asset(
                isVerified
                    ? 'assets/icons/verified-icon.svg'
                    : isPending
                        ? 'assets/icons/clock-icon.svg'
                        : 'assets/icons/file-pdf-icon.svg',
                width: 20, height: 20,
                colorFilter: ColorFilter.mode(
                  isVerified
                      ? AppColors.success
                      : isPending
                          ? AppColors.warning
                          : AppColors.primary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title + subtitle (Required / status)
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['name']?.toString() ?? 'Document',
                  style: appText(size: 13.5, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                isVerified || isPending || isRejected
                    ? statusLabel
                    : (isMandatory ? 'Required' : 'Optional'),
                style: appText(
                  size: 11,
                  weight: FontWeight.w500,
                  color: isVerified
                      ? AppColors.success
                      : isPending
                          ? AppColors.warning
                          : isRejected
                              ? AppColors.error
                              : AppColors.textTertiary,
                ),
              ),
            ]),
          ),
          // Right-aligned outlined "Upload" pill
          if (!isVerified && !isPending)
            OutlinedButton.icon(
              onPressed: () => _pickFile(index),
              icon: SvgPicture.asset('assets/icons/upload-icon.svg', width: 14, height: 14,
                  colorFilter: ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
              label: Text('Upload',
                  style: appText(size: 12.5, weight: FontWeight.w700, color: AppColors.primary)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 36),
              ),
            ),
        ]),
        if ((item['description']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(item['description'].toString(),
              style: appText(size: 11, color: AppColors.textTertiary, height: 1.4)),
        ],
        if (isRejected && remarks != null && remarks.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SvgPicture.asset('assets/icons/warning-icon.svg', width: 14, height: 14,
                  colorFilter: ColorFilter.mode(AppColors.error, BlendMode.srcIn)),
              const SizedBox(width: 6),
              Expanded(child: Text(remarks, style: appText(size: 11, color: AppColors.error))),
            ]),
          ),
        ],
        if (files.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(files.length, (i) => _filePreview(index, i, files[i])),
          ),
        ],
      ]),
    );
  }


  Widget _filePreview(int itemIdx, int fileIdx, File file) {
    final name = file.path.split('/').last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isImg = ['jpg', 'jpeg', 'png', 'webp'].contains(ext);
    final size = file.lengthSync();
    final sizeKb = size / 1024;
    final sizeStr = sizeKb >= 1024 ? '${(sizeKb / 1024).toStringAsFixed(1)} MB' : '${sizeKb.toStringAsFixed(0)} KB';

    return GestureDetector(
      onTap: isImg ? () => _showImagePreview(file, name) : null,
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isImg
                  ? Image.file(file, width: 108, height: 80, fit: BoxFit.cover)
                  : Container(
                      width: 108, height: 80,
                      color: AppColors.primary.withOpacity(0.08),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.picture_as_pdf_rounded, size: 28, color: AppColors.primary),
                        const SizedBox(height: 2),
                        Text(ext.toUpperCase(), style: appText(size: 10, weight: FontWeight.w700, color: AppColors.primary)),
                      ]),
                    ),
            ),
            Positioned(
              top: 2, right: 2,
              child: GestureDetector(
                onTap: () => _removeFile(itemIdx, fileIdx),
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: appText(size: 10, weight: FontWeight.w600)),
          Text(sizeStr, style: appText(size: 9, color: AppColors.textTertiary)),
        ]),
      ),
    );
  }

  void _showImagePreview(File file, String name) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 8, right: 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
