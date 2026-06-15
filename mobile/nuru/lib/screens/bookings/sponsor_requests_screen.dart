import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/widgets/amount_input.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/user_services_service.dart';
import '../../core/utils/money_format.dart';
import '../../core/widgets/nuru_refresh.dart';
import '../../core/widgets/nuru_skeleton.dart';

/// Vendor-side inbox of event sponsorship invitations.
/// Mirrors the bookings screen structure: header, tabs (status filter), list.
class SponsorRequestsScreen extends StatefulWidget {
  const SponsorRequestsScreen({super.key});

  @override
  State<SponsorRequestsScreen> createState() => _SponsorRequestsScreenState();
}

class _SponsorRequestsScreenState extends State<SponsorRequestsScreen> {
  static const _filters = ['pending', 'accepted', 'declined'];
  static const _labels = ['Pending', 'Accepted', 'Declined'];

  int _active = 0;
  bool _loading = true;
  List<dynamic> _items = [];
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await UserServicesService.getMySponsorRequests();
    if (!mounted) return;
    setState(() {
      if (!silent) _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        if (data is Map) {
          final all = (data['items'] ?? []) as List;
          _pendingCount = (data['pending_count'] as num?)?.toInt() ?? 0;
          _items = all
              .where((e) =>
                  e is Map &&
                  (e['status']?.toString() ?? '') == _filters[_active])
              .toList();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            _tabs(),
            const SizedBox(height: 12),
            if (_pendingCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'You have $_pendingCount pending sponsorship ${_pendingCount == 1 ? 'request' : 'requests'}.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: NuruRefresh(
                onRefresh: () => _load(silent: true),
                child: _loading
                    ? _skeleton()
                    : (_items.isEmpty ? _empty() : _list()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SvgPicture.asset('assets/icons/arrow-left-icon.svg',
                width: 22,
                height: 22,
                colorFilter: const ColorFilter.mode(
                    AppColors.textPrimary, BlendMode.srcIn)),
          ),
        ),
        Expanded(
          child: Center(
            child: Text(
              'Sponsorship Requests',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 42),
      ]),
    );
  }

  Widget _tabs() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 1),
        ),
      ),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final selected = i == _active;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _active = i);
                _load();
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                child: Column(
                  children: [
                    Text(
                      _labels[i],
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color:
                            selected ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _skeleton() {
    return const NuruSkeletonEventList(
      itemCount: 4,
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: AlwaysScrollableScrollPhysics(),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(32),
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset('assets/icons/thunder-icon.svg',
                    width: 26,
                    height: 26,
                    colorFilter: const ColorFilter.mode(
                        AppColors.textHint, BlendMode.srcIn)),
              ),
              const SizedBox(height: 16),
              Text('No ${_labels[_active].toLowerCase()} requests',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Organizers can invite your services as event sponsors. Their requests will appear here.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final r = _items[i] as Map<String, dynamic>;
        return _SponsorCard(req: r, onAfter: _load);
      },
    );
  }
}

class _SponsorCard extends StatelessWidget {
  final Map<String, dynamic> req;
  final Future<void> Function() onAfter;
  const _SponsorCard({required this.req, required this.onAfter});

  @override
  Widget build(BuildContext context) {
    final service = req['service'] is Map ? req['service'] as Map : const {};
    final event = req['event'] is Map ? req['event'] as Map : const {};
    final status = (req['status'] ?? 'pending').toString();
    final amount = req['contribution_amount'];
    final image = service['image']?.toString();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  image: image != null && image.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(image), fit: BoxFit.cover)
                      : null,
                ),
                alignment: Alignment.center,
                child: image == null || image.isEmpty
                    ? Text(
                        (service['title']?.toString() ?? 'S')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service['title']?.toString() ?? 'Service',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'For: ${event['title']?.toString() ?? 'Event'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              _statusBadge(status),
            ],
          ),
          if (amount != null) ...[
            const SizedBox(height: 10),
            Text(
              'Suggested: ${formatMoney(amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0, currency: 'TZS')}',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
          if ((req['message']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              req['message'].toString(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
          if (status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.borderLight),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () =>
                        _showRespond(context, req, 'decline', onAfter),
                    child: Text(
                      'Decline',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () =>
                        _showRespond(context, req, 'accept', onAfter),
                    child: Text(
                      'Accept',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(String s) {
    Color bg;
    Color fg;
    String label;
    switch (s) {
      case 'accepted':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        label = 'Accepted';
        break;
      case 'declined':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        label = 'Declined';
        break;
      default:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

Future<void> _showRespond(BuildContext context, Map<String, dynamic> req,
    String action, Future<void> Function() onAfter) async {
  final amountCtrl = TextEditingController(
      text: req['contribution_amount'] != null
          ? '${req['contribution_amount']}'
          : '');
  final noteCtrl = TextEditingController();
  bool submitting = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setSt) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                action == 'accept'
                    ? 'Accept sponsorship'
                    : 'Decline sponsorship',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              if (action == 'accept') ...[
                Text('Confirmed contribution (TZS)',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: amountFormatters,
                  decoration: _fieldDecor('e.g., 500,000'),
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      decorationThickness: 0),
                ),
                const SizedBox(height: 14),
              ],
              Text(action == 'accept' ? 'Message to organizer' : 'Reason',
                  style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: _fieldDecor(action == 'accept'
                    ? 'Glad to be part of your event...'
                    : 'Thanks for the invitation, however...'),
                style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    decorationThickness: 0),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderLight),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Cancel',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              setSt(() => submitting = true);
                              final amt = action == 'accept' &&
                                      amountCtrl.text.trim().isNotEmpty
                                  ? parseAmount(amountCtrl.text)
                                  : null;
                              final res =
                                  await UserServicesService.respondToSponsorRequest(
                                req['id'].toString(),
                                action: action,
                                responseNote: noteCtrl.text.trim().isEmpty
                                    ? null
                                    : noteCtrl.text.trim(),
                                contributionAmount: amt,
                              );
                              if (!ctx.mounted) return;
                              if (res['success'] == true) {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(action == 'accept'
                                        ? 'Sponsorship accepted'
                                        : 'Sponsorship declined'),
                                  ),
                                );
                                await onAfter();
                              } else {
                                setSt(() => submitting = false);
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          (res['message'] ?? 'Failed').toString())),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: action == 'accept'
                            ? AppColors.primary
                            : const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        submitting
                            ? 'Sending...'
                            : (action == 'accept' ? 'Accept' : 'Decline'),
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      });
    },
  );
}

InputDecoration _fieldDecor(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textHint),
    filled: true,
    fillColor: AppColors.surfaceVariant,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderSide: BorderSide.none,
      borderRadius: BorderRadius.circular(12),
    ),
  );
}
