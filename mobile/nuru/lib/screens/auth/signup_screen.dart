import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_logo.dart';
import '../../core/widgets/nuru_loader.dart';
import '../../core/widgets/country_phone_input.dart';
import '../../core/widgets/otp_input.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/auth_skyline.dart';
import '../../providers/auth_provider.dart';
import '../../core/services/otp_service.dart';
import '../onboarding/interests_onboarding_screen.dart';
import 'widgets/auth_text_field.dart';

// ─── Reference palette (match uploaded mockup) ───
const Color _kAccent = AppColors.primary;          // brand orange
const Color _kAccentSoft = Color(0xFFFFF3EC);      // soft cream/peach
const Color _kAccentSofter = Color(0xFFFFF9F5);
const Color _kInk = Color(0xFF111827);
const Color _kInkSoft = Color(0xFF6B7280);
const Color _kBg = Color(0xFFFDFBF7);              // warm off-white
const Color _kCardBorder = Color(0xFFEFE7DD);
const Color _kStepInactive = Color(0xFFE5E7EB);

TextStyle _f({
  required double size,
  FontWeight weight = FontWeight.w500,
  Color color = _kInk,
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

final _pwRules = [
  _R('At least 8 characters', (p) => p.length >= 8),
  _R('One uppercase letter', (p) => RegExp(r'[A-Z]').hasMatch(p)),
  _R('One lowercase letter', (p) => RegExp(r'[a-z]').hasMatch(p)),
  _R('One number', (p) => RegExp(r'\d').hasMatch(p)),
  _R(
    'One special character',
    (p) => RegExp(r'[!@#\$%\^&\*\(\),\.?":{}|<>_\-\+=\[\]\\\/~`]').hasMatch(p),
  ),
];

class _R {
  final String label;
  final bool Function(String) test;
  _R(this.label, this.test);
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  double _step = 1;
  bool _submitting = false;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _obscurePw = true;
  bool _obscureConfirm = true;

  bool _firstNameValid = false;
  bool _lastNameValid = false;
  String? _firstNameError;
  String? _lastNameError;

  String _usernameStatus = 'idle';
  List<String> _usernameSuggestions = [];
  // Proactive suggestions shown on the username step (Gmail-style)
  List<String> _proactiveSuggestions = [];
  bool _suggestionsLoading = false;
  Timer? _usernameTimer;

  String? _userId;
  String? _otpChannel;
  bool _resendLoading = false;
  String _fullPhone = '';

  // Resend countdown
  int _resendSeconds = 0;
  Timer? _resendTimer;

  final _otpCtrls = List.generate(6, (_) => TextEditingController());
  final _otpNodes = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _usernameCtrl.addListener(() => _checkUsername(_usernameCtrl.text));
    _passwordCtrl.addListener(() => setState(() {}));
    _confirmPwCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPwCtrl.dispose();
    _phoneCtrl.dispose();
    _usernameTimer?.cancel();
    _resendTimer?.cancel();
    for (final c in _otpCtrls) c.dispose();
    for (final n in _otpNodes) n.dispose();
    super.dispose();
  }

  AuthProvider get _auth => context.read<AuthProvider>();
  String get _otpValue => _otpCtrls.map((c) => c.text).join();
  bool get _allPwPassed => _pwRules.every((r) => r.test(_passwordCtrl.text));

  // ───────────────────────── LOGIC (UNCHANGED) ─────────────────────────

  Future<void> _validateName(bool isFirst) async {
    final name = isFirst ? _firstNameCtrl.text.trim() : _lastNameCtrl.text.trim();
    if (name.length < 2) return;
    try {
      final res = await _auth.validateName(name);
      if (!mounted) return;
      final data = res['data'];
      if (data is Map && data['valid'] == false) {
        setState(() {
          if (isFirst) { _firstNameError = data['reason'] ?? 'Use your real name'; _firstNameValid = false; }
          else { _lastNameError = data['reason'] ?? 'Use your real name'; _lastNameValid = false; }
        });
      } else {
        setState(() {
          if (isFirst) { _firstNameError = null; _firstNameValid = true; }
          else { _lastNameError = null; _lastNameValid = true; }
        });
      }
    } catch (_) {
      setState(() {
        if (isFirst) { _firstNameError = null; _firstNameValid = true; }
        else { _lastNameError = null; _lastNameValid = true; }
      });
    }
  }

  void _checkUsername(String val) {
    _usernameTimer?.cancel();
    if (val.trim().length < 3) {
      setState(() { _usernameStatus = 'idle'; _usernameSuggestions = []; });
      return;
    }
    setState(() => _usernameStatus = 'checking');
    _usernameTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final res = await _auth.checkUsername(val.trim(), firstName: _firstNameCtrl.text.trim(), lastName: _lastNameCtrl.text.trim());
        if (!mounted) return;
        final data = res['data'];
        if (data is Map) {
          if (data['available'] == true) {
            setState(() { _usernameStatus = 'available'; _usernameSuggestions = []; });
          } else {
            setState(() {
              _usernameStatus = 'taken';
              _usernameSuggestions = data['suggestions'] is List ? (data['suggestions'] as List).cast<String>() : [];
            });
          }
        }
      } catch (_) {
        if (mounted) setState(() => _usernameStatus = 'idle');
      }
    });
  }

  Future<void> _fetchProactiveSuggestions() async {
    final fn = _firstNameCtrl.text.trim();
    final ln = _lastNameCtrl.text.trim();
    if (fn.isEmpty && ln.isEmpty) return;
    setState(() => _suggestionsLoading = true);
    try {
      final res = await _auth.getUsernameSuggestions(firstName: fn, lastName: ln);
      if (!mounted) return;
      final data = res['data'];
      if (data is Map && data['suggestions'] is List) {
        setState(() => _proactiveSuggestions = (data['suggestions'] as List).cast<String>());
      }
    } catch (_) {/* silent */} finally {
      if (mounted) setState(() => _suggestionsLoading = false);
    }
  }

  Future<void> _handleNext() async {
    if (_step == 1) {
      if (_firstNameCtrl.text.trim().isEmpty || _lastNameCtrl.text.trim().isEmpty) {
        AppSnackbar.error(context, 'Please enter your first and last name');
        return;
      }
      if (_firstNameError != null || _lastNameError != null) {
        AppSnackbar.error(context, 'Please fix the name errors');
        return;
      }
      setState(() => _step = 2);
      // Fire-and-forget: fetch proactive Gmail-style suggestions
      _fetchProactiveSuggestions();
    } else if (_step == 2) {
      if (_usernameCtrl.text.trim().length < 3) {
        AppSnackbar.error(context, 'Username must be at least 3 characters');
        return;
      }
      if (_usernameStatus == 'taken') {
        AppSnackbar.error(context, 'Username is taken');
        return;
      }
      setState(() => _step = 3);
    } else if (_step == 3) {
      if (!_allPwPassed) {
        AppSnackbar.error(context, 'Meet all password requirements');
        return;
      }
      if (_passwordCtrl.text != _confirmPwCtrl.text) {
        AppSnackbar.error(context, 'Passwords don\'t match');
        return;
      }
      setState(() => _step = 4);
    } else if (_step == 4) {
      final cleaned = _fullPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (cleaned.length < 7 || cleaned.length > 15) {
        AppSnackbar.error(context, 'Enter a valid phone number');
        return;
      }
      setState(() => _submitting = true);
      final res = await _auth.signUp(
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        phone: cleaned,
        password: _passwordCtrl.text,
      );
      setState(() => _submitting = false);
      if (res['success'] != true) {
        if (mounted) AppSnackbar.error(context, res['message'] ?? 'Signup failed');
        return;
      }
      _userId = res['data']?['id']?.toString();
      if (_userId == null) {
        if (mounted) AppSnackbar.error(context, 'No user ID returned');
        return;
      }
      if (mounted) AppSnackbar.success(context, 'Account created! Verify your phone.');
      await _resendOtp();
      setState(() => _step = 4.5);
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 45);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_resendSeconds <= 1) { t.cancel(); setState(() => _resendSeconds = 0); }
      else { setState(() => _resendSeconds--); }
    });
  }

  Future<void> _resendOtp() async {
    if (_userId == null) return;
    setState(() => _resendLoading = true);
    final cleaned = _fullPhone.replaceAll(RegExp(r'[^\d]'), '');
    final otpRes = await OtpService.requestOtp(phone: cleaned, userId: _userId, purpose: 'phone_verification');
    if (mounted) {
      final channels = (otpRes['channels'] as List?)?.cast<String>() ?? [];
      setState(() {
        if (channels.contains('whatsapp') && channels.contains('sms')) _otpChannel = 'both';
        else if (channels.contains('whatsapp')) _otpChannel = 'whatsapp';
        else _otpChannel = 'sms';
        _resendLoading = false;
      });
      if (otpRes['success'] == true) {
        AppSnackbar.success(context, otpRes['message'] ?? 'Verification code sent');
        _startResendCountdown();
      } else {
        final backendRes = await _auth.requestOtp(userId: _userId!, verificationType: 'phone');
        if (backendRes['success'] == true) {
          setState(() => _otpChannel = 'sms');
          AppSnackbar.success(context, backendRes['message'] ?? 'Code sent via SMS');
          _startResendCountdown();
        } else {
          AppSnackbar.error(context, 'Failed to send verification code');
        }
      }
    }
  }

  Future<void> _verify() async {
    final otp = _otpValue;
    if (otp.length < 6) {
      AppSnackbar.error(context, 'Enter the 6-digit code');
      return;
    }
    setState(() => _submitting = true);
    final cleaned = _fullPhone.replaceAll(RegExp(r'[^\d]'), '');
    final edgeRes = await OtpService.verifyOtp(phone: cleaned, code: otp, purpose: 'phone_verification');
    if (edgeRes['success'] == true) {
      try { await _auth.verifyOtp(userId: _userId!, verificationType: 'phone', otpCode: otp); } catch (_) {}
      await _auth.autoSignInAfterVerification(phone: cleaned, password: _passwordCtrl.text);
      setState(() { _submitting = false; _step = 5; });
      return;
    }
    final backendRes = await _auth.verifyOtp(userId: _userId!, verificationType: 'phone', otpCode: otp);
    if (backendRes['success'] == true) {
      await _auth.autoSignInAfterVerification(phone: cleaned, password: _passwordCtrl.text);
      setState(() { _submitting = false; _step = 5; });
      return;
    }
    setState(() => _submitting = false);
    if (mounted) AppSnackbar.error(context, backendRes['message'] ?? edgeRes['message'] ?? 'Verification failed');
  }

  void _goBack() {
    if (_step == 4.5) setState(() => _step = 4);
    else if (_step > 1) setState(() => _step = _step - 1);
    else Navigator.pop(context);
  }

  // ───────────────────────── UI ─────────────────────────

  /// Map internal step → display step (1..3 visible in stepper).
  int get _displayStep {
    if (_step <= 1) return 1;
    if (_step <= 2) return 2;
    return 3; // password (3) and phone (4) share step 3 visually
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isOtp = _step == 4.5;
    final isWelcome = _step == 5;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _kBg,
      ),
      child: Scaffold(
        backgroundColor: _kBg,
        // Keep decorative footer pinned - don't push it up with the keyboard
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ── Decorations OUTSIDE SafeArea so they reach the true edges ──
            if (_step == 1)
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: AuthSkyline(
                  color: _kAccent,
                  height: 200,
                  opacity: 0.22,
                ),
              ),
            if (_step == 1)
              const Positioned(
                top: 0, right: 0,
                child: AuthCornerBlob(
                  color: _kAccent,
                  size: 240,
                  opacity: 0.22,
                  alignment: Alignment.topRight,
                ),
              ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  final hp = box.maxWidth < 360 ? 20.0 : 24.0;

                  if (isWelcome) return _welcomeStep();

                  return Column(
                    children: [
                      // ── Top header: back / stepper / counter ──
                      Padding(
                        padding: EdgeInsets.fromLTRB(hp, 6, hp, 6),
                        child: _TopBar(
                          step: _displayStep,
                          total: 3,
                          onBack: _goBack,
                          showCounter: !isOtp,
                        ),
                      ),

                      // ── Body ──
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            hp, 8, hp,
                            (bottomInset > 0 ? 24 : 28) + (_step == 1 ? 80 : 0),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.04, 0),
                                  end: Offset.zero,
                                ).animate(anim),
                                child: child,
                              ),
                            ),
                            child: _buildStep(),
                          ),
                        ),
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

  Widget _buildStep() {
    switch (_step) {
      case 1: return _nameStep();
      case 2: return _usernameStep();
      case 3: return _passwordStep();
      case 4: return _phoneStep();
      case 4.5: return _otpStep();
      default: return _nameStep();
    }
  }

  // ─── STEP 1 - Name ───
  Widget _nameStep() {
    return Column(
      key: const ValueKey('s1'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        Text("Let's get to know you",
            style: _f(size: 24, weight: FontWeight.w800, letterSpacing: -0.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Start by entering your name.',
            style: _f(size: 14, color: _kInkSoft, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 26),

        _Card(
          child: Column(
            children: [
              AuthTextField(
                controller: _firstNameCtrl,
                label: 'First Name',
                hintText: 'Enter your first name',
                prefixSvg: 'assets/icons/user-rounded-icon.svg',
                autofocus: true,
                onChanged: (_) => _validateName(true),
                showSuccessTick: _firstNameValid && _firstNameError == null,
              ),
              if (_firstNameError != null) _errorLabel(_firstNameError!),
              const SizedBox(height: 16),
              AuthTextField(
                controller: _lastNameCtrl,
                label: 'Last Name',
                hintText: 'Enter your last name',
                prefixSvg: 'assets/icons/user-rounded-icon.svg',
                onChanged: (_) => _validateName(false),
                showSuccessTick: _lastNameValid && _lastNameError == null,
              ),
              if (_lastNameError != null) _errorLabel(_lastNameError!),
              const SizedBox(height: 16),
              _InfoCard(
                icon: Icons.shield_outlined,
                title: 'Your information is safe with us',
                body: 'We protect your data and will never share it with anyone.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _CtaButton(label: 'Continue', onPressed: _handleNext),
        const SizedBox(height: 14),
        _SignInLink(onTap: () => Navigator.pop(context)),
      ],
    );
  }

  // ─── STEP 2 - Username ───
  Widget _usernameStep() {
    return Column(
      key: const ValueKey('s2'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 4),
        FadeInDown(
          duration: const Duration(milliseconds: 400),
          child: _IllustrationOrb(
            child: Icon(Icons.badge_outlined, size: 56, color: _kAccent),
            badge: const Icon(Icons.check_circle, color: _kAccent, size: 22),
          ),
        ),
        const SizedBox(height: 22),
        Text('Choose your username',
            style: _f(size: 22, weight: FontWeight.w800, letterSpacing: -0.4),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Pick a unique username. You can\nchange it later.',
            style: _f(size: 14, color: _kInkSoft, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 26),

        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthTextField(
                controller: _usernameCtrl,
                label: 'Username',
                hintText: 'Enter your username',
                prefixIcon: Icons.alternate_email_rounded,
                autofocus: true,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
                ],
              ),
              // Proactive Gmail-style suggestions (shown while input is empty)
              if (_usernameCtrl.text.trim().isEmpty) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _suggestionsLoading ? 'Finding usernames for you…' : 'Suggested for you',
                    style: _f(size: 12, color: _kInkSoft, weight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                if (_suggestionsLoading)
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: List.generate(5, (_) => Container(
                      height: 28, width: 96,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1EDE6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    )),
                  )
                else if (_proactiveSuggestions.isNotEmpty)
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _proactiveSuggestions.map((s) => GestureDetector(
                      onTap: () { _usernameCtrl.text = s; _checkUsername(s); setState((){}); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _kAccentSoft,
                          border: Border.all(color: _kAccent.withOpacity(0.35)),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('@$s', style: _f(size: 12, weight: FontWeight.w700, color: _kAccent)),
                      ),
                    )).toList(),
                  ),
              ],
              if (_usernameStatus != 'idle') ...[
                const SizedBox(height: 14),
                _UsernameStatusBanner(
                  status: _usernameStatus,
                  suggestions: _usernameSuggestions,
                  onPick: (s) { _usernameCtrl.text = s; _checkUsername(s); },
                ),
              ],
              const SizedBox(height: 14),
              _InfoCard(
                icon: Icons.lightbulb_outline_rounded,
                title: 'Tips',
                body: 'Usernames can contain letters, numbers, dots and underscores.',
                bg: const Color(0xFFF4F4F6),
                iconColor: _kInkSoft,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _CtaButton(label: 'Continue', onPressed: _handleNext),
        const SizedBox(height: 14),
        _SignInLink(onTap: () => Navigator.pop(context)),
      ],
    );
  }

  // ─── STEP 3 - Password ───
  Widget _passwordStep() {
    return Column(
      key: const ValueKey('s3'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 4),
        FadeInDown(
          duration: const Duration(milliseconds: 400),
          child: const _IllustrationOrb(
            child: Icon(Icons.lock_rounded, size: 54, color: _kAccent),
          ),
        ),
        const SizedBox(height: 22),
        Text('Create a password',
            style: _f(size: 22, weight: FontWeight.w800, letterSpacing: -0.4),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Create a strong password to keep\nyour account secure.',
            style: _f(size: 14, color: _kInkSoft, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 26),

        _Card(
          child: Column(
            children: [
              AuthTextField(
                controller: _passwordCtrl,
                label: 'Password',
                hintText: 'Enter your password',
                prefixSvg: 'assets/icons/lock-icon.svg',
                obscureText: _obscurePw,
                autofocus: true,
                suffixIcon: IconButton(
                  splashRadius: 18,
                  icon: SvgPicture.asset(
                    _obscurePw ? 'assets/icons/eye-off-icon.svg' : 'assets/icons/eye-on-icon.svg',
                    width: 20, height: 20,
                    colorFilter: const ColorFilter.mode(_kInkSoft, BlendMode.srcIn),
                  ),
                  onPressed: () => setState(() => _obscurePw = !_obscurePw),
                ),
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _confirmPwCtrl,
                label: 'Confirm Password',
                hintText: 'Confirm your password',
                prefixSvg: 'assets/icons/lock-icon.svg',
                obscureText: _obscureConfirm,
                suffixIcon: IconButton(
                  splashRadius: 18,
                  icon: SvgPicture.asset(
                    _obscureConfirm ? 'assets/icons/eye-off-icon.svg' : 'assets/icons/eye-on-icon.svg',
                    width: 20, height: 20,
                    colorFilter: const ColorFilter.mode(_kInkSoft, BlendMode.srcIn),
                  ),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              if (_confirmPwCtrl.text.isNotEmpty && _confirmPwCtrl.text != _passwordCtrl.text)
                _errorLabel("Passwords don't match"),
              const SizedBox(height: 14),
              _PasswordRulesCard(password: _passwordCtrl.text),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _CtaButton(label: 'Create Account', onPressed: _handleNext),
        const SizedBox(height: 14),
        _TermsFooter(),
      ],
    );
  }

  // ─── STEP 4 - Phone (kept, styled to match) ───
  Widget _phoneStep() {
    return Column(
      key: const ValueKey('s4'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 4),
        FadeInDown(
          duration: const Duration(milliseconds: 400),
          child: _IllustrationOrb(
            child: SvgPicture.asset(
              'assets/icons/mobile-icon.svg',
              width: 54, height: 54,
              colorFilter: const ColorFilter.mode(_kAccent, BlendMode.srcIn),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text('Verify your phone',
            style: _f(size: 22, weight: FontWeight.w800, letterSpacing: -0.4),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text("We'll send a 6-digit code to confirm\nit's really you.",
            style: _f(size: 14, color: _kInkSoft, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 26),

        _Card(
          child: Column(
            children: [
              CountryPhoneInput(
                controller: _phoneCtrl,
                initialCountryCode: 'TZ',
                onFullNumberChanged: (full) => _fullPhone = full,
              ),
              const SizedBox(height: 14),
              _InfoCard(
                icon: Icons.shield_outlined,
                title: 'Standard rates may apply',
                body: 'Your number is only used for verification and account recovery.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _CtaButton(
          label: _submitting ? 'Creating account...' : 'Send verification code',
          onPressed: _submitting ? null : _handleNext,
          isLoading: _submitting,
        ),
        const SizedBox(height: 14),
        _SignInLink(onTap: () => Navigator.pop(context)),
      ],
    );
  }

  // ─── OTP step ───
  Widget _otpStep() {
    final mm = (_resendSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_resendSeconds % 60).toString().padLeft(2, '0');
    return Column(
      key: const ValueKey('s4_5'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 4),
        FadeInDown(
          duration: const Duration(milliseconds: 400),
          child: const _OtpShieldIllustration(),
        ),
        const SizedBox(height: 22),
        Text("Verify it's you",
            style: _f(size: 22, weight: FontWeight.w800, letterSpacing: -0.4),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text("We've sent a 6-digit verification code to",
            style: _f(size: 14, color: _kInkSoft, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(_maskPhoneDisplay(_fullPhone),
            style: _f(size: 18, weight: FontWeight.w800, letterSpacing: -0.2),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),

        if (_otpChannel != null) ...[
          _OtpChannelChip(channel: _otpChannel!),
          const SizedBox(height: 16),
        ],

        OtpInput(
          controllers: _otpCtrls,
          focusNodes: _otpNodes,
          onCompleted: (_) => _verify(),
        ),
        const SizedBox(height: 18),
        Center(
          child: _resendSeconds > 0
              ? RichText(
                  text: TextSpan(
                    style: _f(size: 14, color: _kInkSoft),
                    children: [
                      const TextSpan(text: 'Code expires in '),
                      TextSpan(
                        text: '$mm:$ss',
                        style: _f(size: 14, color: _kAccent, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                )
              : Text('Code expired',
                  style: _f(size: 14, color: _kInkSoft, weight: FontWeight.w500)),
        ),
        const SizedBox(height: 22),
        _CtaButton(
          label: 'Verify Code',
          onPressed: _submitting ? null : _verify,
          isLoading: _submitting,
        ),
        const SizedBox(height: 14),
        Center(
          child: GestureDetector(
            onTap: (_resendLoading || _resendSeconds > 0) ? null : _resendOtp,
            child: RichText(
              text: TextSpan(
                style: _f(size: 14, color: _kInkSoft),
                children: [
                  const TextSpan(text: "Didn't receive the code? "),
                  TextSpan(
                    text: _resendLoading ? 'Sending...' : 'Resend Code',
                    style: _f(
                      size: 14,
                      color: _resendSeconds > 0 ? _kInkSoft : _kAccent,
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
            color: _kAccentSoft,
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
                child: const Icon(Icons.shield_outlined, size: 18, color: _kAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your security is our priority',
                        style: _f(size: 14, weight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text("We'll never share your code\nor use it for anything else.",
                        style: _f(size: 13, color: _kInkSoft, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Welcome ───
  Widget _welcomeStep() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _step == 5) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const InterestsOnboardingScreen()),
          (_) => false,
        );
      }
    });

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          ZoomIn(
            duration: const Duration(milliseconds: 500),
            child: Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                color: _kAccentSoft,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.check_circle_rounded, size: 56, color: _kAccent),
            ),
          ),
          const SizedBox(height: 28),
          Text('Welcome, ${_firstNameCtrl.text.trim()}!',
              style: _f(size: 26, weight: FontWeight.w800, letterSpacing: -0.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text('Your account is verified.\nTaking you to your workspace…',
              style: _f(size: 14, color: _kInkSoft, height: 1.6),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),
          const SizedBox(width: 80, child: Center(child: NuruLoader(size: 28))),
        ],
      ),
      ),
    );
  }

  // ─── Small helpers ───
  Widget _errorLabel(String msg) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.error),
      const SizedBox(width: 6),
      Expanded(child: Text(msg, style: _f(size: 12, color: AppColors.error, weight: FontWeight.w500))),
    ]),
  );

  Widget _successLabel(String msg) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Row(children: [
      const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
      const SizedBox(width: 6),
      Text(msg, style: _f(size: 12, color: AppColors.success, weight: FontWeight.w600)),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════════
// REUSABLE COMPONENTS
// ════════════════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  final int step;
  final int total;
  final VoidCallback onBack;
  final bool showCounter;
  const _TopBar({required this.step, required this.total, required this.onBack, this.showCounter = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _RoundIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
        const SizedBox(width: 12),
        Expanded(child: _Stepper(current: step, total: total)),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          child: showCounter
              ? Text('$step/$total',
                  textAlign: TextAlign.right,
                  style: _f(size: 13, weight: FontWeight.w700, color: _kInkSoft))
              : const SizedBox(),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          child: Icon(icon, size: 22, color: _kInk),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int current;
  final int total;
  const _Stepper({required this.current, required this.total});

  static const _labels = ['Profile', 'Account', 'Verify'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(total, (i) {
          final n = i + 1;
          final isDone = n < current;
          final isActive = n == current;
          final label = i < _labels.length ? _labels[i] : '';

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == total - 1 ? 0 : 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDone || isActive ? _kAccent : _kStepInactive,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: _kAccent.withOpacity(0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Label
                  Row(
                    children: [
                      if (isDone)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.check_circle_rounded,
                              size: 12, color: _kAccent),
                        ),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _f(
                            size: 11,
                            weight: isActive || isDone
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isActive
                                ? _kAccent
                                : isDone
                                    ? _kInk
                                    : _kInkSoft,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kCardBorder, width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color bg;
  final Color iconColor;
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    this.bg = _kAccentSofter,
    this.iconColor = _kAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _f(size: 13.5, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(body, style: _f(size: 12.5, color: _kInkSoft, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  const _CtaButton({required this.label, required this.onPressed, this.isLoading = false});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kAccent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _kAccent.withOpacity(0.55),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ).copyWith(
          overlayColor: WidgetStateProperty.all(Colors.white.withOpacity(0.08)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: _f(size: 16, weight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(width: 10),
                  const Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.white),
                ],
              ),
      ),
    );
  }
}

class _SignInLink extends StatelessWidget {
  final VoidCallback onTap;
  const _SignInLink({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Already have an account? ', style: _f(size: 14, color: _kInkSoft)),
        GestureDetector(
          onTap: onTap,
          child: Text('Sign in', style: _f(size: 14, color: _kAccent, weight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _TermsFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: _f(size: 12.5, color: _kInkSoft, height: 1.5),
          children: [
            const TextSpan(text: 'By creating an account, you agree to our\n'),
            TextSpan(text: 'Terms of Service', style: _f(size: 12.5, color: _kAccent, weight: FontWeight.w700)),
            const TextSpan(text: ' and '),
            TextSpan(text: 'Privacy Policy', style: _f(size: 12.5, color: _kAccent, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ─── Username status banner (success/checking/taken) ───
class _UsernameStatusBanner extends StatelessWidget {
  final String status;
  final List<String> suggestions;
  final ValueChanged<String> onPick;
  const _UsernameStatusBanner({required this.status, required this.suggestions, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (status == 'checking') {
      return _Banner(
        bg: const Color(0xFFF4F4F6),
        icon: const SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: _kInkSoft),
        ),
        text: 'Checking availability…',
        textColor: _kInkSoft,
      );
    }
    if (status == 'available') {
      return _Banner(
        bg: const Color(0xFFE9F8EC),
        icon: const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF2BA84A)),
        text: 'Great! This username is available.',
        textColor: const Color(0xFF1B7A36),
      );
    }
    // taken
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Banner(
          bg: const Color(0xFFFDECEC),
          icon: const Icon(Icons.cancel_rounded, size: 18, color: AppColors.error),
          text: 'This username is taken.',
          textColor: AppColors.error,
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Try one of these:', style: _f(size: 12, color: _kInkSoft)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions.take(4).map((s) => GestureDetector(
              onTap: () => onPick(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _kAccentSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kAccent.withOpacity(0.25)),
                ),
                child: Text(s, style: _f(size: 13, color: _kAccent, weight: FontWeight.w700)),
              ),
            )).toList(),
          ),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final Color bg;
  final Widget icon;
  final String text;
  final Color textColor;
  const _Banner({required this.bg, required this.icon, required this.text, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          SizedBox(width: 18, height: 18, child: Center(child: icon)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: _f(size: 13, color: textColor, weight: FontWeight.w600))),
        ],
      ),
    );
  }
}

// ─── Password rules card ───
class _PasswordRulesCard extends StatelessWidget {
  final String password;
  const _PasswordRulesCard({required this.password});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kAccentSofter,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: _kAccent.withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.shield_outlined, size: 14, color: _kAccent),
            ),
            const SizedBox(width: 10),
            Text('Password must include:', style: _f(size: 13.5, weight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          ..._pwRules.map((r) {
            final passed = r.test(password);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: passed ? _kAccent : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: passed ? _kAccent : _kStepInactive, width: 1.5),
                    ),
                    child: passed
                        ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    r.label,
                    style: _f(
                      size: 13,
                      color: passed ? _kInk : _kInkSoft,
                      weight: passed ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── OTP channel chip ───
class _OtpChannelChip extends StatelessWidget {
  final String channel;
  const _OtpChannelChip({required this.channel});
  @override
  Widget build(BuildContext context) {
    final isWa = channel == 'whatsapp';
    final isBoth = channel == 'both';
    final color = isBoth ? _kAccent : isWa ? const Color(0xFF25D366) : AppColors.info;
    final icon = isBoth ? Icons.verified_rounded : isWa ? Icons.message_rounded : Icons.sms_outlined;
    final label = isBoth ? 'Sent via WhatsApp & SMS' : isWa ? 'Sent via WhatsApp' : 'Sent via SMS';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: _f(size: 13, color: color, weight: FontWeight.w700))),
        ],
      ),
    );
  }
}

// ─── Nuru wordmark with sun glyph (matches reference) ───
class _NuruWordmark extends StatelessWidget {
  final double size;
  const _NuruWordmark({this.size = 64});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: Image.asset(
        'assets/images/nuru-logo-square.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _kAccent,
            borderRadius: BorderRadius.circular(size * 0.25),
          ),
          alignment: Alignment.center,
          child: Text(
            'N',
            style: GoogleFonts.inter(
              fontSize: size * 0.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _SunPainter extends CustomPainter {
  final Color color;
  _SunPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.22;
    final fill = Paint()..color = color;
    canvas.drawCircle(c, r, fill);
    final ray = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round;
    const rays = 8;
    final inner = r * 1.45;
    final outer = r * 2.05;
    for (int i = 0; i < rays; i++) {
      final a = (i * 2 * math.pi / rays) - math.pi / 2;
      final p1 = Offset(c.dx + math.cos(a) * inner, c.dy + math.sin(a) * inner);
      final p2 = Offset(c.dx + math.cos(a) * outer, c.dy + math.sin(a) * outer);
      canvas.drawLine(p1, p2, ray);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Circular illustration "orb" with optional badge ───
class _IllustrationOrb extends StatelessWidget {
  final Widget child;
  final Widget? badge;
  const _IllustrationOrb({required this.child, this.badge});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180, height: 150,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Decorative confetti dots
          Positioned(left: 4, top: 18, child: _confetti(_kAccent, 8)),
          Positioned(right: 8, top: 28, child: _confetti(const Color(0xFF8B5CF6), 6)),
          Positioned(left: 22, bottom: 14, child: _confetti(_kAccent, 5)),
          Positioned(right: 18, bottom: 8, child: _confetti(const Color(0xFF22C55E), 7)),
          Positioned(left: -2, top: 50, child: _triangle(const Color(0xFF22C55E))),
          Positioned(right: 0, top: 42, child: _triangle(const Color(0xFF8B5CF6))),

          // Soft circle background
          Container(
            width: 130, height: 130,
            decoration: const BoxDecoration(color: _kAccentSoft, shape: BoxShape.circle),
          ),
          // Inner content
          child,
          if (badge != null)
            Positioned(
              right: 30, bottom: 22,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: badge!,
              ),
            ),
        ],
      ),
    );
  }

  Widget _confetti(Color c, double s) =>
      Container(width: s, height: s, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _triangle(Color c) => SizedBox(
    width: 10, height: 10,
    child: CustomPaint(painter: _TrianglePainter(color: c)),
  );
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Decorative city skyline (line art) ───
class _SkylinePainter extends CustomPainter {
  final Color color;
  _SkylinePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final h = size.height;
    final w = size.width;
    final base = h * 0.85;

    // Ground line
    canvas.drawLine(Offset(0, base), Offset(w, base), paint);

    // Palm tree (left)
    _palm(canvas, paint, Offset(w * 0.08, base), h * 0.55);

    // Buildings cluster
    final p = Path();
    double x = w * 0.18;
    final segs = [
      [0.40, 0.10], [0.55, 0.18], [0.45, 0.06], [0.65, 0.14],
      [0.35, 0.10], [0.50, 0.08], [0.60, 0.16], [0.42, 0.12],
    ];
    for (final s in segs) {
      final bh = h * s[0];
      final bw = w * s[1];
      p.moveTo(x, base);
      p.lineTo(x, base - bh);
      p.lineTo(x + bw, base - bh);
      p.lineTo(x + bw, base);
      x += bw;
      if (x > w * 0.78) break;
    }
    canvas.drawPath(p, paint);

    // Eiffel-style tower (center-right)
    _tower(canvas, paint, Offset(w * 0.78, base), h * 0.65);

    // Palm tree (right)
    _palm(canvas, paint, Offset(w * 0.93, base), h * 0.5);
  }

  void _palm(Canvas canvas, Paint paint, Offset baseP, double height) {
    canvas.drawLine(baseP, Offset(baseP.dx, baseP.dy - height), paint);
    final top = Offset(baseP.dx, baseP.dy - height);
    for (int i = 0; i < 5; i++) {
      final a = -math.pi / 2 + (i - 2) * 0.4;
      final end = Offset(top.dx + math.cos(a) * 14, top.dy + math.sin(a) * 14);
      canvas.drawLine(top, end, paint);
    }
  }

  void _tower(Canvas canvas, Paint paint, Offset baseP, double height) {
    final p = Path();
    final w = height * 0.28;
    p.moveTo(baseP.dx - w / 2, baseP.dy);
    p.lineTo(baseP.dx, baseP.dy - height);
    p.lineTo(baseP.dx + w / 2, baseP.dy);
    p.moveTo(baseP.dx - w * 0.36, baseP.dy - height * 0.35);
    p.lineTo(baseP.dx + w * 0.36, baseP.dy - height * 0.35);
    p.moveTo(baseP.dx - w * 0.20, baseP.dy - height * 0.65);
    p.lineTo(baseP.dx + w * 0.20, baseP.dy - height * 0.65);
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Helpers ───
String _maskPhoneDisplay(String phone) {
  final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
  if (cleaned.length < 6) return phone;
  return '${cleaned.substring(0, 3)}****${cleaned.substring(cleaned.length - 3)}';
}

// ─── Shield + paper plane illustration for OTP verification ───
class _OtpShieldIllustration extends StatelessWidget {
  const _OtpShieldIllustration();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 140,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // soft cloud blobs
          Positioned(
            left: 6,
            bottom: 18,
            child: _cloud(opacity: 0.22, scale: 1.0),
          ),
          Positioned(
            right: 12,
            bottom: 10,
            child: _cloud(opacity: 0.45, scale: 0.85),
          ),
          // outer halo
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: _kAccent.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
          ),
          // shield
          CustomPaint(
            size: const Size(96, 110),
            painter: _ShieldPainter(),
          ),
          // lock inside shield
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 30,
              height: 26,
              decoration: BoxDecoration(
                color: _kAccent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Icon(Icons.circle, size: 6, color: Colors.white),
              ),
            ),
          ),
          // dotted arc + paper plane
          Positioned(
            right: -2,
            top: 6,
            child: CustomPaint(
              size: const Size(80, 60),
              painter: _DottedArcPainter(),
            ),
          ),
          const Positioned(
            right: -6,
            top: -4,
            child: Icon(Icons.send_rounded, color: _kAccent, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _cloud({required double opacity, required double scale}) {
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: CustomPaint(
          size: const Size(60, 22),
          painter: _CloudPainter(),
        ),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.18)
      ..lineTo(w, h * 0.55)
      ..quadraticBezierTo(w, h * 0.92, w * 0.5, h)
      ..quadraticBezierTo(0, h * 0.92, 0, h * 0.55)
      ..lineTo(0, h * 0.18)
      ..close();

    final fill = Paint()..color = _kAccent.withOpacity(0.18);
    canvas.drawPath(path, fill);

    final stroke = Paint()
      ..color = _kAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DottedArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kAccent.withOpacity(0.55)
      ..style = PaintingStyle.fill;
    final path = Path();
    for (double t = 0; t <= 1; t += 0.08) {
      final x = size.width * t;
      final y = size.height * (1 - math.sin(t * math.pi)) * 0.9;
      path.addOval(Rect.fromCircle(center: Offset(x, y), radius: 1.6));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CloudPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _kAccent.withOpacity(0.25);
    final h = size.height;
    final w = size.width;
    canvas.drawCircle(Offset(w * 0.25, h * 0.6), h * 0.55, paint);
    canvas.drawCircle(Offset(w * 0.5, h * 0.45), h * 0.7, paint);
    canvas.drawCircle(Offset(w * 0.75, h * 0.6), h * 0.55, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.15, h * 0.55, w * 0.7, h * 0.45),
        Radius.circular(h * 0.3),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
