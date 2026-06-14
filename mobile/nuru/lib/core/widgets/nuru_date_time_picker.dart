import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'app_icon.dart';

/// Picker mode.
enum NuruPickerMode { date, time, dateAndTime }

/// Day-period buckets - mirrors the greeting logic in
/// `home_right_drawer._greeting()` so picker day-period chips and the
/// home-drawer greeting stay aligned.
///
///   Morning:   05:00 – 11:59
///   Afternoon: 12:00 – 16:59
///   Evening:   17:00 – 20:59
///   Night:     21:00 – 04:59
enum NuruDayPeriod { morning, afternoon, evening, night }

NuruDayPeriod nuruDayPeriodForHour(int hour) {
  final h = hour % 24;
  if (h >= 5 && h < 12) return NuruDayPeriod.morning;
  if (h >= 12 && h < 17) return NuruDayPeriod.afternoon;
  if (h >= 17 && h < 21) return NuruDayPeriod.evening;
  return NuruDayPeriod.night;
}

/// `HH:mm` 24-hour string suitable for backend payloads.
String nuruFormatTime24(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// `YYYY-MM-DD` ISO date string (local calendar day) for backend payloads.
String nuruFormatDateIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Local ISO-8601 datetime without timezone suffix (`YYYY-MM-DDTHH:mm:ss`).
String nuruFormatDateTimeLocal(DateTime d) =>
    '${nuruFormatDateIso(d)}T${nuruFormatTime24(TimeOfDay(hour: d.hour, minute: d.minute))}:${d.second.toString().padLeft(2, '0')}';

/// Show the date picker only. Returns a `DateTime` at local midnight.
Future<DateTime?> showNuruDatePicker({
  required BuildContext context,
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String? title,
}) => _showNuruPicker(
      context: context,
      mode: NuruPickerMode.date,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    );

/// Show the time picker only.
Future<TimeOfDay?> showNuruTimePicker({
  required BuildContext context,
  TimeOfDay? initialTime,
  String? title,
}) async {
  final dt = await _showNuruPicker(
    context: context,
    mode: NuruPickerMode.time,
    initialTime: initialTime,
    title: title,
  );
  if (dt == null) return null;
  return TimeOfDay(hour: dt.hour, minute: dt.minute);
}

/// Show the combined date + time picker (tabbed).
Future<DateTime?> showNuruDateTimePicker({
  required BuildContext context,
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
  String? title,
}) => _showNuruPicker(
      context: context,
      mode: NuruPickerMode.dateAndTime,
      initialDate: initial,
      initialTime:
          initial == null ? null : TimeOfDay(hour: initial.hour, minute: initial.minute),
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    );

Future<DateTime?> _showNuruPicker({
  required BuildContext context,
  required NuruPickerMode mode,
  DateTime? initialDate,
  TimeOfDay? initialTime,
  DateTime? firstDate,
  DateTime? lastDate,
  String? title,
}) {
  return showModalBottomSheet<DateTime?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (ctx) => _NuruDateTimeSheet(
      mode: mode,
      initialDate: initialDate,
      initialTime: initialTime,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _NuruDateTimeSheet extends StatefulWidget {
  const _NuruDateTimeSheet({
    required this.mode,
    this.initialDate,
    this.initialTime,
    this.firstDate,
    this.lastDate,
    this.title,
  });

  final NuruPickerMode mode;
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? title;

  @override
  State<_NuruDateTimeSheet> createState() => _NuruDateTimeSheetState();
}

class _NuruDateTimeSheetState extends State<_NuruDateTimeSheet> {
  late DateTime _viewMonth;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late int _tabIndex; // 0=Date, 1=Time
  late DateTime _firstDate;
  late DateTime _lastDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _firstDate = widget.firstDate ?? DateTime(now.year - 5, 1, 1);
    _lastDate = widget.lastDate ?? DateTime(now.year + 5, 12, 31);
    _selectedDate = _clampDate(widget.initialDate ?? now);
    _selectedTime = widget.initialTime ?? TimeOfDay.fromDateTime(now);
    _viewMonth = DateTime(_selectedDate.year, _selectedDate.month);
    _tabIndex = widget.mode == NuruPickerMode.time ? 1 : 0;
  }

  DateTime _clampDate(DateTime d) {
    if (d.isBefore(_firstDate)) return _firstDate;
    if (d.isAfter(_lastDate)) return _lastDate;
    return DateTime(d.year, d.month, d.day);
  }

  bool _isInRange(DateTime d) =>
      !d.isBefore(DateTime(_firstDate.year, _firstDate.month, _firstDate.day)) &&
      !d.isAfter(DateTime(_lastDate.year, _lastDate.month, _lastDate.day));

  void _confirm() {
    final result = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      widget.mode == NuruPickerMode.date ? 0 : _selectedTime.hour,
      widget.mode == NuruPickerMode.date ? 0 : _selectedTime.minute,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.title ??
                    (widget.mode == NuruPickerMode.time
                        ? 'Select time'
                        : _tabIndex == 0
                            ? 'Select date'
                            : 'Select time'),
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.mode == NuruPickerMode.dateAndTime) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _DateTimeTabs(
                    index: _tabIndex,
                    onChanged: (i) => setState(() => _tabIndex = i),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _tabIndex == 0 &&
                          widget.mode != NuruPickerMode.time
                      ? _buildDatePanel()
                      : _buildTimePanel(),
                ),
              ),
              const _ThinDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _SummaryPill(
                  iconName: _tabIndex == 0 && widget.mode != NuruPickerMode.time
                      ? 'calendar'
                      : 'clock',
                  label: _tabIndex == 0 && widget.mode != NuruPickerMode.time
                      ? _formatSummaryDate(_selectedDate)
                      : _formatSummaryTime(_selectedTime),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(children: [
                  Expanded(
                    flex: 2,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: AppColors.textSecondary,
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: ElevatedButton(
                      onPressed: _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Confirm',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Date panel ────────────────────────────────────────────────────────────
  Widget _buildDatePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthHeader(
          month: _viewMonth,
          canPrev: !DateTime(_viewMonth.year, _viewMonth.month)
              .isBefore(DateTime(_firstDate.year, _firstDate.month + 1)),
          canNext: !DateTime(_viewMonth.year, _viewMonth.month)
              .isAfter(DateTime(_lastDate.year, _lastDate.month - 1)),
          onPrev: () => setState(() =>
              _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1)),
          onNext: () => setState(() =>
              _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1)),
        ),
        const SizedBox(height: 10),
        _CalendarGrid(
          month: _viewMonth,
          selected: _selectedDate,
          isEnabled: _isInRange,
          onSelect: (d) => setState(() {
            _selectedDate = d;
            _viewMonth = DateTime(d.year, d.month);
          }),
        ),
        const SizedBox(height: 16),
        _QuickDateChips(
          selected: _selectedDate,
          isEnabled: _isInRange,
          onSelect: (d) => setState(() {
            _selectedDate = d;
            _viewMonth = DateTime(d.year, d.month);
          }),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Time panel ────────────────────────────────────────────────────────────
  Widget _buildTimePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayPeriodChips(
          active: nuruDayPeriodForHour(_selectedTime.hour),
          onSelect: (p) => setState(() {
            switch (p) {
              case NuruDayPeriod.morning:
                _selectedTime = const TimeOfDay(hour: 9, minute: 0);
                break;
              case NuruDayPeriod.afternoon:
                _selectedTime = const TimeOfDay(hour: 14, minute: 0);
                break;
              case NuruDayPeriod.evening:
                _selectedTime = const TimeOfDay(hour: 19, minute: 0);
                break;
              case NuruDayPeriod.night:
                _selectedTime = const TimeOfDay(hour: 22, minute: 0);
                break;
            }
          }),
        ),
        const SizedBox(height: 18),
        _HourMinuteWheels(
          hour: _selectedTime.hour,
          minute: _selectedTime.minute,
          onChanged: (h, m) =>
              setState(() => _selectedTime = TimeOfDay(hour: h, minute: m)),
        ),
        const SizedBox(height: 16),
        _QuickAddChips(
          onAdd: (mins) {
            final total = _selectedTime.hour * 60 + _selectedTime.minute + mins;
            final wrapped = ((total % (24 * 60)) + (24 * 60)) % (24 * 60);
            setState(() => _selectedTime =
                TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60));
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _DateTimeTabs extends StatelessWidget {
  const _DateTimeTabs({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _tab('Date', 0)),
        const SizedBox(width: 14), // explicit gap between tabs per spec
        Expanded(child: _tab('Time', 1)),
      ],
    );
  }

  Widget _tab(String label, int i) {
    final selected = i == index;
    return GestureDetector(
      onTap: () => onChanged(i),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.primaryDark : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.canPrev,
    required this.canNext,
  });
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool canPrev;
  final bool canNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _arrow('chevron-left', canPrev ? onPrev : null),
        Expanded(
          child: Center(
            child: Text(
              '${_monthName(month.month)} ${month.year}',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        _arrow('chevron-right', canNext ? onNext : null),
      ],
    );
  }

  Widget _arrow(String iconName, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Center(
            child: AppIcon(
              iconName,
              size: 18,
              color: onTap == null ? AppColors.textHint : AppColors.textPrimary,
            ),
          ),
        ),
      );
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.selected,
    required this.onSelect,
    required this.isEnabled,
  });
  final DateTime month;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final bool Function(DateTime) isEnabled;

  static const _weekdayLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday = 1 ... Sunday = 7
    final leading = first.weekday - 1;
    final totalCells = ((leading + daysInMonth) / 7).ceil() * 7;

    return Column(children: [
      Row(
        children: _weekdayLabels
            .map((d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
      const SizedBox(height: 6),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: totalCells,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisExtent: 42,
        ),
        itemBuilder: (ctx, i) {
          final dayNum = i - leading + 1;
          final inMonth = dayNum >= 1 && dayNum <= daysInMonth;
          final date = inMonth
              ? DateTime(month.year, month.month, dayNum)
              : DateTime(month.year, month.month, 1)
                  .add(Duration(days: i - leading));
          final selectedDay = date.year == selected.year &&
              date.month == selected.month &&
              date.day == selected.day;
          final enabled = inMonth && isEnabled(date);
          return GestureDetector(
            onTap: enabled ? () => onSelect(date) : null,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selectedDay && enabled
                      ? AppColors.primary
                      : Colors.transparent,
                ),
                child: Text(
                  '${date.day}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: selectedDay
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: !inMonth || !enabled
                        ? AppColors.textHint
                        : selectedDay
                            ? Colors.white
                            : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ]);
  }
}

class _QuickDateChips extends StatelessWidget {
  const _QuickDateChips({
    required this.selected,
    required this.onSelect,
    required this.isEnabled,
  });
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final bool Function(DateTime) isEnabled;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final tomorrow = start.add(const Duration(days: 1));
    final daysUntilSat = (DateTime.saturday - start.weekday) % 7;
    final weekend = start.add(Duration(days: daysUntilSat == 0 ? 7 : daysUntilSat));

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _chip('calendar', 'Today', start),
        _chip('event-calendar-check', 'Tomorrow', tomorrow),
        _chip('star', 'This weekend', weekend),
      ],
    );
  }

  Widget _chip(String iconName, String label, DateTime date) {
    final selectedChip = date.year == selected.year &&
        date.month == selected.month &&
        date.day == selected.day;
    final enabled = isEnabled(date);
    return GestureDetector(
      onTap: enabled ? () => onSelect(date) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selectedChip ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: selectedChip ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(
            iconName,
            size: 16,
            color: enabled
                ? (selectedChip ? AppColors.primaryDark : AppColors.primary)
                : AppColors.textHint,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled
                  ? (selectedChip ? AppColors.primaryDark : AppColors.textPrimary)
                  : AppColors.textHint,
            ),
          ),
        ]),
      ),
    );
  }
}

class _DayPeriodChips extends StatelessWidget {
  const _DayPeriodChips({required this.active, required this.onSelect});
  final NuruDayPeriod active;
  final ValueChanged<NuruDayPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _chip(Icons.wb_sunny_outlined, 'Morning', NuruDayPeriod.morning),
        _chip(Icons.wb_twilight_rounded, 'Afternoon', NuruDayPeriod.afternoon),
        _chip(Icons.nights_stay_outlined, 'Evening', NuruDayPeriod.evening),
        _chip(Icons.bedtime_outlined, 'Night', NuruDayPeriod.night),
      ],
    );
  }

  Widget _chip(IconData icon, String label, NuruDayPeriod p) {
    final selected = p == active;
    return GestureDetector(
      onTap: () => onSelect(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 16,
              color: selected ? AppColors.primaryDark : AppColors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color:
                  selected ? AppColors.primaryDark : AppColors.textPrimary,
            ),
          ),
        ]),
      ),
    );
  }
}

class _HourMinuteWheels extends StatefulWidget {
  const _HourMinuteWheels({
    required this.hour,
    required this.minute,
    required this.onChanged,
  });
  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;

  @override
  State<_HourMinuteWheels> createState() => _HourMinuteWheelsState();
}

class _HourMinuteWheelsState extends State<_HourMinuteWheels> {
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minuteCtrl;
  bool _suppress = false;

  @override
  void initState() {
    super.initState();
    _hourCtrl = FixedExtentScrollController(initialItem: widget.hour);
    _minuteCtrl = FixedExtentScrollController(initialItem: widget.minute);
  }

  @override
  void didUpdateWidget(covariant _HourMinuteWheels oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Defer to post-frame to avoid "setState during build" when a parent
    // setState rebuilds us with new values. jumpToItem can synchronously
    // fire onSelectedItemChanged, which would call back into the parent
    // build phase and trigger duplicate-GlobalKey / setState-in-build errors.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hourCtrl.hasClients && _hourCtrl.selectedItem != widget.hour) {
        _suppress = true;
        _hourCtrl.jumpToItem(widget.hour);
        _suppress = false;
      }
      if (_minuteCtrl.hasClients && _minuteCtrl.selectedItem != widget.minute) {
        _suppress = true;
        _minuteCtrl.jumpToItem(widget.minute);
        _suppress = false;
      }
    });
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildWheels(
      hourCtrl: _hourCtrl,
      minuteCtrl: _minuteCtrl,
      onChanged: (h, m) {
        if (_suppress) return;
        if (h == widget.hour && m == widget.minute) return;
        widget.onChanged(h, m);
      },
    );
  }
}

Widget _buildWheels({
    required FixedExtentScrollController hourCtrl,
    required FixedExtentScrollController minuteCtrl,
    required void Function(int, int) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Center(
              child: Text(
                'HH',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Center(
              child: Text(
                'MM',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: Stack(children: [
            // selection band
            Positioned.fill(
              child: Center(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Row(children: [
              Expanded(
                child: _wheel(
                  controller: hourCtrl,
                  count: 24,
                  format: (v) => v.toString().padLeft(2, '0'),
                  onChanged: (v) =>
                      onChanged(v, minuteCtrl.selectedItem.clamp(0, 59)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _wheel(
                  controller: minuteCtrl,
                  count: 60,
                  format: (v) => v.toString().padLeft(2, '0'),
                  onChanged: (v) =>
                      onChanged(hourCtrl.selectedItem.clamp(0, 23), v),
                ),
              ),
            ]),
          ]),
        ),
      ]),
  );
}


Widget _wheel({
  required FixedExtentScrollController controller,
  required int count,
  required String Function(int) format,
  required ValueChanged<int> onChanged,
}) {
  return ListWheelScrollView.useDelegate(
    controller: controller,
    itemExtent: 50,
    perspective: 0.003,
    diameterRatio: 1.6,
    physics: const FixedExtentScrollPhysics(),
    onSelectedItemChanged: onChanged,
    childDelegate: ListWheelChildBuilderDelegate(
      childCount: count,
      builder: (ctx, i) {
        final selected = i == controller.selectedItem;
        return Center(
          child: Text(
            format(i),
            style: GoogleFonts.inter(
              fontSize: selected ? 28 : 20,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        );
      },
    ),
  );
}

class _QuickAddChips extends StatelessWidget {
  const _QuickAddChips({required this.onAdd});
  final ValueChanged<int> onAdd;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _chip('+15m', 15),
        _chip('+30m', 30),
        _chip('+45m', 45),
        _chip('+1h', 60),
      ],
    );
  }

  Widget _chip(String label, int mins) => GestureDetector(
        onTap: () => onAdd(mins),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      );
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.iconName, required this.label});
  final String iconName;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: AppIcon(iconName, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const AppIcon('chevron-down', size: 18, color: AppColors.textTertiary),
      ]),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: AppColors.borderLight);
}

// ─── Helpers ────────────────────────────────────────────────────────────────

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdayShort = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

String _monthName(int m) => _monthNames[m - 1];

String _formatSummaryDate(DateTime d) =>
    '${_weekdayShort[d.weekday - 1]}, ${d.day} ${_monthName(d.month)} ${d.year}';

String _formatSummaryTime(TimeOfDay t) {
  final hour12 = t.hour == 0
      ? 12
      : t.hour > 12
          ? t.hour - 12
          : t.hour;
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  return '${hour12.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $ampm';
}
