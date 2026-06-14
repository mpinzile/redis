import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/app_colors.dart';

/// Global "love" icon used everywhere a user can like / glow content.
///
/// Backed by `assets/icons/love-icon.svg`. Because the SVG uses
/// `currentColor` via `colorFilter`, we can both stroke (outline) and fill
/// (active) the same path - keeping a single consistent shape for the entire
/// product.
class LoveIcon extends StatelessWidget {
  final bool active;
  final double size;
  final Color? activeColor;
  final Color? inactiveColor;

  const LoveIcon({
    super.key,
    this.active = false,
    this.size = 22,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? (activeColor ?? AppColors.primary)
        : (inactiveColor ?? AppColors.textSecondary);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (active)
            // Filled background heart
            SvgPicture.asset(
              'assets/icons/love-icon.svg',
              width: size,
              height: size,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
          // Outline stroke (always visible - gives the emoji-style love look)
          SvgPicture.asset(
            'assets/icons/love-icon.svg',
            width: size,
            height: size,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ],
      ),
    );
  }
}
