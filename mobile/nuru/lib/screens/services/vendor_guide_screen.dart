import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../core/widgets/app_icon.dart';

/// Vendor Guide — modern step-by-step explainer reached from the
/// "View Guide" button on the Find / Saved Vendors screen.
///
/// Renders a real skeleton while the static guide content "loads" so the
/// transition matches the rest of the app's data-loading screens.
class VendorGuideScreen extends StatefulWidget {
  const VendorGuideScreen({super.key});

  @override
  State<VendorGuideScreen> createState() => _VendorGuideScreenState();
}

class _VendorGuideScreenState extends State<VendorGuideScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Brief delay so the skeleton is visibly meaningful instead of a flash.
    Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  TextStyle _f({double size = 14, FontWeight weight = FontWeight.w500,
      Color color = AppColors.textPrimary, double height = 1.35}) {
    return GoogleFonts.inter(
      fontSize: size, fontWeight: weight, color: color, height: height);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const AppIcon('arrow-left', size: 22, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Vendor Guide',
          style: _f(size: 16, weight: FontWeight.w800)),
      ),
      body: _loading ? _skeleton() : _content(),
    );
  }

  // ─── Loading skeleton ────────────────────────────────────────────────
  Widget _skeleton() {
    return NuruSkeletonGroup(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          NuruSkeleton.box(height: 120, radius: 18),
          const SizedBox(height: 18),
          NuruSkeleton.text(width: 180, height: 16),
          const SizedBox(height: 14),
          for (int i = 0; i < 5; i++) ...[
            _stepSkeleton(),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 18),
          NuruSkeleton.box(height: 78, radius: 14),
        ],
      ),
    );
  }

  Widget _stepSkeleton() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NuruSkeleton.circle(size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NuruSkeleton.text(width: 140, height: 13),
                const SizedBox(height: 8),
                NuruSkeleton.text(width: double.infinity, height: 10),
                const SizedBox(height: 6),
                NuruSkeleton.text(width: 220, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Real content ────────────────────────────────────────────────────
  Widget _content() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        _hero(),
        const SizedBox(height: 20),
        Text('How it works',
          style: _f(size: 13, weight: FontWeight.w800,
            color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        ..._steps.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _stepCard(index: e.key + 1, step: e.value),
        )),
        const SizedBox(height: 18),
        _safetyCard(),
        const SizedBox(height: 14),
        _faqCard(),
      ],
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: AppIcon('verified', size: 28, color: Colors.black),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hire vendors with confidence',
                  style: _f(size: 16, weight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Nuru protects your money with escrow and only releases it once you confirm the service. Here is how a complete booking works, end to end.',
                  style: _f(size: 12, color: AppColors.textSecondary, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCard({required int index, required _Step step}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: step.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: AppIcon(step.iconName, size: 20, color: step.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F3F6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Step $index',
                        style: _f(size: 10, weight: FontWeight.w700,
                          color: AppColors.textTertiary)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(step.title,
                        style: _f(size: 14, weight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(step.body,
                  style: _f(size: 12, color: AppColors.textSecondary, height: 1.5)),
                if (step.tips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...step.tips.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5, right: 8),
                          child: Container(
                            width: 5, height: 5,
                            decoration: BoxDecoration(
                              color: step.accent, shape: BoxShape.circle),
                          ),
                        ),
                        Expanded(
                          child: Text(t,
                            style: _f(size: 11.5,
                              color: AppColors.textSecondary, height: 1.45)),
                        ),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _safetyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1C40),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const AppIcon('shield', size: 22, color: Color(0xFF71E07E)),
            const SizedBox(width: 10),
            Text('Stay protected',
              style: _f(size: 14, weight: FontWeight.w800, color: Colors.white)),
          ]),
          const SizedBox(height: 10),
          _bullet('Keep all conversations inside Nuru chat so we can help if something goes wrong.', Colors.white70),
          _bullet('Never pay outside the app. Funds held in escrow are only released after you confirm.', Colors.white70),
          _bullet('If a vendor cancels or no-shows, request a refund and escrow is reversed in full.', Colors.white70),
        ],
      ),
    );
  }

  Widget _bullet(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 6, right: 8),
          child: AppIcon('check', size: 12, color: Color(0xFF71E07E)),
        ),
        Expanded(child: Text(text, style: _f(size: 12, color: color, height: 1.45))),
      ]),
    );
  }

  Widget _faqCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: _faqs.map((q) => Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            title: Text(q.q, style: _f(size: 13, weight: FontWeight.w700)),
            iconColor: AppColors.textSecondary,
            collapsedIconColor: AppColors.textSecondary,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(q.a, style: _f(size: 12,
                  color: AppColors.textSecondary, height: 1.5)),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  // ─── Static content ──────────────────────────────────────────────────
  static final List<_Step> _steps = const [
    _Step(
      iconName: 'search',
      accent: Color(0xFF2471E7),
      title: 'Find the right vendor',
      body: 'Browse vendors by category, location and price. Save your favourites with the bookmark icon. They show up under Saved Vendors.',
      tips: [
        'Filter by your event date to see who is available.',
        'Tap a vendor to view their portfolio, packages and reviews.',
      ],
    ),
    _Step(
      iconName: 'chat',
      accent: Color(0xFFE7A622),
      title: 'Chat before you book',
      body: 'Open the vendor profile and tap "Message" to discuss details, ask for quotes and confirm what is included.',
      tips: [
        'All chats stay inside Nuru so you have a record.',
        'You can share images, voice notes and pin a quoted price.',
      ],
    ),
    _Step(
      iconName: 'event-calendar-check',
      accent: Color(0xFF71E07E),
      title: 'Send a booking request',
      body: 'Tap "Book" on the package you want, pick the event date, add any notes, and submit. The vendor reviews and either accepts or sends a quote.',
      tips: [
        'You can attach the request to an existing event so it lives on the event timeline.',
        'You will get a push notification when the vendor responds.',
      ],
    ),
    _Step(
      iconName: 'lock',
      accent: Color(0xFF6E59F2),
      title: 'Confirm and pay into escrow',
      body: 'When you accept the quote, your payment is held safely by Nuru escrow. The vendor sees the booking is funded but cannot withdraw yet.',
      tips: [
        'Pay with M-Pesa, Tigo Pesa, Airtel Money, Halo Pesa or bank card.',
        'You can split a deposit now and the balance later if the vendor allows it.',
      ],
    ),
    _Step(
      iconName: 'money',
      accent: Color(0xFFE7A622),
      title: 'Log offline payments (optional)',
      body: 'If you ever pay a vendor outside Nuru (cash, direct deposit), open the booking and tap "Log offline payment". The vendor receives an OTP and must confirm receipt before it is recorded.',
      tips: [
        'Offline payments do not pass through escrow, so confirm only what you really paid.',
        'Vendors confirm by entering the SMS code, so both sides keep an honest record.',
      ],
    ),
    _Step(
      iconName: 'check',
      accent: Color(0xFF71E07E),
      title: 'Confirm service delivered',
      body: 'After the event, open the booking and tap "Confirm delivery". Escrow is released to the vendor and you are asked to leave a review.',
      tips: [
        'If anything went wrong, tap "Report issue" instead — funds stay frozen while support reviews.',
        'Reviews help other organisers choose great vendors.',
      ],
    ),
    _Step(
      iconName: 'wallet',
      accent: Color(0xFF2471E7),
      title: 'Vendors receive payment',
      body: 'Released funds land in the vendor wallet instantly. They can withdraw to mobile money or bank from the Wallet tab.',
      tips: [
        'Nuru deducts a small service fee from each payout, visible before withdrawal.',
        'A full statement is available under Wallet → Transactions.',
      ],
    ),
  ];

  static final List<_Faq> _faqs = const [
    _Faq(
      q: 'What happens if a vendor cancels?',
      a: 'Escrow is automatically reversed in full and the money returns to your wallet within minutes. You can then book another vendor.',
    ),
    _Faq(
      q: 'Can I negotiate the price?',
      a: 'Yes. Message the vendor first to agree on a custom quote. When they send it, you will see a "Pay quote" button to fund escrow.',
    ),
    _Faq(
      q: 'How do I know a vendor is real?',
      a: 'Verified vendors carry a blue tick. We check their ID, business details and bank/mobile money before approving them.',
    ),
    _Faq(
      q: 'What if I paid offline and the vendor does not confirm?',
      a: 'The offline payment stays in "Pending" and is not recorded against the booking. Contact support if you need help reconciling.',
    ),
  ];
}

class _Step {
  final String iconName;
  final Color accent;
  final String title;
  final String body;
  final List<String> tips;
  const _Step({
    required this.iconName,
    required this.accent,
    required this.title,
    required this.body,
    this.tips = const [],
  });
}

class _Faq {
  final String q;
  final String a;
  const _Faq({required this.q, required this.a});
}
