import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// NuruPagination - a small, modern pager designed to be reused anywhere a
/// list view paginates server-side. Renders Prev / numbered pages with
/// ellipses for long ranges / Next, styled with the Nuru palette.
///
/// Pass either an existing pagination map from the API:
/// `{ page, total_pages, has_next, has_previous }`
/// or call the explicit constructor.
class NuruPagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;

  const NuruPagination({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(vertical: 12),
  });

  factory NuruPagination.fromMap(
    Map<String, dynamic>? pagination, {
    required ValueChanged<int> onChanged,
    Key? key,
  }) {
    final p = (pagination?['page'] as num?)?.toInt() ?? 1;
    final t = (pagination?['total_pages'] as num?)?.toInt() ?? 1;
    return NuruPagination(
      key: key,
      page: p,
      totalPages: t,
      onChanged: onChanged,
    );
  }

  List<dynamic> _buildPageList() {
    // Returns a list of int (page number) or '…' for ellipsis.
    if (totalPages <= 7) {
      return List<int>.generate(totalPages, (i) => i + 1);
    }
    final pages = <dynamic>[1];
    final start = (page - 1).clamp(2, totalPages - 3);
    final end = (page + 1).clamp(4, totalPages - 1);
    if (start > 2) pages.add('…');
    for (int i = start; i <= end; i++) {
      pages.add(i);
    }
    if (end < totalPages - 1) pages.add('…');
    pages.add(totalPages);
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    final hasPrev = page > 1;
    final hasNext = page < totalPages;
    final items = _buildPageList();
    return Padding(
      padding: padding,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _iconBtn(Icons.chevron_left_rounded, hasPrev ? () => onChanged(page - 1) : null),
          for (final it in items)
            if (it is int)
              _numberBtn(it)
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('…', style: TextStyle(color: AppColors.textTertiary)),
              ),
          _iconBtn(Icons.chevron_right_rounded, hasNext ? () => onChanged(page + 1) : null),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap) {
    final disabled = onTap == null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.borderLight),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18,
          color: disabled ? AppColors.textHint : AppColors.textSecondary),
      ),
    );
  }

  Widget _numberBtn(int n) {
    final active = n == page;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: active ? null : () => onChanged(n),
      child: Container(
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surface,
          border: Border.all(
            color: active ? AppColors.primary : AppColors.borderLight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$n',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
