import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/services/event_extras_service.dart';
import '../../core/l10n/l10n_helper.dart';

/// Identity Verification - premium redesign per Nuru mockup.
class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

enum _Slot { idFront, idBack }

class _IdentityVerificationScreenState extends State<IdentityVerificationScreen> {
  static const _maxBytes = 5 * 1024 * 1024;
  static const _allowedExt = {'jpg', 'jpeg', 'png', 'webp'};

  // Palette - Nuru primary (gold) replaces the legacy orange accents.
  static const _navy = Color(0xFF0A1C40);
  static const _navySoft = Color(0xFF1A2A4F);
  static const Color _orange = AppColors.primary;      // Nuru gold
  static const Color _orangeSoft = AppColors.primarySoft;
  static const _greenSoft = Color(0x14169B5C);
  static const _green = Color(0xFF169B5C);
  static const _cardBorder = Color(0xFFE6E9F2);
  static const _muted = Color(0xFF6B7891);

  String _status = 'unverified';
  String? _rejectionReason;
  bool _loading = true;
  bool _submitting = false;

  String? _idFrontPath;
  String? _idBackPath;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    final res = await EventExtrasService.getVerificationStatus();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true && res['data'] is Map) {
        final d = res['data'] as Map<String, dynamic>;
        _status = (d['status'] ?? 'unverified').toString();
        _rejectionReason = d['rejection_reason']?.toString();
      }
    });
  }

  Future<void> _pickFor(_Slot slot) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(color: _cardBorder, borderRadius: BorderRadius.circular(4)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Choose source', style: _f(size: 17, weight: FontWeight.w700)),
            ),
            const SizedBox(height: 16),
            _sheetTile('assets/icons/camera-icon.svg', 'Take a photo', 'Capture with your camera',
                () => Navigator.pop(context, ImageSource.camera)),
            const SizedBox(height: 10),
            _sheetTile('assets/icons/gallery-icon.svg', 'Choose from gallery', 'Pick a saved image',
                () => Navigator.pop(context, ImageSource.gallery)),
          ]),
        ),
      ),
    );
    if (source == null) return;

    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 88,
      );
      if (picked == null || !mounted) return;

      final file = File(picked.path);
      final size = await file.length();
      if (size > _maxBytes) {
        AppSnackbar.show(context, type: AppSnackbarType.error,
          title: 'File too large', message: 'Please choose an image 5MB or smaller.');
        return;
      }
      final ext = picked.path.split('.').last.toLowerCase();
      if (!_allowedExt.contains(ext)) {
        AppSnackbar.show(context, type: AppSnackbarType.error,
          title: 'Unsupported format', message: 'Only JPG, PNG, or WEBP images are allowed.');
        return;
      }

      setState(() {
        switch (slot) {
          case _Slot.idFront: _idFrontPath = picked.path; break;
          case _Slot.idBack: _idBackPath = picked.path; break;
        }
      });
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Unable to pick image');
    }
  }

  Widget _sheetTile(String iconAsset, String label, String subtitle, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: SvgPicture.asset(iconAsset, width: 20, height: 20,
                  colorFilter: const ColorFilter.mode(_orange, BlendMode.srcIn)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: _f(size: 14.5, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, style: _f(size: 12, color: _muted)),
            ])),
            SvgPicture.asset('assets/icons/chevron-right-icon.svg', width: 18, height: 18,
                colorFilter: const ColorFilter.mode(_muted, BlendMode.srcIn)),
          ]),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_idFrontPath == null) {
      AppSnackbar.show(context, type: AppSnackbarType.warning,
        title: 'Front of ID required', message: 'Please upload the front side of your ID first.');
      return;
    }
    if (_idBackPath == null) {
      AppSnackbar.show(context, type: AppSnackbarType.warning,
        title: 'Back of ID required', message: 'Please upload the back side of your ID first.');
      return;
    }
    setState(() => _submitting = true);
    final res = await EventExtrasService.submitVerification(
      documentNumber: '',
      idFrontPath: _idFrontPath!,
      idBackPath: _idBackPath,
      selfiePath: null,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res['success'] == true) {
      setState(() {
        _status = 'pending';
        _idFrontPath = null;
        _idBackPath = null;
      });
      AppSnackbar.show(context, type: AppSnackbarType.success,
        title: 'Submitted for review',
        message: 'We\u2019ll get back to you within 1-3 business days.');
    } else {
      final errors = (res['data'] is Map) ? (res['data']['errors'] as Map?) : null;
      final firstErr = errors?.values.first?.toString();
      AppSnackbar.show(context, type: AppSnackbarType.error,
        title: 'Submission failed',
        message: firstErr ?? res['message']?.toString() ?? 'Please try again in a moment.');
    }
  }

  TextStyle _f({required double size, FontWeight weight = FontWeight.w500, Color color = _navy, double height = 1.3, double letterSpacing = 0}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: letterSpacing);

  bool get _canEdit => _status == 'unverified' || _status == 'rejected';

  int get _completedCount {
    if (!_canEdit) return 2;
    int c = 0;
    if (_idFrontPath != null) c++;
    if (_idBackPath != null) c++;
    return c;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: NuruSubPageAppBar(title: context.tr('identity_verification')),
      body: _loading
          ? _skeleton()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _heroCard(),
                if (_status == 'rejected' && (_rejectionReason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.error.withOpacity(0.18)),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SvgPicture.asset('assets/icons/info-icon.svg', width: 16, height: 16,
                          colorFilter: ColorFilter.mode(AppColors.error, BlendMode.srcIn)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_rejectionReason!,
                        style: _f(size: 12.5, color: AppColors.error, height: 1.4))),
                    ]),
                  ),
                ],
                if (_status == 'verified') ...[
                  const SizedBox(height: 14),
                  _verifiedSuccessCard(),
                ],
                if (_status == 'pending') ...[
                  const SizedBox(height: 14),
                  _pendingReviewCard(),
                ],
                if (_canEdit) ...[
                  const SizedBox(height: 22),
                  _uploadHeader(),
                  const SizedBox(height: 8),
                  Text(
                    'Please provide clear, unedited images of both sides of your ID.',
                    style: _f(size: 12.5, color: _muted, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _uploadCard(
                      label: 'Front of ID',
                      hint: 'Upload a clear photo of\nthe front side of your ID.',
                      illustration: 'assets/icons/id-front-icon.svg',
                      path: _idFrontPath,
                      onTap: () => _pickFor(_Slot.idFront),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _uploadCard(
                      label: 'Back of ID',
                      hint: 'Upload a clear photo of\nthe back side of your ID.',
                      illustration: 'assets/icons/id-back-icon.svg',
                      path: _idBackPath,
                      onTap: () => _pickFor(_Slot.idBack),
                    )),
                  ]),
                  const SizedBox(height: 18),
                  _secureCard(),
                  const SizedBox(height: 18),
                  _submitButton(),
                ],
              ],
            ),
    );
  }

  // ── HERO ─────────────────────────────────────────────────────────────
  Widget _heroCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // shield icon chip
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: _orangeSoft, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: SvgPicture.asset('assets/icons/verified-icon.svg', width: 26, height: 26,
                  colorFilter: const ColorFilter.mode(_orange, BlendMode.srcIn)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_heroTitle, style: _f(size: 17, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_heroDesc, style: _f(size: 12.5, color: _muted, height: 1.5)),
            ])),
            const SizedBox(width: 12),
            Container(width: 1, color: _cardBorder),
            const SizedBox(width: 12),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
              RichText(
                text: TextSpan(children: [
                  TextSpan(text: '$_completedCount ',
                    style: _f(size: 28, weight: FontWeight.w800, height: 1)),
                  TextSpan(text: 'of 2',
                    style: _f(size: 13, color: _muted, height: 1)),
                ]),
              ),
              const SizedBox(height: 4),
              Text('uploaded', style: _f(size: 11.5, color: _muted)),
            ]),
          ]),
        ),
        if (_canEdit) ...[
          const SizedBox(height: 18),
          Divider(height: 1, color: _cardBorder),
          const SizedBox(height: 14),
          _stepper(),
        ],
      ]),
    );
  }

  Widget _stepper() {
    final s1Done = _idFrontPath != null;
    final s2Done = _idBackPath != null;
    final s2Active = s1Done;
    return Row(children: [
      _step(index: 1, label: 'Front of ID', done: s1Done, active: true),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: CustomPaint(
            painter: _DashPainter(color: _cardBorder),
            size: const Size(double.infinity, 1),
          ),
        ),
      ),
      _step(index: 2, label: 'Back of ID', done: s2Done, active: s2Active),
    ]);
  }

  Widget _step({required int index, required String label, required bool done, required bool active}) {
    final fillColor = done ? _green : (active ? Colors.white : Colors.white);
    final borderColor = done ? _green : (active ? _navy : _cardBorder);
    final textColor = done ? Colors.white : (active ? _navy : _muted);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: fillColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.4),
        ),
        alignment: Alignment.center,
        child: done
            ? SvgPicture.asset('assets/icons/check-icon.svg', width: 14, height: 14,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))
            : Text('$index', style: _f(size: 12, weight: FontWeight.w700, color: textColor, height: 1)),
      ),
      const SizedBox(height: 6),
      Text(label, style: _f(size: 11.5, weight: FontWeight.w600, color: active ? _navy : _muted)),
    ]);
  }

  // ── UPLOAD SECTION ───────────────────────────────────────────────────
  Widget _uploadHeader() {
    return Row(children: [
      Text('Upload your ID', style: _f(size: 16, weight: FontWeight.w700)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(20)),
        child: Text('REQUIRED',
          style: _f(size: 9.5, weight: FontWeight.w800, color: _orange, height: 1, letterSpacing: 0.7)),
      ),
    ]);
  }

  Widget _uploadCard({
    required String label,
    required String hint,
    required String illustration,
    required String? path,
    required VoidCallback onTap,
  }) {
    final hasFile = path != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hasFile ? _orange : _cardBorder, width: hasFile ? 1.4 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Illustration with upload bubble
        SizedBox(
          height: 70,
          child: Stack(clipBehavior: Clip.none, children: [
            Align(
              alignment: Alignment.center,
              child: hasFile
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(path), width: 84, height: 60, fit: BoxFit.cover))
                  : SvgPicture.asset(illustration, width: 84, height: 60,
                      colorFilter: const ColorFilter.mode(_navy, BlendMode.srcIn)),
            ),
            Positioned(
              right: 12, top: 6,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: _orange, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                    hasFile ? 'assets/icons/check-icon.svg' : 'assets/icons/upload-icon.svg',
                    width: 14, height: 14,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Center(child: Text(label, style: _f(size: 14.5, weight: FontWeight.w800))),
        const SizedBox(height: 6),
        Text(hint, textAlign: TextAlign.center,
          style: _f(size: 11.5, color: _muted, height: 1.45)),
        const SizedBox(height: 12),
        // Dashed divider
        SizedBox(
          height: 1,
          child: CustomPaint(painter: _DashPainter(color: _cardBorder), size: const Size(double.infinity, 1)),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text('JPG, PNG, WEBP  •  Max 5MB',
            style: _f(size: 10.5, color: _muted, letterSpacing: 0.2)),
        ),
        const SizedBox(height: 10),
        // Choose file button
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cardBorder),
              ),
              alignment: Alignment.center,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                SvgPicture.asset(
                    hasFile ? 'assets/icons/upload-icon.svg' : 'assets/icons/plus-icon.svg',
                    width: 14, height: 14,
                    colorFilter: const ColorFilter.mode(_navy, BlendMode.srcIn)),
                const SizedBox(width: 6),
                Text(hasFile ? 'Replace' : 'Choose file',
                  style: _f(size: 12.5, weight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ── SECURE CARD ──────────────────────────────────────────────────────
  Widget _secureCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: _greenSoft, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: SvgPicture.asset('assets/icons/lock-icon.svg', width: 20, height: 20,
              colorFilter: const ColorFilter.mode(_green, BlendMode.srcIn)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Your data is secure', style: _f(size: 13.5, weight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
            'End-to-end encrypted. Documents are used only for verification and reviewed within 1-3 business days.',
            style: _f(size: 11.5, color: _muted, height: 1.5),
          ),
        ])),
      ]),
    );
  }

  // ── SUBMIT BUTTON ────────────────────────────────────────────────────
  Widget _submitButton() {
    final ready = !_submitting && _idFrontPath != null && _idBackPath != null;
    return SizedBox(
      width: double.infinity, height: 56,
      child: ElevatedButton(
        onPressed: ready ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _navySoft.withOpacity(0.6),
          disabledForegroundColor: Colors.white.withOpacity(0.85),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _submitting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SvgPicture.asset('assets/icons/send-icon.svg', width: 16, height: 16,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                const SizedBox(width: 10),
                Text('Submit for verification',
                  style: _f(size: 15, weight: FontWeight.w700, color: Colors.white)),
              ]),
      ),
    );
  }

  // ── VERIFIED SUCCESS STATE ───────────────────────────────────────────
  Widget _verifiedSuccessCard() {
    Widget benefit(String icon, String title, String sub) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: _greenSoft, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: SvgPicture.asset('assets/icons/$icon.svg', width: 16, height: 16,
                  colorFilter: const ColorFilter.mode(_green, BlendMode.srcIn)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: _f(size: 13.5, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, style: _f(size: 12, color: _muted, height: 1.4)),
            ])),
          ]),
        );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: _greenSoft, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: SvgPicture.asset('assets/icons/check-icon.svg', width: 22, height: 22,
                colorFilter: const ColorFilter.mode(_green, BlendMode.srcIn)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Identity confirmed', style: _f(size: 15.5, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Your documents passed our checks.',
                style: _f(size: 12.5, color: _muted)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _greenSoft, borderRadius: BorderRadius.circular(999)),
            child: Text('Verified',
              style: _f(size: 11, weight: FontWeight.w700, color: _green)),
          ),
        ]),
        const SizedBox(height: 8),
        Divider(height: 1, color: _cardBorder),
        const SizedBox(height: 4),
        benefit('shield-icon', 'Trusted badge',
            'Your profile now shows a verified mark across the app.'),
        benefit('wallet-icon', 'Higher limits',
            'Send and receive larger amounts without extra checks.'),
        benefit('lock-icon', 'Documents secured',
            'We keep your ID encrypted and never share it with third parties.'),
      ]),
    );
  }

  Widget _pendingReviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: _orangeSoft, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: SvgPicture.asset('assets/icons/clock-icon.svg', width: 22, height: 22,
              colorFilter: const ColorFilter.mode(_orange, BlendMode.srcIn)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Awaiting review', style: _f(size: 15, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Our trust team usually reviews documents within 1-3 business days. We\u2019ll notify you the moment a decision is made.',
            style: _f(size: 12.5, color: _muted, height: 1.45),
          ),
        ])),
      ]),
    );
  }



  String get _heroTitle {
    switch (_status) {
      case 'verified': return 'You\u2019re verified';
      case 'pending': return 'Under review';
      case 'rejected': return 'Verification rejected';
      default: return 'Verify your identity';
    }
  }

  String get _heroDesc {
    switch (_status) {
      case 'verified': return 'Your identity has been confirmed. You now have full access to trusted features.';
      case 'pending': return 'Our team is reviewing your documents. This typically takes 1-3 business days.';
      case 'rejected': return 'We couldn\u2019t verify your identity. Please re-upload clearer documents below.';
      default: return 'Confirm your identity to build trust, unlock advanced features, and access higher limits.';
    }
  }

  // ── SKELETON LOADER ──────────────────────────────────────────────────
  Widget _skeleton() {
    Widget bar({double w = double.infinity, double h = 12, double r = 6}) => Container(
          width: w, height: h,
          decoration: BoxDecoration(color: _cardBorder, borderRadius: BorderRadius.circular(r)),
        );
    Widget uploadSkel() => Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(
              height: 70,
              child: Stack(clipBehavior: Clip.none, children: [
                Align(alignment: Alignment.center, child: bar(w: 84, h: 60, r: 10)),
                Positioned(
                  right: 12, top: 6,
                  child: Container(width: 28, height: 28,
                    decoration: BoxDecoration(color: _cardBorder, shape: BoxShape.circle)),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            bar(w: 90, h: 12),
            const SizedBox(height: 8),
            bar(w: 140, h: 10),
            const SizedBox(height: 4),
            bar(w: 110, h: 10),
            const SizedBox(height: 14),
            bar(h: 1, r: 0),
            const SizedBox(height: 10),
            bar(w: 130, h: 9),
            const SizedBox(height: 12),
            bar(h: 40, r: 12),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // Hero skeleton
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cardBorder),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 52, height: 52,
                decoration: BoxDecoration(color: _cardBorder, shape: BoxShape.circle)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                bar(w: 170, h: 14),
                const SizedBox(height: 8),
                bar(w: double.infinity, h: 10),
                const SizedBox(height: 4),
                bar(w: 220, h: 10),
              ])),
              const SizedBox(width: 12),
              Container(width: 1, height: 44, color: _cardBorder),
              const SizedBox(width: 12),
              Column(children: [
                bar(w: 44, h: 22),
                const SizedBox(height: 6),
                bar(w: 50, h: 10),
              ]),
            ]),
            const SizedBox(height: 18),
            Divider(height: 1, color: _cardBorder),
            const SizedBox(height: 14),
            Row(children: [
              Column(children: [
                Container(width: 28, height: 28,
                  decoration: BoxDecoration(color: _cardBorder, shape: BoxShape.circle)),
                const SizedBox(height: 6),
                bar(w: 60, h: 10),
              ]),
              const SizedBox(width: 8),
              Expanded(child: bar(h: 1, r: 0)),
              const SizedBox(width: 8),
              Column(children: [
                Container(width: 28, height: 28,
                  decoration: BoxDecoration(color: _cardBorder, shape: BoxShape.circle)),
                const SizedBox(height: 6),
                bar(w: 60, h: 10),
              ]),
            ]),
          ]),
        ),
        const SizedBox(height: 22),
        bar(w: 140, h: 14),
        const SizedBox(height: 10),
        bar(w: 260, h: 10),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: uploadSkel()),
          const SizedBox(width: 12),
          Expanded(child: uploadSkel()),
        ]),
        const SizedBox(height: 18),
        Container(
          height: 70,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBorder),
          ),
        ),
        const SizedBox(height: 18),
        bar(h: 56, r: 16),
      ]
        .map((w) => Padding(padding: EdgeInsets.zero, child: w))
        .toList(),
    );
  }
}


/// Dashed horizontal line painter used in the stepper connector and the
/// dotted divider inside each upload card.
class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const dash = 4.0, gap = 4.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) => oldDelegate.color != color;
}
