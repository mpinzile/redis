import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/media_transfer_manager.dart';

/// Background transfers list - shows uploads + downloads in progress / completed
/// for one library (or all libraries if [libraryId] is null).
class TransfersScreen extends StatelessWidget {
  final String? libraryId;
  const TransfersScreen({super.key, this.libraryId});

  List<TransferTask> _tasks() {
    final all = MediaTransferManager.instance.tasks;
    if (libraryId == null) return all;
    return all.where((t) => t.libraryId == libraryId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: MediaTransferManager.instance,
          builder: (_, __) {
            final tasks = _tasks();
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
                child: Row(children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: SvgPicture.asset('assets/icons/arrow-left-icon.svg', width: 22, height: 22,
                      colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
                  ),
                  Expanded(child: Text('Transfers', style: appText(size: 17, weight: FontWeight.w700))),
                  if (tasks.any((t) => t.status == TransferStatus.done))
                    TextButton(
                      onPressed: () => MediaTransferManager.instance.clearCompleted(libraryId: libraryId),
                      child: Text('Clear done', style: appText(size: 12, weight: FontWeight.w700, color: AppColors.primary)),
                    ),
                ]),
              ),
              Expanded(
                child: tasks.isEmpty
                    ? Center(child: Text('No transfers',
                        style: appText(size: 13, color: AppColors.textTertiary)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _TransferRow(task: tasks[i]),
                      ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  final TransferTask task;
  const _TransferRow({required this.task});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: task,
      builder: (_, __) {
        final isUpload = task.kind == TransferKind.upload;
        final pct = (task.progress * 100).round();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isUpload ? Icons.upload_rounded : Icons.download_rounded,
                size: 18, color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.name, style: appText(size: 12, weight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: task.sizeBytes > 0 ? task.progress : (task.isActive ? null : 0),
                  minHeight: 4,
                  backgroundColor: const Color(0xFFF3F4F6),
                  valueColor: AlwaysStoppedAnimation(
                    task.status == TransferStatus.error ? AppColors.error
                      : task.status == TransferStatus.done ? AppColors.accent
                      : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(_statusLine(task, pct),
                  style: appText(size: 10, color: AppColors.textTertiary)),
            ])),
            const SizedBox(width: 8),
            _action(),
          ]),
        );
      },
    );
  }

  String _statusLine(TransferTask t, int pct) {
    switch (t.status) {
      case TransferStatus.done:
        return t.kind == TransferKind.download && t.localResultPath != null
            ? 'Saved to phone'
            : 'Uploaded';
      case TransferStatus.error:
        return t.error ?? 'Failed';
      case TransferStatus.paused:
        return 'Paused · $pct%';
      case TransferStatus.cancelled:
        return 'Cancelled';
      case TransferStatus.queued:
        return 'Queued';
      default:
        return '$pct%';
    }
  }

  Widget _action() {
    if (task.status == TransferStatus.done) {
      if (task.kind == TransferKind.download && task.localResultPath != null) {
        return IconButton(
          onPressed: () => OpenFilex.open(task.localResultPath!),
          icon: const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.accent),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.check_circle, color: AppColors.accent, size: 20),
      );
    }
    if (task.status == TransferStatus.error) {
      return IconButton(
        onPressed: () => MediaTransferManager.instance.retry(task),
        icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.error),
      );
    }
    if (task.status == TransferStatus.paused) {
      return IconButton(
        onPressed: () => MediaTransferManager.instance.resume(task),
        icon: const Icon(Icons.play_circle_outline_rounded, size: 20, color: AppColors.textPrimary),
      );
    }
    if (task.isActive) {
      return IconButton(
        onPressed: task.pause,
        icon: const Icon(Icons.pause_circle_outline_rounded, size: 20, color: AppColors.textPrimary),
      );
    }
    return IconButton(
      onPressed: () { task.cancel(); MediaTransferManager.instance.remove(task); },
      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
    );
  }
}
