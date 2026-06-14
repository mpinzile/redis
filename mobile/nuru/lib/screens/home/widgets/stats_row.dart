import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Stats summary row - modern card style
class StatItem {
  final String label;
  final String value;
  const StatItem(this.label, this.value);
}

class StatsRow extends StatelessWidget {
  final List<StatItem> items;
  final bool dark;

  const StatsRow({super.key, required this.items, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: dark ? null : Border.all(color: AppColors.borderLight, width: 1),
      ),
      child: Row(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: i < items.length - 1
                    ? const Border(right: BorderSide(color: AppColors.borderLight, width: 1))
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.value,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: dark ? AppColors.textOnDark : AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: dark ? AppColors.textOnDarkMuted : AppColors.textTertiary,
                      letterSpacing: 0.3,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
