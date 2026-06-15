import '../../../core/widgets/nuru_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/events_service.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/l10n/l10n_helper.dart';

class EventScheduleTab extends StatefulWidget {
  final String eventId;
  const EventScheduleTab({super.key, required this.eventId});

  @override
  State<EventScheduleTab> createState() => _EventScheduleTabState();
}

class _EventScheduleTabState extends State<EventScheduleTab> with AutomaticKeepAliveClientMixin {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await EventsService.getSchedule(widget.eventId);
    if (mounted) setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        _items = data is List ? data : (data is Map ? (data['items'] ?? []) : []);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return SkeletonList(
        padding: const EdgeInsets.all(16),
        count: 6,
        spacing: 12,
        builder: (_, __) => const SkeletonListTile(padding: EdgeInsets.zero, trailing: true),
      );
    }

    return NuruRefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: _items.isEmpty
          ? ListView(children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
              Center(child: Column(children: [
                Icon(Icons.schedule_rounded, size: 48, color: AppColors.textHint),
                const SizedBox(height: 12),
                Text('No schedule items', style: appText(size: 14, color: AppColors.textTertiary)),
              ])),
            ])
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length + 1,
              itemBuilder: (_, i) {
                if (i == _items.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: GestureDetector(
                      onTap: _showAddSheet,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text('Add Schedule Item', style: appText(size: 14, weight: FontWeight.w600, color: AppColors.primary)),
                        ]),
                      ),
                    ),
                  );
                }
                return _scheduleTile(_items[i], i);
              },
            ),
    );
  }

  Widget _scheduleTile(Map<String, dynamic> item, int index) {
    final title = item['title']?.toString() ?? '';
    final startTime = item['start_time']?.toString() ?? '';
    final endTime = item['end_time']?.toString() ?? '';
    final desc = item['description']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
            if (index < _items.length - 1)
              Container(width: 2, height: 50, color: AppColors.border),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(title, style: appText(size: 14, weight: FontWeight.w600))),
                    GestureDetector(
                      onTap: () => _deleteItem(item['id']?.toString() ?? ''),
                      child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textHint),
                    ),
                  ]),
                  if (startTime.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('$startTime${endTime.isNotEmpty ? ' - $endTime' : ''}', style: appText(size: 12, color: AppColors.primary, weight: FontWeight.w600)),
                    ),
                  if (desc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(desc, style: appText(size: 12, color: AppColors.textTertiary), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(String id) async {
    if (id.isEmpty) return;
    final res = await EventsService.deleteScheduleItem(widget.eventId, id);
    if (mounted) {
      if (res['success'] == true) _load();
      else AppSnackbar.error(context, res['message'] ?? 'Failed');
    }
  }

  void _showAddSheet() {
    final titleCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('Add Schedule Item', style: appText(size: 18, weight: FontWeight.w700)),
            const SizedBox(height: 18),
            _input(titleCtrl, 'Title'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _input(startCtrl, 'Start Time (e.g. 09:00)')),
              const SizedBox(width: 12),
              Expanded(child: _input(endCtrl, 'End Time')),
            ]),
            const SizedBox(height: 12),
            _input(descCtrl, 'Description (optional)'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx);
                  final res = await EventsService.addScheduleItem(widget.eventId, {
                    'title': titleCtrl.text.trim(),
                    'start_time': startCtrl.text.trim(),
                    'end_time': endCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                  });
                  if (mounted) {
                    if (res['success'] == true) { AppSnackbar.success(context, 'Added'); _load(); }
                    else AppSnackbar.error(context, res['message'] ?? 'Failed');
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                child: Text('Save', style: appText(size: 15, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: appText(size: 15),
      decoration: InputDecoration(
        hintText: hint, hintStyle: appText(size: 14, color: AppColors.textHint),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: const Color(0xFFE5E7EB), width: 1)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
