/// /set-password/:token landing page - premium Nuru branding.
///
/// Flow:
///   1. GET  /api/v1/auth/account-setup/validate?token=...
///   2. POST /api/v1/auth/account-setup/set-password { token, password, password_confirmation }
///   3. On success: persist returned tokens, route to home.
///
/// Public - no existing session required to render. Distinguishes valid /
/// expired / used / invalid token states with clear messaging. Shows live
/// password rule checklist as the user types.
import 'package:flutter/material.dart';
import '../../core/services/api_base.dart';
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_logo.dart';
import 'login_screen.dart';

class SetPasswordScreen extends StatefulWidget {
  final String token;
  const SetPasswordScreen({super.key, required this.token});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  bool _validating = true;
  bool _submitting = false;
  bool _success = false;
  String? _validationError;
  String? _validationState; // 'valid', 'expired', 'used', 'invalid'
  String? _firstName;

  final _formKey = GlobalKey<FormState>();
  final _pwd = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPwd = false;

  @override
  void initState() {
    super.initState();
    _pwd.addListener(() => setState(() {}));
    _confirm.addListener(() => setState(() {}));
    _validate();
  }

  @override
  void dispose() {
    _pwd.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    debugPrint('[SetPassword] validating token');
    setState(() {
      _validating = true;
      _validationError = null;
    });
    final res = await ApiBase.get(
      '/auth/account-setup/validate',
      auth: false,
      queryParams: {'token': widget.token},
    );
    debugPrint('[SetPassword] validate success=${res['success']}');
    if (!mounted) return;
    final data = (res['data'] is Map ? res['data'] as Map : const {});
    setState(() {
      _validating = false;
      _validationState = (data['state'] ?? (res['success'] == true ? 'valid' : 'invalid')).toString();
      _firstName = (data['first_name'] ?? '').toString();
      if (res['success'] != true) {
        _validationError = (res['message'] ?? 'This setup link is invalid.').toString();
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final res = await ApiBase.post(
      '/auth/account-setup/set-password',
      {
        'token': widget.token,
        'password': _pwd.text,
        'password_confirmation': _confirm.text,
      },
      auth: false,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (res['success'] == true && res['data'] is Map) {
      final data = res['data'] as Map;
      final access = (data['access_token'] ?? '').toString();
      final refresh = (data['refresh_token'] ?? '').toString();
      if (access.isNotEmpty) await SecureTokenStorage.setToken(access);
      if (refresh.isNotEmpty) await SecureTokenStorage.setRefreshToken(refresh);
      setState(() => _success = true);
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      if (access.isNotEmpty) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((res['message'] ?? 'Could not set password').toString()),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: _build()),
    );
  }

  Widget _build() {
    if (_validating) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          NuruLogo(size: 44),
          SizedBox(height: 18),
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary)),
          SizedBox(height: 12),
          Text('Checking your setup link…', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      );
    }

    if (_success) {
      return _SuccessView(firstName: _firstName ?? '');
    }

    if (_validationState != 'valid') {
      final isExpired = _validationState == 'expired' || _validationState == 'used';
      return _InvalidLinkView(
        title: isExpired ? 'This setup link has expired' : 'This setup link is invalid',
        message: _validationError ??
            (isExpired
                ? 'For security, setup links are single-use and time-limited. Please request a new one.'
                : 'The link may be wrong or already used. Please request a new setup link.'),
      );
    }

    final pwd = _pwd.text;
    final rules = [
      _Rule('At least 8 characters', pwd.length >= 8),
      _Rule('One uppercase letter', RegExp(r'[A-Z]').hasMatch(pwd)),
      _Rule('One lowercase letter', RegExp(r'[a-z]').hasMatch(pwd)),
      _Rule('One number', RegExp(r'[0-9]').hasMatch(pwd)),
      _Rule('One special character', RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=]').hasMatch(pwd)),
      _Rule('Passwords match', _confirm.text.isNotEmpty && _confirm.text == pwd),
    ];
    final allOk = rules.every((r) => r.ok);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 16),
          Center(child: NuruLogo(size: 52)),
          const SizedBox(height: 22),
          Text(
            _firstName?.isNotEmpty == true ? 'Welcome, $_firstName' : 'Welcome to Nuru',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a secure password to finish setting up your account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _pwd,
            obscureText: !_showPwd,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _decoration(
              label: 'New password',
              suffix: IconButton(
                icon: Icon(_showPwd ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: AppColors.textTertiary),
                onPressed: () => setState(() => _showPwd = !_showPwd),
              ),
            ),
            validator: (v) {
              if (v == null || v.length < 8) return 'At least 8 characters';
              if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Add an uppercase letter';
              if (!RegExp(r'[a-z]').hasMatch(v)) return 'Add a lowercase letter';
              if (!RegExp(r'[0-9]').hasMatch(v)) return 'Add a number';
              if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=]').hasMatch(v)) return 'Add a special character';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirm,
            obscureText: !_showPwd,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _decoration(label: 'Confirm password'),
            validator: (v) => v == _pwd.text ? null : 'Passwords do not match',
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Password must include',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              for (final r in rules)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(
                      r.ok ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 16,
                      color: r.ok ? AppColors.success : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      r.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: r.ok ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: r.ok ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: (_submitting || !allOk) ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Set password & continue',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Your password is encrypted and never shared.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary.withOpacity(0.9)),
            ),
          ),
        ]),
      ),
    );
  }

  InputDecoration _decoration({required String label, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.surface,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}

class _Rule {
  final String text;
  final bool ok;
  _Rule(this.text, this.ok);
}

class _SuccessView extends StatelessWidget {
  final String firstName;
  const _SuccessView({required this.firstName});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(28)),
            child: const Icon(Icons.check_circle, color: AppColors.success, size: 44),
          ),
          const SizedBox(height: 22),
          Text(
            firstName.isNotEmpty ? 'You are all set, $firstName' : 'You are all set',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your password is saved. Welcome to Nuru.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 22),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
        ]),
      ),
    );
  }
}

class _InvalidLinkView extends StatelessWidget {
  final String title;
  final String message;
  const _InvalidLinkView({required this.title, required this.message});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const NuruLogo(size: 44),
        const SizedBox(height: 22),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(24)),
          child: const Icon(Icons.lock_clock_outlined, color: AppColors.warning, size: 32),
        ),
        const SizedBox(height: 18),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          ),
          child: const Text('Go to sign in'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
          child: const Text('Back to home'),
        ),
      ]),
    );
  }
}
