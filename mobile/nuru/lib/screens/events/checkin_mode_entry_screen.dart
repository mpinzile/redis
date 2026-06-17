import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/services/checkin_session.dart';
import '../../core/services/checkin_team_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import 'checkin_mode_screen.dart';

/// Entry screen for the **Check-In Mode** flow.
///
/// A team member taps the QR icon on the My Events tab, enters the
/// `NRU-XXXX-XXXX` access code shared by the event organizer, and the
/// backend exchanges it for a scoped scanner session. Once redeemed we
/// push the locked scanner shell ([CheckinModeScreen]).
class CheckinModeEntryScreen extends StatefulWidget {
  const CheckinModeEntryScreen({super.key});

  @override
  State<CheckinModeEntryScreen> createState() => _CheckinModeEntryScreenState();
}

class _CheckinModeEntryScreenState extends State<CheckinModeEntryScreen> {
  final List<TextEditingController> _ctrls =
      List.generate(8, (_) => TextEditingController());
  final List<FocusNode> _focus = List.generate(8, (_) => FocusNode());
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // If a session is already live, jump straight into Check-In Mode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (CheckinSession.isActive && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const CheckinModeScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code {
    final left = _ctrls.sublist(0, 4).map((c) => c.text).join();
    final right = _ctrls.sublist(4, 8).map((c) => c.text).join();
    return 'NRU-$left-$right';
  }

  bool get _ready => _ctrls.every((c) => c.text.trim().isNotEmpty);

  Future<void> _redeem() async {
    if (!_ready || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await CheckinTeamService.redeem(_code);
    if (!mounted) return;
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
    if (res['success'] == true && (data['session_token']?.toString().isNotEmpty ?? false)) {
      final event = data['event'] is Map ? Map<String, dynamic>.from(data['event'] as Map) : <String, dynamic>{};
      await CheckinSession.begin(
        token: data['session_token'].toString(),
        sessionId: (data['session_id'] ?? '').toString(),
        eventId: (event['id'] ?? data['event_id'] ?? '').toString(),
        event: event.isEmpty ? null : event,
        permissions: data['permissions'] is Map ? Map<String, dynamic>.from(data['permissions'] as Map) : null,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CheckinModeScreen()),
      );
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _submitting = false;
        _error = (res['message'] ?? 'That code is invalid or expired.').toString();
      });
    }
  }

  void _pasteCode(String raw) {
    // Accept "NRU-ABCD-1234", "ABCD-1234", "ABCD1234" or even spaces.
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final trimmed = cleaned.startsWith('NRU') ? cleaned.substring(3) : cleaned;
    final chars = trimmed.split('').take(8).toList();
    for (var i = 0; i < 8; i++) {
      _ctrls[i].text = i < chars.length ? chars[i] : '';
    }
    setState(() {});
    if (chars.length >= 8) {
      FocusScope.of(context).unfocus();
      _redeem();
    } else {
      _focus[chars.length].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('Check-In Mode', style: appText(size: 18, weight: FontWeight.w800)),
        leading: IconButton(
          icon: SvgPicture.asset(
            'assets/icons/arrow-left-icon.svg',
            width: 22,
            height: 22,
            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // ── Hero ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.08),
                    AppColors.primary.withValues(alpha: 0.02),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
              ),
              child: Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/icons/check-in-reception-icon.svg',
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Enter Access Code', style: appText(size: 16, weight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      'Paste the NRU code shared by the event organizer to start scanning guests or tickets.',
                      style: appText(size: 12, color: AppColors.textSecondary, weight: FontWeight.w500),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 24),

            // ── Code input ──
            Center(
              child: Text('NRU',
                  style: appText(size: 13, weight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 3)),
            ),
            const SizedBox(height: 8),
            _codeRow(0, 4),
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 22,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _codeRow(4, 8),
            const SizedBox(height: 16),
            if (_error != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFD32F2F), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: appText(size: 12, color: const Color(0xFFD32F2F), weight: FontWeight.w600)),
                  ),
                ]),
              ),
            if (_error != null) const SizedBox(height: 14),

            // ── Submit ──
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _ready && !_submitting ? _redeem : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.borderLight,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text('Enter Check-In Mode',
                        style: appText(size: 15, weight: FontWeight.w800, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  final t = data?.text?.trim();
                  if (t != null && t.isNotEmpty) _pasteCode(t);
                },
                icon: const Icon(Icons.content_paste_rounded, size: 16, color: AppColors.textSecondary),
                label: Text('Paste from clipboard',
                    style: appText(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary)),
              ),
            ),
            const SizedBox(height: 28),

            // ── Helper ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You will only be able to scan guests or tickets for the event tied to this code. You will not gain access to the organizer account.',
                    style: appText(size: 12, color: AppColors.textSecondary, weight: FontWeight.w500, height: 1.4),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeRow(int start, int end) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(end - start, (i) {
        final idx = start + i;
        return Padding(
          padding: EdgeInsets.only(right: i == (end - start - 1) ? 0 : 8),
          child: _codeBox(idx),
        );
      }),
    );
  }

  Widget _codeBox(int i) {
    return SizedBox(
      width: 40,
      height: 56,
      child: TextField(
        controller: _ctrls[i],
        focusNode: _focus[i],
        textAlign: TextAlign.center,
        maxLength: 1,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        style: appText(size: 20, weight: FontWeight.w800, letterSpacing: 0),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
          TextInputFormatter.withFunction((oldV, newV) =>
              newV.copyWith(text: newV.text.toUpperCase())),
        ],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary, width: 1.6),
          ),
        ),
        onChanged: (v) {
          if (v.length > 1) {
            _pasteCode(v);
            return;
          }
          if (v.isNotEmpty && i < 7) {
            _focus[i + 1].requestFocus();
          } else if (v.isEmpty && i > 0) {
            _focus[i - 1].requestFocus();
          }
          setState(() {});
          if (_ready) {
            FocusScope.of(context).unfocus();
            _redeem();
          }
        },
      ),
    );
  }
}
