// PublicCardViewScreen - opens when the user taps a nuru.tz/cards/:id deep
// link (Android App Link / iOS Universal Link) or the nuru://cards/:id
// custom scheme. Loads the rendered thank-you card PNG from the backend's
// public endpoint and offers a download/share affordance.
import 'package:flutter/material.dart';
import 'package:nuru/core/services/api_service.dart';
import 'package:nuru/core/theme/app_colors.dart';

class PublicCardViewScreen extends StatelessWidget {
  final String cardId;
  const PublicCardViewScreen({super.key, required this.cardId});

  String get _imageUrl => '${ApiService.baseUrl}/cards/public/$cardId.png';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Thank-you card'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    _imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (ctx, child, p) => p == null
                        ? child
                        : const Padding(
                            padding: EdgeInsets.all(48),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                    errorBuilder: (ctx, _, __) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('This card is no longer available.'),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Plan Smarter. Celebrate Better.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
