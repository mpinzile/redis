/// PublicContributeScreen - native parity for the web `/c/:token` page.
///
/// Shows a hero event cover, pledge / paid / balance breakdown with a
/// progress bar, then opens the canonical [MakePaymentScreen] checkout.
import 'package:nuru/core/utils/money_format.dart'
    show getActiveCurrency, formatMoney;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/event_cover_image.dart';
import '../../core/services/api_base.dart';
import '../wallet/make_payment_screen.dart';

class PublicContributeScreen extends StatefulWidget {
  final String token;

  const PublicContributeScreen({super.key, required this.token});

  @override
  State<PublicContributeScreen> createState() => _PublicContributeScreenState();
}

class _PublicContributeScreenState extends State<PublicContributeScreen> {
  Map<String, dynamic>? _link;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLink();
  }

  Future<void> _loadLink({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await ApiBase.getRaw('/public/contributions/${widget.token}');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true && res['data'] is Map<String, dynamic>) {
        _link = res['data'] as Map<String, dynamic>;
      }
    });
    if (_link == null && !silent) {
      AppSnackbar.error(context, 'Link is invalid or expired');
    }
  }

  String? _eventId() {
    final ev = _link?['event'];
    if (ev is Map) return ev['id']?.toString();
    return _link?['event_id']?.toString();
  }

  num _num(dynamic raw) {
    if (raw is num) return raw;
    return num.tryParse(raw?.toString() ?? '') ?? 0;
  }

  num get _pledge => _num(_link?['pledge_amount'] ?? _link?['suggested_amount']);
  num get _paid => _num(_link?['total_paid']);
  num get _balance {
    final b = _link?['balance'];
    if (b != null) return _num(b);
    final diff = _pledge - _paid;
    return diff < 0 ? 0 : diff;
  }

  void _openCheckout() {
    final eventId = _eventId();
    if (eventId == null || eventId.isEmpty) {
      AppSnackbar.error(context, 'This link is missing event details');
      return;
    }
    final ev = _link?['event'] is Map ? _link!['event'] as Map : const {};
    final eventTitle = (ev['name'] ?? ev['title'] ?? 'Event contribution')
        .toString();
    final cover =
        (ev['cover_image_url'] ?? ev['cover_image'] ?? '').toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MakePaymentScreen(
          targetType: 'event_contribution',
          targetId: eventId,
          amount: _balance > 0 ? _balance : null,
          amountEditable: true,
          allowBank: false,
          title: 'Pay contribution',
          description: 'For $eventTitle',
          summaryImageUrl: cover.isNotEmpty ? cover : null,
          summaryMeta: eventTitle,
          onSuccess: (_) {
            _loadLink(silent: true);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ev = _link?['event'] is Map ? _link!['event'] as Map : const {};
    final eventTitle = (ev['name'] ?? ev['title'] ?? 'Event contribution')
        .toString();
    final cover =
        (ev['cover_image_url'] ?? ev['cover_image'] ?? '').toString();
    final organiser =
        (ev['organiser_name'] ?? _link?['organiser_name'] ?? '').toString();

    final currency =
        (_link?['currency_code'] ?? _link?['currency'] ?? getActiveCurrency())
            .toString();
    final note = (_link?['contribution_payment_instructions'] ?? '')
        .toString()
        .trim();

    final contributor = _link?['contributor'] is Map
        ? _link!['contributor'] as Map
        : const {};
    final contributorName = (contributor['name'] ?? '').toString();

    final pledged = _pledge;
    final paid = _paid;
    final balance = _balance;
    final progress = pledged > 0
        ? (paid / pledged).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final fullySettled = pledged > 0 && balance <= 0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const NuruSubPageAppBar(title: 'Contribute'),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          : _link == null
              ? _invalidLinkState()
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => _loadLink(silent: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      // Hero event cover
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: EventCoverImage(
                          url: cover.isNotEmpty ? cover : null,
                          width: double.infinity,
                          height: 180,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        eventTitle,
                        style: GoogleFonts.sora(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      if (organiser.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Organised by $organiser',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Target / Paid / Balance summary
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.borderLight),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x08000000),
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (contributorName.isNotEmpty)
                              Text(
                                'Hi $contributorName, your pledge',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            else
                              Text(
                                'Your pledge',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            const SizedBox(height: 6),
                            Text(
                              formatMoney(pledged, currency: currency),
                              style: GoogleFonts.sora(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 10,
                                backgroundColor: AppColors.borderLight,
                                valueColor: const AlwaysStoppedAnimation(
                                  AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _statTile(
                                    'Paid so far',
                                    formatMoney(paid, currency: currency),
                                    valueColor: AppColors.success,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 36,
                                  color: AppColors.borderLight,
                                ),
                                Expanded(
                                  child: _statTile(
                                    fullySettled ? 'Status' : 'Balance',
                                    fullySettled
                                        ? 'Fully settled'
                                        : formatMoney(balance,
                                            currency: currency),
                                    valueColor: fullySettled
                                        ? AppColors.success
                                        : AppColors.primary,
                                    alignEnd: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            note,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: fullySettled ? null : _openCheckout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: AppColors.borderLight,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            fullySettled
                                ? 'Pledge fully settled'
                                : 'Continue to payment',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: fullySettled
                                  ? AppColors.textTertiary
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Pay with Nuru Wallet, mobile money (M-Pesa, Tigo Pesa, Airtel Money), or bank transfer. You\u2019ll get a receipt right after.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _statTile(
    String label,
    String value, {
    Color? valueColor,
    bool alignEnd = false,
  }) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.sora(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _invalidLinkState() => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link_off_rounded,
                size: 56, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              'This contribution link is invalid or expired.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}
