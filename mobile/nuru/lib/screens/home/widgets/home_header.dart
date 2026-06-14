import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/l10n/l10n_helper.dart';

class HomeHeader extends StatelessWidget {
  final String name;
  final String? avatar;
  final int unreadNotifications;
  final VoidCallback onMenuTap;
  final VoidCallback onSearchTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onRightPanelTap;
  final VoidCallback onProfileTap;
  final String? title;

  /// Optional "Create moment" action shown immediately after the search icon.
  /// When null the button is hidden so other tabs aren't affected.
  final VoidCallback? onMomentTap;
  final bool momentActive;

  const HomeHeader({
    super.key,
    required this.name,
    this.avatar,
    this.unreadNotifications = 0,
    required this.onMenuTap,
    required this.onSearchTap,
    required this.onNotificationsTap,
    required this.onRightPanelTap,
    required this.onProfileTap,
    this.title,
    this.onMomentTap,
    this.momentActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(
        top: topPadding + 8,
        left: 16,
        right: 16,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            _iconButton('assets/icons/menu-icon.svg', onMenuTap),
            const SizedBox(width: 12),
            if (title != null)
              Expanded(
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
              )
            else ...[
              Transform.translate(
                offset: const Offset(-15, -1),
                child: Image.asset(
                  'assets/images/nuru-logo.png',
                  height: 44,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/nuru-logo-square.png',
                    height: 44,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const Spacer(),
            ],
            _iconButton('assets/icons/search-icon.svg', onSearchTap),
            const SizedBox(width: 6),
            if (onMomentTap != null) ...[
              _iconButton(
                momentActive
                    ? 'assets/icons/close-circle-icon.svg'
                    : 'assets/icons/pen-icon.svg',
                onMomentTap!,
              ),
              const SizedBox(width: 6),
            ],
            _iconButton(
              'assets/icons/bell-icon.svg',
              onNotificationsTap,
              badge: unreadNotifications,
            ),
            const SizedBox(width: 6),
            _iconButton('assets/icons/panel-right-icon.svg', onRightPanelTap),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(String svgAsset, VoidCallback onTap, {int badge = 0}) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: SvgPicture.asset(
                svgAsset,
                width: 22,
                height: 22,
                colorFilter: const ColorFilter.mode(
                  AppColors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              top: 6,
              right: 4,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: Center(
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
