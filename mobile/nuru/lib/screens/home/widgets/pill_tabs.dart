import 'package:flutter/material.dart';
import '../../../core/widgets/nuru_scrollable_tabs.dart';

/// Horizontal scrollable pill-style tab bar (YouTube-style).
///
/// Thin wrapper around [NuruScrollableTabs] so the entire app shares one
/// canonical pill appearance: black selected pill with white label and gray
/// unselected pills with dark labels.
class PillTabs extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;

  const PillTabs({super.key, required this.tabs, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return NuruScrollableTabs(
      labels: tabs,
      activeIndex: selected,
      onChanged: onChanged,
      padding: EdgeInsets.zero,
    );
  }
}
