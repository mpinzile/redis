import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/text_styles.dart';
import '../core/widgets/app_icon.dart';

/// A single action in [AppActionSheet].
class MenuAction<T> {
  final T value;
  final String label;
  final String? icon; // AppIcon name (e.g. 'pen', 'delete')
  final String? description;
  final bool destructive;
  final bool selected;
  final bool enabled;

  const MenuAction({
    required this.value,
    required this.label,
    this.icon,
    this.description,
    this.destructive = false,
    this.selected = false,
    this.enabled = true,
  });
}

/// Modern bottom-sheet action picker. Drop-in replacement for
/// PopupMenuButton - call [show] from any onTap and use the returned
/// value to drive the existing onSelected handler.
class AppActionSheet {
  AppActionSheet._();

  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    String? subtitle,
    required List<MenuAction<T>> actions,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => _ActionSheet<T>(
        title: title,
        subtitle: subtitle,
        actions: actions,
      ),
    );
  }
}

class _ActionSheet<T> extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final List<MenuAction<T>> actions;

  const _ActionSheet({this.title, this.subtitle, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            if (title != null) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title!,
                            style: appText(
                                size: 17, weight: FontWeight.w700),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: appText(
                                  size: 12,
                                  color: AppColors.textTertiary),
                            ),
                          ],
                        ],
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
            ],
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: Column(
                children: [
                  for (int i = 0; i < actions.length; i++) ...[
                    _ActionTile<T>(action: actions[i]),
                    if (i < actions.length - 1) const SizedBox(height: 2),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile<T> extends StatelessWidget {
  final MenuAction<T> action;
  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final destructive = action.destructive;
    final selected = action.selected;
    final disabled = !action.enabled;

    final fg = destructive
        ? AppColors.error
        : (disabled ? AppColors.textHint : AppColors.textPrimary);
    final iconFg = destructive
        ? AppColors.error
        : (disabled ? AppColors.textHint : AppColors.textSecondary);
    final bg = destructive
        ? AppColors.errorSoft
        : (selected ? AppColors.primarySoft : Colors.transparent);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: disabled
            ? null
            : () => Navigator.of(context).pop(action.value),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              if (action.icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: destructive
                        ? AppColors.error.withOpacity(0.10)
                        : (selected
                            ? AppColors.primary.withOpacity(0.12)
                            : Colors.white),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: AppIcon(action.icon!, size: 18, color: iconFg),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action.label,
                      style: appText(
                          size: 14,
                          weight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                          color: fg),
                    ),
                    if (action.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        action.description!,
                        style: appText(
                            size: 12, color: AppColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: AppIcon('check',
                      size: 20, color: AppColors.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
