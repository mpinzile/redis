import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/services/events_service.dart';
import '../../../core/services/scan_resolve_service.dart';
import '../checkin_success_screen.dart';
import '../checkin_failed_screen.dart';
import '../../../core/widgets/self_scrolling_pills.dart';

/// Premium full-screen Guest / Ticket Check-In scanner.
///
/// Continuous live camera, event hero card with real-time aggregate stats
/// (total / checked in / pending - labels & counts depend on whether the
/// event sells tickets), manual code entry, and a recent scans feed.
class EventCheckinTab extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic>? permissions;
  final String? eventTitle;
  final String? eventDate;
  final String? eventLocation;
  final int guestCount;
  final int confirmedCount;

  /// Called whenever the scanner resolves the page title from the API
  /// ("Guest Check In" / "Ticket Check In"). Hosts can use this to update
  /// their own AppBar title.
  final ValueChanged<String>? onTitleResolved;

  const EventCheckinTab({
    super.key,
    required this.eventId,
    this.permissions,
    this.eventTitle,
    this.eventDate,
    this.eventLocation,
    this.guestCount = 0,
    this.confirmedCount = 0,
    this.onTitleResolved,
  });

  @override
  State<EventCheckinTab> createState() => _EventCheckinTabState();
}

class _EventCheckinTabState extends State<EventCheckinTab>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _scanLineController;
  bool _torchOn = false;
  CameraFacing _facing = CameraFacing.back;
  bool _processing = false;
  bool _resultOpen = false;
  String? _lastCode;
  DateTime? _lastAt;

  Map<String, dynamic>? _event;
  Map<String, dynamic> _stats = {
    'mode': 'guests',
    'labels': {'total': 'Total Guests', 'checked_in': 'Checked In', 'pending': 'Pending'},
    'total': 0,
    'checked_in': 0,
    'pending': 0,
  };
  List<Map<String, dynamic>> _recent = [];
  bool _loadingStats = true;
  String? _resolvedTitle;
  bool _showingAllRecent = false;
  int _previewScenario = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    )..repeat(reverse: true);
    _loadStats();
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadStats({int limit = 10}) async {
    final res = await EventsService.getScanStats(widget.eventId, limit: limit);
    if (!mounted) return;
    if (res['success'] == true && res['data'] is Map) {
      final data = Map<String, dynamic>.from(res['data'] as Map);
      setState(() {
        _event = data['event'] is Map ? Map<String, dynamic>.from(data['event']) : null;
        if (data['stats'] is Map) {
          _stats = Map<String, dynamic>.from(data['stats'] as Map);
        }
        _recent = (data['recent_scans'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
        _loadingStats = false;
        _showingAllRecent = limit > 10;
        final t = data['title']?.toString();
        if (t != null && t.isNotEmpty && t != _resolvedTitle) {
          _resolvedTitle = t;
          widget.onTitleResolved?.call(t);
        }
      });
    } else {
      setState(() => _loadingStats = false);
    }
  }

  void _onBarcode(BarcodeCapture cap) {
    if (_resultOpen || _processing) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    _process(raw.trim());
  }

  /// Push a result screen, block further scans until it's dismissed, and
  /// auto-pop after 5 seconds so a guest holding the QR up doesn't cause
  /// the scanner to stack multiple result pages.
  Future<void> _pushResult(WidgetBuilder builder) async {
    _resultOpen = true;
    Timer? autoClose;
    final route = MaterialPageRoute(builder: builder);
    autoClose = Timer(const Duration(seconds: 5), () {
      if (route.isCurrent) Navigator.of(context).maybePop();
    });
    await Navigator.of(context).push(route);
    autoClose.cancel();
    _resultOpen = false;
    _lastCode = null;
    _lastAt = null;
  }

  Future<void> _process(String raw) async {
    if (_processing || _resultOpen) return;
    final now = DateTime.now();
    if (_lastCode == raw && _lastAt != null && now.difference(_lastAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastCode = raw;
    _lastAt = now;
    setState(() => _processing = true);

    // 1. Universal resolver — figure out what this QR is BEFORE mutating.
    final resolved = await ScanResolveService.resolve(raw, eventId: widget.eventId);
    final r = (resolved['data'] is Map)
        ? Map<String, dynamic>.from(resolved['data'] as Map)
        : <String, dynamic>{};
    final route = (r['route'] ?? 'unknown').toString();
    final payload = (r['payload'] is Map)
        ? Map<String, dynamic>.from(r['payload'] as Map)
        : <String, dynamic>{};
    final crossEvent = payload['cross_event'] == true;
    final resolvedMsg = (r['message'] ?? '').toString();

    String? blockMessage;
    if (route == 'checkin_code') {
      blockMessage = 'This is a Check-In Team access code. Tap the QR icon on My Events to redeem it.';
    } else if (route == 'contribution_pay' || route == 'contribution_receipt') {
      blockMessage = '${resolvedMsg.isEmpty ? 'Contribution link detected' : resolvedMsg} is not a pass for this event.';
    } else if (crossEvent) {
      final otherName = (r['event'] is Map) ? (r['event']['name'] ?? '').toString() : '';
      blockMessage = otherName.isNotEmpty
          ? 'This pass belongs to "$otherName". Open that event to check it in.'
          : 'This pass belongs to a different event.';
    } else if (route == 'unknown') {
      blockMessage = resolvedMsg.isEmpty ? 'We could not recognize this QR code.' : resolvedMsg;
    }

    if (blockMessage != null) {
      if (!mounted) return;
      setState(() => _processing = false);
      await _pushResult((_) => CheckinFailedScreen(
            data: r,
            message: blockMessage!,
            onScanAgain: () {},
            onManualCheckIn: () => _showManualEntry(),
          ));
      return;
    }

    final res = await EventsService.checkinByQR(widget.eventId, raw);
    if (!mounted) return;
    setState(() => _processing = false);

    final data = res['data'] is Map
        ? Map<String, dynamic>.from(res['data'] as Map)
        : <String, dynamic>{};
    if (data['stats'] is Map) {
      _stats = Map<String, dynamic>.from(data['stats'] as Map);
    }

    if (res['success'] == true) {
      setState(() {});
      await _pushResult((_) => CheckinSuccessScreen(
            data: data,
            onScanNext: () {},
          ));
      _loadStats();
    } else {
      setState(() {});
      await _pushResult((_) => CheckinFailedScreen(
            data: data,
            message: ((res['message'] ?? '').toString().isNotEmpty
                ? res['message'].toString()
                : (resolvedMsg.isNotEmpty ? resolvedMsg : 'Check-in failed')),
            onScanAgain: () {},
            onManualCheckIn: () => _showManualEntry(),
          ));
    }
  }

  void _showManualEntry() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 44, height: 4,
                decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Enter Ticket Code Manually',
                style: appText(size: 16, weight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Type the invitation or ticket code printed on the pass.',
                style: appText(size: 12, color: AppColors.textTertiary), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: appText(size: 16, weight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'e.g. AWD20260824-1587',
                hintStyle: appText(size: 14, color: AppColors.textHint),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  final v = ctrl.text.trim();
                  if (v.isEmpty) return;
                  Navigator.pop(ctx);
                  _lastCode = null;
                  _process(v);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Check In', style: appText(size: 14, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loadingStats && _event == null) return _skeleton();

    final cover = (_event?['cover_image'] ?? _event?['image'])?.toString();
    final eventName = (_event?['name'] ?? widget.eventTitle ?? 'Event').toString();
    final eventDate = _formatEventDate(_event?['start_date']?.toString() ?? widget.eventDate);
    final labels = (_stats['labels'] is Map)
        ? Map<String, dynamic>.from(_stats['labels'] as Map)
        : {'total': 'Total', 'checked_in': 'Checked In', 'pending': 'Pending'};
    final isTickets = _stats['mode'] == 'tickets';
    final total = _stats['total'] ?? 0;
    final checkedIn = _stats['checked_in'] ?? 0;
    final pending = _stats['pending'] ?? (total - checkedIn);

    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Event hero card ───
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 76, height: 92,
                  child: cover != null && cover.isNotEmpty
                      ? Image.network(cover, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _coverFallback())
                      : _coverFallback(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(eventName, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: appText(size: 15, weight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Row(children: [
                    SvgPicture.asset('assets/icons/calendar-icon.svg',
                        width: 12, height: 12,
                        colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                    const SizedBox(width: 5),
                    Text(eventDate, style: appText(size: 11, color: AppColors.textSecondary, weight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _miniStat(
                        isTickets ? 'assets/icons/ticket-icon.svg' : 'assets/icons/users-icon.svg',
                        labels['total']?.toString() ?? 'Total', '$total'),
                    _divider(),
                    _miniStat('assets/icons/verified-icon.svg',
                        labels['checked_in']?.toString() ?? 'Checked In', '$checkedIn'),
                    _divider(),
                    _miniStat('assets/icons/clock-icon.svg',
                        labels['pending']?.toString() ?? 'Pending', '$pending'),
                  ]),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // ─── Camera viewfinder ───
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onBarcode,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: const Text(
                        'QR scanning requires a physical device camera. Please test this feature on a real iPhone or iPad.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                      ),
                    ),
                  ),

                  // Pill label
                  Positioned(
                    top: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                          isTickets ? 'Scan ticket QR code' : 'Scan guest QR code',
                          style: appText(size: 12, weight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),

                  // Torch (svg)
                  Positioned(
                    top: 14, left: 14,
                    child: GestureDetector(
                      onTap: () { _controller.toggleTorch(); setState(() => _torchOn = !_torchOn); },
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/icons/thunder-icon.svg',
                            width: 18, height: 18,
                            colorFilter: ColorFilter.mode(
                              _torchOn ? AppColors.primary : Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Switch camera (svg)
                  Positioned(
                    top: 14, right: 14,
                    child: GestureDetector(
                      onTap: () {
                        _controller.switchCamera();
                        setState(() {
                          _facing = _facing == CameraFacing.back
                              ? CameraFacing.front
                              : CameraFacing.back;
                        });
                      },
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/icons/camera-icon.svg',
                            width: 20,
                            height: 20,
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Corner brackets - Nuru primary color
                  _frame(),
                  if (!_processing) _scannerLine(),

                  if (_processing)
                    Container(
                      color: Colors.black.withOpacity(0.55),
                      child: const Center(
                        child: SizedBox(
                          width: 32, height: 32,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── "or" divider ───
          Row(children: [
            Expanded(child: Divider(color: AppColors.borderLight, thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('or', style: appText(size: 12, color: AppColors.textTertiary)),
            ),
            Expanded(child: Divider(color: AppColors.borderLight, thickness: 1)),
          ]),
          const SizedBox(height: 12),

          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _showManualEntry,
              icon: SvgPicture.asset('assets/icons/keyboard-icon.svg',
                  width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
              label: Text('Enter Ticket Code Manually',
                  style: appText(size: 14, weight: FontWeight.w700, color: AppColors.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.primary, width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 22),

          // ─── Recent Scans ───
          Row(children: [
            Text('Recent Scans', style: appText(size: 15, weight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(
              onTap: () => _loadStats(limit: _showingAllRecent ? 10 : 100),
              child: Row(children: [
                Text(_showingAllRecent ? 'Show Less' : 'View All', style: appText(size: 12, weight: FontWeight.w700, color: AppColors.primary)),
                const SizedBox(width: 2),
                SvgPicture.asset('assets/icons/arrow-right-icon.svg',
                    width: 14, height: 14,
                    colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Builder(builder: (_) {
            // Show only actual check-in scans - pending RSVPs from the
            // backend feed are not real scans and must be hidden here.
            final scans = _recent.where((r) =>
                (r['status'] ?? '').toString() == 'checked_in').toList();
            if (_loadingStats) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            if (scans.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: SvgPicture.asset('assets/icons/qr-icon.svg',
                        width: 22, height: 22,
                        colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                  ),
                  const SizedBox(height: 10),
                  Text('No scans yet',
                      style: appText(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(isTickets ? 'Scan a ticket QR to begin.' : 'Scan a guest QR to begin.',
                      style: appText(size: 12, color: AppColors.textTertiary)),
                ]),
              );
            }
            return Column(
              children: List.generate(scans.length, (i) {
                return _recentTile(scans[i], isLast: i == scans.length - 1);
              }),
            );
          }),
          const SizedBox(height: 18),
          _testPreviewSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _testPreviewSection() {
    final scenarios = <_PreviewScenario>[
      const _PreviewScenario(
        label: 'Guest checked in', kind: 'success',
        title: 'Check in successful!', subtitle: 'Guest verified and admitted.',
        name: 'Amani Mushi', ticketType: 'Guest Pass',
        code: 'NRU-GST-1942', checkedInAt: '17 Jun 2026, 7:32 PM',
      ),
      const _PreviewScenario(
        label: 'Ticket checked in', kind: 'success',
        title: 'Check in successful!', subtitle: 'Ticket verified and admitted.',
        name: 'Neema Kileo', ticketType: 'VIP',
        code: 'NRU-T7-92K1', checkedInAt: '17 Jun 2026, 7:45 PM',
      ),
      const _PreviewScenario(
        label: 'Already checked in', kind: 'warning',
        title: 'Already Checked In', subtitle: 'Checked in earlier at 2:22 PM.',
        name: 'Baraka Mwakasege', ticketType: 'Guest Pass',
        code: 'NRU-GST-2048', checkedInAt: '17 Jun 2026, 2:22 PM',
      ),
      const _PreviewScenario(
        label: 'Not recognised', kind: 'error',
        title: "We couldn't check in this guest",
        subtitle: "We couldn't match this QR to any guest or ticket for this event.",
        name: 'Unknown', code: 'UNMATCHED-QR',
        reasonLabel: 'Not Recognised',
        whatThisMeans: 'The code may belong to another event, or the guest is not on the list.',
      ),
      const _PreviewScenario(
        label: 'Wrong event', kind: 'error',
        title: "We couldn't check in this guest",
        subtitle: 'This QR code belongs to a different event.',
        name: 'Joseph Kimaro', code: 'NRU-GST-7711',
        reasonLabel: 'Wrong Event',
        whatThisMeans: 'Switch to the correct event in the scanner and try again.',
      ),
      const _PreviewScenario(
        label: 'Awaiting payment', kind: 'error',
        title: "We couldn't check in this guest",
        subtitle: "This ticket hasn't been paid for yet.",
        name: 'Halima Said', code: 'NRU-T7-55C2',
        reasonLabel: 'Awaiting Payment',
        whatThisMeans: 'The buyer must complete payment before this ticket can be used.',
      ),
      const _PreviewScenario(
        label: 'Event ended', kind: 'warning',
        title: 'Check-In Closed', subtitle: 'This event has already ended.',
        name: 'Amani Mushi', ticketType: 'Guest Pass',
        code: 'NRU-GST-1942', checkedInAt: '17 Jun 2026, 7:32 PM',
        reasonLabel: 'Event Ended',
        whatThisMeans: 'Reopen check-in from event settings if guests are still arriving.',
      ),
    ];
    final idx = _previewScenario.clamp(0, scenarios.length - 1);
    final s = scenarios[idx];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(11)),
            child: Center(child: SvgPicture.asset('assets/icons/qr-icon.svg', width: 17, height: 17,
                colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Scan Previews', style: appText(size: 14, weight: FontWeight.w800)),
            Text('Preview every scan result.', style: appText(size: 11.5, color: AppColors.textTertiary)),
          ])),
        ]),
        const SizedBox(height: 12),
        SelfScrollingPills(
          activeIndex: idx,
          height: 34,
          children: List.generate(scenarios.length, (i) {
            final selected = i == idx;
            return GestureDetector(
              onTap: () => setState(() => _previewScenario = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: selected ? AppColors.primary : AppColors.borderLight),
                ),
                child: Text(scenarios[i].label, style: appText(
                  size: 11.5, weight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textSecondary,
                )),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Container(
            key: ValueKey(s.label),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
              color: Colors.white,
            ),
            child: s.kind == 'error' ? _previewError(s) : _previewSuccessOrWarning(s),
          ),
        ),
      ]),
    );
  }

  Widget _previewSuccessOrWarning(_PreviewScenario s) {
    final tone = s.kind == 'warning' ? const Color(0xFFB7791F) : AppColors.success;
    final iconAsset = s.kind == 'warning'
        ? 'assets/icons/secure-shield-icon.svg'
        : 'assets/icons/verified-icon.svg';
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [tone.withOpacity(0.18), tone.withOpacity(0.04)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
        child: Column(children: [
          Container(
            width: 76, height: 76,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            child: Center(child: SvgPicture.asset(iconAsset, width: 38, height: 38,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))),
          ),
          const SizedBox(height: 12),
          Text(s.title, style: appText(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(s.subtitle, style: appText(size: 12.5, color: AppColors.textTertiary), textAlign: TextAlign.center),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Guest Details', style: appText(size: 13, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          _previewRow('assets/icons/user-icon.svg', 'Guest Name', s.name, tone: tone),
          _previewRow('assets/icons/ticket-icon.svg', 'Ticket Type', s.ticketType ?? 'Guest Pass', tone: tone),
          _previewRow('assets/icons/ticket-icon.svg', 'Ticket ID', s.code, tone: tone, mono: true),
          _previewRow('assets/icons/clock-icon.svg', 'Checked In At', s.checkedInAt ?? '-', tone: tone, last: true),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tone.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withOpacity(0.22)),
        ),
        child: Row(children: [
          SvgPicture.asset('assets/icons/secure-shield-icon.svg', width: 18, height: 18,
              colorFilter: ColorFilter.mode(tone, BlendMode.srcIn)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.kind == 'warning' ? 'Already on the list' : 'All good to go',
                style: appText(size: 12.5, weight: FontWeight.w800)),
            Text(s.kind == 'warning' ? 'No duplicate entry recorded.' : 'Enjoy the event!',
                style: appText(size: 11.5, color: AppColors.textTertiary)),
          ])),
        ]),
      ),
    ]);
  }

  Widget _previewError(_PreviewScenario s) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        child: Column(children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.08), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Container(
              width: 58, height: 58,
              decoration: BoxDecoration(color: AppColors.error.withOpacity(0.14), shape: BoxShape.circle),
              child: Center(child: SvgPicture.asset('assets/icons/close-circle-icon.svg', width: 32, height: 32,
                  colorFilter: const ColorFilter.mode(AppColors.error, BlendMode.srcIn))),
            ),
          ),
          const SizedBox(height: 12),
          Text(s.title, style: appText(size: 16, weight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(s.subtitle, style: appText(size: 12, color: AppColors.textTertiary), textAlign: TextAlign.center),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Scan Details', style: appText(size: 13, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          _previewRow('assets/icons/clock-icon.svg', 'Scan Time', '17 Jun 2026, 7:32 PM', tone: AppColors.primary),
          _previewRow('assets/icons/user-icon.svg', 'Guest', s.name, tone: AppColors.primary),
          _previewRow('assets/icons/calendar-icon.svg', 'Event', 'Mlimani City Hall', tone: AppColors.primary),
          _previewRow('assets/icons/ticket-icon.svg', 'Ticket / QR Code', s.code, tone: AppColors.primary, mono: true),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: AppColors.error.withOpacity(0.10), shape: BoxShape.circle),
                child: Center(child: SvgPicture.asset('assets/icons/info-icon.svg', width: 14, height: 14,
                    colorFilter: const ColorFilter.mode(AppColors.error, BlendMode.srcIn))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('Reason', style: appText(size: 12.5, color: AppColors.textSecondary, weight: FontWeight.w500))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.error.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
                child: Text(s.reasonLabel ?? '-', style: appText(size: 11.5, weight: FontWeight.w700, color: AppColors.error)),
              ),
            ]),
          ),
        ]),
      ),
      if ((s.whatThisMeans ?? '').isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withOpacity(0.18)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('What this means', style: appText(size: 12.5, weight: FontWeight.w800, color: AppColors.error)),
            const SizedBox(height: 3),
            Text(s.whatThisMeans!, style: appText(size: 12, color: AppColors.textSecondary, weight: FontWeight.w500)),
          ]),
        ),
    ]);
  }

  Widget _previewRow(String iconAsset, String label, String value, {required Color tone, bool last = false, bool mono = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: AppColors.borderLight.withOpacity(0.7))),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: tone.withOpacity(0.12), shape: BoxShape.circle),
          child: Center(child: SvgPicture.asset(iconAsset, width: 14, height: 14,
              colorFilter: ColorFilter.mode(tone, BlendMode.srcIn))),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(label, style: appText(size: 12.5, color: AppColors.textSecondary, weight: FontWeight.w500)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(value,
                textAlign: TextAlign.right,
                style: appText(
                  size: mono ? 11.5 : 12.5,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.35,
                )),
          ),
        ),
      ]),
    );
  }


  Widget _miniPill(String text, {bool mono = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.borderLight)),
        child: Text(text, style: appText(size: mono ? 10.5 : 11, weight: FontWeight.w700, color: AppColors.textSecondary)),
      );

  Widget _coverFallback() => Container(
        color: AppColors.primary.withOpacity(0.12),
        child: Center(
          child: SvgPicture.asset('assets/icons/calendar-icon.svg',
              width: 28, height: 28,
              colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
        ),
      );

  Widget _miniStat(String iconAsset, String label, String value) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SvgPicture.asset(iconAsset, width: 11, height: 11,
              colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: appText(size: 9.5, color: AppColors.textTertiary, weight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 2),
        Text(value, style: appText(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
      ]),
    );
  }

  Widget _divider() => Container(
        width: 1, height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: AppColors.borderLight,
      );

  Widget _frame() {
    const c = AppColors.primary;
    BoxDecoration corner({bool top = false, bool bottom = false, bool left = false, bool right = false}) {
      return BoxDecoration(
        border: Border(
          top: top ? const BorderSide(color: c, width: 3.5) : BorderSide.none,
          bottom: bottom ? const BorderSide(color: c, width: 3.5) : BorderSide.none,
          left: left ? const BorderSide(color: c, width: 3.5) : BorderSide.none,
          right: right ? const BorderSide(color: c, width: 3.5) : BorderSide.none,
        ),
      );
    }

    Widget cornerW(BoxDecoration d, {Alignment align = Alignment.topLeft}) =>
        Align(alignment: align, child: Container(width: 32, height: 32, decoration: d));

    return Padding(
      padding: const EdgeInsets.all(64),
      child: Stack(children: [
        cornerW(corner(top: true, left: true), align: Alignment.topLeft),
        cornerW(corner(top: true, right: true), align: Alignment.topRight),
        cornerW(corner(bottom: true, left: true), align: Alignment.bottomLeft),
        cornerW(corner(bottom: true, right: true), align: Alignment.bottomRight),
      ]),
    );
  }

  Widget _scannerLine() {
    return Padding(
      padding: const EdgeInsets.all(72),
      child: AnimatedBuilder(
        animation: _scanLineController,
        builder: (context, child) {
          final y = Alignment.lerp(
            const Alignment(0, -0.92),
            const Alignment(0, 0.92),
            Curves.easeInOut.transform(_scanLineController.value),
          )!;
          return Align(alignment: y, child: child);
        },
        child: Container(
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withOpacity(0),
                AppColors.primary.withOpacity(0.95),
                AppColors.primary.withOpacity(0),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.55),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentTile(Map<String, dynamic> r, {bool isLast = false}) {
    final name = (r['name'] ?? 'Guest').toString();
    final ref = (r['ref'] ?? '').toString();
    final at = r['checked_in_at']?.toString();
    final isTicket = r['kind'] == 'ticket';
    final initials = _initials(name);
    final time = _formatTime(at);
    final av = (r['avatar'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          av.isNotEmpty
              ? CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withOpacity(0.10),
                  backgroundImage: NetworkImage(av),
                )
              : CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withOpacity(0.10),
                  child: Text(initials,
                      style: appText(size: 13, weight: FontWeight.w800, color: AppColors.primary)),
                ),
          Positioned(
            right: -2, bottom: -2,
            child: Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(child: SvgPicture.asset('assets/icons/check-icon.svg', width: 10, height: 10,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))),
            ),
          ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: appText(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 3),
            Row(children: [
              SvgPicture.asset(isTicket ? 'assets/icons/ticket-icon.svg' : 'assets/icons/email-icon.svg',
                  width: 12, height: 12,
                  colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(ref.isEmpty ? (isTicket ? 'Ticket' : 'Invitation') : '#$ref',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: appText(size: 11.5, color: AppColors.textTertiary, weight: FontWeight.w600)),
              ),
            ]),
          ]),
        ),
        if (time.isNotEmpty)
          Text(time,
              style: appText(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary)),
      ]),
    );
  }

  String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return 'G';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final norm = (iso.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso)) ? iso : '${iso}Z';
    final dt = DateTime.tryParse(norm)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Widget _skeleton() {
    Widget box({double? w, required double h, double r = 12, Color? c}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c ?? const Color(0xFFF1F1F4),
        borderRadius: BorderRadius.circular(r),
      ),
    );

    Widget shimmerBox({double? w, required double h, double r = 12, Color? c}) =>
        box(w: w, h: h, r: r, c: c);

    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero card placeholder
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              shimmerBox(w: 76, h: 92, r: 12),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                shimmerBox(w: 180, h: 15, r: 4),
                const SizedBox(height: 8),
                shimmerBox(w: 120, h: 11, r: 4),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: shimmerBox(h: 42, r: 10)),
                  const SizedBox(width: 8),
                  Expanded(child: shimmerBox(h: 42, r: 10)),
                  const SizedBox(width: 8),
                  Expanded(child: shimmerBox(h: 42, r: 10)),
                ]),
              ])),
            ]),
          ),
          const SizedBox(height: 14),
          // Camera viewfinder placeholder with corner brackets + pill
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(alignment: Alignment.center, children: [
                Positioned(
                  top: 14,
                  child: Container(
                    width: 150, height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                Positioned(top: 14, left: 14, child: Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle))),
                Positioned(top: 14, right: 14, child: Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle))),
                _frame(),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          // "or" divider
          Row(children: [
            Expanded(child: Divider(color: AppColors.borderLight, thickness: 1)),
            const SizedBox(width: 10),
            shimmerBox(w: 14, h: 10, r: 4),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: AppColors.borderLight, thickness: 1)),
          ]),
          const SizedBox(height: 12),
          // Manual entry button placeholder
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Center(child: shimmerBox(w: 160, h: 14, r: 4)),
          ),
          const SizedBox(height: 22),
          // Recent Scans header
          Row(children: [shimmerBox(w: 110, h: 15, r: 4), const Spacer(), shimmerBox(w: 58, h: 12, r: 4)]),
          const SizedBox(height: 10),
          for (int i = 0; i < 3; i++) ...[
            shimmerBox(h: 72, r: 16),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  String _formatEventDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _PreviewScenario {
  final String label;
  final String kind; // success | warning | error
  final String title;
  final String subtitle;
  final String name;
  final String code;
  final String? ticketType;
  final String? checkedInAt;
  final String? reasonLabel;
  final String? whatThisMeans;

  const _PreviewScenario({
    required this.label,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.name,
    required this.code,
    this.ticketType,
    this.checkedInAt,
    this.reasonLabel,
    this.whatThisMeans,
  });
}

