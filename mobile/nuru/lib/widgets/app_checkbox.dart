import 'package:flutter/material.dart';
import '../core/widgets/app_icon.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/text_styles.dart';

/// Modern, reusable checkbox tile. Drop-in replacement for
/// `CheckboxListTile` - same value/onChanged semantics but with a
/// custom-painted check, no Material baggage, and a polished
/// title/description layout.
class AppCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? description;
  final Widget? title;
  final Widget? subtitle;
  final bool enabled;
  final EdgeInsetsGeometry padding;
  final bool dense;

  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.title,
    this.subtitle,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
    this.dense = false,
  });

  /// Standalone box (no label) - useful inside compact rows.
  factory AppCheckbox.box({
    Key? key,
    required bool value,
    required ValueChanged<bool>? onChanged,
    bool enabled = true,
  }) =>
      AppCheckbox(
        key: key,
        value: value,
        onChanged: onChanged,
        enabled: enabled,
        padding: EdgeInsets.zero,
      );

  @override
  Widget build(BuildContext context) {
    final disabled = !enabled || onChanged == null;
    final box = _CheckBox(checked: value, disabled: disabled);

    if (title == null && (label ?? '').isEmpty && subtitle == null && (description ?? '').isEmpty) {
      // Box-only variant
      return Opacity(
        opacity: disabled ? 0.45 : 1,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : () => onChanged!(!value),
          child: Padding(padding: padding, child: box),
        ),
      );
    }

    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: disabled ? null : () => onChanged!(!value),
        child: Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: dense ? 1 : 2),
                child: box,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title ??
                        Text(
                          label ?? '',
                          style: appText(
                              size: dense ? 13 : 14,
                              weight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                        style: appText(
                            size: dense ? 11 : 12,
                            color: AppColors.textTertiary),
                        child: subtitle!,
                      ),
                    ] else if ((description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: appText(
                            size: dense ? 11 : 12,
                            color: AppColors.textTertiary,
                            height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  final bool checked;
  final bool disabled;
  const _CheckBox({required this.checked, required this.disabled});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked
              ? AppColors.primary
              : (disabled ? AppColors.border : AppColors.borderLight),
          width: 1.5,
        ),
      ),
      child: checked ? const AppIcon('check', size: 14, color: Colors.white) : null,
    );
  }
}
