/// Minimal public read-only landing for deep links whose dedicated mobile
/// screen has not been built yet. Honours the audit rule: "do not silently
/// redirect deep links to home". Shows what the user opened plus two CTAs:
///   - Open in browser (always works, hits the live web page)
///   - Sign in to continue (jumps to auth, preserves the original link as
///     a `redirect` query param so we can resume after login later)
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';

class DeepLinkPlaceholderScreen extends StatelessWidget {
  final String kind;        // 'ticket', 'rsvp', 'invitation', 'post', 'moment'
  final String identifier;  // code / id / token
  final String webPath;     // e.g. /rsvp/ABC123 - used for "Open in browser"

  const DeepLinkPlaceholderScreen({
    super.key,
    required this.kind,
    required this.identifier,
    required this.webPath,
  });

  Future<void> _openInBrowser() async {
    final uri = Uri.parse('https://nuru.tz$webPath');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String get _title {
    switch (kind) {
      case 'ticket':     return 'Ticket';
      case 'rsvp':       return 'RSVP';
      case 'invitation': return 'Invitation';
      case 'post':       return 'Post';
      case 'moment':     return 'Moment';
      default:           return 'Open link';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(_title), elevation: 0, backgroundColor: AppColors.surface),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Reference: $identifier',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            Text(
              'This page is not yet available natively in the app. You can still open it in your browser.',
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _openInBrowser,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Open in browser'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Go to home'),
            ),
          ],
        ),
      ),
    );
  }
}
