import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../theme/text_styles.dart';
import 'app_snackbar.dart';

/// Reusable bottom sheet that lets the user contact a person via:
///   • Nuru voice call (in-app)   - uses the Nuru logo
///   • WhatsApp                   - uses the brand-colored WhatsApp SVG
///   • Phone (normal dialer)      - uses the project call-icon SVG
///
/// Drop in anywhere a phone number is shown (RSVP, contributors, vendors…):
///   showCallOptions(context, name: 'Alice', phone: '+255712…',
///                   avatarUrl: maybeAvatar);
///
/// The sheet performs a backend lookup `/users/by-phone/{phone}` on open so
/// that a contributor saved under a nickname still resolves to their real
/// Nuru account (avatar + nuru user id) - the phone is the source of truth.
Future<void> showCallOptions(
  BuildContext context, {
  required String name,
  required String phone,
  String? nuruUserId,
  String? avatarUrl,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CallOptionsSheet(
      name: name,
      phone: phone,
      nuruUserId: nuruUserId,
      avatarUrl: avatarUrl,
    ),
  );
}

class _CallOptionsSheet extends StatefulWidget {
  final String name;
  final String phone;
  final String? nuruUserId;
  final String? avatarUrl;
  const _CallOptionsSheet({
    required this.name,
    required this.phone,
    this.nuruUserId,
    this.avatarUrl,
  });

  @override
  State<_CallOptionsSheet> createState() => _CallOptionsSheetState();
}

class _CallOptionsSheetState extends State<_CallOptionsSheet> {
  String? _nuruUserId;
  String? _nuruName;
  String? _avatarUrl;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _nuruUserId = widget.nuruUserId;
    _avatarUrl = widget.avatarUrl;
    _lookup();
  }

  /// Phone is the source of truth - even if the organiser saved the
  /// contributor under a nickname, look up their real Nuru account so
  /// the avatar + ability to start a Nuru call work correctly.
  Future<void> _lookup() async {
    final res = await ApiService.get(
      '/users/by-phone/${Uri.encodeComponent(widget.phone)}',
    );
    if (!mounted) return;
    final ok = res['success'] == true && res['data'] is Map;
    setState(() {
      _checking = false;
      if (ok) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        _nuruUserId ??= (data['id'] ?? data['user_id'])?.toString();
        _nuruName = (data['full_name'] ??
                data['display_name'] ??
                [data['first_name'], data['last_name']]
                    .whereType<String>()
                    .join(' ')
                    .trim())
            ?.toString();
        final candidate = (data['avatar'] ?? data['avatar_url'] ?? '').toString();
        if (candidate.isNotEmpty) {
          _avatarUrl = candidate;
        }
      }
    });
  }

  /// Digits used by WhatsApp's deep link · no '+' allowed.
  String get _waDigits => widget.phone.replaceAll(RegExp(r'\D'), '');

  /// Phone string used by the native dialer. If the number already includes
  /// a country code (most easily detected by length ≥ 11 digits or a leading
  /// '+'), prefix '+' so the dialer treats it as international.
  String get _dialerNumber {
    final raw = widget.phone.trim();
    if (raw.startsWith('+')) return raw;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    // 10+ digits and no leading zero ⇒ already contains a country code.
    if (digits.length >= 10 && !digits.startsWith('0')) {
      return '+$digits';
    }
    return raw;
  }

  Future<void> _launch(Uri uri, BuildContext ctx, String errLabel) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && ctx.mounted) {
        AppSnackbar.show(ctx,
            type: AppSnackbarType.error, message: 'Could not open $errLabel');
      }
    } catch (_) {
      if (ctx.mounted) {
        AppSnackbar.show(ctx,
            type: AppSnackbarType.error, message: 'Could not open $errLabel');
      }
    }
  }

  Widget _avatar() {
    final url = _avatarUrl ?? '';
    final initial = widget.name.trim().isNotEmpty
        ? widget.name.trim()[0].toUpperCase()
        : '?';
    Widget fallback() => Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Text(initial,
              style: appText(
                  size: 22,
                  weight: FontWeight.w800,
                  color: AppColors.primaryDark)),
        );
    if (url.isEmpty) return fallback();
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback(),
        errorWidget: (_, __, ___) => fallback(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnNuru = _nuruUserId != null && _nuruUserId!.isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              _avatar(),
              const SizedBox(height: 10),
              Text(_nuruName?.isNotEmpty == true ? _nuruName! : widget.name,
                  style: appText(size: 16, weight: FontWeight.w800),
                  textAlign: TextAlign.center),
              const SizedBox(height: 2),
              Text(widget.phone,
                  style: appText(size: 12.5, color: AppColors.textTertiary)),
            ]),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F1F4)),
          _OptionTile(
            iconBg: const Color(0xFFFFF1F2),
            leading: Image.asset(
              'assets/images/nuru-logo-square.png',
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
            title: 'Nuru call',
            subtitle: _checking
                ? 'Checking if ${widget.name.split(' ').first} is on Nuru…'
                : isOnNuru
                    ? 'Free voice call inside Nuru'
                    : '${widget.name.split(' ').first} is not on Nuru yet',
            enabled: !_checking && isOnNuru,
            onTap: () {
              Navigator.pop(context);
              AppSnackbar.show(context,
                  type: AppSnackbarType.success,
                  message: 'Starting Nuru call…');
              // TODO: wire to CallsService.startCall when conversation_id is known.
            },
          ),
          const Divider(height: 1, color: Color(0xFFF1F1F4), indent: 70),
          _OptionTile(
            iconBg: const Color(0xFFE8F8EC),
            leading: SvgPicture.asset(
              'assets/icons/whatsapp-color.svg',
              width: 28,
              height: 28,
            ),
            title: 'WhatsApp',
            subtitle: 'Open chat in WhatsApp',
            onTap: () {
              Navigator.pop(context);
              _launch(Uri.parse('https://wa.me/$_waDigits'), context, 'WhatsApp');
            },
          ),
          const Divider(height: 1, color: Color(0xFFF1F1F4), indent: 70),
          _OptionTile(
            iconBg: const Color(0xFFEFF6FF),
            leading: SvgPicture.asset(
              'assets/icons/call-icon.svg',
              width: 24,
              height: 24,
            ),
            title: 'Phone call',
            subtitle: 'Dial using your phone',
            onTap: () {
              Navigator.pop(context);
              _launch(Uri(scheme: 'tel', path: _dialerNumber), context, 'dialer');
            },
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: appText(
                    size: 13,
                    weight: FontWeight.w700,
                    color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final Color iconBg;
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  const _OptionTile({
    required this.iconBg,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = enabled ? 1.0 : 0.55;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: opacity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: leading,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: appText(size: 14, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: appText(
                          size: 11.5, color: AppColors.textTertiary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textTertiary),
          ]),
        ),
      ),
    );
  }
}
