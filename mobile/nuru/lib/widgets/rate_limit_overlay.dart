import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/rate_limit_notifier.dart';

/// Mount once at the root of the app. Listens to [RateLimitNotifier.instance]
/// and shows a friendly modal with a live countdown when a 429 hits.
class RateLimitOverlay extends StatefulWidget {
  final Widget child;
  const RateLimitOverlay({super.key, required this.child});

  @override
  State<RateLimitOverlay> createState() => _RateLimitOverlayState();
}

class _RateLimitOverlayState extends State<RateLimitOverlay> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    RateLimitNotifier.instance.addListener(_onEvent);
  }

  @override
  void dispose() {
    RateLimitNotifier.instance.removeListener(_onEvent);
    super.dispose();
  }

  void _onEvent() {
    final ev = RateLimitNotifier.instance.value;
    if (ev == null || _showing || !mounted) return;
    _showing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RateLimitDialog(event: ev),
    ).whenComplete(() {
      _showing = false;
      RateLimitNotifier.instance.clear();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RateLimitDialog extends StatefulWidget {
  final RateLimitEvent event;
  const _RateLimitDialog({required this.event});

  @override
  State<_RateLimitDialog> createState() => _RateLimitDialogState();
}

class _RateLimitDialogState extends State<_RateLimitDialog> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.event.retryAfterSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) _remaining--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(int s) {
    if (s <= 0) return '0s';
    final m = s ~/ 60;
    final sec = s % 60;
    if (m > 0) return '${m}m ${sec.toString().padLeft(2, '0')}s';
    return '${sec}s';
  }

  @override
  Widget build(BuildContext context) {
    final canRetry = _remaining == 0;
    final isAuth = widget.event.isAuth;
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: cs.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isAuth ? Icons.shield_outlined : Icons.hourglass_top_rounded,
                color: cs.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isAuth ? 'Hold on a moment' : "You're going a bit fast",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.event.message ??
                  (isAuth
                      ? "You're making sign-in attempts too quickly. We've temporarily limited access to protect your account."
                      : "You're making requests too quickly. We've temporarily limited access to protect your data."),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        canRetry ? 'You can try again now' : 'Try again in',
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  Text(
                    canRetry ? '-' : _format(_remaining),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canRetry ? () => Navigator.of(context).pop() : null,
                child: Text(canRetry ? 'Continue' : 'Please wait…'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'This protects everyone on Nuru from abuse. Thanks for your patience.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
