import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import 'widgets/event_checkin_tab.dart';

/// Standalone host for [EventCheckinTab] - used when the user opens the
/// scanner directly from a quick action. Title resolves dynamically from
/// the backend ("Guest Check In" or "Ticket Check In").
class EventCheckinScreen extends StatefulWidget {
  final String eventId;
  final String? eventTitle;
  final String? eventDate;
  final String? eventLocation;
  final Map<String, dynamic>? permissions;

  const EventCheckinScreen({
    super.key,
    required this.eventId,
    this.eventTitle,
    this.eventDate,
    this.eventLocation,
    this.permissions,
  });

  @override
  State<EventCheckinScreen> createState() => _EventCheckinScreenState();
}

class _EventCheckinScreenState extends State<EventCheckinScreen> {
  String _title = 'Check In';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(_title, style: appText(size: 18, weight: FontWeight.w800)),
        leading: IconButton(
          icon: SvgPicture.asset(
            'assets/icons/arrow-left-icon.svg',
            width: 22, height: 22,
            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: EventCheckinTab(
        eventId: widget.eventId,
        permissions: widget.permissions,
        eventTitle: widget.eventTitle,
        eventDate: widget.eventDate,
        eventLocation: widget.eventLocation,
        onTitleResolved: (t) {
          if (mounted && t != _title) setState(() => _title = t);
        },
      ),
    );
  }
}
