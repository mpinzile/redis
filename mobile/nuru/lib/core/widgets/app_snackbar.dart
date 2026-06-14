import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Modern, reusable feedback snackbar for the Nuru app.
///
/// Renders bottom feedback (success/error/warning/info) as a single,
/// premium card with an icon, optional strong title, a clear message,
/// optional action button (e.g. "Pay now", "Try again", "View details"),
/// safe-area handling on Android & iOS, smooth animations and manual dismiss.
///
/// Two API levels:
///   1. Legacy one-liner: `AppSnackbar.error(context, 'msg')` - still works.
///   2. Rich:             `AppSnackbar.show(context, type: ..., title: ..., message: ..., actionLabel: ..., onAction: ...)`.
class AppSnackbar {
  // ── Legacy API (kept for backward compatibility) ─────────────────────
  static void error(BuildContext context, String msg) =>
      show(context, type: AppSnackbarType.error, message: msg);

  static void success(BuildContext context, String msg) =>
      show(context, type: AppSnackbarType.success, message: msg);

  static void info(BuildContext context, String msg) =>
      show(context, type: AppSnackbarType.info, message: msg);

  static void warning(BuildContext context, String msg) =>
      show(context, type: AppSnackbarType.warning, message: msg);

  // ── Rich API ─────────────────────────────────────────────────────────
  static void show(
    BuildContext context, {
    required AppSnackbarType type,
    String? title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();

    final effectiveDuration = duration ??
        (actionLabel != null
            ? const Duration(seconds: 6)
            : type == AppSnackbarType.error
                ? const Duration(seconds: 4)
                : const Duration(seconds: 3));

    messenger.showSnackBar(
      SnackBar(
        content: _AppSnackbarContent(
          type: type,
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: () {
            messenger.hideCurrentSnackBar();
            onAction?.call();
          },
          onDismiss: () => messenger.hideCurrentSnackBar(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        duration: effectiveDuration,
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }
}

enum AppSnackbarType { success, error, warning, info }

class _AppSnackbarContent extends StatelessWidget {
  final AppSnackbarType type;
  final String? title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  const _AppSnackbarContent({
    required this.type,
    required this.message,
    required this.onDismiss,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  _Style get _style {
    switch (type) {
      case AppSnackbarType.success:
        return const _Style(
          accent: AppColors.success,
          icon: Icons.check_circle_rounded,
          fallbackTitle: 'Success',
        );
      case AppSnackbarType.error:
        return const _Style(
          accent: AppColors.error,
          icon: Icons.error_rounded,
          fallbackTitle: 'Something went wrong',
        );
      case AppSnackbarType.warning:
        return _Style(
          accent: const Color(0xFFD97706), // amber-600 - readable on white
          icon: Icons.warning_rounded,
          fallbackTitle: 'Heads up',
        );
      case AppSnackbarType.info:
        return const _Style(
          accent: AppColors.info,
          icon: Icons.info_rounded,
          fallbackTitle: 'Notice',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final hasTitle = (title ?? '').trim().isNotEmpty;
    final hasAction = (actionLabel ?? '').trim().isNotEmpty && onAction != null;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.zero,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) {
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 16),
              child: child,
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56, maxWidth: 560),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE9EBF1)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left accent stripe - subtle status indicator.
                    Container(width: 4, color: s.accent),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          12,
                          hasAction ? 8 : 8,
                          12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Icon chip
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: s.accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Icon(s.icon, size: 18, color: s.accent),
                            ),
                            const SizedBox(width: 12),
                            // Text block
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    hasTitle ? title! : s.fallbackTitle,
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    message,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                  if (hasAction) ...[
                                    const SizedBox(height: 10),
                                    _ActionButton(
                                      label: actionLabel!,
                                      color: s.accent,
                                      onTap: onAction!,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Manual dismiss
                            _DismissButton(onTap: onDismiss),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Style {
  final Color accent;
  final IconData icon;
  final String fallbackTitle;
  const _Style({
    required this.accent,
    required this.icon,
    required this.fallbackTitle,
  });
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.1,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DismissButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
      ),
    );
  }
}
