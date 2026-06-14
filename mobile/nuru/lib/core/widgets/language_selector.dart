import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/locale_provider.dart';
import '../theme/app_colors.dart';
import '../../core/l10n/l10n_helper.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Modern segmented language toggle - premium pill with sliding indicator.
class LanguageToggle extends StatelessWidget {
  final bool showLabel;
  final double size;

  const LanguageToggle({super.key, this.showLabel = true, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final isEn = locale.isEnglish;

    const double segW = 40;
    const double segH = 30;
    const double pad = 3;

    return Container(
      padding: const EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.9),
            blurRadius: 0,
            spreadRadius: 1.5,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Row sets the Stack's size so the AnimatedPositioned has room to slide.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: segW, height: segH),
              SizedBox(width: segW, height: segH),
            ],
          ),
          // Sliding indicator - animates between EN and SW slots.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: isEn ? 0 : segW,
            top: 0,
            child: IgnorePointer(
              child: Container(
                width: segW,
                height: segH,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.30),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Tappable labels on top of the indicator.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _seg(label: 'EN', active: isEn,
                  onTap: () => locale.setLocale('en'),
                  width: segW, height: segH),
              _seg(label: 'SW', active: !isEn,
                  onTap: () => locale.setLocale('sw'),
                  width: segW, height: segH),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seg({
    required String label,
    required bool active,
    required VoidCallback onTap,
    required double width,
    required double height,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          width: width,
          height: height,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: active ? Colors.white : AppColors.primary,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full language selector card for settings
class LanguageSettingsCard extends StatelessWidget {
  const LanguageSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    'assets/icons/language-icon.svg',
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
                      context.tr('language'),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locale.isEnglish ? 'English' : 'Kiswahili',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _LanguageOption(
                  flag: '🇬🇧',
                  label: 'English',
                  selected: locale.isEnglish,
                  onTap: () => locale.setLocale('en'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LanguageOption(
                  flag: '🇹🇿',
                  label: 'Kiswahili',
                  selected: locale.isSwahili,
                  onTap: () => locale.setLocale('sw'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String flag;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.flag,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle, size: 16, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }
}
