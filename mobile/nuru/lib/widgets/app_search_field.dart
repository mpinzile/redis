import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/app_icon.dart';

/// AppSearchField - the canonical search input used across the app.
/// Matches the "Search conversations" aesthetic: soft surface bg, rounded,
/// custom SVG search icon, optional clear button.
class AppSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool loading;
  final VoidCallback? onClear;

  const AppSearchField({
    super.key,
    this.controller,
    this.hint = 'Search...',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.loading = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = (controller?.text ?? '').isNotEmpty;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        autocorrect: false,
        style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textHint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: SvgPicture.asset(
              'assets/icons/search-icon.svg',
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                  AppColors.textHint, BlendMode.srcIn),
            ),
          ),
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                )
              : (hasText && onClear != null)
                  ? IconButton(
                      icon: const AppIcon('close',
                          size: 18, color: AppColors.textTertiary),
                      onPressed: onClear,
                    )
                  : null,
        ),
      ),
    );
  }
}
