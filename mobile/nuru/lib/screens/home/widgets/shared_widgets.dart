import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Section header - clean, minimal
class SectionHeader extends StatelessWidget {
  final String title;
  final String? count;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AppColors.textPrimary),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.3, height: 1.2)),
        ),
        if (count != null && count != '0') ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(count!, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary, height: 1.0)),
          ),
        ],
        if (onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel ?? 'See all',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600, height: 1.2),
            ),
          ),
      ],
    );
  }
}

/// Empty state - clean, modern. Pass [iconAsset] to render a Nuru SVG icon
/// from `assets/icons/` (preferred); falls back to the Material [icon] if no
/// asset is supplied. Keeps legacy callers compiling.
class EmptyState extends StatelessWidget {
  final IconData? icon;
  final String? iconAsset;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    this.icon,
    this.iconAsset,
    required this.title,
    required this.subtitle,
    this.action,
  }) : assert(icon != null || iconAsset != null,
            'Provide either icon or iconAsset');

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: iconAsset != null
                  ? SvgPicture.asset(
                      iconAsset!,
                      width: 30,
                      height: 30,
                      colorFilter: const ColorFilter.mode(
                          AppColors.primary, BlendMode.srcIn),
                    )
                  : Icon(icon, size: 30, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.3),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

/// Shimmer loading card
class ShimmerCard extends StatefulWidget {
  final double height;
  const ShimmerCard({super.key, this.height = 200});

  @override
  State<ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight, width: 1),
          ),
          child: ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
                end: Alignment(-0.5 + 2.0 * _ctrl.value, 0),
                colors: [
                  AppColors.surfaceVariant,
                  AppColors.surfaceMuted,
                  AppColors.surfaceVariant,
                ],
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcATop,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: widget.height * 0.5,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 12,
                          width: 140,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 10,
                          width: 90,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
