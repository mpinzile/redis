import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Horizontal scrollable pill-style tab bar - modern, clean
class PillTabs extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;

  const PillTabs({super.key, required this.tabs, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final isActive = i == selected;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isActive ? Colors.black : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: isActive ? null : Border.all(color: AppColors.borderLight, width: 1),
              ),
              alignment: Alignment.center,
              child: Text(
                tabs[i],
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : AppColors.textSecondary,
                  letterSpacing: 0.2,
                  height: 1.0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
