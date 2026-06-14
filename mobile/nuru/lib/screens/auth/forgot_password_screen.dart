import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/country_phone_input.dart';
import '../../core/widgets/otp_input.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/auth_skyline.dart';
import '../../providers/auth_provider.dart';
import '../../core/utils/password_strength.dart';

import 'widgets/auth_text_field.dart';
import '../../core/l10n/l10n_helper.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  String _step = 'choose';
  bool _loading = false;

  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  String _fullPhone = '';
  String? _otpChannel;
  String? _resetToken;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  final _otpCtrls = List.generate(6, (_) => TextEditingController());
  final _otpNodes = List.generate(6, (_) => FocusNode());

  AuthProvider get _auth => context.read<AuthProvider>();
  String get _otpValue => _otpCtrls.map((c) => c.text).join();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    for (final c in _otpCtrls) c.dispose();
    for (final n in _otpNodes) n.dispose();
    super.dispose();
  }

  Future<void> _handleEmailReset() async {
    if (_emailCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, context.tr('enter_your_email'));
      return;
    }
    setState(() => _loading = true);
    final res = await _auth.forgotPassword(_emailCtrl.text.trim());
    setState(() => _loading = false);
    if (res['success'] == true) {
      if (mounted) {
        AppSnackbar.success(context, res['message'] ?? context.tr('reset_link_sent'));
        Navigator.pop(context);
      }
    } else {
      if (mounted) AppSnackbar.error(context, res['message'] ?? 'Failed');
    }
  }

  Future<void> _handlePhoneReset() async {
    final cleaned = _fullPhone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.length < 7) {
      AppSnackbar.error(context, context.tr('enter_your_phone'));
      return;
    }
    setState(() => _loading = true);

    // Only use backend flow (it handles WhatsApp/SMS routing internally)
    final backendRes = await _auth.forgotPasswordPhone(cleaned);

    setState(() => _loading = false);

    if (backendRes['success'] == true) {
      final msg = (backendRes['message'] ?? '').toString().toLowerCase();
      setState(() {
        if (msg.contains('whatsapp')) {
          _otpChannel = 'whatsapp';
        } else if (msg.contains('sms')) {
          _otpChannel = 'sms';
        } else {
          _otpChannel = 'sms';
        }
        _step = 'otp';
      });
      if (mounted)
        AppSnackbar.success(context, backendRes['message'] ?? context.tr('code_sent'));
    } else {
      if (mounted)
        AppSnackbar.error(context, backendRes['message'] ?? 'Failed');
    }
  }

  Future<void> _handleVerifyOtp() async {
    final otp = _otpValue;
    if (otp.length < 6) {
      AppSnackbar.error(context, context.tr('enter_6_digit_code'));
      return;
    }
    setState(() => _loading = true);
    final cleaned = _fullPhone.replaceAll(RegExp(r'[^\d]'), '');

    // Only use backend verification (matches the backend-sent OTP)
    final res = await _auth.verifyResetOtp(cleaned, otp);
    setState(() => _loading = false);

    if (res['success'] == true && res['data']?['reset_token'] != null) {
      _resetToken = res['data']['reset_token'];
      setState(() => _step = 'reset');
    } else {
      if (mounted)
        AppSnackbar.error(context, res['message'] ?? context.tr('verification_failed'));
    }
  }

  Future<void> _handleResetPassword() async {
    final err = PasswordStrength.firstError(_newPwCtrl.text);
    if (err != null) {
      AppSnackbar.error(context, err);
      return;
    }
    if (_newPwCtrl.text != _confirmPwCtrl.text) {
      AppSnackbar.error(context, context.tr('passwords_dont_match'));
      return;
    }
    setState(() => _loading = true);
    final res = await _auth.resetPassword(
      _resetToken!,
      _newPwCtrl.text,
      _confirmPwCtrl.text,
    );
    setState(() => _loading = false);
    if (res['success'] == true) {
      if (mounted) {
        AppSnackbar.success(context, context.tr('password_reset_success'));
        Navigator.pop(context);
      }
    } else {
      if (mounted) AppSnackbar.error(context, res['message'] ?? context.tr('reset_failed'));
    }
  }

  void _goBack() {
    if (_step == 'otp')
      setState(() => _step = 'phone');
    else if (_step == 'reset')
      setState(() => _step = 'otp');
    else if (_step != 'choose')
      setState(() => _step = 'choose');
    else
      Navigator.pop(context);
  }

  String get _title {
    switch (_step) {
      case 'email':
        return context.tr('reset_via_email');
      case 'phone':
        return context.tr('reset_via_phone');
      case 'otp':
        return context.tr('enter_code');
      case 'reset':
        return context.tr('new_password');
      default:
        return context.tr('reset_password');
    }
  }

  String get _subtitle {
    switch (_step) {
      case 'email':
        return context.tr('enter_email_reset');
      case 'phone':
        return context.tr('enter_phone_reset');
      case 'otp':
        return '${context.tr('we_sent_code_to')} ${maskPhoneDisplay(_fullPhone)}';
      case 'reset':
        return context.tr('choose_new_password');
      default:
        return context.tr('choose_recovery');
    }
  }

  IconData get _icon {
    switch (_step) {
      case 'email':
        return Icons.email_outlined;
      case 'phone':
        return Icons.phone_android_rounded;
      case 'otp':
        return Icons.verified_rounded;
      case 'reset':
        return Icons.shield_rounded;
      default:
        return Icons.lock_reset_rounded;
    }
  }

  String? get _iconSvg {
    switch (_step) {
      case 'email':
        return 'assets/icons/email-icon.svg';
      case 'phone':
        return 'assets/icons/mobile-icon.svg';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        // Keep the decorative wave pinned to the bottom even with keyboard up
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Bottom decorative wave
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AuthSkyline(
                color: AppColors.primary,
                height: 200,
                opacity: 0.55,
              ),
            ),
            // Top-right organic curved accent
            const Positioned(
              top: 0, right: 0,
              child: AuthCornerBlob(
                color: AppColors.primary,
                size: 240,
                opacity: 0.55,
                alignment: Alignment.topRight,
              ),
            ),
            SafeArea(
              child: Stack(
                children: [

              Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _goBack,
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: AppColors.textPrimary, size: 22),
                          splashRadius: 22,
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 24,
                        right: 24,
                        bottom: bottomInset > 0 ? 24 : 130,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Padlock illustration
                          _LockIllustration(icon: _icon, svgAsset: _iconSvg),
                          const SizedBox(height: 20),
                          Text(
                            _title,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.4,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _subtitle,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 28),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: _buildCurrentStep(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 'choose':
        return _chooseStep();
      case 'email':
        return _emailStep();
      case 'phone':
        return _phoneStep();
      case 'otp':
        return _otpStep();
      case 'reset':
        return _resetStep();
      default:
        return _chooseStep();
    }
  }

  Widget _chooseStep() {
    return Column(
      key: const ValueKey('choose'),
      children: [
        _optionCard(
          'assets/icons/email-icon.svg',
          context.tr('reset_via_email'),
          context.tr('well_send_reset_link'),
          () => setState(() => _step = 'email'),
        ),
        const SizedBox(height: 12),
        _optionCard(
          'assets/icons/mobile-icon.svg',
          context.tr('reset_via_phone'),
          context.tr('well_send_otp'),
          () => setState(() => _step = 'phone'),
        ),
      ],
    );
  }

  Widget _optionCard(
    String svgAsset,
    String label,
    String desc,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border.withOpacity(0.5), width: 0.7),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F5F8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SvgPicture.asset(
                svgAsset,
                width: 22, height: 22,
                colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(desc, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _emailStep() {
    return Column(
      key: const ValueKey('email'),
      children: [
        AuthTextField(
          controller: _emailCtrl,
          label: context.tr('email_address'),
          hintText: context.tr('email_hint'),
          prefixSvg: 'assets/icons/email-icon.svg',
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
        ),
        const SizedBox(height: 28),
        _ctaBtn(
          label: context.tr('send_reset_link'),
          onPressed: _loading ? null : _handleEmailReset,
          isLoading: _loading,
        ),
      ],
    );
  }

  Widget _phoneStep() {
    return Column(
      key: const ValueKey('phone'),
      children: [
        CountryPhoneInput(
          controller: _phoneCtrl,
          initialCountryCode: 'TZ',
          onFullNumberChanged: (f) => _fullPhone = f,
        ),
        const SizedBox(height: 28),
        _ctaBtn(
          label: context.tr('send_reset_code'),
          onPressed: _loading ? null : _handlePhoneReset,
          isLoading: _loading,
        ),
      ],
    );
  }

  Widget _otpStep() {
    return Column(
      key: const ValueKey('otp'),
      children: [
        if (_otpChannel != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: _otpChannel == 'whatsapp'
                  ? const Color(0x1225D366)
                  : AppColors.infoSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  _otpChannel == 'whatsapp'
                      ? Icons.message_rounded
                      : Icons.sms_outlined,
                  size: 16,
                  color: _otpChannel == 'whatsapp'
                      ? const Color(0xFF25D366)
                      : AppColors.info,
                ),
                const SizedBox(width: 8),
                Text(
                  _otpChannel == 'whatsapp' ? context.tr('check_whatsapp') : context.tr('check_sms'),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _otpChannel == 'whatsapp'
                        ? const Color(0xFF25D366)
                        : AppColors.info,
                  ),
                ),
              ],
            ),
          ),
        OtpInput(
          controllers: _otpCtrls,
          focusNodes: _otpNodes,
          onCompleted: (_) => _handleVerifyOtp(),
        ),
        const SizedBox(height: 28),
        _ctaBtn(
          label: context.tr('verify_and_continue'),
          onPressed: _loading ? null : _handleVerifyOtp,
          isLoading: _loading,
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: _loading ? null : _handlePhoneReset,
            child: Text(
              context.tr('didnt_get_code'),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _resetStep() {
    return Column(
      key: const ValueKey('reset'),
      children: [
        AuthTextField(
          controller: _newPwCtrl,
          label: context.tr('new_password_label'),
          hintText: context.tr('create_new_password_hint'),
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: _obscureNew,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureNew
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.textHint,
              size: 20,
            ),
            onPressed: () => setState(() => _obscureNew = !_obscureNew),
          ),
        ),
        const SizedBox(height: 18),
        AuthTextField(
          controller: _confirmPwCtrl,
          label: context.tr('confirm_password_label'),
          hintText: context.tr('reenter_password_hint'),
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: _obscureConfirm,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureConfirm
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.textHint,
              size: 20,
            ),
            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),
        const SizedBox(height: 28),
        _ctaBtn(
          label: context.tr('reset_password'),
          onPressed: _loading ? null : _handleResetPassword,
          isLoading: _loading,
        ),
      ],
    );
  }

  Widget _ctaBtn({required String label, VoidCallback? onPressed, bool isLoading = false}) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: isLoading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Text(label, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

/// Decorative padlock-with-refresh illustration shown on the forgot-password
/// hero, matching the reference design (soft circle, golden lock, confetti).
class _LockIllustration extends StatelessWidget {
  final IconData icon;
  final String? svgAsset;
  const _LockIllustration({required this.icon, this.svgAsset});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      width: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft background circle
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
          ),
          // Confetti dots
          const Positioned(
            left: 8, top: 24,
            child: _Dot(color: Color(0xFF22C55E), size: 8),
          ),
          const Positioned(
            right: 12, top: 18,
            child: _Dot(color: Color(0xFFA855F7), size: 8),
          ),
          const Positioned(
            right: 0, bottom: 28,
            child: _Dot(color: Color(0xFFFFC233), size: 7),
          ),
          const Positioned(
            left: 18, bottom: 36,
            child: _Dot(color: Color(0xFFFFC233), size: 6),
          ),
          // Main lock icon
          Container(
            width: 86,
            height: 86,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: svgAsset != null
                ? SvgPicture.asset(svgAsset!, width: 44, height: 44,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))
                : Icon(icon, size: 44, color: Colors.white),
          ),
          // Refresh badge
          Positioned(
            right: 50, bottom: 36,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFF111827),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.refresh_rounded,
                  size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final double size;
  const _Dot({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
