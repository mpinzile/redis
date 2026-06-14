import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:animate_do/animate_do.dart';

import '../../core/theme/app_colors.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Brand palette
// ─────────────────────────────────────────────────────────────────────────────
const Color _kGold = Color(0xFFE7A622);
const Color _kGoldSoft = Color(0xFFFFF4D6);
const Color _kInk = Color(0xFF111111);
const Color _kInkSoft = Color(0xFF6B7280);
const Color _kCream = Color(0xFFFFFBF2);
const Color _kSurface = Colors.white;
const Color _kBorder = Color(0xFFEFE7D6);

TextStyle _f({
  required double size,
  FontWeight weight = FontWeight.w500,
  Color color = _kInk,
  double height = 1.2,
  double letterSpacing = 0,
}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding screen — logic preserved (skip / next / completeOnboarding / routes)
// ─────────────────────────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) => setState(() => _page = page);

  void _skip() {
    context.read<AuthProvider>().completeOnboarding();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, a, __) => const LoginScreen(),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  void _next() {
    if (_page < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _skip();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _kCream,
      ),
      child: Scaffold(
        backgroundColor: _kCream,
        body: Stack(
          children: [
            // ── Pages (full-bleed so page 1 image can extend edge-to-edge) ──
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                itemCount: 3,
                onPageChanged: _onPageChanged,
                itemBuilder: (ctx, index) {
                  switch (index) {
                    case 0:
                      return const _Page1BrandIntro();
                    case 1:
                      return const _Page2Workspace();
                    case 2:
                      return _Page3Collaboration(onGetStarted: _next, onSignIn: _skip);
                    default:
                      return const SizedBox.shrink();
                  }
                },
              ),
            ),

            // ── Skip (top-right, persistent) ──
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: TextButton(
                    onPressed: _skip,
                    style: TextButton.styleFrom(
                      foregroundColor: _kInkSoft,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: const Size(52, 36),
                    ),
                    child: Text(
                      'Skip',
                      style: _f(size: 14, weight: FontWeight.w600, color: _kInkSoft),
                    ),
                  ),
                ),
              ),
            ),

            // ── Page indicator (bottom, above optional CTA) ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: SafeArea(
                top: false,
                child: Center(
                  child: AnimatedSmoothIndicator(
                    activeIndex: _page,
                    count: 3,
                    effect: const WormEffect(
                      activeDotColor: _kGold,
                      dotColor: Color(0xFFE3DCC8),
                      dotHeight: 8,
                      dotWidth: 8,
                      spacing: 8,
                      type: WormType.normal,
                    ),
                    onDotClicked: (i) => _pageController.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared title widget — gold-highlighted keywords (no translation key changes)
// ═════════════════════════════════════════════════════════════════════════════
class _HighlightedTitle extends StatelessWidget {
  final String text;
  final List<String> highlights;
  final TextStyle baseStyle;
  final TextStyle highlightStyle;
  final TextAlign textAlign;

  const _HighlightedTitle({
    required this.text,
    required this.highlights,
    required this.baseStyle,
    required this.highlightStyle,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    if (highlights.isEmpty) {
      return Text(text, textAlign: textAlign, style: baseStyle);
    }
    final sorted = [...highlights]..sort((a, b) => b.length.compareTo(a.length));
    final pattern = sorted.map(RegExp.escape).join('|');
    final re = RegExp('($pattern)', caseSensitive: false);

    final spans = <TextSpan>[];
    int last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: baseStyle));
      }
      spans.add(TextSpan(text: m.group(0), style: highlightStyle));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: baseStyle));
    }
    return RichText(
      textAlign: textAlign,
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PAGE 1 — Brand Introduction
// Full-bleed hero image at bottom, top-only rounded corners, soft top blur fade.
// Floating white feature panel overlaps bottom of image.
// ═════════════════════════════════════════════════════════════════════════════
class _Page1BrandIntro extends StatelessWidget {
  const _Page1BrandIntro();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final hp = box.maxWidth < 360 ? 18.0 : 24.0;
        final titleSize = (box.maxHeight * 0.040).clamp(26.0, 32.0);

        // Image starts ~ below the title block
        final imageTop = box.maxHeight * 0.40;
        // Panel sits near bottom (above dots)
        final panelBottom = 64.0;

        return Stack(
          children: [
            // ── Full-bleed bottom hero image (rounded TOP corners only) ──
            Positioned(
              left: 0,
              right: 0,
              top: imageTop,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/onboarding_workspace.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => Container(color: _kGoldSoft),
                    ),
                    // Soft cream blur fade at the top of the image
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: 90,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _kCream,
                              _kCream.withOpacity(0.85),
                              _kCream.withOpacity(0.0),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Header content (logo + title + subtitle) ──
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 56, hp, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Nuru wordmark logo
                    FadeIn(
                      duration: const Duration(milliseconds: 420),
                      child: Image.asset(
                        'assets/images/nuru-logo.png',
                        height: (box.maxHeight * 0.085).clamp(54.0, 72.0),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Text(
                          'nuru',
                          style: _f(size: 44, weight: FontWeight.w800, color: _kInk),
                        ),
                      ),
                    ),
                    SizedBox(height: box.maxHeight * 0.024),

                    // Title — exact reference text
                    FadeIn(
                      duration: const Duration(milliseconds: 480),
                      delay: const Duration(milliseconds: 80),
                      child: _HighlightedTitle(
                        text: 'Plan Smarter.\nCelebrate Better.',
                        highlights: const ['Smarter.', 'Better.'],
                        baseStyle: _f(
                          size: titleSize,
                          weight: FontWeight.w800,
                          color: _kInk,
                          height: 1.18,
                          letterSpacing: -0.6,
                        ),
                        highlightStyle: _f(
                          size: titleSize,
                          weight: FontWeight.w800,
                          color: _kGold,
                          height: 1.18,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                    SizedBox(height: box.maxHeight * 0.016),

                    // Subtitle
                    FadeIn(
                      duration: const Duration(milliseconds: 540),
                      delay: const Duration(milliseconds: 140),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Nuru is your all-in-one platform to plan, organize, and manage events effortlessly. Everything you need, in one place.',
                          textAlign: TextAlign.center,
                          style: _f(
                            size: 13.5,
                            weight: FontWeight.w500,
                            color: _kInkSoft,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Full-width feature panel pinned to bottom (rounded top only) ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FadeInUp(
                duration: const Duration(milliseconds: 560),
                delay: const Duration(milliseconds: 180),
                from: 24,
                child: const _FeaturePanel(
                  items: [
                    _FeatureItem(Icons.event_available_rounded, 'Create & Manage\nEvents',
                        svgAsset: 'assets/icons/calendar-icon.svg'),
                    _FeatureItem(Icons.group_add_rounded, 'Invite & Connect\nPeople',
                        svgAsset: 'assets/icons/contributors-icon.svg'),
                    _FeatureItem(Icons.account_balance_wallet_rounded,
                        'Contributions\n& Payments',
                        svgAsset: 'assets/icons/card-icon.svg'),
                    _FeatureItem(Icons.storefront_rounded, 'Vendors\n& Services',
                        svgAsset: 'assets/icons/package-icon.svg'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String label;
  final String? svgAsset;
  const _FeatureItem(this.icon, this.label, {this.svgAsset});
}

/// Renders an SVG asset (with color tint) when [svgAsset] is non-null,
/// otherwise falls back to the provided material [icon].
Widget _featureGlyph({
  required String? svgAsset,
  required IconData icon,
  required Color color,
  required double size,
}) {
  if (svgAsset != null) {
    return SvgPicture.asset(
      svgAsset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
  return Icon(icon, color: color, size: size);
}

class _FeaturePanel extends StatelessWidget {
  final List<_FeatureItem> items;
  const _FeaturePanel({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 64),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 24,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((it) {
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _featureGlyph(
                  svgAsset: it.svgAsset,
                  icon: it.icon,
                  color: _kInk,
                  size: 28,
                ),
                const SizedBox(height: 12),
                Text(
                  it.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: _f(
                    size: 11,
                    weight: FontWeight.w600,
                    color: _kInk,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PAGE 2 — Workspace ecosystem with skyline footer
// ═════════════════════════════════════════════════════════════════════════════
class _Page2Workspace extends StatelessWidget {
  const _Page2Workspace();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final hp = box.maxWidth < 360 ? 18.0 : 24.0;
        final titleSize = (box.maxHeight * 0.038).clamp(24.0, 30.0);

        // Reserve bottom area for the ecosystem panel
        final panelHeight = box.maxHeight * 0.56;

        return Stack(
          children: [
            // ── Header content (title + subtitle) ──
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 60, hp, 0),
                child: Column(
                  children: [
                    FadeIn(
                      duration: const Duration(milliseconds: 480),
                      child: _HighlightedTitle(
                        text: 'Everything your\nevent needs\nin one workspace.',
                        highlights: const ['one workspace.'],
                        baseStyle: _f(
                          size: titleSize,
                          weight: FontWeight.w800,
                          color: _kInk,
                          height: 1.2,
                          letterSpacing: -0.5,
                        ),
                        highlightStyle: _f(
                          size: titleSize,
                          weight: FontWeight.w800,
                          color: _kGold,
                          height: 1.2,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    SizedBox(height: box.maxHeight * 0.016),
                    FadeIn(
                      duration: const Duration(milliseconds: 540),
                      delay: const Duration(milliseconds: 100),
                      child: Text(
                        'From budgeting and ticketing to vendor booking,\ncontributions, and guest management,\nNuru keeps everything organized and transparent.',
                        textAlign: TextAlign.center,
                        style: _f(
                          size: 12.5,
                          weight: FontWeight.w500,
                          color: _kInkSoft,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Ecosystem panel pinned to bottom (full width, rounded top) ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: panelHeight,
              child: FadeInUp(
                duration: const Duration(milliseconds: 560),
                from: 24,
                child: Container(
                  decoration: const BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 24,
                        offset: Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Skyline along the bottom of the panel
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 50,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 0.85,
                            child: Image.asset(
                              'assets/images/onboarding_skyline.png',
                              fit: BoxFit.fitWidth,
                              height: 90,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                      // Ecosystem
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 18, 12, 56),
                        child: const _WorkspaceEcosystem(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceEcosystem extends StatelessWidget {
  const _WorkspaceEcosystem();

  @override
  Widget build(BuildContext context) {
    const features = <_FeatureItem>[
      _FeatureItem(Icons.confirmation_number_rounded, 'Ticketing &\nCheck-in',
          svgAsset: 'assets/icons/ticket-icon.svg'),
      _FeatureItem(Icons.account_balance_wallet_rounded,
          'Contributions\n& Payments',
          svgAsset: 'assets/icons/card-icon.svg'),
      _FeatureItem(Icons.person_add_alt_1_rounded, 'Guest List &\nInvitations',
          svgAsset: 'assets/icons/user-profile-icon.svg'),
      _FeatureItem(Icons.chat_bubble_rounded, 'Chat &\nAnnouncements',
          svgAsset: 'assets/icons/chat-icon.svg'),
      _FeatureItem(Icons.storefront_rounded, 'Vendors &\nServices',
          svgAsset: 'assets/icons/package-icon.svg'),
      _FeatureItem(Icons.pie_chart_rounded, 'Budget &\nExpenses'),
    ];

    return LayoutBuilder(
      builder: (ctx, box) {
        final size = math.min(box.maxWidth, box.maxHeight);
        final radius = size * 0.34;
        final centerCardSize = size * 0.22;

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size(size, size),
                  painter: _DottedCirclePainter(
                    radius: radius,
                    color: const Color(0xFFCFC6AE),
                  ),
                ),
                Container(
                  width: centerCardSize,
                  height: centerCardSize,
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kBorder, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Image.asset(
                    'assets/images/nuru-logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/nuru-logo-square.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                for (int i = 0; i < features.length; i++)
                  _orbitChild(
                    radius: radius,
                    angleDeg: -90 + (360 / features.length) * i,
                    child: _OrbitBubble(
                      item: features[i],
                      iconColor: _bubbleColors[i % _bubbleColors.length],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const List<Color> _bubbleColors = [
    Color(0xFF6D5BD0), // ticketing - purple
    Color(0xFF1E9E5C), // payments - green
    Color(0xFF2E86DE), // guest - blue
    Color(0xFFE08A1E), // chat - amber
    Color(0xFFD03B3B), // vendors - red
    Color(0xFF1E9E5C), // budget - green
  ];

  Widget _orbitChild({
    required double radius,
    required double angleDeg,
    required Widget child,
  }) {
    final a = angleDeg * math.pi / 180;
    final dx = math.cos(a) * radius;
    final dy = math.sin(a) * radius;
    return Transform.translate(offset: Offset(dx, dy), child: child);
  }
}

class _OrbitBubble extends StatelessWidget {
  final _FeatureItem item;
  final Color iconColor;
  const _OrbitBubble({required this.item, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _kSurface,
              shape: BoxShape.circle,
              border: Border.all(color: _kBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: _featureGlyph(
              svgAsset: item.svgAsset,
              icon: item.icon,
              color: iconColor,
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: _f(
              size: 10,
              weight: FontWeight.w600,
              color: _kInk,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DottedCirclePainter extends CustomPainter {
  final double radius;
  final Color color;
  _DottedCirclePainter({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    const dotCount = 70;
    for (int i = 0; i < dotCount; i++) {
      final a = (i / dotCount) * 2 * math.pi;
      final p = Offset(
        center.dx + math.cos(a) * radius,
        center.dy + math.sin(a) * radius,
      );
      canvas.drawCircle(p, 1.4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedCirclePainter old) =>
      old.radius != radius || old.color != color;
}

// ═════════════════════════════════════════════════════════════════════════════
// PAGE 3 — Collaboration with phone mockup, floating chips, plant + shapes
// CTA + Sign in footer live ONLY on this page.
// ═════════════════════════════════════════════════════════════════════════════
class _Page3Collaboration extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;
  const _Page3Collaboration({required this.onGetStarted, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final hp = box.maxWidth < 360 ? 18.0 : 24.0;
        final titleSize = (box.maxHeight * 0.038).clamp(24.0, 30.0);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hp, 56, hp, 16),
            child: Column(
              children: [
                FadeIn(
                  duration: const Duration(milliseconds: 480),
                  child: _HighlightedTitle(
                    text: 'Connect. Collaborate.\nMake every moment\nmemorable.',
                    highlights: const [
                      'Make every moment\nmemorable.',
                    ],
                    baseStyle: _f(
                      size: titleSize,
                      weight: FontWeight.w800,
                      color: _kInk,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                    highlightStyle: _f(
                      size: titleSize,
                      weight: FontWeight.w800,
                      color: _kGold,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                SizedBox(height: box.maxHeight * 0.014),
                FadeIn(
                  duration: const Duration(milliseconds: 540),
                  delay: const Duration(milliseconds: 100),
                  child: Text(
                    'Work with your committee, communicate in real time,\nhost meetings, share updates and make your\nevent experience seamless for everyone.',
                    textAlign: TextAlign.center,
                    style: _f(
                      size: 12.5,
                      weight: FontWeight.w500,
                      color: _kInkSoft,
                      height: 1.55,
                    ),
                  ),
                ),
                SizedBox(height: box.maxHeight * 0.012),

                // Hero meeting scene
                Expanded(
                  child: FadeInUp(
                    duration: const Duration(milliseconds: 560),
                    from: 24,
                    child: const _MeetingHero(),
                  ),
                ),

                // Bottom space reserved for the page indicator dots
                const SizedBox(height: 44),

                // CTA button — last page only
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: onGetStarted,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGold,
                      foregroundColor: _kInk,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Let's Get Started",
                          style: _f(size: 16, weight: FontWeight.w700, color: _kInk),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: _kInk,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: _kGold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: _f(size: 13, weight: FontWeight.w500, color: _kInkSoft),
                    ),
                    GestureDetector(
                      onTap: onSignIn,
                      child: Text(
                        'Sign in',
                        style: _f(size: 13, weight: FontWeight.w800, color: _kGold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MeetingHero extends StatelessWidget {
  const _MeetingHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final phoneH = box.maxHeight * 0.92;
        final phoneW = phoneH * 0.50;
        final orbitRadius = math.min(box.maxWidth, box.maxHeight) * 0.46;

        return Center(
          child: SizedBox(
            width: box.maxWidth,
            height: box.maxHeight,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Soft dotted orbit
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DottedCirclePainter(
                      radius: orbitRadius,
                      color: _kGold.withOpacity(0.35),
                    ),
                  ),
                ),

                // Phone mockup
                _PhoneMockup(width: phoneW, height: phoneH),

                // Floating chips
                Positioned(
                  top: box.maxHeight * 0.06,
                  left: 0,
                  child: const _FeatureChip(
                    color: Color(0xFFEDE7FF),
                    iconColor: Color(0xFF6D5BD0),
                    icon: Icons.videocam_rounded,
                    svgAsset: 'assets/icons/video-icon.svg',
                    label: 'Video\nMeetings',
                  ),
                ),
                Positioned(
                  top: box.maxHeight * 0.16,
                  right: 0,
                  child: const _FeatureChip(
                    color: Color(0xFFE6F6E1),
                    iconColor: Color(0xFF3E9B2F),
                    icon: Icons.campaign_rounded,
                    svgAsset: 'assets/icons/bell-icon.svg',
                    label: 'Live\nUpdates',
                  ),
                ),
                Positioned(
                  bottom: box.maxHeight * 0.30,
                  left: 0,
                  child: const _FeatureChip(
                    color: Color(0xFFFFE9CF),
                    iconColor: Color(0xFFE08A1E),
                    icon: Icons.chat_rounded,
                    svgAsset: 'assets/icons/chat-icon.svg',
                    label: 'Quick\nChats',
                  ),
                ),
                Positioned(
                  bottom: box.maxHeight * 0.18,
                  right: 0,
                  child: const _FeatureChip(
                    color: Color(0xFFFFE1E1),
                    iconColor: Color(0xFFD03B3B),
                    icon: Icons.calendar_today_rounded,
                    svgAsset: 'assets/icons/calendar-icon.svg',
                    label: 'Event\nReminders',
                  ),
                ),

                // Plant decor (bottom left)
                Positioned(
                  bottom: 0,
                  left: 6,
                  child: _PlantDecor(),
                ),

                // Geometric shapes (bottom right)
                Positioned(
                  bottom: 4,
                  right: 8,
                  child: _GeometricShapes(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PhoneMockup extends StatelessWidget {
  final double width;
  final double height;
  const _PhoneMockup({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _kInk,
        borderRadius: BorderRadius.circular(38),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      padding: const EdgeInsets.all(5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // In-app rendered meeting grid (no external image)
            Container(color: const Color(0xFF111317)),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 32, 8, 56),
              child: _MeetingGrid(),
            ),
            // Status bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 24,
                color: Colors.black.withOpacity(0.55),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Row(
                  children: [
                    Text('18:01',
                        style: _f(size: 10, color: Colors.white, weight: FontWeight.w600)),
                    const Spacer(),
                    const Icon(Icons.signal_cellular_alt_rounded,
                        size: 10, color: Colors.white),
                    const SizedBox(width: 4),
                    const Icon(Icons.wifi_rounded, size: 10, color: Colors.white),
                    const SizedBox(width: 4),
                    const Icon(Icons.battery_full_rounded, size: 10, color: Colors.white),
                  ],
                ),
              ),
            ),
            // Notch
            Positioned(
              top: 4,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: width * 0.34,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            // Call controls bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: const [
                    _CallControl(icon: Icons.mic_rounded),
                    _CallControl(icon: Icons.videocam_rounded),
                    _CallControl(icon: Icons.screen_share_rounded),
                    _CallControl(icon: Icons.more_horiz_rounded),
                    _CallControl(icon: Icons.call_end_rounded, danger: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallControl extends StatelessWidget {
  final IconData icon;
  final bool danger;
  const _CallControl({required this.icon, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFE53935) : Colors.white24,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 12),
    );
  }
}

// 2x2 meeting grid rendered fully in-app (no external photo).
class _MeetingGrid extends StatelessWidget {
  const _MeetingGrid();

  static const _tiles = <_MeetingTile>[
    _MeetingTile(initials: 'AK', name: 'Amani', bg: Color(0xFF8B5E3C), accent: Color(0xFFFFD8A8)),
    _MeetingTile(initials: 'NJ', name: 'Neema', bg: Color(0xFF2E5266), accent: Color(0xFFB8E0F2)),
    _MeetingTile(initials: 'DM', name: 'David', bg: Color(0xFF4A3B2A), accent: Color(0xFFFFE0B2)),
    _MeetingTile(initials: 'ZM', name: 'Zawadi', bg: Color(0xFF6B4423), accent: Color(0xFFFFCC99)),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.85,
      children: _tiles.map((t) => _MeetingTileView(tile: t)).toList(),
    );
  }
}

class _MeetingTile {
  final String initials;
  final String name;
  final Color bg;
  final Color accent;
  const _MeetingTile({
    required this.initials,
    required this.name,
    required this.bg,
    required this.accent,
  });
}

class _MeetingTileView extends StatelessWidget {
  final _MeetingTile tile;
  const _MeetingTileView({required this.tile});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soft radial-ish background
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.3),
                radius: 1.0,
                colors: [tile.bg.withOpacity(0.95), Colors.black.withOpacity(0.85)],
              ),
            ),
          ),
          // Avatar circle
          Center(
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tile.accent,
                border: Border.all(color: Colors.white.withOpacity(0.6), width: 1),
              ),
              alignment: Alignment.center,
              child: Text(
                tile.initials,
                style: _f(size: 11, weight: FontWeight.w800, color: tile.bg),
              ),
            ),
          ),
          // Name pill
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF34C759),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tile.name,
                    style: _f(size: 7.5, weight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final Color color;
  final Color iconColor;
  final IconData icon;
  final String? svgAsset;
  final String label;
  const _FeatureChip({
    required this.color,
    required this.iconColor,
    required this.icon,
    this.svgAsset,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: _featureGlyph(
              svgAsset: svgAsset,
              icon: icon,
              color: iconColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: _f(size: 10.5, weight: FontWeight.w700, color: _kInk, height: 1.2),
          ),
        ],
      ),
    );
  }
}

// Decorative plant (CSS-style minimal pot + leaves)
class _PlantDecor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 64,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Pot
          Positioned(
            bottom: 0,
            child: Container(
              width: 36,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(10),
                  top: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
          // Leaves
          Positioned(
            bottom: 18,
            child: Icon(Icons.spa_rounded, size: 38, color: const Color(0xFF3E9B2F)),
          ),
        ],
      ),
    );
  }
}

// Decorative geometric shapes (golden triangle + cream sphere)
class _GeometricShapes extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 40,
      child: Stack(
        children: [
          // Triangle
          Positioned(
            left: 0,
            bottom: 0,
            child: CustomPaint(
              size: const Size(34, 28),
              painter: _TrianglePainter(color: _kGold),
            ),
          ),
          // Sphere
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.2, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
