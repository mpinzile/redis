import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/nuru_scrollable_tabs.dart';
import '../../core/services/social_service.dart';
import '../../core/l10n/l10n_helper.dart';

class RemovedContentScreen extends StatefulWidget {
  const RemovedContentScreen({super.key});

  @override
  State<RemovedContentScreen> createState() => _RemovedContentScreenState();
}

class _RemovedContentScreenState extends State<RemovedContentScreen> {
  int _activeTab = 0;
  List<dynamic> _removedPosts = [];
  List<dynamic> _removedMoments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SocialService.getMyRemovedPosts(),
      SocialService.getMyRemovedMoments(),
    ]);
    if (mounted) {
      setState(() {
        _loading = false;
        if (results[0]['success'] == true) {
          final data = results[0]['data'];
          _removedPosts = data is List ? data : (data is Map ? (data['posts'] ?? []) : []);
        }
        if (results[1]['success'] == true) {
          final data = results[1]['data'];
          _removedMoments = data is List ? data : (data is Map ? (data['moments'] ?? []) : []);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: NuruSubPageAppBar(title: 'Removed Content'),
      body: Column(
        children: [
          NuruScrollableTabs(
            labels: [
              '${context.tr('posts')} (${_removedPosts.length})',
              '${context.tr('moments')} (${_removedMoments.length})',
            ],
            activeIndex: _activeTab,
            onChanged: (i) => setState(() => _activeTab = i),
          ),
          Expanded(
            child: _loading
                ? SkeletonList(
                    padding: const EdgeInsets.all(16),
                    count: 5,
                    spacing: 12,
                    builder: (_, __) => const SkeletonCard(height: 140),
                  )
                : (_activeTab == 0
                    ? _contentList(_removedPosts, isPost: true)
                    : _contentList(_removedMoments, isPost: false)),
          ),
        ],
      ),
    );
  }

  Widget _contentList(List<dynamic> items, {required bool isPost}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderLight),
              ),
              child: const Icon(Icons.visibility_off_outlined, size: 28, color: AppColors.textHint),
            ),
            const SizedBox(height: 16),
            Text('No removed ${isPost ? "posts" : "moments"}',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'You haven\'t had any ${isPost ? "posts" : "moments"} removed. Anything taken down will appear here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textTertiary, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: items.length,
      itemBuilder: (_, i) => _removedItem(items[i], isPost: isPost),
    );
  }

  Widget _removedItem(dynamic item, {required bool isPost}) {
    final m = item is Map<String, dynamic> ? item : <String, dynamic>{};
    final content = m['content']?.toString() ?? m['caption']?.toString() ?? '';
    final reason = m['removal_reason']?.toString() ?? m['reason']?.toString() ?? 'Policy violation';
    final removedAt = m['removed_at']?.toString() ?? m['updated_at']?.toString() ?? '';
    final hasAppeal = m['appeal_status'] != null;
    final appealStatus = m['appeal_status']?.toString() ?? '';
    final id = m['id']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: AppColors.errorSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(reason,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.3)),
            ),
          ]),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(content,
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.45)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (removedAt.isNotEmpty)
                Text(SocialService.getTimeAgo(removedAt),
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
              const Spacer(),
              if (hasAppeal)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Text('Appeal: $appealStatus',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                )
              else
                GestureDetector(
                  onTap: () => _showAppealDialog(id, isPost),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Appeal',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAppealDialog(String id, bool isPost) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Submit Appeal', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(hintText: 'Explain why this should be restored...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              if (isPost) {
                await SocialService.submitPostAppeal(id, ctrl.text.trim());
              } else {
                await SocialService.submitMomentAppeal(id, ctrl.text.trim());
              }
              _load();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
