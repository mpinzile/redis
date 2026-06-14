import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/text_styles.dart';
import '../core/widgets/app_icon.dart';
import '../core/widgets/nuru_search_bar.dart';

/// A single option in [AppSelect].
class AppSelectOption<T> {
  final T value;
  final Widget label;
  final String? searchText;
  final Widget? leading;
  final Widget? subtitle;
  final bool enabled;

  const AppSelectOption({
    required this.value,
    required this.label,
    this.searchText,
    this.leading,
    this.subtitle,
    this.enabled = true,
  });
}

/// Modern, reusable select input. Renders as a text-input style trigger and
/// opens a polished bottom-sheet picker with optional search.
///
/// Drop-in replacement for `DropdownButton`/`DropdownButtonFormField` -
/// preserves value/onChanged semantics so behaviour is unchanged.
class AppSelect<T> extends StatelessWidget {
  final T? value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final String? title;
  final bool enabled;
  final bool searchable;
  final EdgeInsetsGeometry? contentPadding;
  final double borderRadius;
  final Color? fillColor;
  final Color? borderColor;
  final double fontSize;
  final IconData? leadingIcon;

  const AppSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
    this.title,
    this.enabled = true,
    this.searchable = false,
    this.contentPadding,
    this.borderRadius = 12,
    this.fillColor,
    this.borderColor,
    this.fontSize = 14,
    this.leadingIcon,
  });

  /// Compatibility constructor - accepts the same `List<DropdownMenuItem<T>>`
  /// already used across the codebase. Lets us swap existing call sites
  /// without rewriting the items list.
  static AppSelect<T> fromItems<T>({
    Key? key,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    String? hint,
    String? title,
    bool enabled = true,
    bool searchable = false,
    EdgeInsetsGeometry? contentPadding,
    double borderRadius = 12,
    Color? fillColor,
    Color? borderColor,
    double fontSize = 14,
    IconData? leadingIcon,
  }) {
    final opts = items
        .where((i) => i.value != null)
        .map((i) => AppSelectOption<T>(
              value: i.value as T,
              label: i.child,
              searchText: _extractText(i.child),
              enabled: i.enabled,
            ))
        .toList();
    return AppSelect<T>(
      key: key,
      value: value,
      options: opts,
      onChanged: onChanged,
      hint: hint,
      title: title,
      enabled: enabled,
      searchable: searchable,
      contentPadding: contentPadding,
      borderRadius: borderRadius,
      fillColor: fillColor,
      borderColor: borderColor,
      fontSize: fontSize,
      leadingIcon: leadingIcon,
    );
  }

  static String? _extractText(Widget w) {
    if (w is Text) return w.data;
    if (w is RichText) return w.text.toPlainText();
    return null;
  }

  AppSelectOption<T>? get _selected {
    for (final o in options) {
      if (o.value == value) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final disabled = !enabled || onChanged == null;

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: disabled ? null : () => _openPicker(context),
          child: Container(
            padding: contentPadding ??
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: fillColor ?? Colors.white,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? AppColors.borderLight,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 18, color: AppColors.textTertiary),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: selected != null
                      ? DefaultTextStyle.merge(
                          style: appText(
                              size: fontSize,
                              weight: FontWeight.w600,
                              color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          child: selected.label,
                        )
                      : Text(
                          hint ?? 'Select',
                          style: appText(
                              size: fontSize, color: AppColors.textHint),
                        ),
                ),
                const SizedBox(width: 8),
                const AppIcon('chevron-down',
                    size: 20, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<_PickResult<T>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => _AppSelectSheet<T>(
        title: title ?? hint ?? 'Select',
        options: options,
        currentValue: value,
        searchable: searchable || options.length > 8,
      ),
    );
    if (picked != null && onChanged != null) {
      onChanged!(picked.value);
    }
  }
}

class _PickResult<T> {
  final T? value;
  const _PickResult(this.value);
}

class _AppSelectSheet<T> extends StatefulWidget {
  final String title;
  final List<AppSelectOption<T>> options;
  final T? currentValue;
  final bool searchable;

  const _AppSelectSheet({
    required this.title,
    required this.options,
    required this.currentValue,
    required this.searchable,
  });

  @override
  State<_AppSelectSheet<T>> createState() => _AppSelectSheetState<T>();
}

class _AppSelectSheetState<T> extends State<_AppSelectSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.trim().isEmpty
        ? widget.options
        : widget.options.where((o) {
            final s = (o.searchText ?? '').toLowerCase();
            return s.contains(_query.trim().toLowerCase());
          }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: widget.options.length > 6 ? 0.65 : 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: appText(size: 17, weight: FontWeight.w700),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: const AppIcon('close',
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.searchable) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: NuruSearchBar(
                  hintText: 'Search...',
                  debounce: Duration.zero,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matches',
                        style: appText(
                            size: 13, color: AppColors.textTertiary),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (_, i) {
                        final o = filtered[i];
                        final isSelected = o.value == widget.currentValue;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: o.enabled
                                ? () => Navigator.of(context)
                                    .pop(_PickResult<T>(o.value))
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primarySoft
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  if (o.leading != null) ...[
                                    o.leading!,
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        DefaultTextStyle.merge(
                                          style: appText(
                                              size: 14,
                                              weight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                              color: AppColors.textPrimary),
                                          child: o.label,
                                        ),
                                        if (o.subtitle != null) ...[
                                          const SizedBox(height: 2),
                                          DefaultTextStyle.merge(
                                            style: appText(
                                                size: 12,
                                                color:
                                                    AppColors.textTertiary),
                                            child: o.subtitle!,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const AppIcon('check',
                                        size: 20, color: AppColors.primary),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
