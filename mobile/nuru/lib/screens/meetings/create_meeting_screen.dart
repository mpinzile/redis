import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:nuru/core/services/meetings_service.dart';
import 'package:nuru/core/l10n/app_translations.dart';
import 'package:nuru/providers/locale_provider.dart';
import 'package:nuru/core/widgets/nuru_date_time_picker.dart';

class CreateMeetingScreen extends StatefulWidget {
  final String eventId;
  final String? eventName;

  const CreateMeetingScreen({
    super.key,
    required this.eventId,
    this.eventName,
  });

  @override
  State<CreateMeetingScreen> createState() => _CreateMeetingScreenState();
}

class _CreateMeetingScreenState extends State<CreateMeetingScreen> {
  final MeetingsService _service = MeetingsService();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _duration = '60';
  int _step = 0;
  bool _submitting = false;

  String _t(String key) {
    final locale = context.read<LocaleProvider>().languageCode;
    return AppTranslations.tr(key, locale);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// Format a local DateTime as ISO 8601 with the user's UTC offset
  /// (e.g. 2026-05-22T10:00:00+03:00). This preserves the wall-clock time
  /// and timezone exactly, regardless of where the viewer is.
  String _localIsoWithOffset(DateTime local) {
    final off = local.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final hh = off.inHours.abs().toString().padLeft(2, '0');
    final mm = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    String two(int n) => n.toString().padLeft(2, '0');
    final base =
        '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}'
        'T${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    return '$base$sign$hh:$mm';
  }

  Future<void> _submit() async {
    if (_selectedDate == null || _selectedTime == null) {
      _snack(_t('enter_title_date_time'));
      return;
    }
    setState(() => _submitting = true);
    final dt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
    try {
      final res = await _service.createMeeting(
        widget.eventId,
        title: _titleCtrl.text.trim(),
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        // Send the wall-clock time with the user's local UTC offset so the
        // backend stores the meeting against the creator's timezone.
        scheduledAt: _localIsoWithOffset(dt),
        timezone: dt.timeZoneName,
        durationMinutes: _duration,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        _snack(_t('meeting_scheduled_invites'));
        Navigator.of(context).pop(true);
      } else {
        setState(() => _submitting = false);
        _snack(_t('something_went_wrong'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        _snack(_t('something_went_wrong'));
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: SvgPicture.asset('assets/icons/arrow-left-icon.svg',
              width: 22, height: 22),
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(_step == 0 ? 'New Meeting' : 'Date & Time',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        centerTitle: true,
      ),
      body: AbsorbPointer(
        absorbing: _submitting,
        child: SafeArea(
          child: Column(
            children: [
              // Progress bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: _step >= 1 ? primary : Colors.grey[200],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: _step == 0 ? _buildStep1(theme) : _buildStep2(theme),
                ),
              ),
              _buildBottomBar(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((widget.eventName ?? '').isNotEmpty) ...[
          Text('For ${widget.eventName}',
              style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
        ],
        _label('Meeting title'),
        const SizedBox(height: 6),
        TextField(
          controller: _titleCtrl,
          decoration: _input('e.g. Full Committee Meeting'),
        ),
        const SizedBox(height: 16),
        _label('Description'),
        const SizedBox(height: 6),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: _input('What will you discuss?'),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFCE4A6)),
          ),
          child: Row(children: [
            const Icon(Icons.lock_outline_rounded,
                size: 18, color: Color(0xFF8A6A00)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'A 6-digit passcode is generated automatically and shown on the meeting details.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[800],
                  height: 1.35,
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildStep2(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Pick date'),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final d = await showNuruDatePicker(
              context: context,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              initialDate: _selectedDate ?? DateTime.now(),
            );
            if (d != null) setState(() => _selectedDate = d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_rounded,
                  size: 18, color: Colors.grey[700]),
              const SizedBox(width: 10),
              Text(
                _selectedDate != null
                    ? DateFormat('EEEE, MMM d, yyyy').format(_selectedDate!)
                    : 'Pick date',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color:
                      _selectedDate != null ? Colors.black : Colors.grey[600],
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        _label('Pick time'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(children: [
            Text('HOUR',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Colors.grey[500])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(24, (h) {
                final sel = _selectedTime?.hour == h;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTime =
                      TimeOfDay(hour: h, minute: _selectedTime?.minute ?? 0)),
                  child: Container(
                    width: 48, height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel ? primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(h.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? Colors.white : Colors.grey[700],
                        )),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: Colors.grey[200]),
            const SizedBox(height: 12),
            Text('MINUTE',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Colors.grey[500])),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [0, 15, 30, 45].map((m) {
                final sel = (_selectedTime?.minute ?? 0) == m;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTime = TimeOfDay(
                      hour: _selectedTime?.hour ?? 9, minute: m)),
                  child: Container(
                    width: 58, height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel ? primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(':${m.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? Colors.white : Colors.grey[700],
                        )),
                  ),
                );
              }).toList(),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        _label('Duration'),
        const SizedBox(height: 8),
        Row(
          children: [
            {'val': '30', 'lbl': '30 min'},
            {'val': '60', 'lbl': '1 hour'},
            {'val': '90', 'lbl': '1.5 hr'},
            {'val': '120', 'lbl': '2 hr'},
          ].map((d) {
            final active = _duration == d['val'];
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _duration = d['val']!),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active ? primary : Colors.grey[300]!,
                    ),
                  ),
                  child: Text(d['lbl']!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? Colors.white : Colors.grey[700],
                      )),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        children: [
          if (_step == 1)
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _step = 0),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50)),
                  ),
                  child: const Text('Back',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          if (_step == 1) const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _submitting
                    ? null
                    : () {
                        if (_step == 0) {
                          if (_titleCtrl.text.trim().isEmpty) {
                            _snack('Please enter a title');
                            return;
                          }
                          setState(() => _step = 1);
                        } else {
                          _submit();
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF7B500),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.black),
                      )
                    : Text(
                        _step == 0 ? 'Continue' : 'Schedule Meeting',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Color(0xFF6B7280)));

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF7B500), width: 1.5),
        ),
      );
}
