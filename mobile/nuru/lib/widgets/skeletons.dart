import 'package:flutter/material.dart';

/// Reusable shimmer-style skeleton primitives for loading states.
/// Use these instead of CircularProgressIndicator for page/section loads.
/// All pieces share a single animated [AnimatedBuilder] when wrapped in
/// [SkeletonGroup] for performance; otherwise each box animates standalone.
class _ShimmerController extends StatefulWidget {
  final Widget child;
  const _ShimmerController({required this.child});

  @override
  State<_ShimmerController> createState() => _ShimmerControllerState();
}

class _ShimmerControllerState extends State<_ShimmerController>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final base = Color.lerp(
          const Color(0xFFEEEEEE),
          const Color(0xFFF7F7F7),
          t,
        )!;
        return _SkeletonColorScope(color: base, child: widget.child);
      },
    );
  }
}

class _SkeletonColorScope extends InheritedWidget {
  final Color color;
  const _SkeletonColorScope({required this.color, required super.child});
  static Color of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<_SkeletonColorScope>();
    return s?.color ?? const Color(0xFFEEEEEE);
  }

  @override
  bool updateShouldNotify(_SkeletonColorScope old) => old.color != color;
}

/// Wrap a tree of skeleton primitives to share one shimmer animation.
class SkeletonGroup extends StatelessWidget {
  final Widget child;
  const SkeletonGroup({super.key, required this.child});
  @override
  Widget build(BuildContext context) => _ShimmerController(child: child);
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _SkeletonColorScope.of(context),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  final double widthFactor;
  final double height;
  const SkeletonLine({super.key, this.widthFactor = 1.0, this.height = 12});
  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SkeletonBox(height: height, radius: 6),
    );
  }
}

class SkeletonAvatar extends StatelessWidget {
  final double size;
  const SkeletonAvatar({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _SkeletonColorScope.of(context),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Standard list tile skeleton: avatar + two text lines + optional trailing.
class SkeletonListTile extends StatelessWidget {
  final bool trailing;
  final EdgeInsets padding;
  const SkeletonListTile({
    super.key,
    this.trailing = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          const SkeletonAvatar(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonLine(widthFactor: 0.55, height: 12),
                SizedBox(height: 8),
                SkeletonLine(widthFactor: 0.35, height: 10),
              ],
            ),
          ),
          if (trailing) ...[
            const SizedBox(width: 12),
            const SkeletonBox(width: 56, height: 24, radius: 12),
          ],
        ],
      ),
    );
  }
}

/// Larger card skeleton — image header + 2 text lines + meta row.
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 180});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEFEFEF)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: height, radius: 12),
          const SizedBox(height: 12),
          const SkeletonLine(widthFactor: 0.7, height: 13),
          const SizedBox(height: 8),
          const SkeletonLine(widthFactor: 0.45, height: 11),
        ],
      ),
    );
  }
}

/// N copies of [child] separated by [spacing].
class SkeletonList extends StatelessWidget {
  final int count;
  final double spacing;
  final Widget Function(BuildContext context, int index) builder;
  final EdgeInsets padding;
  const SkeletonList({
    super.key,
    required this.builder,
    this.count = 6,
    this.spacing = 0,
    this.padding = EdgeInsets.zero,
  });
  @override
  Widget build(BuildContext context) {
    return SkeletonGroup(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        separatorBuilder: (_, __) => SizedBox(height: spacing),
        itemBuilder: builder,
      ),
    );
  }
}

/// Photo grid placeholder (N cells, square).
class SkeletonGrid extends StatelessWidget {
  final int count;
  final int crossAxisCount;
  final double spacing;
  final EdgeInsets padding;
  const SkeletonGrid({
    super.key,
    this.count = 9,
    this.crossAxisCount = 3,
    this.spacing = 6,
    this.padding = const EdgeInsets.all(12),
  });
  @override
  Widget build(BuildContext context) {
    return SkeletonGroup(
      child: GridView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
        ),
        itemBuilder: (_, __) => const SkeletonBox(height: 0, radius: 10),
      ),
    );
  }
}

/// Chat bubble skeleton row — alternates left/right.
class SkeletonChatBubbles extends StatelessWidget {
  final int count;
  const SkeletonChatBubbles({super.key, this.count = 6});
  @override
  Widget build(BuildContext context) {
    return SkeletonGroup(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final left = i.isEven;
          return Row(
            mainAxisAlignment:
                left ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              SkeletonBox(
                width: 200 + (i % 3) * 20,
                height: 44,
                radius: 16,
              ),
            ],
          );
        },
      ),
    );
  }
}
