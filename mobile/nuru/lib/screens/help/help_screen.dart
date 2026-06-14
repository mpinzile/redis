import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import 'ai_assistant_screen.dart';
import 'help_category_screen.dart';
import 'live_chat_screen.dart';
import '../issues/my_issues_screen.dart';
import '../../core/l10n/l10n_helper.dart';

/// Redesigned Help Center - uses Nuru's custom SVG iconography (no Flutter Material icons).
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int? _openFaq;

  static const _faqs = <Map<String, String>>[
    {
      'q': 'How do I make a contribution?',
      'a': 'Open the event you were invited to, tap "Contribute", choose how you want to pay, and follow the prompts. Your pledge and payment are tracked automatically.',
    },
    {
      'q': 'How do I check my balance?',
      'a': 'Go to Wallet from the home tab. You\'ll see your available balance, recent payments, and any pending withdrawals.',
    },
    {
      'q': 'How can I contact event organizers?',
      'a': 'Open the event, tap the organizer name, then "Message". You can also call them if they\'ve enabled their phone number.',
    },
    {
      'q': 'How do I update my account details?',
      'a': 'Go to Profile → Edit Profile. You can change your name, photo, phone, and notification preferences from there.',
    },
  ];

  static final List<_HelpCategory> _categories = <_HelpCategory>[
    _HelpCategory('assets/icons/rocket-icon.svg', 'Getting Started',
        HelpCategoryContent.gettingStarted),
    _HelpCategory('assets/icons/user-icon.svg', 'Account Settings',
        HelpCategoryContent.accountSettings),
    _HelpCategory('assets/icons/wallet-icon.svg', 'Payments & Contributions',
        HelpCategoryContent.paymentsContributions),
    _HelpCategory('assets/icons/ticket-icon.svg', 'Events & Tickets',
        HelpCategoryContent.eventsTickets),
    _HelpCategory('assets/icons/shield-icon.svg', 'Safety & Privacy',
        HelpCategoryContent.safetyPrivacy),
  ];

  TextStyle _f({
    required double size,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double height = 1.3,
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
      backgroundColor: AppColors.surface,
      appBar: NuruSubPageAppBar(title: context.tr('help_center')),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 132 + bottomInset),
            children: [
              _heroCard(),
              const SizedBox(height: 22),
              _sectionTitle('Quick Links'),
              const SizedBox(height: 10),
              _quickLinks(),
              const SizedBox(height: 22),
              _sectionTitle('Browse Categories'),
              const SizedBox(height: 10),
              _categoriesCard(),
              const SizedBox(height: 22),
              _sectionTitle('Frequently Asked Questions'),
              const SizedBox(height: 10),
              ..._faqs.asMap().entries.map((e) => _faqItem(e.key, e.value['q']!, e.value['a']!)),
              const SizedBox(height: 18),
              _needHelpCard(),
              const SizedBox(height: 24),
            ],
          ),
          // (removed white surface + shadow strip behind the FAB so the
          // transparent system nav bar shows the page content underneath)

          Positioned(
            right: 14,
            bottom: bottomInset + 18,
            child: _askAiPill(),
          ),
        ],
      ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t, style: _f(size: 16, weight: FontWeight.w700));

  Widget _heroCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(child: _svg('assets/icons/headset-icon.svg', size: 38)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How can we help you today?',
                      style: _f(size: 15, weight: FontWeight.w800, height: 1.25)),
                  const SizedBox(height: 6),
                  Text(
                    "We're here to make your Nuru experience smooth and worry-free.",
                    style: _f(size: 12, color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _quickLinks() {
    final links = <_Quick>[
      _Quick('assets/icons/chat-icon.svg', 'Live Chat', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveChatScreen()));
      }),
      _Quick('assets/icons/call-icon.svg', 'Call', () => _callSupport()),
      _Quick('assets/icons/email-icon.svg', 'Email', () => _emailSupport()),
      _Quick('assets/icons/sparkle-icon.svg', 'Nuru Assistant', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantScreen()));
      }),
      _Quick('assets/icons/issue-icon.svg', 'My Issues', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MyIssuesScreen()));
      }),
    ];
    return Row(
      children: [
        for (int i = 0; i < links.length; i++) ...[
          Expanded(child: _quickTile(links[i])),
          if (i < links.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _quickTile(_Quick q) => GestureDetector(
        onTap: q.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            children: [
              _svg(q.asset, size: 24),
              const SizedBox(height: 8),
              Text(q.label,
                  style: _f(size: 11, weight: FontWeight.w600), textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _categoriesCard() => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          children: [
            for (int i = 0; i < _categories.length; i++) ...[
              _categoryRow(_categories[i]),
              if (i < _categories.length - 1)
                Divider(height: 1, color: AppColors.borderLight, indent: 52),
            ],
          ],
        ),
      );

  Widget _categoryRow(_HelpCategory cat) => InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => cat.builder())),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            _svg(cat.asset, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(cat.title, style: _f(size: 14, weight: FontWeight.w600))),
            _svg('assets/icons/chevron-right-icon.svg', size: 18, color: AppColors.textHint),
          ]),
        ),
      );

  Widget _faqItem(int index, String q, String a) {
    final open = _openFaq == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _openFaq = open ? null : index),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              Expanded(child: Text(q, style: _f(size: 13, weight: FontWeight.w600))),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: _svg('assets/icons/chevron-down-icon.svg',
                    size: 18, color: AppColors.textHint),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(a,
                  style: _f(size: 12, color: AppColors.textSecondary, height: 1.5)),
            ),
          ),
          crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ]),
    );
  }

  Widget _needHelpCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: _svg('assets/icons/support-icon.svg', size: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Need more help? Contact our live team',
                      style: _f(size: 13, weight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text("We're ready to assist you with anything you need.",
                      style: _f(size: 11, color: AppColors.textSecondary, height: 1.4)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveChatScreen()));
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                child: Text('Contact Support',
                    style: _f(size: 13, weight: FontWeight.w700, color: AppColors.primary)),
              ),
            ),
          ],
        ),
      );

  Widget _askAiPill() => Material(
        color: AppColors.primary,
        elevation: 6,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AiAssistantScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _svg('assets/icons/sparkle-icon.svg', size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text('Ask Nuru AI',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ),
      );

  Future<void> _callSupport() async {
    final uri = Uri.parse('tel:+255653750805');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _copy('+255653750805', 'Phone copied');
    }
  }

  Future<void> _emailSupport() async {
    final uri = Uri.parse('mailto:support@nuru.tz');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _copy('support@nuru.tz', 'Email copied');
    }
  }

  Future<void> _copy(String value, String success) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) AppSnackbar.success(context, success);
  }
}

class _Quick {
  final String asset;
  final String label;
  final VoidCallback onTap;
  _Quick(this.asset, this.label, this.onTap);
}

class _HelpCategory {
  final String asset;
  final String title;
  final HelpCategoryScreen Function() builder;
  const _HelpCategory(this.asset, this.title, this.builder);
}
