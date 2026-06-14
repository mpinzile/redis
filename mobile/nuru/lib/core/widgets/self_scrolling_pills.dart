import 'package:flutter/material.dart';

/// Horizontally-scrolling pill strip that smoothly centers the active pill
/// when [activeIndex] changes - matches the auto-scroll behaviour of the
/// event-detail tab bar but for pill-style filters.
///
/// Use:
///   SelfScrollingPills(
///     activeIndex: index,
///     children: [..],
///   )
class SelfScrollingPills extends StatefulWidget {
  final List<Widget> children;
  final int activeIndex;
  final double height;
  final EdgeInsetsGeometry padding;
  final double spacing;

  const SelfScrollingPills({
    super.key,
    required this.children,
    required this.activeIndex,
    this.height = 36,
    this.padding = EdgeInsets.zero,
    this.spacing = 8,
  });

  @override
  State<SelfScrollingPills> createState() => _SelfScrollingPillsState();
}

class _SelfScrollingPillsState extends State<SelfScrollingPills> {
  final ScrollController _ctrl = ScrollController();
  final List<GlobalKey> _keys = [];

  @override
  void initState() {
    super.initState();
    _ensureKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveIntoView());
  }

  @override
  void didUpdateWidget(covariant SelfScrollingPills oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureKeys();
    if (oldWidget.activeIndex != widget.activeIndex ||
        oldWidget.children.length != widget.children.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveIntoView());
    }
  }

  void _ensureKeys() {
    while (_keys.length < widget.children.length) {
      _keys.add(GlobalKey());
    }
  }

  void _scrollActiveIntoView() {
    if (!mounted || !_ctrl.hasClients) return;
    if (widget.activeIndex < 0 || widget.activeIndex >= _keys.length) return;
    final ctx = _keys[widget.activeIndex].currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final viewport = _ctrl.position.viewportDimension;
    final pillOffset =
        box.localToGlobal(Offset.zero, ancestor: context.findRenderObject()).dx;
    final pillWidth = box.size.width;
    final centerAbs = _ctrl.offset + pillOffset + pillWidth / 2;
    final target = (centerAbs - viewport / 2).clamp(
      _ctrl.position.minScrollExtent,
      _ctrl.position.maxScrollExtent,
    );
    _ctrl.animateTo(target,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureKeys();
    return SizedBox(
      height: widget.height,
      child: SingleChildScrollView(
        controller: _ctrl,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: widget.padding,
        child: Row(
          children: [
            for (var i = 0; i < widget.children.length; i++) ...[
              if (i > 0) SizedBox(width: widget.spacing),
              KeyedSubtree(key: _keys[i], child: widget.children[i]),
            ],
          ],
        ),
      ),
    );
  }
}
