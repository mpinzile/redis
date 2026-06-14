import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_snackbar.dart';

/// Inline form to register a Nuru user on behalf of someone who is not
/// yet on the platform. Mirrors the web `UserSearchInput` register flow
/// (committee / guest dialogs) - first name, last name, phone, optional
/// email, default password `Nuru@2026`.
///
/// On success [onRegistered] is called with the freshly created user map
/// (already shaped like a search result: id / first_name / last_name /
/// username / email / phone / avatar).
class RegisterMissingMemberForm extends StatefulWidget {
  final void Function(Map<String, dynamic> user) onRegistered;
  final VoidCallback onCancel;
  final String? registeredByName;
  final String submitLabel;

  const RegisterMissingMemberForm({
    super.key,
    required this.onRegistered,
    required this.onCancel,
    this.registeredByName,
    this.submitLabel = 'Register & select',
  });

  @override
  State<RegisterMissingMemberForm> createState() => _RegisterMissingMemberFormState();
}

class _RegisterMissingMemberFormState extends State<RegisterMissingMemberForm> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: appText(size: 13, color: AppColors.textHint),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.2),
        ),
      );

  Future<void> _submit() async {
    final firstName = _firstCtrl.text.trim();
    final lastName = _lastCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || phone.isEmpty) {
      AppSnackbar.error(context, 'First name, last name and phone are required');
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await AuthApi.signup(
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        password: 'Nuru@2026',
        email: email.isEmpty ? null : email,
        registeredBy: widget.registeredByName,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        final data = res['data'] is Map ? Map<String, dynamic>.from(res['data']) : <String, dynamic>{};
        final user = <String, dynamic>{
          'id': data['id'] ?? '',
          'first_name': firstName,
          'last_name': lastName,
          'full_name': '$firstName $lastName',
          'username': data['username'] ?? '',
          'email': email,
          'phone': phone,
          'avatar': data['avatar'],
        };
        widget.onRegistered(user);
      } else {
        AppSnackbar.error(context, (res['message'] ?? 'Registration failed').toString());
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Registration failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const AppIcon('user-add', size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Register a new Nuru user',
                        style: appText(size: 14, weight: FontWeight.w700)),
                    Text('They can sign in later with their phone and the default password',
                        style: appText(size: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _firstCtrl,
                style: appText(size: 14),
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('First name *'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _lastCtrl,
                style: appText(size: 14),
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Last name *'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: appText(size: 14),
            decoration: _decoration('Phone *'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            style: appText(size: 14),
            decoration: _decoration('Email (optional)'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : widget.onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Cancel', style: appText(size: 13, weight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : Text(widget.submitLabel, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            'If this phone is already on Nuru, the existing user is selected instead of creating a duplicate. Default password: Nuru@2026',
            style: appText(size: 10.5, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
