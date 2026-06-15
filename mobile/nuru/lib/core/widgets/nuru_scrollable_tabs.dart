import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Horizontally scrollable pill-style tab bar (YouTube-style).
///
/// - Selected pill: solid black background, white label.
/// - Unselected pill: light gray background, dark label.
/// - Rounded rectangular pills with comfortable horizontal padding.
///
/// This is the canonical tab strip across the mobile app (excluding the
/// bottom nav). Prefer it over Material's [TabBar]. For screens that already
/// use a [TabController] with a [TabBarView], use [NuruPillTabBar] which
/// drives the same visuals from a controller.
class NuruScrollableTabs extends StatefulWidget {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;
  final bool showBottomBorder;

  const NuruScrollableTabs({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.showBottomBorder = false,
  });

  @override
  State<NuruScrollableTabs> createState() => _NuruScrollableTabsState();
}

class _NuruScrollableTabsState extends State<NuruScrollableTabs> {
  final ScrollController _scrollCtrl = ScrollController();
  final List<GlobalKey> _tabKeys = [];

  @override
  void initState() {
    super.initState();
    _ensureKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveIntoView());
  }

  void _ensureKeys() {
    while (_tabKeys.length < widget.labels.length) {
      _tabKeys.add(GlobalKey());
    }
  }

  @override
  void didUpdateWidget(covariant NuruScrollableTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureKeys();
    if (oldWidget.activeIndex != widget.activeIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveIntoView());
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollActiveIntoView() {
    if (!mounted || widget.activeIndex >= _tabKeys.length) return;
    final ctx = _tabKeys[widget.activeIndex].currentContext;
    if (ctx == null || !_scrollCtrl.hasClients) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final viewportWidth = _scrollCtrl.position.viewportDimension;
    final tabOffset =
        box.localToGlobal(Offset.zero, ancestor: context.findRenderObject()).dx;
    final tabWidth = box.size.width;
    final currentScroll = _scrollCtrl.offset;
    final tabCenterAbs = currentScroll + tabOffset + tabWidth / 2;
    final target = (tabCenterAbs - viewportWidth / 2).clamp(
      _scrollCtrl.position.minScrollExtent,
      _scrollCtrl.position.maxScrollExtent,
    );
    _scrollCtrl.animateTo(target,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    _ensureKeys();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: widget.showBottomBorder
            ? const Border(
                bottom: BorderSide(color: AppColors.borderLight, width: 1),
              )
            : null,
      ),
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: widget.padding,
        child: Row(
          children: List.generate(widget.labels.length, (i) {
            final selected = i == widget.activeIndex;
            return Padding(
              key: _tabKeys[i],
              padding: EdgeInsets.only(right: i == widget.labels.length - 1 ? 0 : 8),
              child: _NuruTabPill(
                label: widget.labels[i],
                selected: selected,
                onTap: () {
                  widget.onChanged(i);
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scrollActiveIntoView());
                },
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NuruTabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NuruTabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? Colors.black
                : const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF1F1F1F),
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill-style tab strip driven by a [TabController], for screens that pair the
/// tab bar with a [TabBarView]. Renders the same visuals as
/// [NuruScrollableTabs] but syncs with the controller's animation.
class NuruPillTabBar extends StatefulWidget {
  final TabController controller;
  final List<String> labels;
  final EdgeInsetsGeometry padding;
  final bool showBottomBorder;

  const NuruPillTabBar({
    super.key,
    required this.controller,
    required this.labels,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.showBottomBorder = false,
  });

  @override
  State<NuruPillTabBar> createState() => _NuruPillTabBarState();
}

class _NuruPillTabBarState extends State<NuruPillTabBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return NuruScrollableTabs(
      labels: widget.labels,
      activeIndex: widget.controller.index,
      onChanged: (i) => widget.controller.animateTo(i),
      padding: widget.padding,
      showBottomBorder: widget.showBottomBorder,
    );
  }
}
