import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/api_service.dart';
import '../../core/services/events_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/language_selector.dart';
import '../../core/widgets/nuru_date_time_picker.dart';
import '../../core/l10n/l10n_helper.dart';
import '../auth/widgets/auth_text_field.dart';
import 'identity_verification_screen.dart';
import '../wallet/payout_profile_screen.dart';
import 'terms_screen.dart';
import 'privacy_policy_screen.dart';
import 'licenses_screen.dart';
import '../onboarding/interests_onboarding_screen.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/settings_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/utils/password_strength.dart';

class SettingsScreen extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final VoidCallback? onProfileUpdated;
  final int initialSection;
  const SettingsScreen({
    super.key,
    this.profile,
    this.onProfileUpdated,
    this.initialSection = 0,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _section;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (_section == 0)
                          Navigator.pop(context);
                        else
                          setState(() => _section = 0);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SvgPicture.asset(
                          'assets/icons/chevron-left-icon.svg',
                          width: 20,
                          height: 20,
                          colorFilter: const ColorFilter.mode(
                            AppColors.textPrimary,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _sectionTitle(),
                        style: appText(size: 18, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildSection()),
            ],
          ),
        ),
      ),
    );
  }

  String _sectionTitle() {
    switch (_section) {
      case 1:
        return context.trw('edit_profile');
      case 2:
        return context.trw('change_password');
      case 3:
        return context.trw('privacy_security');
      case 4:
        return context.trw('notifications');
      case 5:
        return context.trw('about_nuru');
      case 6:
        return 'Preferences';
      case 7:
        return 'Security';
      default:
        return context.trw('settings');
    }
  }

  Widget _buildSection() {
    switch (_section) {
      case 1:
        return _EditProfileSection(
          profile: widget.profile,
          onUpdated: widget.onProfileUpdated,
        );
      case 2:
        return _ChangePasswordSection();
      case 3:
        return _PrivacySection();
      case 4:
        return _NotificationsSection();
      case 5:
        return _AboutSection();
      case 6:
        return _PreferencesSection();
      case 7:
        return _SecuritySection();
      default:
        return _menuSection();
    }
  }

  Widget _menuSection() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _sectionLabel(context.trw('account').toUpperCase()),
        _menuItem(
          'assets/icons/user-icon.svg',
          context.trw('edit_profile'),
          context.trw('update_personal_info'),
          () => setState(() => _section = 1),
        ),
        _menuItem(
          'assets/icons/shield-icon.svg',
          context.trw('change_password'),
          context.trw('update_account_password'),
          () => setState(() => _section = 2),
        ),
        _menuItem(
          'assets/icons/verified-icon.svg',
          context.trw('identity_verification'),
          context.trw('verify_identity'),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const IdentityVerificationScreen(),
              ),
            );
          },
        ),
        _menuItem(
          'assets/icons/card-icon.svg',
          'Payments & Payouts',
          'Country, currency, mobile money & bank',
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PayoutProfileScreen()),
            );
          },
        ),
        const SizedBox(height: 20),
        _sectionLabel(context.trw('preferences').toUpperCase()),
        const LanguageSettingsCard(),
        _menuItem(
          'assets/icons/heart-icon.svg',
          'Your interests',
          'Personalise your feed and recommendations',
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const InterestsOnboardingScreen(fromSettings: true),
              ),
            );
          },
        ),
        _menuItem(
          'assets/icons/bell-icon.svg',
          context.trw('notifications'),
          context.trw('manage_notifications'),
          () => setState(() => _section = 4),
        ),
        _menuItem(
          'assets/icons/shield-icon.svg',
          context.trw('privacy_security'),
          context.trw('control_privacy'),
          () => setState(() => _section = 3),
        ),
        _menuItem(
          'assets/icons/settings-icon.svg',
          'Preferences',
          'Language, currency, timezone, theme',
          () => setState(() => _section = 6),
        ),
        _menuItem(
          'assets/icons/shield-icon.svg',
          'Security',
          'Password, two-factor, active sessions',
          () => setState(() => _section = 7),
        ),
        const SizedBox(height: 20),
        _sectionLabel(context.trw('about').toUpperCase()),
        _menuItem(
          'assets/icons/info-icon.svg',
          context.trw('about_nuru'),
          context.trw('terms_and_licenses'),
          () => setState(() => _section = 5),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 10),
      child: Text(
        text,
        style: appText(
          size: 10,
          weight: FontWeight.w600,
          color: AppColors.textHint,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _menuItem(
    String icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: SvgPicture.asset(
                  icon,
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(
                    AppColors.primary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: appText(size: 14, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: appText(size: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            SvgPicture.asset(
              'assets/icons/chevron-right-icon.svg',
              width: 18,
              height: 18,
              colorFilter: const ColorFilter.mode(
                AppColors.textHint,
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// EDIT PROFILE - Redesigned with hero avatar, segmented form cards
class _EditProfileSection extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final VoidCallback? onUpdated;
  const _EditProfileSection({this.profile, this.onUpdated});

  @override
  State<_EditProfileSection> createState() => _EditProfileSectionState();
}

class _EditProfileSectionState extends State<_EditProfileSection> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  bool _saving = false;
  bool _loadingProfile = true;
  String? _avatarPath;
  Map<String, dynamic> _loadedProfile = {};

  @override
  void initState() {
    super.initState();
    _hydrateProfile();
  }

  void _applyProfile(Map<String, dynamic> p) {
    _firstNameCtrl.text = p['first_name']?.toString() ?? '';
    _lastNameCtrl.text = p['last_name']?.toString() ?? '';
    _usernameCtrl.text = p['username']?.toString() ?? '';
    _phoneCtrl.text = p['phone']?.toString() ?? '';
    _bioCtrl.text = p['bio']?.toString() ?? '';
    _locationCtrl.text = p['location']?.toString() ?? '';
  }

  Future<void> _hydrateProfile() async {
    final initial = widget.profile;
    if (initial != null && initial.isNotEmpty) {
      _loadedProfile = Map<String, dynamic>.from(initial);
      _applyProfile(_loadedProfile);
    }

    final meRes = await AuthApi.me();
    Map<String, dynamic>? userData;
    if (meRes['success'] == true && meRes['data'] is Map<String, dynamic>) {
      userData = meRes['data'] as Map<String, dynamic>;
    } else if (meRes['data'] is Map<String, dynamic> &&
        meRes['data']['id'] != null) {
      userData = meRes['data'] as Map<String, dynamic>;
    }

    final profileRes = await EventsService.getProfile();
    if (profileRes['success'] == true &&
        profileRes['data'] is Map<String, dynamic>) {
      final profileData = profileRes['data'] as Map<String, dynamic>;
      userData = {...(userData ?? {}), ...profileData};
    }

    if (mounted && userData != null) {
      _loadedProfile = userData;
      _applyProfile(_loadedProfile);
    }
    setState(() => _loadingProfile = false);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                context.tr('change_profile_photo'),
                style: appText(size: 16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/icons/camera-icon.svg',
                      width: 20,
                      height: 20,
                      colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
                    ),
                  ),
                ),
                title: Text(
                  context.tr('take_photo'),
                  style: appText(size: 14, weight: FontWeight.w600),
                ),
                subtitle: Text(
                  context.tr('use_camera'),
                  style: appText(size: 12, color: AppColors.textTertiary),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const Divider(height: 1, indent: 72),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/icons/gallery-icon.svg',
                      width: 20,
                      height: 20,
                      colorFilter: const ColorFilter.mode(Color(0xFF2E7D32), BlendMode.srcIn),
                    ),
                  ),
                ),
                title: Text(
                  context.tr('choose_from_gallery'),
                  style: appText(size: 14, weight: FontWeight.w600),
                ),
                subtitle: Text(
                  context.tr('pick_from_photos'),
                  style: appText(size: 12, color: AppColors.textTertiary),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: context.tr('crop_profile_photo'),
          toolbarColor: Colors.white,
          toolbarWidgetColor: AppColors.textPrimary,
          statusBarColor: Colors.white,
          activeControlsWidgetColor: AppColors.primary,
          backgroundColor: const Color(0xFFF7F8FA),
          dimmedLayerColor: const Color(0xCC0A1C40),
          cropFrameColor: AppColors.primary,
          cropGridColor: const Color(0x40FFFFFF),
          cropFrameStrokeWidth: 3,
          cropGridStrokeWidth: 1,
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
          hideBottomControls: true,
          showCropGrid: true,
          initAspectRatio: CropAspectRatioPreset.square,
        ),
        IOSUiSettings(
          title: context.tr('crop_profile_photo'),
          doneButtonTitle: 'Done',
          cancelButtonTitle: 'Cancel',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          rotateButtonsHidden: true,
          aspectRatioPickerButtonHidden: true,
          minimumAspectRatio: 1.0,
        ),
      ],
    );
    if (cropped != null && mounted) {
      setState(() => _avatarPath = cropped.path);
    }
  }

  bool _hasChanged(String field) {
    final original = _loadedProfile[field]?.toString() ?? '';
    switch (field) {
      case 'first_name':
        return _firstNameCtrl.text.trim() != original;
      case 'last_name':
        return _lastNameCtrl.text.trim() != original;
      case 'phone':
        return _phoneCtrl.text.trim() != original;
      case 'bio':
        return _bioCtrl.text.trim() != original;
      case 'location':
        return _locationCtrl.text.trim() != original;
      default:
        return false;
    }
  }

  Future<void> _save() async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      AppSnackbar.error(context, context.tr('required_field'));
      return;
    }

    // Check if phone changed - phone requires separate verification
    final phoneChanged = _hasChanged('phone');
    final newPhone = _phoneCtrl.text.trim();

    if (phoneChanged && newPhone.isNotEmpty) {
      // Show confirmation that phone change requires verification
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            context.tr('verify_phone'),
            style: appText(size: 16, weight: FontWeight.w700),
          ),
          content: Text(
            'Changing your phone number to $newPhone will require verification via SMS or WhatsApp. Continue?',
            style: appText(size: 13, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                context.tr('cancel'),
                style: appText(size: 13, color: AppColors.textTertiary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                context.tr('continue_text'),
                style: appText(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final nothingChanged =
        !_hasChanged('first_name') &&
        !_hasChanged('last_name') &&
        !_hasChanged('phone') &&
        !_hasChanged('bio') &&
        !_hasChanged('location') &&
        _avatarPath == null;
    if (nothingChanged) {
      if (mounted) AppSnackbar.info(context, context.tr('no_changes'));
      return;
    }

    setState(() => _saving = true);

    // Mirror web behaviour: always send the full set of editable fields so
    // backend validators receive a complete payload (mobile previously sent
    // only changed fields which triggered "validation failed" responses).
    final res = await EventsService.updateProfile(
      firstName: firstName,
      lastName: lastName,
      phone: phoneChanged ? newPhone : null,
      bio: _bioCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      avatarPath: _avatarPath,
    );

    setState(() => _saving = false);
    if (mounted) {
      if (res['success'] == true) {
        // Evict the old avatar from the in-memory + disk cache so the
        // new photo shows instantly across every screen (Profile,
        // Circles, Glimpses). Without this, CachedNetworkImage keeps
        // serving the previous bytes for the same URL.
        final oldAvatar =
            (_loadedProfile['avatar'] ?? widget.profile?['avatar'])?.toString();
        if (oldAvatar != null && oldAvatar.isNotEmpty) {
          try {
            await CachedNetworkImage.evictFromCache(oldAvatar);
          } catch (_) {}
        }
        _avatarPath = null;
        // Update loaded profile with new data
        if (res['data'] is Map<String, dynamic>) {
          _loadedProfile = res['data'] as Map<String, dynamic>;
        }
        // Refresh the global auth user so every screen subscribed to
        // AuthProvider re-renders with the new avatar URL right away.
        try {
          if (mounted) {
            await context.read<AuthProvider>().refreshUser();
          }
        } catch (_) {}
        AppSnackbar.success(context, context.tr('profile_updated'));
        widget.onUpdated?.call();
      } else {
        final errors = res['data']?['errors'];
        if (errors is Map) {
          final msg =
              (errors.values.first is List
                      ? errors.values.first.first
                      : errors.values.first)
                  .toString();
          AppSnackbar.error(context, msg);
        } else {
          AppSnackbar.error(context, res['message'] ?? 'Failed to update');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar =
        (_loadedProfile['avatar'] ?? widget.profile?['avatar']) as String?;
    final username = _loadedProfile['username']?.toString() ?? '';
    final fullName =
        '${_loadedProfile['first_name'] ?? ''} ${_loadedProfile['last_name'] ?? ''}'
            .trim();
    final email = _loadedProfile['email']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingProfile)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: AppColors.primary,
              ),
            ),

          // ─── Hero Avatar Card ───
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            margin: const EdgeInsets.only(bottom: 20, top: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 3,
                          ),
                        ),
                        child: ClipOval(
                          child: _avatarPath != null
                              ? Image.file(
                                  File(_avatarPath!),
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _fallback(),
                                )
                              : (avatar != null && avatar.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: avatar,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => _fallback(),
                                        errorWidget: (_, __, ___) =>
                                            _fallback(),
                                      )
                                    : _fallback()),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF1A1A2E),
                              width: 3,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (fullName.isNotEmpty)
                  Text(
                    fullName,
                    style: appText(
                      size: 18,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                if (username.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '@$username',
                      style: appText(size: 13, color: Colors.white70),
                    ),
                  ),
                if (email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      email,
                      style: appText(size: 12, color: Colors.white54),
                    ),
                  ),
              ],
            ),
          ),

          // ─── Personal Info Card ───
          _formCard(context.tr('personal_info'), [
            _formRow(
              context.tr('first_name'),
              _firstNameCtrl,
              context.tr('your_first_name'),
              TextInputType.name,
            ),
            _formRow(
              context.tr('last_name'),
              _lastNameCtrl,
              context.tr('your_last_name'),
              TextInputType.name,
            ),
            _formRow(
              context.tr('username'),
              _usernameCtrl,
              context.tr('username'),
              TextInputType.text,
              enabled: false,
            ),
          ]),

          const SizedBox(height: 14),

          // ─── Contact Card ───
          _formCard(context.tr('contact_info'), [
            _formRow(
              context.tr('phone'),
              _phoneCtrl,
              '+255 XXX XXX XXX',
              TextInputType.phone,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 12,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Changing your phone number will require verification',
                      style: appText(size: 10, color: AppColors.textHint),
                    ),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 14),

          // ─── About Card ───
          _formCard(context.tr('about'), [
            _formRow(
              context.tr('bio'),
              _bioCtrl,
              context.tr('write_bio'),
              TextInputType.multiline,
              maxLines: 3,
            ),
            _formRow(
              context.tr('location'),
              _locationCtrl,
              context.tr('city_country'),
              TextInputType.text,
            ),
          ]),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      context.tr('save_changes'),
                      style: appText(
                        size: 15,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _formCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: appText(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _formRow(
    String label,
    TextEditingController ctrl,
    String hint,
    TextInputType type, {
    int maxLines = 1,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: appText(
              size: 12,
              weight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: type,
            maxLines: maxLines,
            enabled: enabled,
            style: appText(size: 14, weight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: appText(size: 13, color: AppColors.textHint),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderLight),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() => Container(
    width: 100,
    height: 100,
    color: const Color(0xFF2A2A4A),
    child: const Center(
      child: Icon(Icons.person_rounded, size: 40, color: Colors.white38),
    ),
  );
}

class _ChangePasswordSection extends StatefulWidget {
  @override
  State<_ChangePasswordSection> createState() => _ChangePasswordSectionState();
}

class _ChangePasswordSectionState extends State<_ChangePasswordSection> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;
  bool _showCurrent = false;
  bool _showNew = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (_newCtrl.text != _confirmCtrl.text) {
      AppSnackbar.error(context, context.tr('passwords_dont_match'));
      return;
    }
    final err = PasswordStrength.firstError(_newCtrl.text);
    if (err != null) {
      AppSnackbar.error(context, err);
      return;
    }
    setState(() => _saving = true);
    final res = await EventsService.changePassword(
      _currentCtrl.text,
      _newCtrl.text,
      _confirmCtrl.text,
    );
    setState(() => _saving = false);
    if (mounted) {
      if (res['success'] == true) {
        AppSnackbar.success(context, context.tr('password_changed'));
        _currentCtrl.clear();
        _newCtrl.clear();
        _confirmCtrl.clear();
      } else {
        AppSnackbar.error(
          context,
          res['message'] ?? 'Failed to change password',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('password_hint'),
                    style: appText(size: 12, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _passwordField(
            _currentCtrl,
            context.tr('current_password'),
            context.tr('enter_current_password'),
            _showCurrent,
            (v) => setState(() => _showCurrent = v),
          ),
          const SizedBox(height: 16),
          _passwordField(
            _newCtrl,
            context.tr('new_password'),
            context.tr('enter_new_password'),
            _showNew,
            (v) => setState(() => _showNew = v),
          ),
          const SizedBox(height: 16),
          AuthTextField(
            controller: _confirmCtrl,
            label: context.tr('confirm_password'),
            hintText: context.tr('confirm_new_password'),
            obscureText: true,
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _change,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      context.tr('change_password'),
                      style: appText(
                        size: 15,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField(
    TextEditingController ctrl,
    String label,
    String hint,
    bool show,
    ValueChanged<bool> toggle,
  ) {
    return AuthTextField(
      controller: ctrl,
      label: label,
      hintText: hint,
      obscureText: !show,
      suffixIcon: GestureDetector(
        onTap: () => toggle(!show),
        child: Icon(
          show ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          size: 20,
          color: AppColors.textHint,
        ),
      ),
    );
  }
}

// ─── Reusable widgets ───────────────────────────────────────────────────

/// Resolve a Material icon to a project SVG asset path. Returns null when
/// no matching SVG exists - callers should fall back to the Material icon.
String? _svgForIcon(IconData? icon) {
  if (icon == null) return null;
  final map = <int, String>{
    Icons.lock_outline_rounded.codePoint: 'assets/icons/shield-icon.svg',
    Icons.public_rounded.codePoint: 'assets/icons/website-click.svg',
    Icons.language_rounded.codePoint: 'assets/icons/language-icon.svg',
    Icons.attach_money_rounded.codePoint: 'assets/icons/wallet-icon.svg',
    Icons.palette_rounded.codePoint: 'assets/icons/palette-icon.svg',
    Icons.calendar_today_rounded.codePoint: 'assets/icons/calendar-icon.svg',
    Icons.access_time_rounded.codePoint: 'assets/icons/clock-icon.svg',
    Icons.bedtime_rounded.codePoint: 'assets/icons/clock-icon.svg',
    Icons.wb_sunny_rounded.codePoint: 'assets/icons/clock-icon.svg',
    Icons.block_rounded.codePoint: 'assets/icons/block-icon.svg',
    Icons.description_rounded.codePoint: 'assets/icons/info-icon.svg',
    Icons.privacy_tip_rounded.codePoint: 'assets/icons/secure-shield-icon.svg',
    Icons.code_rounded.codePoint: 'assets/icons/license.svg',
    Icons.email_rounded.codePoint: 'assets/icons/chat-icon.svg',
    Icons.system_update_rounded.codePoint: 'assets/icons/thunder-icon.svg',
    Icons.devices_other_rounded.codePoint: 'assets/icons/user-icon.svg',
    Icons.fingerprint_rounded.codePoint: 'assets/icons/secure-shield-icon.svg',
  };
  return map[icon.codePoint];
}

Widget _settingsCard({required Widget child}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: child,
  );
}

Widget _settingsToggle({
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool>? onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: appText(size: 14, weight: FontWeight.w600)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: appText(
                    size: 11,
                    color: AppColors.textTertiary,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
        ),
      ],
    ),
  );
}

Widget _settingsTile({
  required String title,
  String? subtitle,
  Widget? trailing,
  VoidCallback? onTap,
  IconData? icon,
  Color? iconBg,
  Color? iconColor,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg ?? AppColors.primarySoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Builder(
                builder: (_) {
                  final svg = _svgForIcon(icon);
                  final color = iconColor ?? AppColors.primary;
                  if (svg != null) {
                    return Center(
                      child: SvgPicture.asset(
                        svg,
                        width: 18,
                        height: 18,
                        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                      ),
                    );
                  }
                  return Icon(icon, color: color, size: 18);
                },
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: appText(size: 14, weight: FontWeight.w600)),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: appText(size: 11, color: AppColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
          if (onTap != null && trailing == null)
            SvgPicture.asset(
              'assets/icons/chevron-right-icon.svg',
              width: 18,
              height: 18,
              colorFilter: const ColorFilter.mode(
                AppColors.textHint,
                BlendMode.srcIn,
              ),
            ),
        ],
      ),
    ),
  );
}

Widget _sectionHeading(String label) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 14, 0, 8),
  child: Text(
    label.toUpperCase(),
    style: appText(
      size: 10,
      weight: FontWeight.w700,
      color: AppColors.textHint,
      height: 1.0,
    ),
  ),
);

// ─── PRIVACY ───────────────────────────────────────────────────────────

class _PrivacySection extends StatefulWidget {
  @override
  State<_PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends State<_PrivacySection> {
  bool _loading = true;
  Map<String, dynamic> _p = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await SettingsService.fetchAll();
    if (mounted) {
      setState(() {
        _loading = false;
        if (res['success'] == true && res['data'] is Map) {
          _p = Map<String, dynamic>.from(res['data']['privacy'] ?? {});
        }
      });
    }
  }

  Future<void> _update(String key, dynamic value) async {
    setState(() => _p[key] = value);
    final res = await SettingsService.updatePrivacy({key: value});
    if (mounted && res['success'] != true) {
      AppSnackbar.error(context, res['message'] ?? 'Update failed');
    }
  }

  bool _b(String key, [bool def = true]) =>
      _p[key] == null ? def : _p[key] == true;

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _sectionHeading('Profile'),
        _settingsCard(
          child: _settingsTile(
            title: 'Profile visibility',
            subtitle: (_p['profile_visibility'] ?? 'public')
                .toString()
                .toUpperCase(),
            icon: Icons.public_rounded,
            onTap: () async {
              final choice = await showModalBottomSheet<String>(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final v in const ['public', 'followers', 'private'])
                        ListTile(
                          title: Text(
                            v[0].toUpperCase() + v.substring(1),
                            style: appText(size: 14, weight: FontWeight.w600),
                          ),
                          trailing: (_p['profile_visibility'] ?? 'public') == v
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(ctx, v),
                        ),
                    ],
                  ),
                ),
              );
              if (choice != null) _update('profile_visibility', choice);
            },
          ),
        ),
        _settingsCard(
          child: _settingsToggle(
            title: 'Private account',
            subtitle: 'Only approved followers can see your moments and events',
            value: _p['private_profile'] == true,
            onChanged: (v) => _update('private_profile', v),
          ),
        ),
        _settingsCard(
          child: _settingsToggle(
            title: 'Hide from search',
            subtitle: 'Stop your profile appearing in search and suggestions',
            value: _p['hide_from_search'] == true,
            onChanged: (v) => _update('hide_from_search', v),
          ),
        ),

        _sectionHeading('Activity'),
        _settingsCard(
          child: _settingsToggle(
            title: 'Show online status',
            value: _b('show_online_status'),
            onChanged: (v) => _update('show_online_status', v),
          ),
        ),
        _settingsCard(
          child: _settingsToggle(
            title: 'Show last seen',
            value: _b('show_last_seen'),
            onChanged: (v) => _update('show_last_seen', v),
          ),
        ),
        _settingsCard(
          child: _settingsToggle(
            title: 'Read receipts',
            subtitle: 'Let people know when you\u2019ve read their messages',
            value: _b('show_read_receipts'),
            onChanged: (v) => _update('show_read_receipts', v),
          ),
        ),

        _sectionHeading('Interactions'),
        _settingsCard(
          child: _settingsToggle(
            title: 'Allow tagging',
            subtitle: 'Others can tag you in moments and events',
            value: _b('allow_tagging'),
            onChanged: (v) => _update('allow_tagging', v),
          ),
        ),
        _settingsCard(
          child: _settingsToggle(
            title: 'Allow mentions',
            value: _b('allow_mentions'),
            onChanged: (v) => _update('allow_mentions', v),
          ),
        ),
        _settingsCard(
          child: _settingsToggle(
            title: 'Message requests',
            subtitle: 'Receive requests from people outside your circle',
            value: _b('allow_message_requests'),
            onChanged: (v) => _update('allow_message_requests', v),
          ),
        ),

        _sectionHeading('Blocked'),
        _settingsCard(
          child: _settingsTile(
            title: 'Blocked users',
            subtitle: '${_p['blocked_users_count'] ?? 0} blocked',
            icon: Icons.block_rounded,
            iconBg: const Color(0xFFFEECEC),
            iconColor: const Color(0xFFD64545),
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

// ─── NOTIFICATIONS ─────────────────────────────────────────────────────

class _NotificationsSection extends StatefulWidget {
  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  bool _loading = true;
  Map<String, dynamic> _n = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await SettingsService.fetchAll();
    if (mounted)
      setState(() {
        _loading = false;
        if (res['success'] == true && res['data'] is Map) {
          _n = Map<String, dynamic>.from(res['data']['notifications'] ?? {});
        }
      });
  }

  Future<void> _update(String key, dynamic value) async {
    setState(() => _n[key] = value);
    final res = await SettingsService.updateNotifications({key: value});
    if (mounted && res['success'] != true) {
      AppSnackbar.error(context, res['message'] ?? 'Update failed');
    }
  }

  bool _b(String key, [bool def = true]) =>
      _n[key] == null ? def : _n[key] == true;

  Future<void> _pickTime(String key) async {
    final current = (_n[key] ?? '22:00').toString();
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 22,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showNuruTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final s = nuruFormatTime24(picked);
      _update(key, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _sectionHeading('Channels'),
        _settingsCard(
          child: Column(
            children: [
              _settingsToggle(
                title: 'Push notifications',
                value: _b('push_notifications'),
                onChanged: (v) => _update('push_notifications', v),
              ),
              const Divider(height: 1, indent: 14),
              _settingsToggle(
                title: 'Email notifications',
                value: _b('email_notifications'),
                onChanged: (v) => _update('email_notifications', v),
              ),
              const Divider(height: 1, indent: 14),
              _settingsToggle(
                title: 'SMS notifications',
                subtitle: 'Standard SMS rates may apply',
                value: _b('sms_notifications', false),
                onChanged: (v) => _update('sms_notifications', v),
              ),
            ],
          ),
        ),

        _sectionHeading('Events'),
        _settingsCard(
          child: Column(
            children: [
              _settingsToggle(
                title: 'Event invitations',
                value: _b('event_invitation_notifications'),
                onChanged: (v) => _update('event_invitation_notifications', v),
              ),
              const Divider(height: 1, indent: 14),
              _settingsToggle(
                title: 'RSVP updates',
                value: _b('rsvp_notifications'),
                onChanged: (v) => _update('rsvp_notifications', v),
              ),
              const Divider(height: 1, indent: 14),
              _settingsToggle(
                title: 'Contributions',
                subtitle: 'When someone contributes to your event',
                value: _b('contribution_notifications'),
                onChanged: (v) => _update('contribution_notifications', v),
              ),
            ],
          ),
        ),

        _sectionHeading('Social'),
        _settingsCard(
          child: Column(
            children: [
              _settingsToggle(
                title: 'Direct messages',
                value: _b('message_notifications'),
                onChanged: (v) => _update('message_notifications', v),
              ),
              const Divider(height: 1, indent: 14),
              _settingsToggle(
                title: 'Mentions',
                value: _b('mention_notifications'),
                onChanged: (v) => _update('mention_notifications', v),
              ),
              const Divider(height: 1, indent: 14),
              _settingsToggle(
                title: 'New followers',
                value: _b('follower_notifications'),
                onChanged: (v) => _update('follower_notifications', v),
              ),
              const Divider(height: 1, indent: 14),
              _settingsToggle(
                title: 'Glows & Echoes',
                subtitle: 'Reactions on your moments and posts',
                value: _b('glows_echoes_notifications'),
                onChanged: (v) => _update('glows_echoes_notifications', v),
              ),
            ],
          ),
        ),

        _sectionHeading('Email digest'),
        _settingsCard(
          child: Column(
            children: [
              _settingsToggle(
                title: 'Weekly digest',
                subtitle: 'A weekly summary of what matters',
                value: _b('weekly_digest'),
                onChanged: (v) => _update('weekly_digest', v),
              ),
              const Divider(height: 1, indent: 14),
              _settingsToggle(
                title: 'Marketing emails',
                subtitle: 'Tips, product news and offers',
                value: _b('marketing_emails', false),
                onChanged: (v) => _update('marketing_emails', v),
              ),
            ],
          ),
        ),

        _sectionHeading('Quiet hours'),
        _settingsCard(
          child: Column(
            children: [
              _settingsToggle(
                title: 'Enable quiet hours',
                subtitle: 'Mute push notifications during this window',
                value: _b('quiet_hours_enabled', false),
                onChanged: (v) => _update('quiet_hours_enabled', v),
              ),
              if (_b('quiet_hours_enabled', false)) ...[
                const Divider(height: 1, indent: 14),
                _settingsTile(
                  title: 'Start',
                  subtitle: (_n['quiet_hours_start'] ?? '22:00').toString(),
                  icon: Icons.bedtime_rounded,
                  onTap: () => _pickTime('quiet_hours_start'),
                ),
                const Divider(height: 1, indent: 14),
                _settingsTile(
                  title: 'End',
                  subtitle: (_n['quiet_hours_end'] ?? '07:00').toString(),
                  icon: Icons.wb_sunny_rounded,
                  onTap: () => _pickTime('quiet_hours_end'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── PREFERENCES ───────────────────────────────────────────────────────

class _PreferencesSection extends StatefulWidget {
  @override
  State<_PreferencesSection> createState() => _PreferencesSectionState();
}

class _PreferencesSectionState extends State<_PreferencesSection> {
  bool _loading = true;
  Map<String, dynamic> _p = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await SettingsService.fetchAll();
    if (mounted)
      setState(() {
        _loading = false;
        if (res['success'] == true && res['data'] is Map) {
          _p = Map<String, dynamic>.from(res['data']['preferences'] ?? {});
        }
      });
  }

  Future<void> _update(String key, dynamic value) async {
    setState(() => _p[key] = value);
    final res = await SettingsService.updatePreferences({key: value});
    if (mounted && res['success'] != true) {
      AppSnackbar.error(context, res['message'] ?? 'Update failed');
    }
  }

  Future<String?> _pickFromList(
    String title,
    List<MapEntry<String, String>> options,
    String current,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                title,
                style: appText(size: 14, weight: FontWeight.w700),
              ),
            ),
            for (final opt in options)
              ListTile(
                title: Text(
                  opt.value,
                  style: appText(size: 14, weight: FontWeight.w600),
                ),
                trailing: opt.key == current
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, opt.key),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );

    final lang = (_p['language'] ?? 'en').toString();
    final notifLang = (_p['notification_language'] ?? 'sw').toString();
    final cur = (_p['currency'] ?? 'TZS').toString();
    final tz = (_p['timezone'] ?? 'Africa/Nairobi').toString();
    final theme = (_p['theme'] ?? 'system').toString();
    final dateFmt = (_p['date_format'] ?? 'DD/MM/YYYY').toString();
    final timeFmt = (_p['time_format'] ?? '24h').toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _sectionHeading('Region'),
        _settingsCard(
          child: Column(
            children: [
              _settingsTile(
                icon: Icons.language_rounded,
                title: 'Language',
                subtitle:
                    const {'en': 'English', 'sw': 'Kiswahili'}[lang] ?? lang,
                onTap: () async {
                  final v = await _pickFromList('Language', const [
                    MapEntry('en', 'English'),
                    MapEntry('sw', 'Kiswahili'),
                  ], lang);
                  if (v != null) _update('language', v);
                },
              ),
              const Divider(height: 1, indent: 14),
              _settingsTile(
                icon: Icons.notifications_active_rounded,
                title: 'Notification Language',
                subtitle:
                    const {'sw': 'Swahili', 'en': 'English'}[notifLang] ??
                    'Swahili',
                onTap: () async {
                  final v = await _pickFromList('Notification Language', const [
                    MapEntry('sw', 'Swahili'),
                    MapEntry('en', 'English'),
                  ], notifLang);
                  if (v != null) _update('notification_language', v);
                },
              ),
              const Divider(height: 1, indent: 14),
              _settingsTile(
                icon: Icons.attach_money_rounded,
                title: 'Currency',
                subtitle: cur,
                onTap: () async {
                  final v = await _pickFromList('Currency', const [
                    MapEntry('TZS', 'Tanzanian Shilling (TZS)'),
                    MapEntry('KES', 'Kenyan Shilling (KES)'),
                    MapEntry('UGX', 'Ugandan Shilling (UGX)'),
                    MapEntry('USD', 'US Dollar (USD)'),
                    MapEntry('EUR', 'Euro (EUR)'),
                  ], cur);
                  if (v != null) _update('currency', v);
                },
              ),
              const Divider(height: 1, indent: 14),
              _settingsTile(
                icon: Icons.public_rounded,
                title: 'Time zone',
                subtitle: tz,
                onTap: () async {
                  final v = await _pickFromList('Time zone', const [
                    MapEntry('Africa/Dar_es_Salaam', 'Dar es Salaam (EAT)'),
                    MapEntry('Africa/Nairobi', 'Nairobi (EAT)'),
                    MapEntry('Africa/Kampala', 'Kampala (EAT)'),
                    MapEntry('UTC', 'UTC'),
                  ], tz);
                  if (v != null) _update('timezone', v);
                },
              ),
            ],
          ),
        ),

        _sectionHeading('Display'),
        _settingsCard(
          child: Column(
            children: [
              _settingsTile(
                icon: Icons.palette_rounded,
                title: 'Theme',
                subtitle: theme[0].toUpperCase() + theme.substring(1),
                onTap: () async {
                  final v = await _pickFromList('Theme', const [
                    MapEntry('system', 'System default'),
                    MapEntry('light', 'Light'),
                    MapEntry('dark', 'Dark'),
                  ], theme);
                  if (v != null) _update('theme', v);
                },
              ),
              const Divider(height: 1, indent: 14),
              _settingsTile(
                icon: Icons.calendar_today_rounded,
                title: 'Date format',
                subtitle: dateFmt,
                onTap: () async {
                  final v = await _pickFromList('Date format', const [
                    MapEntry('DD/MM/YYYY', 'DD/MM/YYYY'),
                    MapEntry('MM/DD/YYYY', 'MM/DD/YYYY'),
                    MapEntry('YYYY-MM-DD', 'YYYY-MM-DD'),
                  ], dateFmt);
                  if (v != null) _update('date_format', v);
                },
              ),
              const Divider(height: 1, indent: 14),
              _settingsTile(
                icon: Icons.access_time_rounded,
                title: 'Time format',
                subtitle: timeFmt == '24h' ? '24-hour' : '12-hour',
                onTap: () async {
                  final v = await _pickFromList('Time format', const [
                    MapEntry('24h', '24-hour'),
                    MapEntry('12h', '12-hour'),
                  ], timeFmt);
                  if (v != null) _update('time_format', v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── SECURITY ──────────────────────────────────────────────────────────

class _SecuritySection extends StatefulWidget {
  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  bool _loading = true;
  bool _twoFA = false;
  bool _loginAlerts = true;
  bool _passkeyEnabled = false;
  bool _biometricsAvailable = false;
  String? _userEmail;
  int _activeSessions = 0;
  List<dynamic> _sessions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await SettingsService.fetchAll();
    final ses = await SettingsService.sessions();
    try {
      final auth = LocalAuthentication();
      _biometricsAvailable =
          await auth.canCheckBiometrics && await auth.isDeviceSupported();
    } catch (_) {
      _biometricsAvailable = false;
    }
    if (mounted)
      setState(() {
        _loading = false;
        if (res['success'] == true && res['data'] is Map) {
          final sec = Map<String, dynamic>.from(res['data']['security'] ?? {});
          _twoFA = sec['two_factor_enabled'] == true;
          _loginAlerts = sec['login_alerts'] != false;
          _passkeyEnabled = sec['passkey_enabled'] == true;
          _userEmail =
              (res['data']['account']?['email'] ??
                      res['data']['profile']?['email'] ??
                      sec['email'])
                  ?.toString();
          _activeSessions =
              (sec['active_sessions_count'] as num?)?.toInt() ?? 0;
        }
        if (ses['success'] == true && ses['data'] is List) {
          _sessions = ses['data'] as List;
          _activeSessions = _sessions.length;
        }
      });
  }

  Future<void> _toggleLoginAlerts(bool v) async {
    setState(() => _loginAlerts = v);
    await SettingsService.updateSecurity({'login_alerts': v});
  }

  Future<void> _toggle2FA() async {
    if (_twoFA) {
      final code = await _promptCode(
        'Enter your authenticator code to disable 2FA',
      );
      if (code == null) return;
      final res = await SettingsService.disable2fa(code);
      if (mounted) {
        if (res['success'] == true) {
          setState(() => _twoFA = false);
          AppSnackbar.success(context, 'Two-factor authentication disabled');
        } else {
          AppSnackbar.error(context, res['message'] ?? 'Failed');
        }
      }
    } else {
      final res = await SettingsService.enable2fa();
      if (!mounted) return;
      if (res['success'] != true || res['data'] is! Map) {
        AppSnackbar.error(context, res['message'] ?? 'Failed to start 2FA');
        return;
      }
      final data = Map<String, dynamic>.from(res['data']);
      final secret = data['secret']?.toString() ?? '';
      final otpauth = data['otpauth_url']?.toString().isNotEmpty == true
          ? data['otpauth_url'].toString()
          : 'otpauth://totp/Nuru:${Uri.encodeComponent(_userEmail ?? 'account')}?secret=$secret&issuer=Nuru';
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Set up Authenticator',
                style: appText(size: 18, weight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Scan this QR with Google Authenticator, Authy, 1Password or any TOTP app.',
                style: appText(
                  size: 12,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: QrImageView(
                    data: otpauth,
                    size: 200,
                    backgroundColor: Colors.white,
                    version: QrVersions.auto,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Or enter this code manually',
                style: appText(
                  size: 11,
                  weight: FontWeight.w700,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: secret));
                  AppSnackbar.success(context, 'Copied');
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          secret,
                          style: appText(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      SvgPicture.asset(
                        'assets/icons/share-icon.svg',
                        width: 16,
                        height: 16,
                        colorFilter: const ColorFilter.mode(
                          AppColors.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'I\'ve added it',
                    style: appText(
                      size: 14,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      final code = await _promptCode('Enter the 6-digit code from your app');
      if (code == null) return;
      final v = await SettingsService.verify2fa(code);
      if (mounted) {
        if (v['success'] == true) {
          setState(() => _twoFA = true);
          AppSnackbar.success(context, 'Two-factor authentication enabled');
        } else {
          AppSnackbar.error(context, v['message'] ?? 'Invalid code');
        }
      }
    }
  }

  Future<void> _togglePasskey(bool v) async {
    if (v && !_biometricsAvailable) {
      AppSnackbar.error(context, 'No biometrics enrolled on this device');
      return;
    }
    if (v) {
      try {
        final auth = LocalAuthentication();
        final ok = await auth.authenticate(
          localizedReason: 'Confirm to register a passkey for this device',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
          ),
        );
        if (!ok) return;
      } catch (_) {
        return;
      }
    }
    setState(() => _passkeyEnabled = v);
    final res = await SettingsService.updateSecurity({'passkey_enabled': v});
    if (mounted && res['success'] != true) {
      setState(() => _passkeyEnabled = !v);
      AppSnackbar.error(context, res['message'] ?? 'Failed to update');
    } else if (mounted) {
      AppSnackbar.success(
        context,
        v ? 'Passkey enabled on this device' : 'Passkey disabled',
      );
    }
  }

  Future<String?> _promptCode(String label) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Verification',
          style: appText(size: 16, weight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: appText(
                size: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: '123456',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: appText(size: 13, color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(
              'Verify',
              style: appText(
                size: 13,
                color: AppColors.primary,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeSession(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sign out this device?',
          style: appText(size: 15, weight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: appText(size: 13, color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sign out',
              style: appText(
                size: 13,
                weight: FontWeight.w700,
                color: const Color(0xFFD64545),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await SettingsService.revokeSession(id);
    if (mounted && res['success'] == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _sectionHeading('Account'),
        _settingsCard(
          child: _settingsTile(
            icon: Icons.lock_outline_rounded,
            title: 'Change password',
            subtitle: 'Use a strong, unique password',
            onTap: () {
              final state = context
                  .findAncestorStateOfType<_SettingsScreenState>();
              state?.setState(() => state._section = 2);
            },
          ),
        ),

        _sectionHeading('Two-factor authentication'),
        _settingsCard(
          child: _settingsToggle(
            title: 'Authenticator app (TOTP)',
            subtitle: _twoFA
                ? 'Enabled · extra protection on every sign-in'
                : 'Add a 6-digit code from your authenticator app',
            value: _twoFA,
            onChanged: (_) => _toggle2FA(),
          ),
        ),
        _settingsCard(
          child: _settingsToggle(
            title: 'Passkey (this device)',
            subtitle: _biometricsAvailable
                ? 'Use Face ID, fingerprint or device PIN to sign in faster'
                : 'No biometrics enrolled on this device',
            value: _passkeyEnabled,
            onChanged: _biometricsAvailable ? _togglePasskey : null,
          ),
        ),

        _sectionHeading('Alerts'),
        _settingsCard(
          child: _settingsToggle(
            title: 'Login alerts',
            subtitle: 'Email me when a new device signs in',
            value: _loginAlerts,
            onChanged: _toggleLoginAlerts,
          ),
        ),

        _sectionHeading('Active sessions ($_activeSessions)'),
        if (_sessions.isEmpty)
          _settingsCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No other active sessions.',
                style: appText(size: 12, color: AppColors.textTertiary),
              ),
            ),
          )
        else
          ..._sessions.map((s) {
            final m = Map<String, dynamic>.from(s as Map);
            final name =
                (m['device_name'] ?? m['user_agent'] ?? 'Unknown device')
                    .toString();
            final ip = (m['ip_address'] ?? '').toString();
            final last = (m['last_active_at'] ?? '').toString();
            return _settingsCard(
              child: _settingsTile(
                icon: Icons.devices_other_rounded,
                title: name,
                subtitle: [
                  if (ip.isNotEmpty) ip,
                  if (last.isNotEmpty)
                    'Active ${last.substring(0, last.length > 16 ? 16 : last.length)}',
                ].join(' • '),
                trailing: TextButton(
                  onPressed: () => _revokeSession(m['id'].toString()),
                  child: Text(
                    'Sign out',
                    style: appText(
                      size: 12,
                      weight: FontWeight.w700,
                      color: const Color(0xFFD64545),
                    ),
                  ),
                ),
              ),
            );
          }),

        if (_sessions.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: () async {
                final res = await SettingsService.revokeAllSessions();
                if (mounted && res['success'] == true) _load();
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD64545)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Sign out all other sessions',
                style: appText(
                  size: 13,
                  weight: FontWeight.w700,
                  color: const Color(0xFFD64545),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── ABOUT ─────────────────────────────────────────────────────────────

class _AboutSection extends StatefulWidget {
  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  String _installedVersion = '';
  String _installedBuild = '';
  String? _latestVersion;
  int _latestBuild = 0;
  String? _updateUrl;
  bool _hasUpdate = false;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _installedVersion = info.version;
      _installedBuild = info.buildNumber;
    } catch (_) {}
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final res = await SettingsService.appVersion(platform);
      if (res['success'] == true && res['data'] is Map) {
        final d = Map<String, dynamic>.from(res['data']);
        _latestVersion = d['latest_version']?.toString();
        _updateUrl = d['update_url']?.toString();
        final latestBuild = _asInt(d['latest_build']);
        final installedBuildNum = int.tryParse(_installedBuild) ?? 0;
        _latestBuild = latestBuild;
        final hasNewerBuild =
            latestBuild > 0 &&
            installedBuildNum > 0 &&
            latestBuild > installedBuildNum;
        final hasNewerVersion =
            (_latestVersion ?? '').isNotEmpty &&
            _installedVersion.isNotEmpty &&
            _compareVersions(_latestVersion!, _installedVersion) > 0;
        _hasUpdate = hasNewerBuild || hasNewerVersion;
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  int _compareVersions(String a, String b) {
    final left = a
        .split(RegExp(r'[^0-9]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final right = b
        .split(RegExp(r'[^0-9]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/nuru-logo-square.png',
                  width: 76,
                  height: 76,
                  errorBuilder: (_, __, ___) => Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        'N',
                        style: appText(
                          size: 30,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                'Plan smarter. Celebrate better.',
                textAlign: TextAlign.center,
                style: appText(
                  size: 12,
                  color: const Color(0xFF4B5563),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              if (_installedVersion.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.18),
                    ),
                  ),
                  child: Text(
                    'v$_installedVersion${_installedBuild.isNotEmpty ? ' ($_installedBuild)' : ''}',
                    style: appText(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_hasUpdate) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF5C45E)),
            ),
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/icons/thunder-icon.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFFB8860B),
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Update available',
                        style: appText(
                          size: 13,
                          weight: FontWeight.w700,
                          color: const Color(0xFF7A5400),
                        ),
                      ),
                      Text(
                        'Latest v$_latestVersion${_latestBuild > 0 ? ' ($_latestBuild)' : ''} is available now.',
                        style: appText(
                          size: 11,
                          color: const Color(0xFF7A5400),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final uri = Uri.tryParse(_updateUrl ?? '');
                    if (uri != null)
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                  },
                  child: Text(
                    'Update',
                    style: appText(
                      size: 13,
                      weight: FontWeight.w700,
                      color: const Color(0xFFB8860B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),

        _sectionHeading('Legal'),
        _settingsCard(
          child: _settingsTile(
            icon: Icons.description_rounded,
            title: 'Terms of Service',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            ),
          ),
        ),
        _settingsCard(
          child: _settingsTile(
            icon: Icons.privacy_tip_rounded,
            title: 'Privacy Policy',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
            ),
          ),
        ),
        _settingsCard(
          child: _settingsTile(
            icon: Icons.code_rounded,
            title: 'Open-source licenses',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LicensesScreen()),
            ),
          ),
        ),
        _settingsCard(
          child: _settingsTile(
            icon: Icons.delete_forever_rounded,
            title: 'Request data deletion',
            subtitle: 'Delete your Nuru account and personal data',
            onTap: () => launchUrl(
              Uri.parse('https://nuru.tz/data-deletion'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),

        _sectionHeading('Connect'),
        _settingsCard(
          child: _settingsTile(
            icon: Icons.email_rounded,
            title: 'Support',
            subtitle: 'support@nuru.tz',
            onTap: () => launchUrl(Uri.parse('mailto:support@nuru.tz')),
          ),
        ),
        _settingsCard(
          child: _settingsTile(
            icon: Icons.public_rounded,
            title: 'Website',
            subtitle: 'nuru.tz',
            onTap: () => launchUrl(
              Uri.parse('https://nuru.tz'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),

        const SizedBox(height: 20),
        Center(
          child: Text(
            '© ${DateTime.now().year} Nuru. All rights reserved.',
            style: appText(size: 11, color: AppColors.textHint),
          ),
        ),
      ],
    );
  }
}
