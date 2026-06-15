import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/l10n_helper.dart';
import '../../core/services/api_base.dart';
import '../../core/theme/app_colors.dart';
import '../home/home_screen.dart';

/// Post-signup personalisation: which kinds of events the user cares about
/// + how they engage with events on Nuru. Three short steps, icon-led,
/// translation-aware, no emojis.
class InterestsOnboardingScreen extends StatefulWidget {
  /// When true, behaves as an in-app editor opened from Settings.
  /// Pops back instead of pushing HomeScreen, "Skip" becomes "Cancel".
  final bool fromSettings;
  const InterestsOnboardingScreen({super.key, this.fromSettings = false});

  @override
  State<InterestsOnboardingScreen> createState() =>
      _InterestsOnboardingScreenState();
}

class _InterestsOnboardingScreenState extends State<InterestsOnboardingScreen> {
  bool _loading = true;
  bool _saving = false;
  int _step = 0; // 0 = signup intents, 1 = interests, 2 = role
  List<Map<String, dynamic>> _catalogue = const [];
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _intentsCatalogue = const [];
  final Set<String> _selected = {};
  final Set<String> _intents = {};
  String? _role;

  // Icon mapping per slug (Material icons, since per-category SVGs not bundled)
  static const Map<String, IconData> _interestIcons = {
    'weddings': Icons.favorite_outline,
    'birthdays': Icons.cake_outlined,
    'graduations': Icons.school_outlined,
    'anniversaries': Icons.celebration_outlined,
    'baby_showers': Icons.child_friendly_outlined,
    'private_parties': Icons.local_bar_outlined,
    'concerts': Icons.music_note_outlined,
    'festivals': Icons.festival_outlined,
    'nightlife': Icons.nights_stay_outlined,
    'conferences': Icons.mic_external_on_outlined,
    'workshops': Icons.build_outlined,
    'networking': Icons.people_outline,
    'corporate': Icons.business_center_outlined,
    'exhibitions': Icons.photo_library_outlined,
    'fashion_shows': Icons.checkroom_outlined,
    'sports_events': Icons.sports_soccer_outlined,
    'faith': Icons.volunteer_activism_outlined,
    'cultural': Icons.theater_comedy_outlined,
    'community': Icons.diversity_3_outlined,
    'charity': Icons.favorite_border_outlined,
    'food_events': Icons.restaurant_outlined,
    'memorials': Icons.spa_outlined,
    'retreats': Icons.park_outlined,
  };

  static const Map<String, IconData> _intentIcons = {
    'plan_event': Icons.event_note_outlined,
    'buy_tickets': Icons.confirmation_number_outlined,
    'discover_events': Icons.travel_explore_outlined,
    'offer_service': Icons.room_service_outlined,
    'host_community': Icons.diversity_3_outlined,
    'share_moments': Icons.photo_camera_outlined,
    'network': Icons.handshake_outlined,
    'just_exploring': Icons.auto_awesome_outlined,
  };

  static const Map<String, IconData> _roleIcons = {
    'attendee': Icons.local_activity_outlined,
    'host': Icons.celebration_outlined,
    'planner': Icons.assignment_outlined,
    'vendor': Icons.store_outlined,
  };

  IconData _iconForIntent(String slug) =>
      _intentIcons[slug] ?? Icons.auto_awesome_outlined;
  IconData _iconForInterest(String slug) =>
      _interestIcons[slug] ?? Icons.event_outlined;
  IconData _iconForRole(String slug) =>
      _roleIcons[slug] ?? Icons.person_outline;

  static const _fallbackCatalogue = <Map<String, dynamic>>[
    {'slug': 'weddings'},
    {'slug': 'birthdays'},
    {'slug': 'graduations'},
    {'slug': 'anniversaries'},
    {'slug': 'baby_showers'},
    {'slug': 'private_parties'},
    {'slug': 'concerts'},
    {'slug': 'festivals'},
    {'slug': 'nightlife'},
    {'slug': 'conferences'},
    {'slug': 'workshops'},
    {'slug': 'networking'},
    {'slug': 'corporate'},
    {'slug': 'exhibitions'},
    {'slug': 'fashion_shows'},
    {'slug': 'sports_events'},
    {'slug': 'faith'},
    {'slug': 'cultural'},
    {'slug': 'community'},
    {'slug': 'charity'},
    {'slug': 'food_events'},
    {'slug': 'memorials'},
    {'slug': 'retreats'},
  ];

  static const _fallbackRoles = <Map<String, dynamic>>[
    {'slug': 'attendee'},
    {'slug': 'host'},
    {'slug': 'planner'},
    {'slug': 'vendor'},
  ];

  static const _fallbackIntents = <Map<String, dynamic>>[
    {'slug': 'plan_event'},
    {'slug': 'buy_tickets'},
    {'slug': 'discover_events'},
    {'slug': 'offer_service'},
    {'slug': 'host_community'},
    {'slug': 'share_moments'},
    {'slug': 'network'},
    {'slug': 'just_exploring'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiBase.get('/users/profile/interests');
    if (!mounted) return;
    final data = res['data'];
    final cat = (data is Map ? data['catalogue'] : null);
    final sel = (data is Map ? data['selected'] : null);
    final roles = (data is Map ? data['roles'] : null);
    final role = (data is Map ? data['role'] : null);
    final intentsCat = (data is Map ? data['intents_catalogue'] : null);
    final intentsSel = (data is Map ? data['intents'] : null);
    setState(() {
      _loading = false;
      _catalogue = (cat is List && cat.isNotEmpty)
          ? cat
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
          : _fallbackCatalogue;
      _roles = (roles is List && roles.isNotEmpty)
          ? roles
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
          : _fallbackRoles;
      _intentsCatalogue = (intentsCat is List && intentsCat.isNotEmpty)
          ? intentsCat
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
          : _fallbackIntents;
      if (sel is List) _selected.addAll(sel.map((e) => e.toString()));
      if (intentsSel is List) _intents.addAll(intentsSel.map((e) => e.toString()));
      if (role is String && role.isNotEmpty) _role = role;
    });
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    try {
      await ApiBase.put('/users/profile/interests', {
        'interests': _selected.toList(),
        'intents': _intents.toList(),
        if (_role != null) 'role': _role,
      });
    } catch (_) {}
    if (!mounted) return;
    if (widget.fromSettings) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _next() {
    if (_step == 0 && _intents.isNotEmpty) {
      setState(() => _step = 1);
      return;
    }
    if (_step == 1 && _selected.length >= 3) {
      setState(() => _step = 2);
      return;
    }
    _finish();
  }

  String _primaryCta(BuildContext context) {
    if (_step == 0) {
      if (_intents.isEmpty) return context.trw('interests_pick_at_least_one');
      return context.trw('continue');
    }
    if (_step == 1) {
      if (_selected.length < 3) {
        return context
            .trw('interests_pick_n_more')
            .replaceAll('{n}', '${3 - _selected.length}');
      }
      return context.trw('continue');
    }
    if (widget.fromSettings) return context.trw('interests_save_changes');
    return _role == null
        ? context.trw('interests_finish')
        : context.trw('interests_lets_go');
  }

  bool get _canPrimary {
    if (_saving) return false;
    if (_step == 0) return _intents.isNotEmpty;
    if (_step == 1) return _selected.length >= 3;
    return true;
  }

  String _intentLabel(String slug) => context.trw('intent_$slug');
  String _intentHint(String slug) => context.trw('intent_${slug}_hint');
  String _interestLabel(String slug) => context.trw('interest_$slug');
  String _roleLabel(String slug) => context.trw('role_$slug');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 8),
                  _progress(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _step == 0
                          ? _stepIntents()
                          : (_step == 1 ? _stepInterests() : _stepRole()),
                    ),
                  ),
                  _footer(context),
                ],
              ),
      ),
    );
  }

  // ── Header ──
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          if (_step >= 1)
            GestureDetector(
              onTap: () => setState(() => _step -= 1),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEDEDF2)),
                ),
                child: const Icon(Icons.chevron_left_rounded,
                    size: 20, color: AppColors.textPrimary),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: _saving
                ? null
                : (widget.fromSettings
                    ? () => Navigator.of(context).pop()
                    : _finish),
            child: Text(
              widget.fromSettings
                  ? context.trw('cancel')
                  : context.trw('skip'),
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        Expanded(child: _bar(active: true)),
        const SizedBox(width: 6),
        Expanded(child: _bar(active: _step >= 1)),
        const SizedBox(width: 6),
        Expanded(child: _bar(active: _step >= 2)),
      ]),
    );
  }

  Widget _bar({required bool active}) => AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        height: 4,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : const Color(0xFFEDEDF2),
          borderRadius: BorderRadius.circular(4),
        ),
      );

  // ── Step 0: Signup intents ──
  Widget _stepIntents() {
    return ListView(
      key: const ValueKey('s0'),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      children: [
        Text(
          context.trw('interests_step_intent_title'),
          style: GoogleFonts.inter(
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.trw('interests_step_intent_subtitle'),
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        ..._intentsCatalogue.map(_intentCard),
      ],
    );
  }

  Widget _intentCard(Map<String, dynamic> r) {
    final slug = r['slug']?.toString() ?? '';
    final on = _intents.contains(slug);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            if (on) {
              _intents.remove(slug);
            } else {
              _intents.add(slug);
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: on ? AppColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on ? AppColors.primary : const Color(0xFFEDEDF2),
              width: on ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.primary : const Color(0xFFFBFAF7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _iconForIntent(slug),
                size: 22,
                color: on ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _intentLabel(slug),
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _intentHint(slug),
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: on ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: on ? AppColors.primary : const Color(0xFFD8D6CD),
                  width: 1.5,
                ),
              ),
              child: on
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
          ]),
        ),
      ),
    );
  }

  // ── Step 1: Interests ──
  Widget _stepInterests() {
    return ListView(
      key: const ValueKey('s1'),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      children: [
        Text(
          context.trw('interests_step_kinds_title'),
          style: GoogleFonts.inter(
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.trw('interests_step_kinds_subtitle'),
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _catalogue.map(_chip).toList(),
        ),
      ],
    );
  }

  Widget _chip(Map<String, dynamic> item) {
    final slug = item['slug']?.toString() ?? '';
    final on = _selected.contains(slug);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (on) {
            _selected.remove(slug);
          } else {
            _selected.add(slug);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: on ? AppColors.primary : const Color(0xFFE8E6DE),
          ),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.20),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            _iconForInterest(slug),
            size: 16,
            color: on ? Colors.white : AppColors.textPrimary,
          ),
          const SizedBox(width: 8),
          Text(
            _interestLabel(slug),
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: on ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ]),
      ),
    );
  }

  // ── Step 2: Role ──
  Widget _stepRole() {
    return ListView(
      key: const ValueKey('s2'),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      children: [
        Text(
          context.trw('interests_step_role_title'),
          style: GoogleFonts.inter(
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.trw('interests_step_role_subtitle'),
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        ..._roles.map(_roleCard),
      ],
    );
  }

  Widget _roleCard(Map<String, dynamic> r) {
    final slug = r['slug']?.toString() ?? '';
    final on = _role == slug;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _role = on ? null : slug);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: on ? AppColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on ? AppColors.primary : const Color(0xFFEDEDF2),
              width: on ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.primary : const Color(0xFFFBFAF7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _iconForRole(slug),
                size: 22,
                color: on ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _roleLabel(slug),
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: on ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: on ? AppColors.primary : const Color(0xFFD8D6CD),
                  width: 1.5,
                ),
              ),
              child: on
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
          ]),
        ),
      ),
    );
  }

  // ── Footer ──
  Widget _footer(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _canPrimary ? _next : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE5E5EA),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              textStyle: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(_primaryCta(context)),
          ),
        ),
      ),
    );
  }
}
