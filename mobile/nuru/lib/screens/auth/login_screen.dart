import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/saved_accounts_service.dart';
import '../../core/widgets/nuru_logo.dart';
import '../../core/widgets/auth_skyline.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/language_selector.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../providers/auth_provider.dart';
import '../home/home_screen.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'widgets/auth_text_field.dart';
import '../../core/widgets/otp_input.dart';
import 'package:animate_do/animate_do.dart';
import 'widgets/auth_otp_widgets.dart';

TextStyle _f({
  required double size,
  FontWeight weight = FontWeight.w500,
  Color color = AppColors.textPrimary,
  double height = 1.2,
  double letterSpacing = 0,
}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _credCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  List<SavedAccount> _savedAccounts = const [];
  String? _quickLoadingId;

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    final list = await SavedAccountsService.list();
    if (mounted) setState(() => _savedAccounts = list);
  }

  Future<void> _quickSignIn(SavedAccount acc) async {
    if (_quickLoadingId != null) return;
    setState(() => _quickLoadingId = acc.id);
    final ok = await context.read<AuthProvider>().quickSignIn(acc.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } else {
      setState(() => _quickLoadingId = null);
      AppSnackbar.error(context, 'Session expired · please sign in with your password.');
      _credCtrl.text = acc.email ?? acc.phone ?? '';
    }
  }

  Future<void> _confirmRemoveAccount(SavedAccount acc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Remove ${acc.name}?',
            style: _f(size: 16, weight: FontWeight.w700)),
        content: Text(
          'This account will be removed from this device. You can still sign in again with your password.',
          style: _f(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: _f(size: 13, weight: FontWeight.w600, color: AppColors.textTertiary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Remove', style: _f(size: 13, weight: FontWeight.w700, color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) {
      await context.read<AuthProvider>().forgetSavedAccount(acc.id);
      await _loadSavedAccounts();
    }
  }

  Widget _accountSwitcher() {
    if (_savedAccounts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              _savedAccounts.length == 1 ? 'Continue as' : 'Pick an account',
              style: _f(size: 12, weight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 0.4),
            ),
          ),
          SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: _savedAccounts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _accountTile(_savedAccounts[i]),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Container(height: 1, color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or use another account',
                  style: _f(size: 11, weight: FontWeight.w600, color: AppColors.textTertiary)),
            ),
            Expanded(child: Container(height: 1, color: AppColors.border)),
          ]),
        ],
      ),
    );
  }

  Widget _accountTile(SavedAccount acc) {
    final loading = _quickLoadingId == acc.id;
    final initials = acc.name.trim().isEmpty
        ? '?'
        : acc.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    return GestureDetector(
      onTap: loading ? null : () => _quickSignIn(acc),
      onLongPress: loading ? null : () => _confirmRemoveAccount(acc),
      child: Container(
        width: 108,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primary.withOpacity(0.18), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (acc.avatar != null && acc.avatar!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: acc.avatar!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Center(
                            child: Text(initials,
                                style: _f(size: 18, weight: FontWeight.w800, color: AppColors.primary)),
                          ),
                        )
                      : Center(
                          child: Text(initials,
                              style: _f(size: 18, weight: FontWeight.w800, color: AppColors.primary)),
                        ),
                ),
                if (loading)
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.7),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              acc.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _f(size: 12.5, weight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _credCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final res = await context.read<AuthProvider>().signIn(
        credential: _credCtrl.text.trim(),
        password: _pwCtrl.text,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        final data = res['data'] as Map<String, dynamic>?;
        final user = data?['user'] as Map<String, dynamic>?;

        if (user != null && user['is_phone_verified'] == false) {
          final userId = user['id']?.toString() ?? '';
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => _PhoneVerificationScreen(
                  userId: userId,
                  phone: _credCtrl.text.trim(),
                  password: _pwCtrl.text,
                ),
              ),
            );
          }
          return;
        }

        AppSnackbar.success(context, res['message'] ?? 'Welcome back!');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      } else {
        final data = res['data'];
        if (data is Map && data['suspended'] == true) {
          _showSuspendedDialog(data['suspension_reason']?.toString());
        } else {
          AppSnackbar.error(context, res['message'] ?? 'Login failed');
        }
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Unable to reach server. Try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuspendedDialog(String? reason) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        title: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.errorSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.block_rounded, color: AppColors.error, size: 20),
          ),
          const SizedBox(width: 12),
          Text('Account Suspended', style: AppTheme.heading(fontSize: 17)),
        ]),
        content: Text(
          reason ?? 'Your account has been suspended. Contact support for help.',
          style: AppTheme.body(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK',
                style: _f(size: 13, weight: FontWeight.w700, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        // Keep decorative footer pinned - don't push it up with keyboard
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Bottom decorative wave (fixed, ignores keyboard)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: AuthSkyline(
                color: AppColors.primary,
                height: 200,
                opacity: 0.22,
              ),
            ),
            // Top-right organic curved accent
            const Positioned(
              top: 0, right: 0,
              child: AuthCornerBlob(
                color: AppColors.primary,
                size: 240,
                opacity: 0.22,
                alignment: Alignment.topRight,
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  final hp = box.maxWidth < 360 ? 20.0 : 26.0;

                  return Stack(
                    children: [
                      // Top-left back button - only when there's somewhere to go
                      if (canPop)
                        Positioned(
                          top: 6,
                          left: hp - 8,
                          child: IconButton(
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: AppColors.textPrimary, size: 22),
                            splashRadius: 22,
                          ),
                        ),

                  SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: hp,
                      right: hp,
                      top: 60,
                      bottom: 200,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: box.maxHeight - 260,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 32),

                          // ── Title (single-line, scales down on narrow screens) ──
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              context.trw('welcome_back'),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
                              style: _f(
                                size: 28,
                                weight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                height: 1.15,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.trw('sign_in_subtitle'),
                            textAlign: TextAlign.center,
                            style: _f(
                              size: 14,
                              weight: FontWeight.w500,
                              color: AppColors.textSecondary,
                              height: 1.45,
                            ),
                          ),

                          const SizedBox(height: 28),
                          _accountSwitcher(),

                          // ── Form ──
                          Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AuthTextField(
                                  controller: _credCtrl,
                                  label: context.trw('phone_or_email'),
                                  hintText: 'Enter your username or email',
                                  prefixSvg: 'assets/icons/user-rounded-icon.svg',
                                  validator: (v) =>
                                      (v == null || v.isEmpty) ? 'Required' : null,
                                ),
                                const SizedBox(height: 16),
                                AuthTextField(
                                  controller: _pwCtrl,
                                  label: context.trw('password'),
                                  hintText: 'Enter your password',
                                  prefixSvg: 'assets/icons/lock-icon.svg',
                                  obscureText: _obscure,
                                  suffixIcon: IconButton(
                                    icon: SvgPicture.asset(
                                      _obscure
                                          ? 'assets/icons/eye-off-icon.svg'
                                          : 'assets/icons/eye-on-icon.svg',
                                      width: 20,
                                      height: 20,
                                      colorFilter: const ColorFilter.mode(
                                          AppColors.textHint, BlendMode.srcIn),
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.isEmpty) ? 'Required' : null,
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const ForgotPasswordScreen()),
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 4),
                                      minimumSize: const Size(52, 32),
                                    ),
                                    child: Text(
                                      context.trw('forgot_password'),
                                      style: _f(
                                        size: 13,
                                        weight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // ── Sign In CTA ──
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          AppColors.primary.withOpacity(0.5),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: _loading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                context.trw('sign_in'),
                                                style: _f(
                                                  size: 16,
                                                  weight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.arrow_forward_rounded,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 26),

                          // ── Sign up link ──
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                context.trw('dont_have_account'),
                                style: _f(
                                  size: 14,
                                  weight: FontWeight.w500,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  PageRouteBuilder(
                                    transitionDuration:
                                        const Duration(milliseconds: 350),
                                    pageBuilder: (_, a, __) =>
                                        const SignupScreen(),
                                    transitionsBuilder: (_, a, __, child) =>
                                        SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(1, 0),
                                        end: Offset.zero,
                                      ).animate(CurvedAnimation(
                                        parent: a,
                                        curve: Curves.easeOutCubic,
                                      )),
                                      child: child,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  context.trw('sign_up'),
                                  style: _f(
                                    size: 14,
                                    weight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                      // Top-right language switcher - rendered last so the scroll view cannot intercept taps
                      Positioned(
                        top: 10,
                        right: hp,
                        child: const LanguageToggle(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// PHONE VERIFICATION (post-login)
class _PhoneVerificationScreen extends StatefulWidget {
  final String userId;
  final String phone;
  final String password;
  const _PhoneVerificationScreen({required this.userId, required this.phone, required this.password});

  @override
  State<_PhoneVerificationScreen> createState() => _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<_PhoneVerificationScreen> {
  final List<TextEditingController> _otpCtrls = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());
  bool _verifying = false;
  bool _resending = false;
  int _countdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    // Request OTP immediately
    context.read<AuthProvider>().requestOtp(userId: widget.userId, verificationType: 'phone');
  }

  void _startCountdown() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) { t.cancel(); }
      if (mounted) setState(() => _countdown--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _otpCtrls) c.dispose();
    for (final f in _otpFocus) f.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _otpCtrls.map((c) => c.text).join();
    if (code.length < 6) {
      AppSnackbar.error(context, 'Enter the 6-digit code');
      return;
    }
    setState(() => _verifying = true);
    final res = await context.read<AuthProvider>().verifyOtp(
      userId: widget.userId,
      verificationType: 'phone',
      otpCode: code,
    );
    if (!mounted) return;

    if (res['success'] == true) {
      // Auto sign-in after verification
      final ok = await context.read<AuthProvider>().autoSignInAfterVerification(
        phone: widget.phone,
        password: widget.password,
      );
      if (mounted) {
        if (ok) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
          );
        } else {
          AppSnackbar.error(context, 'Verified but sign-in failed. Please log in again.');
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          );
        }
      }
    } else {
      setState(() => _verifying = false);
      AppSnackbar.error(context, res['message'] ?? 'Invalid OTP');
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    await context.read<AuthProvider>().requestOtp(userId: widget.userId, verificationType: 'phone');
    if (mounted) {
      setState(() => _resending = false);
      _startCountdown();
      AppSnackbar.success(context, 'OTP sent');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mm = (_countdown ~/ 60).toString().padLeft(2, '0');
    final ss = (_countdown % 60).toString().padLeft(2, '0');
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                FadeInDown(
                  duration: const Duration(milliseconds: 400),
                  child: const OtpShieldIllustration(),
                ),
                const SizedBox(height: 22),
                Text("Verify it's you",
                    style: authF(size: 22, weight: FontWeight.w800, letterSpacing: -0.4),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text("We've sent a 6-digit verification code to",
                    style: authF(size: 14, color: kAuthInkSoft, height: 1.5),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(maskPhoneDisplay(widget.phone),
                    style: authF(size: 18, weight: FontWeight.w800, letterSpacing: -0.2),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),

                OtpInput(
                  controllers: _otpCtrls,
                  focusNodes: _otpFocus,
                  onCompleted: (_) => _verify(),
                ),
                const SizedBox(height: 18),
                Center(
                  child: _countdown > 0
                      ? RichText(
                          text: TextSpan(
                            style: authF(size: 14, color: kAuthInkSoft),
                            children: [
                              const TextSpan(text: 'Code expires in '),
                              TextSpan(
                                text: '$mm:$ss',
                                style: authF(size: 14, color: kAuthAccent, weight: FontWeight.w700),
                              ),
                            ],
                          ),
                        )
                      : Text('Code expired',
                          style: authF(size: 14, color: kAuthInkSoft, weight: FontWeight.w500)),
                ),
                const SizedBox(height: 22),
                AuthCtaButton(
                  label: 'Verify Code',
                  onPressed: _verifying ? null : _verify,
                  isLoading: _verifying,
                ),
                const SizedBox(height: 14),
                Center(
                  child: GestureDetector(
                    onTap: (_resending || _countdown > 0) ? null : _resend,
                    child: RichText(
                      text: TextSpan(
                        style: authF(size: 14, color: kAuthInkSoft),
                        children: [
                          const TextSpan(text: "Didn't receive the code? "),
                          TextSpan(
                            text: _resending ? 'Sending...' : 'Resend Code',
                            style: authF(
                              size: 14,
                              color: _countdown > 0 ? kAuthInkSoft : kAuthAccent,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kAuthAccentSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.shield_outlined, size: 18, color: kAuthAccent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Your security is our priority',
                                style: authF(size: 14, weight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text("We'll never share your code\nor use it for anything else.",
                                style: authF(size: 13, color: kAuthInkSoft, height: 1.45)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
