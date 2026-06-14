import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Floating label field - consistent Plus Jakarta Sans
class AuthTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final IconData? prefixIcon;
  /// Optional SVG asset path used as a prefix icon (preferred over [prefixIcon]).
  final String? prefixSvg;
  final bool obscureText;
  final Widget? suffixIcon;
  /// When true, shows a green check inline at the end of the input
  /// (combined with [suffixIcon] if provided).
  final bool showSuccessTick;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.prefixIcon,
    this.prefixSvg,
    this.obscureText = false,
    this.suffixIcon,
    this.showSuccessTick = false,
    this.keyboardType,
    this.validator,
    this.inputFormatters,
    this.maxLength,
    this.autofocus = false,
    this.onChanged,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _focused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _focused ? AppColors.primary : AppColors.textSecondary,
            height: 1.2,
            letterSpacing: 0.1,
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(widget.label),
          ),
        ),

        // Field - premium: subtle gradient border on focus, soft shadow lift
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: _focused
                ? LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.10),
                      AppColors.primary.withOpacity(0.02),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: _focused ? null : Colors.white,
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.18),
                      blurRadius: 24,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.035),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          padding: const EdgeInsets.all(1.5),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.5),
            ),
            child: TextFormField(
              controller: widget.controller,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              validator: widget.validator,
              inputFormatters: widget.inputFormatters,
              maxLength: widget.maxLength,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              cursorColor: AppColors.primary,
              cursorWidth: 1.6,
              cursorRadius: const Radius.circular(2),
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
              onTap: () => setState(() => _focused = true),
              onEditingComplete: () => setState(() => _focused = false),
              onTapOutside: (_) {
                setState(() => _focused = false);
                FocusScope.of(context).unfocus();
              },
              decoration: InputDecoration(
                hintText: widget.hintText ?? widget.label,
                counterText: '',
                prefixIcon: (widget.prefixSvg != null || widget.prefixIcon != null)
                    ? Padding(
                        padding: const EdgeInsets.only(left: 18, right: 12),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: widget.prefixSvg != null
                              ? SvgPicture.asset(
                                  widget.prefixSvg!,
                                  key: ValueKey('${widget.prefixSvg}-$_focused'),
                                  width: 20,
                                  height: 20,
                                  colorFilter: ColorFilter.mode(
                                    _focused ? AppColors.primary : AppColors.textHint,
                                    BlendMode.srcIn,
                                  ),
                                )
                              : Icon(
                                  widget.prefixIcon,
                                  key: ValueKey(_focused),
                                  size: 20,
                                  color: _focused
                                      ? AppColors.primary
                                      : AppColors.textHint,
                                ),
                        ),
                      )
                    : null,
                prefixIconConstraints: (widget.prefixSvg != null || widget.prefixIcon != null)
                    ? const BoxConstraints(minWidth: 50)
                    : null,
                suffixIcon: widget.showSuccessTick
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.suffixIcon != null) widget.suffixIcon!,
                          Padding(
                            padding: EdgeInsets.only(
                              left: widget.suffixIcon != null ? 0 : 8,
                              right: 14,
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: Color(0xFF2BA84A),
                            ),
                          ),
                        ],
                      )
                    : widget.suffixIcon,
                filled: true,
                fillColor: Colors.white,
                hintStyle: GoogleFonts.inter(
                  color: AppColors.textHint,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
                errorStyle: GoogleFonts.inter(
                  color: AppColors.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: (widget.prefixSvg != null || widget.prefixIcon != null) ? 0 : 20,
                  vertical: 18,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.5),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.5),
                  borderSide: BorderSide(
                    color: const Color(0xFFE5E7EB),
                    width: 1.2,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.5),
                  borderSide: BorderSide.none,
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.5),
                  borderSide: const BorderSide(
                      color: AppColors.error, width: 1.2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.5),
                  borderSide: const BorderSide(
                      color: AppColors.error, width: 1.6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
