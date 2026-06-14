import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import 'ai_assistant_screen.dart';
import 'live_chat_screen.dart';

/// One generic, premium help-guide screen reused for every Browse Category
/// (Getting Started, Account Settings, Payments & Contributions, Events &
/// Tickets, Safety & Privacy). Renders a hero header, numbered step cards
/// and a "still need help" footer.
class HelpCategoryScreen extends StatelessWidget {
  final String iconAsset;
  final String title;
  final String tagline;
  final String intro;
  final List<HelpStep> steps;
  final List<String>? tips;

  const HelpCategoryScreen({
    super.key,
    required this.iconAsset,
    required this.title,
    required this.tagline,
    required this.intro,
    required this.steps,
    this.tips,
  });

  TextStyle _f({
    required double size,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double height = 1.35,
  }) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

  Widget _svg(String asset, {double size = 22, Color? color}) => SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color ?? AppColors.primary, BlendMode.srcIn),
      );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
      backgroundColor: AppColors.surface,
      appBar: NuruSubPageAppBar(title: title),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _hero(),
          const SizedBox(height: 22),
          Text('Step by step',
              style: _f(size: 11, weight: FontWeight.w800, color: AppColors.textTertiary)
                  .copyWith(letterSpacing: 1.4)),
          const SizedBox(height: 10),
          for (int i = 0; i < steps.length; i++) ...[
            _stepCard(i + 1, steps[i]),
            const SizedBox(height: 10),
          ],
          if (tips != null && tips!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Tips',
                style: _f(size: 11, weight: FontWeight.w800, color: AppColors.textTertiary)
                    .copyWith(letterSpacing: 1.4)),
            const SizedBox(height: 10),
            _tipsCard(),
          ],
          const SizedBox(height: 22),
          _footer(context),
        ],
      ),
      ),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(child: _svg(iconAsset, size: 30)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tagline,
                    style: _f(size: 11, weight: FontWeight.w800, color: AppColors.primary)
                        .copyWith(letterSpacing: 1.3)),
                const SizedBox(height: 6),
                Text(title, style: _f(size: 20, weight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 8),
                Text(intro,
                    style: _f(size: 13, color: AppColors.textSecondary, height: 1.5)),
              ]),
            ),
          ],
        ),
      );

  Widget _stepCard(int n, HelpStep s) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text('$n',
                style: _f(size: 13, weight: FontWeight.w800, color: AppColors.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.title, style: _f(size: 14, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(s.body,
                  style: _f(size: 12, color: AppColors.textSecondary, height: 1.5)),
            ]),
          ),
        ]),
      );

  Widget _tipsCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < tips!.length; i++) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  margin: const EdgeInsets.only(top: 6, right: 10),
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                ),
                Expanded(
                  child: Text(tips![i],
                      style: _f(size: 12, color: AppColors.textSecondary, height: 1.5)),
                ),
              ]),
              if (i < tips!.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      );

  Widget _footer(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Still need help?', style: _f(size: 14, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Ask Nuru AI for a quick answer or chat with a human teammate.',
              style: _f(size: 12, color: AppColors.textSecondary, height: 1.5)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const LiveChatScreen())),
                icon: _svg('assets/icons/chat-icon.svg',
                    size: 16, color: AppColors.primary),
                label: Text('Live Chat',
                    style: _f(size: 12, weight: FontWeight.w700, color: AppColors.primary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AiAssistantScreen())),
                icon: _svg('assets/icons/sparkle-icon.svg',
                    size: 16, color: Colors.white),
                label: Text('Ask Nuru AI',
                    style: _f(size: 12, weight: FontWeight.w700, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
          ]),
        ]),
      );
}

class HelpStep {
  final String title;
  final String body;
  const HelpStep(this.title, this.body);
}

/// Centralised category content so help_screen.dart stays compact.
class HelpCategoryContent {
  static HelpCategoryScreen gettingStarted() => const HelpCategoryScreen(
        iconAsset: 'assets/icons/rocket-icon.svg',
        title: 'Getting Started',
        tagline: 'WELCOME TO NURU',
        intro:
            "Set up your Nuru account in minutes and learn the essentials so you can plan, contribute and host with confidence.",
        steps: [
          HelpStep('Create your profile',
              'Add your full name, photo and phone. A complete profile builds trust with organisers and contributors.'),
          HelpStep('Verify your phone',
              'Confirm the OTP sent to you. Verified accounts can receive payments, send invitations and post reviews.'),
          HelpStep('Explore the home tab',
              'Browse trending events, vendors and stories. Tap any card to see full details, ratings and pricing.'),
          HelpStep('Create or join an event',
              'Tap the + button to start a new event, or open an invitation link to RSVP and contribute to one you were invited to.'),
          HelpStep('Set up your wallet',
              'Open Wallet to add a payout method. You only need this to receive money · paying is free and instant via M-Pesa, Airtel Money, Tigo Pesa or card.'),
        ],
        tips: [
          'Add a profile photo so organisers recognise you in their guest list.',
          'Turn on notifications to never miss an RSVP, payment or contribution update.',
          'You can always come back to Help and tap "Ask Nuru AI" for live answers.',
        ],
      );

  static HelpCategoryScreen accountSettings() => const HelpCategoryScreen(
        iconAsset: 'assets/icons/user-icon.svg',
        title: 'Account Settings',
        tagline: 'YOUR ACCOUNT',
        intro:
            "Update your personal information, language, notifications and security preferences from one place.",
        steps: [
          HelpStep('Edit your profile',
              'Profile tab → Edit Profile. Change your name, bio, photo, gender and date of birth.'),
          HelpStep('Switch language',
              'Settings → Language. Nuru speaks English and Kiswahili · the whole app updates instantly.'),
          HelpStep('Manage notifications',
              'Settings → Notifications. Mute event reminders, payments, social activity or messages independently.'),
          HelpStep('Change your password',
              'Settings → Security → Change Password. Use 8+ characters with a mix of letters and numbers.'),
          HelpStep('Delete your account',
              'Settings → Privacy → Delete Account. We hold the request for 30 days so you can reactivate if you change your mind.'),
        ],
        tips: [
          'Keep your phone number up to date · we use it for OTP login and payment confirmations.',
          'Verified accounts unlock service listings, ticket payouts and event sponsorship.',
        ],
      );

  static HelpCategoryScreen paymentsContributions() => const HelpCategoryScreen(
        iconAsset: 'assets/icons/wallet-icon.svg',
        title: 'Payments & Contributions',
        tagline: 'MONEY ON NURU',
        intro:
            "Send pledges, pay contributions and withdraw earnings safely in TZS using mobile money or card.",
        steps: [
          HelpStep('Open your event',
              'Tap the event you were invited to from My Events or your invitation link.'),
          HelpStep('Make a pledge',
              'Tap "Pledge" and enter the amount you commit to give. Pledges are visible to the event committee.'),
          HelpStep('Pay your contribution',
              'Tap "Pay" and choose M-Pesa, Airtel Money, Tigo Pesa or card. You will receive an STK push to confirm.'),
          HelpStep('Track your progress',
              'My Contributions shows pledged, paid and pending balances per event with a percentage progress bar.'),
          HelpStep('Withdraw earnings',
              'Wallet → Withdraw. Funds settle to your registered mobile money number, usually within minutes.'),
        ],
        tips: [
          'Receipts for every contribution are saved automatically and can be shared as a PDF.',
          'If a payment is stuck on Pending for over 5 minutes, pull to refresh · it usually clears itself.',
          'Use "Pending Pledge" to see what you still owe at a glance.',
        ],
      );

  static HelpCategoryScreen eventsTickets() => const HelpCategoryScreen(
        iconAsset: 'assets/icons/ticket-icon.svg',
        title: 'Events & Tickets',
        tagline: 'PLAN AND ATTEND',
        intro:
            "Create events, invite guests, sell tickets and check attendees in · all from your phone.",
        steps: [
          HelpStep('Create an event',
              'Home → + → New Event. Add a title, date, venue (with map), cover photo and event type.'),
          HelpStep('Invite guests',
              'Open the event → Guests → Add. Import from contacts, paste numbers or send WhatsApp invitation cards.'),
          HelpStep('Sell tickets',
              'Open the event → Tickets → New Class. Set price, quantity and sales window. Sales close automatically.'),
          HelpStep('Buy a ticket',
              'Open any public event → Get Tickets → choose class → pay. The ticket lands in My Tickets with a QR code.'),
          HelpStep('Check guests in',
              'Event day: open Guests → Check-In. Scan the QR code or tap the guest to mark them used.'),
        ],
        tips: [
          'Each invitation has a unique RSVP link · sharing the same link twice still counts as one guest.',
          'Tickets become "used" the moment a guest is checked in by QR scan or manually.',
        ],
      );

  static HelpCategoryScreen safetyPrivacy() => const HelpCategoryScreen(
        iconAsset: 'assets/icons/shield-icon.svg',
        title: 'Safety & Privacy',
        tagline: 'YOU ARE IN CONTROL',
        intro:
            "How Nuru protects your data, your money and your guests, and what you can do to stay safe.",
        steps: [
          HelpStep('Your data is encrypted',
              'All traffic uses TLS, and sensitive fields (phone, payout details) are encrypted at rest in our Tanzania-hosted database.'),
          HelpStep('Money is held in escrow',
              'Vendor payments stay in escrow until the service is delivered, so you can request a refund if something goes wrong within 48 hours.'),
          HelpStep('Control who sees you',
              'Settings → Privacy lets you hide your phone, restrict who can message you, and turn off your public profile.'),
          HelpStep('Block and report',
              'Long-press any user, post or message to block or report it. Our team reviews reports within 24 hours.'),
          HelpStep('Two-step protection',
              'OTP login plus device-bound sessions mean even a leaked password cannot sign someone else in as you.'),
        ],
        tips: [
          'Never share your OTP code · Nuru staff will never ask for it.',
          'Pay only inside the app. If a vendor asks for direct mobile money, decline and report them.',
          'You can request a full export or deletion of your data at any time from Settings → Privacy.',
        ],
      );
}
