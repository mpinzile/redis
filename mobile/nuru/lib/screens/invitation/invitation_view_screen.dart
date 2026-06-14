/// Public Invitation / RSVP landing screen - premium Nuru-branded.
///
/// Deep links:
///   /i/:code     → mode = 'view'  (full invitation card + event detail)
///   /rsvp/:code  → mode = 'rsvp'  (focused on Accept / Decline CTAs)
///
/// Public endpoints (no auth required):
///   GET  /api/v1/rsvp/{code}
///   POST /api/v1/rsvp/{code}/respond
///
/// States covered: loading, valid, already-responded, used (checked-in),
/// expired, invalid / not-found, network error.
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import '../../core/services/api_base.dart';
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/date_formatters.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/nuru_logo.dart';
import '../events/event_public_view_screen.dart';
import '../auth/login_screen.dart';

class InvitationViewScreen extends StatefulWidget {
  final String code;
  final String mode; // 'view' or 'rsvp'

  const InvitationViewScreen({super.key, required this.code, this.mode = 'view'});

  @override
  State<InvitationViewScreen> createState() => _InvitationViewScreenState();
}

class _InvitationViewScreenState extends State<InvitationViewScreen> {
  bool _loading = true;
  String? _error;
  String? _errorCode;
  Map<String, dynamic>? _data;
  bool _submitting = false;
  bool _isSignedIn = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
    _load();
  }

  Future<void> _checkSession() async {
    final t = await SecureTokenStorage.getToken();
    if (!mounted) return;
    setState(() => _isSignedIn = (t != null && t.isNotEmpty));
  }

  Future<void> _load() async {
    debugPrint('[InvitationView] loading code=${widget.code} mode=${widget.mode}');
    setState(() {
      _loading = true;
      _error = null;
      _errorCode = null;
    });
    final res = await ApiBase.get('/rsvp/${widget.code}', auth: false);
    debugPrint('[InvitationView] response success=${res['success']}');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = (res['message'] ?? 'Could not load invitation').toString();
        final errs = res['errors'];
        if (errs is List && errs.isNotEmpty) _errorCode = errs.first.toString();
      }
    });
  }

  Future<void> _respond(String status) async {
    setState(() => _submitting = true);
    final res = await ApiBase.post(
      '/rsvp/${widget.code}/respond',
      {'rsvp_status': status},
      auth: false,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (status == 'confirmed' ? 'RSVP confirmed. See you there.' : 'RSVP declined.')
          : (res['message'] ?? 'Could not submit RSVP').toString()),
      backgroundColor: ok ? AppColors.success : AppColors.error,
      behavior: SnackBarBehavior.floating,
    ));
    if (ok) await _load();
  }

  void _share() {
    final url = 'https://nuru.tz/${widget.mode == 'rsvp' ? 'rsvp' : 'i'}/${widget.code}';
    Share.share(url, subject: 'You are invited', sharePositionOrigin: sharePositionOrigin(context));
  }

  void _openEvent(String eventId) {
    if (eventId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EventPublicViewScreen(eventId: eventId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const _PremiumLoading(label: 'Opening your invitation…');
    if (_error != null) {
      final notFound = _errorCode == 'NOT_FOUND' || _errorCode == 'EVENT_NOT_FOUND';
      return _PremiumErrorState(
        title: notFound ? 'Invitation not found' : 'We could not load this invitation',
        message: notFound
            ? 'The link may be wrong, or the invitation was withdrawn.'
            : (_error ?? ''),
        primaryLabel: 'Try again',
        onPrimary: _load,
      );
    }
    final data = _data!;
    final event = (data['event'] is Map ? data['event'] as Map : data);
    final eventId = (event['id'] ?? event['event_id'] ?? '').toString();
    final eventName = (event['name'] ?? event['title'] ?? 'Event').toString();
    final eventType = (event['event_type'] ?? event['type'] ?? '').toString();
    final guestName = (data['guest_name'] ?? '').toString();
    final venue = (event['location'] ?? event['venue'] ?? '').toString();
    final eventDateRaw = (event['event_date'] ?? event['start_date'] ?? '').toString();
    final eventDate = eventDateRaw.isEmpty ? 'Date to be confirmed' : formatDateFull(eventDateRaw);
    final organiser = (data['organizer_name'] ?? event['organizer_name'] ?? '').toString();
    final coverImage = (data['event_image'] ?? event['cover_image_url'] ?? event['image_url'] ?? '').toString();
    final currentStatus = (data['rsvp_status'] ?? '').toString().toLowerCase();
    final alreadyUsed = data['checked_in'] == true;
    final hasResponded = currentStatus == 'confirmed' || currentStatus == 'declined';

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _InvitationHero(
            coverImage: coverImage,
            eventName: eventName,
            eventType: eventType,
            onShare: _share,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (guestName.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.primary.withOpacity(0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const AppIcon('user', size: 14, color: AppColors.primaryDark),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'For $guestName',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
              ],
              _InfoCard(children: [
                _DetailRow(iconName: 'calendar', label: 'When', value: eventDate),
                _DetailRow(iconName: 'location', label: 'Where', value: venue.isEmpty ? 'Venue to be confirmed' : venue),
                if (organiser.isNotEmpty)
                  _DetailRow(iconName: 'crown', label: 'Hosted by', value: organiser),
                if (currentStatus.isNotEmpty)
                  _DetailRow(
                    iconName: 'verified',
                    label: 'Your status',
                    value: _statusLabel(currentStatus),
                    valueColor: _statusColor(currentStatus),
                  ),
              ]),
              const SizedBox(height: 22),
              if (alreadyUsed)
                const _SoftNotice(
                  iconName: 'verified',
                  color: AppColors.success,
                  title: 'Checked in',
                  message: 'This invitation has been used at check-in and can no longer be changed.',
                )
              else if (hasResponded)
                _SoftNotice(
                  iconName: currentStatus == 'confirmed' ? 'sparkle' : 'info',
                  color: _statusColor(currentStatus),
                  title: currentStatus == 'confirmed' ? 'You are going' : 'You declined',
                  message: 'You can change your response any time before the event.',
                  trailing: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => _respond(currentStatus == 'confirmed' ? 'declined' : 'confirmed'),
                    child: Text(currentStatus == 'confirmed' ? 'Change to decline' : 'Change to accept'),
                  ),
                )
              else
                _RespondBlock(
                  submitting: _submitting,
                  onAccept: () => _respond('confirmed'),
                  onDecline: () => _respond('declined'),
                  label: widget.mode == 'rsvp' ? 'Will you attend?' : 'Respond to your invitation',
                ),
              const SizedBox(height: 16),
              if (eventId.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _openEvent(eventId),
                  icon: const AppIcon('link', size: 16, color: AppColors.textPrimary),
                  label: const Text('Open event page'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textPrimary,
                  ),
                ),
              if (!_isSignedIn) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  icon: const AppIcon('lock', size: 14, color: AppColors.textSecondary),
                  label: const Text('Sign in for more options'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 16),
              const _NuruFootBadge(),
            ]),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'confirmed':
        return 'Attending';
      case 'declined':
        return 'Not attending';
      case 'maybe':
        return 'Maybe';
      default:
        return s.toUpperCase();
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'confirmed':
        return AppColors.success;
      case 'declined':
        return AppColors.error;
      case 'maybe':
        return AppColors.warning;
      default:
        return AppColors.blue;
    }
  }
}

class _InvitationHero extends StatelessWidget {
  final String coverImage;
  final String eventName;
  final String eventType;
  final VoidCallback onShare;
  final VoidCallback onBack;

  const _InvitationHero({
    required this.coverImage,
    required this.eventName,
    required this.eventType,
    required this.onShare,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(
        height: 320,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (coverImage.isNotEmpty)
            Opacity(
              opacity: 0.92,
              child: CachedNetworkImage(
                imageUrl: coverImage,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.10),
                  Colors.black.withOpacity(0.55),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Text(
                  eventType.isEmpty ? 'INVITATION' : eventType.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                eventName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
                ),
              ),
            ]),
          ),
        ]),
      ),
      Positioned(
        top: 8,
        left: 4,
        right: 4,
        child: Row(children: [
          IconButton(
            onPressed: onBack,
            icon: const AppIcon('arrow-left', size: 20, color: Colors.white),
          ),
          const Spacer(),
          IconButton(
            onPressed: onShare,
            icon: const AppIcon('share-upload', size: 20, color: Colors.white),
          ),
        ]),
      ),
    ]);
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            const Divider(height: 1, color: AppColors.borderLight, indent: 56),
        ],
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String iconName;
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailRow({required this.iconName, required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: AppIcon(iconName, size: 16, color: AppColors.primaryDark),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _RespondBlock extends StatelessWidget {
  final bool submitting;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final String label;
  const _RespondBlock({
    required this.submitting,
    required this.onAccept,
    required this.onDecline,
    required this.label,
  });
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: submitting ? null : onAccept,
            icon: submitting
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const AppIcon('double-check', size: 16, color: Colors.white),
            label: const Text('Accept'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: submitting ? null : onDecline,
            icon: const AppIcon('close', size: 16, color: AppColors.textPrimary),
            label: const Text('Decline'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 15),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ]),
    ]);
  }
}

class _SoftNotice extends StatelessWidget {
  final String iconName;
  final Color color;
  final String title;
  final String message;
  final Widget? trailing;
  const _SoftNotice({required this.iconName, required this.color, required this.title, required this.message, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppIcon(iconName, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 4),
            Text(message, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
            if (trailing != null) Align(alignment: Alignment.centerRight, child: trailing!),
          ]),
        ),
      ]),
    );
  }
}

class _PremiumLoading extends StatelessWidget {
  final String label;
  const _PremiumLoading({required this.label});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const NuruLogo(size: 40),
        const SizedBox(height: 18),
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary)),
        const SizedBox(height: 14),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ]),
    );
  }
}

class _PremiumErrorState extends StatelessWidget {
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  const _PremiumErrorState({
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(24)),
          child: const AppIcon('email', size: 28, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: onPrimary,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          ),
          child: Text(primaryLabel),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Go back'),
        ),
      ]),
    );
  }
}

class _NuruFootBadge extends StatelessWidget {
  const _NuruFootBadge();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Powered by Nuru',
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary.withOpacity(0.85), letterSpacing: 0.8),
        ),
      ),
    );
  }
}
