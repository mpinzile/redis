import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/theme/text_styles.dart';
import '../../core/l10n/l10n_helper.dart';

/// Full-screen PDF preview with save, share, and print options.
/// Premium native rendering with polished action bar.
class ReportPreviewScreen extends StatefulWidget {
  final String title;
  final Uint8List pdfBytes;
  final String? filePath;

  const ReportPreviewScreen({
    super.key,
    required this.title,
    required this.pdfBytes,
    this.filePath,
  });

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  bool _saved = false;
  bool _sharing = false;

  Future<String> _ensureFile() async {
    if (widget.filePath != null && File(widget.filePath!).existsSync()) {
      return widget.filePath!;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${widget.title.replaceAll(' ', '_').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(widget.pdfBytes);
    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Premium header
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0), width: 1)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: SvgPicture.asset(
                        'assets/icons/chevron-left-icon.svg',
                        width: 22, height: 22,
                        colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: appText(size: 16, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('Preview & share your report', style: appText(size: 11, color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                    // Quick print button in header
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.print_rounded, size: 20, color: AppColors.textSecondary),
                        onPressed: () => Printing.layoutPdf(onLayout: (_) => widget.pdfBytes),
                        tooltip: 'Print',
                      ),
                    ),
                  ],
                ),
              ),

              // PDF viewer
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 2)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: PdfPreview(
                    build: (_) => widget.pdfBytes,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    pdfFileName: widget.title.replaceAll(' ', '_').toLowerCase(),
                    allowPrinting: false,
                    allowSharing: false,
                    useActions: false,
                    loadingWidget: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(
                          width: 36, height: 36,
                          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                        ),
                        const SizedBox(height: 16),
                        Text('Loading preview...', style: appText(size: 13, color: AppColors.textTertiary)),
                      ]),
                    ),
                    onError: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Center(
                              child: SvgPicture.asset(
                                'assets/icons/pdf-file-type-icon.svg',
                                width: 32, height: 32,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('Unable to preview PDF', style: appText(size: 16, weight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text('You can still share, print, or save the report.',
                            style: appText(size: 13, color: AppColors.textTertiary), textAlign: TextAlign.center),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),

              // Premium bottom action bar
              Container(
                padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding + 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, -4))],
                ),
                child: Row(
                  children: [
                    // Share
                    _roundActionBtn(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      isLoading: _sharing,
                      onTap: () async {
                        setState(() => _sharing = true);
                        try {
                          final path = await _ensureFile();
                          await Share.shareXFiles([XFile(path)], subject: widget.title, sharePositionOrigin: sharePositionOrigin(context));
                        } catch (_) {
                          if (mounted) AppSnackbar.error(context, 'Failed to share');
                        }
                        if (mounted) setState(() => _sharing = false);
                      },
                    ),
                    const SizedBox(width: 10),
                    // Print
                    _roundActionBtn(
                      icon: Icons.print_rounded,
                      label: 'Print',
                      onTap: () => Printing.layoutPdf(onLayout: (_) => widget.pdfBytes),
                    ),
                    const SizedBox(width: 10),
                    // Save - primary CTA
                    Expanded(
                      flex: 3,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        child: ElevatedButton.icon(
                          onPressed: _saved ? null : () async {
                            await _ensureFile();
                            setState(() => _saved = true);
                            HapticFeedback.mediumImpact();
                            if (mounted) AppSnackbar.success(context, 'Report saved to device');
                          },
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Icon(
                              _saved ? Icons.check_rounded : Icons.save_alt_rounded,
                              key: ValueKey(_saved),
                              size: 18,
                            ),
                          ),
                          label: Text(
                            _saved ? 'Saved ✓' : 'Save to Device',
                            style: appText(
                              size: 13,
                              weight: FontWeight.w700,
                              color: _saved ? AppColors.textTertiary : Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _saved ? const Color(0xFFE2E8F0) : AppColors.primary,
                            foregroundColor: _saved ? AppColors.textTertiary : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: _saved ? 0 : 2,
                            shadowColor: AppColors.primary.withOpacity(0.3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(height: 4),
                Text(label, style: appText(size: 11, weight: FontWeight.w600, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
