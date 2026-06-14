import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Premium illustrated empty-state component used across the app.
///
/// Five canonical variants ship inline (no extra asset packaging required):
/// `events`, `contributions`, `messages`, `tickets`, `services`.
///
/// Falls back to a generic shape if [variant] isn't recognised.
class EmptyStateIllustration extends StatelessWidget {
  final String variant;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyStateIllustration({
    super.key,
    required this.variant,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 180,
            height: 140,
            child: SvgPicture.string(_svgFor(variant), fit: BoxFit.contain),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16, fontWeight: FontWeight.w700,
              color: AppColors.textPrimary, height: 1.3,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13, color: AppColors.textTertiary, height: 1.45,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }

  // ---------- Inline SVG illustration set ----------
  // Soft editorial line art tinted with brand orange + ink.
  // Single-color blob behind a thin line illustration for the 5 contexts.

  static const String _kPrimary = '#E7A622';
  static const String _kPrimarySoft = '#FFE7DE';
  static const String _kInk = '#0A1C40';
  static const String _kSurface = '#FFFFFF';

  String _svgFor(String v) {
    switch (v) {
      case 'events': return _events;
      case 'contributions': return _contributions;
      case 'messages': return _messages;
      case 'tickets': return _tickets;
      case 'services': return _services;
      default: return _generic;
    }
  }

  static const String _events = '''
<svg viewBox="0 0 200 160" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="100" cy="130" rx="78" ry="10" fill="$_kPrimarySoft"/>
  <rect x="40" y="38" width="120" height="86" rx="14" fill="$_kSurface" stroke="$_kInk" stroke-width="2"/>
  <rect x="40" y="38" width="120" height="22" rx="14" fill="$_kPrimary"/>
  <circle cx="64" cy="32" r="6" fill="$_kInk"/>
  <circle cx="136" cy="32" r="6" fill="$_kInk"/>
  <rect x="58" y="74" width="22" height="18" rx="3" fill="$_kPrimarySoft"/>
  <rect x="88" y="74" width="22" height="18" rx="3" fill="$_kPrimarySoft"/>
  <rect x="118" y="74" width="22" height="18" rx="3" fill="$_kPrimary"/>
  <rect x="58" y="100" width="22" height="14" rx="3" fill="#F0F0F4"/>
  <rect x="88" y="100" width="22" height="14" rx="3" fill="#F0F0F4"/>
  <rect x="118" y="100" width="22" height="14" rx="3" fill="#F0F0F4"/>
</svg>''';

  static const String _contributions = '''
<svg viewBox="0 0 200 160" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="100" cy="130" rx="78" ry="10" fill="$_kPrimarySoft"/>
  <circle cx="100" cy="78" r="48" fill="$_kSurface" stroke="$_kInk" stroke-width="2"/>
  <circle cx="100" cy="78" r="34" fill="$_kPrimarySoft"/>
  <text x="100" y="86" text-anchor="middle" font-family="Georgia,serif" font-size="32" font-weight="700" fill="$_kPrimary">TZS</text>
  <circle cx="56" cy="50" r="10" fill="$_kPrimary"/>
  <circle cx="148" cy="50" r="8" fill="$_kInk"/>
  <circle cx="160" cy="100" r="6" fill="$_kPrimary"/>
</svg>''';

  static const String _messages = '''
<svg viewBox="0 0 200 160" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="100" cy="130" rx="78" ry="10" fill="$_kPrimarySoft"/>
  <path d="M50 40 H140 a14 14 0 0 1 14 14 V94 a14 14 0 0 1 -14 14 H92 L72 124 V108 H50 a14 14 0 0 1 -14 -14 V54 a14 14 0 0 1 14 -14 z" fill="$_kSurface" stroke="$_kInk" stroke-width="2"/>
  <circle cx="74" cy="74" r="4" fill="$_kInk"/>
  <circle cx="94" cy="74" r="4" fill="$_kInk"/>
  <circle cx="114" cy="74" r="4" fill="$_kInk"/>
  <path d="M120 38 a18 18 0 1 1 -0.1 0 z" fill="$_kPrimary"/>
  <text x="120" y="44" text-anchor="middle" font-family="sans-serif" font-size="20" font-weight="700" fill="$_kSurface">!</text>
</svg>''';

  static const String _tickets = '''
<svg viewBox="0 0 200 160" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="100" cy="130" rx="78" ry="10" fill="$_kPrimarySoft"/>
  <path d="M40 56 H160 a8 8 0 0 1 8 8 V76 a10 10 0 0 0 0 20 V108 a8 8 0 0 1 -8 8 H40 a8 8 0 0 1 -8 -8 V96 a10 10 0 0 0 0 -20 V64 a8 8 0 0 1 8 -8 z" fill="$_kSurface" stroke="$_kInk" stroke-width="2"/>
  <line x1="110" y1="60" x2="110" y2="112" stroke="$_kInk" stroke-width="1.5" stroke-dasharray="3 3"/>
  <rect x="50" y="72" width="50" height="6" rx="3" fill="$_kPrimary"/>
  <rect x="50" y="84" width="36" height="4" rx="2" fill="#C9CFDC"/>
  <rect x="50" y="94" width="42" height="4" rx="2" fill="#C9CFDC"/>
  <circle cx="138" cy="86" r="14" fill="$_kPrimary"/>
  <text x="138" y="91" text-anchor="middle" font-family="Georgia,serif" font-size="14" font-weight="700" fill="$_kSurface">N</text>
</svg>''';

  static const String _services = '''
<svg viewBox="0 0 200 160" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="100" cy="130" rx="78" ry="10" fill="$_kPrimarySoft"/>
  <rect x="50" y="56" width="100" height="68" rx="10" fill="$_kSurface" stroke="$_kInk" stroke-width="2"/>
  <path d="M50 70 H150 V60 a4 4 0 0 0 -4 -4 H54 a4 4 0 0 0 -4 4 z" fill="$_kPrimary"/>
  <rect x="84" y="44" width="32" height="14" rx="4" fill="$_kSurface" stroke="$_kInk" stroke-width="2"/>
  <rect x="64" y="84" width="38" height="6" rx="3" fill="#C9CFDC"/>
  <rect x="64" y="98" width="58" height="4" rx="2" fill="#E5E5EA"/>
  <rect x="64" y="108" width="46" height="4" rx="2" fill="#E5E5EA"/>
  <circle cx="134" cy="98" r="12" fill="$_kPrimarySoft"/>
  <path d="M128 98 l4 4 l8 -8" stroke="$_kPrimary" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

  static const String _generic = '''
<svg viewBox="0 0 200 160" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="100" cy="130" rx="78" ry="10" fill="$_kPrimarySoft"/>
  <circle cx="100" cy="80" r="44" fill="$_kSurface" stroke="$_kInk" stroke-width="2"/>
  <circle cx="100" cy="80" r="22" fill="$_kPrimarySoft"/>
</svg>''';
}
