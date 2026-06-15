import '../../core/widgets/nuru_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/services/nuru_cards_service.dart';
import '../../core/l10n/l10n_helper.dart';

class NuruCardsScreen extends StatefulWidget {
  const NuruCardsScreen({super.key});

  @override
  State<NuruCardsScreen> createState() => _NuruCardsScreenState();
}

class _NuruCardsScreenState extends State<NuruCardsScreen> {
  List<dynamic> _cards = [];
  List<dynamic> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      NuruCardsService.getMyCards(),
      NuruCardsService.getMyOrders(),
    ]);
    if (mounted) {
      setState(() {
        _loading = false;
        if (results[0]['success'] == true) {
          final data = results[0]['data'];
          _cards = data is List ? data : (data is Map ? (data['cards'] ?? []) : []);
        }
        if (results[1]['success'] == true) {
          final data = results[1]['data'];
          _orders = data is List ? data : (data is Map ? (data['orders'] ?? []) : []);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: NuruSubPageAppBar(title: context.tr('invitation_card')),
      body: NuruRefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _loading
            ? SkeletonGroup(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    SkeletonBox(height: 160, radius: 18),
                    SizedBox(height: 18),
                    SkeletonLine(widthFactor: 0.5, height: 14),
                    SizedBox(height: 14),
                    SkeletonListTile(padding: EdgeInsets.zero, trailing: true),
                    SkeletonListTile(padding: EdgeInsets.zero, trailing: true),
                    SkeletonListTile(padding: EdgeInsets.zero, trailing: true),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Hero section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.credit_card_rounded, size: 32, color: Colors.white),
                        const SizedBox(height: 12),
                        Text('Nuru Card', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2)),
                        const SizedBox(height: 6),
                        Text('Instant event check-ins and exclusive benefits',
                            style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withOpacity(0.8), height: 1.4)),
                        const SizedBox(height: 16),
                        if (_cards.isEmpty)
                          GestureDetector(
                            onTap: _showOrderDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                              child: Text('Order Your Card', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (_cards.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Your Cards', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    ..._cards.map((c) => _cardItem(c)),
                  ],

                  if (_orders.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Orders', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    ..._orders.map((o) => _orderItem(o)),
                  ],

                  // Features section
                  const SizedBox(height: 24),
                  Text('Card Benefits', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  _featureRow(Icons.flash_on_rounded, 'Instant Check-in', 'Skip queues with NFC tap'),
                  _featureRow(Icons.qr_code_rounded, 'QR Code', 'Unique code for every event'),
                  _featureRow(Icons.star_rounded, 'Premium Access', 'Exclusive VIP benefits'),
                  _featureRow(Icons.share_rounded, 'Digital Sharing', 'Share your profile instantly'),
                ],
              ),
      ),
    );
  }

  Widget _cardItem(dynamic card) {
    final c = card is Map<String, dynamic> ? card : <String, dynamic>{};
    final cardNumber = c['card_number']?.toString() ?? '****';
    final cardType = c['card_type']?.toString() ?? 'standard';
    final status = c['status']?.toString() ?? 'active';
    final isPremium = cardType.toLowerCase() == 'premium';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPremium ? const Color(0xFF1A1A2E) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: isPremium ? null : Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Icon(Icons.credit_card, size: 28, color: isPremium ? Colors.amber : AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${cardType.toUpperCase()} CARD', style: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1,
                    color: isPremium ? Colors.amber : AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(cardNumber, style: GoogleFonts.inter(fontSize: 14, color: isPremium ? Colors.white70 : AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'active' ? AppColors.successSoft : AppColors.errorSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(status, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600,
                color: status == 'active' ? AppColors.success : AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _orderItem(dynamic order) {
    final o = order is Map<String, dynamic> ? order : <String, dynamic>{};
    final type = o['type']?.toString() ?? 'standard';
    final status = o['status']?.toString() ?? 'pending';
    final createdAt = o['created_at']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${type.toUpperCase()} Card Order', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                if (createdAt.isNotEmpty)
                  Text(createdAt.split('T').first, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'delivered' ? AppColors.successSoft : AppColors.warningSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(status, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600,
                color: status == 'delivered' ? AppColors.success : AppColors.warning)),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.3)),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showOrderDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Order Nuru Card', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Text('Choose your card type to get started with instant event check-ins.',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(ctx);
              await NuruCardsService.orderCard({'type': 'standard', 'holder_name': '', 'payment_method': 'cash'});
              _load();
            },
            child: const Text('Order Standard'),
          ),
        ],
      ),
    );
  }
}
