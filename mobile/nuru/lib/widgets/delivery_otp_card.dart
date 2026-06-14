import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/services/delivery_otp_service.dart';
import '../core/theme/app_colors.dart';

/// Phase 1.3 - On-site service-delivery check-in card.
///
/// Vendor view: "Arrived" button → 6-digit input.
/// Organiser view: shows the 6-digit code to read out.
/// Once confirmed, both sides see a green "Delivery confirmed" panel and the
/// organiser can release escrow.
class DeliveryOtpCard extends StatefulWidget {
  final String bookingId;
  final String viewerRole; // 'organiser' | 'vendor'
  final VoidCallback? onConfirmed;

  const DeliveryOtpCard({
    super.key,
    required this.bookingId,
    required this.viewerRole,
    this.onConfirmed,
  });

  @override
  State<DeliveryOtpCard> createState() => _DeliveryOtpCardState();
}

class _DeliveryOtpCardState extends State<DeliveryOtpCard> {
  Map<String, dynamic>? _state;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  Timer? _ticker;
  String _countdown = '';

  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _recomputeCountdown());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await DeliveryOtpService.getState(widget.bookingId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _state = res['data'] as Map<String, dynamic>?;
        _recomputeCountdown();
      } else {
        _error = res['message']?.toString() ?? 'Failed to load';
      }
    });
  }

  void _recomputeCountdown() {
    final active = _state?['active'] as Map<String, dynamic>?;
    final expiresAt = active?['expires_at']?.toString();
    if (expiresAt == null) {
      if (_countdown.isNotEmpty && mounted) setState(() => _countdown = '');
      return;
    }
    final exp = DateTime.tryParse(expiresAt);
    if (exp == null) return;
    final diff = exp.difference(DateTime.now());
    final newVal = diff.isNegative
        ? 'expired'
        : '${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}';
    if (newVal != _countdown && mounted) {
      setState(() => _countdown = newVal);
    }
  }

  Future<void> _arrive() async {
    setState(() => _busy = true);
    final res = await DeliveryOtpService.arrive(widget.bookingId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res['message']?.toString() ?? 'Done')),
    );
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code')),
      );
      return;
    }
    setState(() => _busy = true);
    final res = await DeliveryOtpService.verify(widget.bookingId, code);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res['message']?.toString() ?? 'Done')),
    );
    if (res['success'] == true) {
      _codeCtrl.clear();
      widget.onConfirmed?.call();
      await _load();
    } else {
      await _load();
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    await DeliveryOtpService.cancel(widget.bookingId);
    if (!mounted) return;
    setState(() => _busy = false);
    _codeCtrl.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            : _error != null
                ? Text(_error!, style: GoogleFonts.inter(color: Colors.redAccent))
                : _build(),
      ),
    );
  }

  Widget _build() {
    final state = _state ?? {};
    final confirmed = state['confirmed'] as Map<String, dynamic>?;
    final active = state['active'] as Map<String, dynamic>?;
    final maxAttempts = state['max_attempts'] ?? 5;

    // ✅ Confirmed
    if (confirmed != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.verified_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 6),
            Text('Delivery confirmed',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 6),
          Text('Confirmed on ${confirmed['confirmed_at']}',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary)),
          if (widget.viewerRole == 'organiser') ...[
            const SizedBox(height: 8),
            Text('You can now release funds to the vendor.',
                style: GoogleFonts.inter(fontSize: 13)),
          ],
        ],
      );
    }

    // Header
    final header = Row(children: [
      Icon(Icons.shield_outlined, size: 18, color: AppColors.primary),
      const SizedBox(width: 6),
      Text('On-site check-in',
          style:
              GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15)),
    ]);

    // No active code
    if (active == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 10),
          Text(
            widget.viewerRole == 'vendor'
                ? "When you arrive on site, tap below to issue a one-time code. Ask the organiser to read it out, then enter it here to confirm delivery and unlock payment."
                : 'The vendor will tap "Arrived" on their side. A 6-digit code will then appear here for you to share in person.',
            style: GoogleFonts.inter(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          if (widget.viewerRole == 'vendor') ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : _arrive,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text("I've arrived · issue code"),
            ),
          ],
        ],
      );
    }

    // Active code present - branch on viewer
    if (widget.viewerRole == 'organiser') {
      final code = active['code']?.toString() ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 8),
          Text(
            'Read this code to the vendor in person. Expires in $_countdown.',
            style: GoogleFonts.inter(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                code,
                style: GoogleFonts.robotoMono(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Do not share over phone or text · only in person.',
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      );
    }

    // Vendor: enter code
    final attempts = active['attempts'] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 8),
        Text(
          'Code issued. Ask the organiser for the 6 digits and enter them below. Expires in $_countdown.',
          style: GoogleFonts.inter(
              fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.robotoMono(
              fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 6),
          decoration: InputDecoration(
            counterText: '',
            hintText: '------',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 6),
        Text('Attempts: $attempts/$maxAttempts',
            style: GoogleFonts.inter(
                fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _busy ? null : _verify,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Confirm delivery'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy ? null : _cancel,
            child: const Text('Cancel'),
          ),
        ]),
      ],
    );
  }
}
