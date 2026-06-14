library;

import 'package:flutter/material.dart';

/// NuruSkeleton — modern shimmer skeleton loaders used across data-loading
/// screens. Provides primitive boxes plus a set of curated presets (list
/// tile, event card, grid tile, profile header, stat tiles, message row)
/// so every screen feels coherent.
///
/// Usage:
///   const NuruSkeletonList(itemCount: 6) // ready-made list skeleton
///   const NuruSkeletonEventList()        // event-card list
///   NuruSkeleton.box(height: 12, width: 120)
///   NuruSkeleton.text(width: 160)
///   NuruSkeleton.circle(size: 40)
///
/// Wrap a complex layout in NuruSkeletonGroup to share a single shimmer
/// animation controller across many child boxes (cheaper than many tickers).

const Color _kBase = Color(0xFFE8ECF1);
const Color _kHighlight = Color(0xFFF5F7FA);

/// Shared shimmer ticker provided to descendant boxes.
class NuruSkeletonGroup extends StatefulWidget {
  final Widget child;
  const NuruSkeletonGroup({super.key, required this.child});

  @override
  State<NuruSkeletonGroup> createState() => _NuruSkeletonGroupState();
}

class _NuruSkeletonGroupState extends State<NuruSkeletonGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SkeletonScope(controller: _ctrl, child: widget.child);
}

class _SkeletonScope extends InheritedWidget {
  final AnimationController controller;
  const _SkeletonScope({required this.controller, required super.child});

  static AnimationController? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_SkeletonScope>()?.controller;

  @override
  bool updateShouldNotify(_SkeletonScope old) => old.controller != controller;
}

/// A single shimmer block. Use the named constructors for common shapes.
class NuruSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const NuruSkeleton({
    super.key,
    this.width,
    this.height = 12,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  /// Rectangular block.
  factory NuruSkeleton.box({
    double? width,
    double height = 80,
    double radius = 12,
  }) => NuruSkeleton(
    width: width,
    height: height,
    borderRadius: BorderRadius.circular(radius),
  );

  /// Single text line. Default 12px tall, 4px radius.
  factory NuruSkeleton.text({double? width, double height = 12}) =>
      NuruSkeleton(
        width: width,
        height: height,
        borderRadius: BorderRadius.circular(4),
      );

  /// Circular avatar/icon placeholder.
  factory NuruSkeleton.circle({double size = 40}) => NuruSkeleton(
    width: size,
    height: size,
    borderRadius: BorderRadius.circular(size),
  );

  @override
  State<NuruSkeleton> createState() => _NuruSkeletonState();
}

class _NuruSkeletonState extends State<NuruSkeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _local;

  AnimationController _resolve(BuildContext c) {
    final shared = _SkeletonScope.maybeOf(c);
    if (shared != null) return shared;
    _local ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    return _local!;
  }

  @override
  void dispose() {
    _local?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _resolve(context);
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final t = ctrl.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * t, 0),
              end: Alignment(-0.3 + 2.0 * t, 0),
              colors: const [_kBase, _kHighlight, _kBase],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// List of avatar + 2-line text rows. Great for follow lists, contributors,
/// messages, groups, issues, communities, circles, payment history, etc.
class NuruSkeletonList extends StatelessWidget {
  final int itemCount;
  final EdgeInsets padding;
  final bool showAvatar;
  final bool showTrailing;
  final ScrollPhysics? physics;

  const NuruSkeletonList({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
    this.showAvatar = true,
    this.showTrailing = false,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return NuruSkeletonGroup(
      child: ListView.separated(
        padding: padding,
        physics: physics ?? const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => Row(
          children: [
            if (showAvatar) ...[
              NuruSkeleton.circle(size: 44),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NuruSkeleton.text(width: 140, height: 12),
                  const SizedBox(height: 8),
                  NuruSkeleton.text(width: 200, height: 10),
                ],
              ),
            ),
            if (showTrailing) ...[
              const SizedBox(width: 12),
              NuruSkeleton.box(width: 60, height: 28, radius: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Vertical list of event-style cards: cover + title + meta line + chip.
class NuruSkeletonEventList extends StatelessWidget {
  final int itemCount;
  final EdgeInsets padding;
  final ScrollPhysics? physics;
  const NuruSkeletonEventList({
    super.key,
    this.itemCount = 4,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return NuruSkeletonGroup(
      child: ListView.separated(
        padding: padding,
        physics: physics ?? const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF0F0F4)),
          ),
          child: Row(
            children: [
              NuruSkeleton.box(width: 64, height: 64, radius: 14),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NuruSkeleton.text(width: 160, height: 13),
                    const SizedBox(height: 10),
                    NuruSkeleton.text(width: 110, height: 10),
                    const SizedBox(height: 8),
                    NuruSkeleton.text(width: 80, height: 10),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              NuruSkeleton.box(width: 54, height: 22, radius: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grid of square cover + 2 caption lines. Photos, moments, tickets, services.
class NuruSkeletonGrid extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;
  final EdgeInsets padding;
  final double aspectRatio;
  final bool showCaption;

  const NuruSkeletonGrid({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 2,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
    this.aspectRatio = 0.82,
    this.showCaption = true,
  });

  @override
  Widget build(BuildContext context) {
    return NuruSkeletonGroup(
      child: GridView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: aspectRatio,
        ),
        itemBuilder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: NuruSkeleton.box(radius: 16, height: double.infinity),
            ),
            if (showCaption) ...[
              const SizedBox(height: 10),
              NuruSkeleton.text(width: 110, height: 11),
              const SizedBox(height: 6),
              NuruSkeleton.text(width: 70, height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

/// Profile header skeleton: avatar, name, handle, stats strip.
class NuruSkeletonProfileHeader extends StatelessWidget {
  const NuruSkeletonProfileHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return NuruSkeletonGroup(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NuruSkeleton.circle(size: 72),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NuruSkeleton.text(width: 160, height: 16),
                      const SizedBox(height: 10),
                      NuruSkeleton.text(width: 110, height: 11),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            NuruSkeleton.box(height: 56, radius: 14),
            const SizedBox(height: 16),
            NuruSkeleton.text(width: 220, height: 10),
            const SizedBox(height: 6),
            NuruSkeleton.text(width: 180, height: 10),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row of stat tiles (e.g. 4 KPI cards).
class NuruSkeletonStats extends StatelessWidget {
  final int count;
  final EdgeInsets padding;
  const NuruSkeletonStats({
    super.key,
    this.count = 4,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 8),
  });

  @override
  Widget build(BuildContext context) {
    return NuruSkeletonGroup(
      child: Padding(
        padding: padding,
        child: Row(
          children: List.generate(count, (i) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == count - 1 ? 0 : 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF0F0F4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NuruSkeleton.text(width: 40, height: 10),
                      const SizedBox(height: 10),
                      NuruSkeleton.text(width: 60, height: 16),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Chat / message skeleton with alternating bubble sides.
class NuruSkeletonMessages extends StatelessWidget {
  final int itemCount;
  const NuruSkeletonMessages({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return NuruSkeletonGroup(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          final mine = i.isOdd;
          return Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              NuruSkeleton.box(
                width: 180 + (i % 3) * 30.0,
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

/// Feed post-card skeleton: avatar + name/handle + media block + action row.
/// Visually matches `MomentCard` so the feed swap is seamless.
class NuruSkeletonPostCard extends StatelessWidget {
  final double mediaHeight;
  const NuruSkeletonPostCard({super.key, this.mediaHeight = 220});

  @override
  Widget build(BuildContext context) {
    return NuruSkeletonGroup(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF0F0F4)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NuruSkeleton.circle(size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NuruSkeleton.text(width: 130, height: 12),
                      const SizedBox(height: 8),
                      NuruSkeleton.text(width: 80, height: 10),
                    ],
                  ),
                ),
                NuruSkeleton.box(width: 22, height: 22, radius: 6),
              ],
            ),
            const SizedBox(height: 12),
            NuruSkeleton.text(width: double.infinity, height: 10),
            const SizedBox(height: 6),
            NuruSkeleton.text(width: 220, height: 10),
            const SizedBox(height: 14),
            NuruSkeleton.box(height: mediaHeight, radius: 14),
            const SizedBox(height: 14),
            Row(
              children: [
                NuruSkeleton.box(width: 60, height: 22, radius: 11),
                const SizedBox(width: 10),
                NuruSkeleton.box(width: 60, height: 22, radius: 11),
                const SizedBox(width: 10),
                NuruSkeleton.box(width: 60, height: 22, radius: 11),
                const Spacer(),
                NuruSkeleton.box(width: 22, height: 22, radius: 6),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab-specific skeleton variants for the home feed so the placeholder
/// matches the data shape the user is waiting on.
enum FeedSkeletonVariant { post, moment, event, glimpse }

/// Vertical list of post-card skeletons for the home feed.
class NuruSkeletonPostList extends StatelessWidget {
  final int itemCount;
  final EdgeInsets padding;
  final FeedSkeletonVariant variant;
  const NuruSkeletonPostList({
    super.key,
    this.itemCount = 3,
    this.padding = EdgeInsets.zero,
    this.variant = FeedSkeletonVariant.post,
  });

  @override
  Widget build(BuildContext context) {
    return NuruSkeletonGroup(
      child: Padding(
        padding: padding,
        child: Column(
          children: List.generate(itemCount, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _cardForVariant(variant),
          )),
        ),
      ),
    );
  }

  Widget _cardForVariant(FeedSkeletonVariant v) {
    switch (v) {
      case FeedSkeletonVariant.moment:
        return const _MomentSkeletonCard();
      case FeedSkeletonVariant.event:
        return const _EventShareSkeletonCard();
      case FeedSkeletonVariant.glimpse:
        return const _GlimpseGroupSkeletonCard();
      case FeedSkeletonVariant.post:
        return const NuruSkeletonPostCard();
    }
  }
}

/// Image-led moment card placeholder mirroring MomentCard layout:
/// header (avatar + name/time), caption lines, big media block, action row.
class _MomentSkeletonCard extends StatelessWidget {
  const _MomentSkeletonCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0F0F4)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name/time + menu dot
          Row(children: [
            NuruSkeleton.circle(size: 40),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NuruSkeleton.text(width: 130, height: 12),
                const SizedBox(height: 6),
                NuruSkeleton.text(width: 70, height: 9),
              ],
            )),
            NuruSkeleton.circle(size: 18),
          ]),
          const SizedBox(height: 12),
          // Caption lines
          NuruSkeleton.text(width: double.infinity, height: 11),
          const SizedBox(height: 6),
          NuruSkeleton.text(width: 220, height: 11),
          const SizedBox(height: 12),
          // Media block
          NuruSkeleton.box(height: 320, radius: 16),
          const SizedBox(height: 12),
          // Action row: glow / comment / share / save
          Row(children: [
            NuruSkeleton.box(width: 56, height: 22, radius: 12),
            const SizedBox(width: 14),
            NuruSkeleton.box(width: 56, height: 22, radius: 12),
            const SizedBox(width: 14),
            NuruSkeleton.box(width: 32, height: 22, radius: 12),
            const Spacer(),
            NuruSkeleton.box(width: 32, height: 22, radius: 12),
          ]),
        ],
      ),
    );
  }
}


/// Event-share card placeholder: cover row + title + meta + CTA.
class _EventShareSkeletonCard extends StatelessWidget {
  const _EventShareSkeletonCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0F0F4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NuruSkeleton.box(height: 140, radius: 14),
          const SizedBox(height: 12),
          Row(children: [
            NuruSkeleton.box(width: 56, height: 56, radius: 12),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NuruSkeleton.text(width: 180, height: 13),
                const SizedBox(height: 8),
                NuruSkeleton.text(width: 130, height: 10),
                const SizedBox(height: 6),
                NuruSkeleton.text(width: 90, height: 10),
              ],
            )),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: NuruSkeleton.box(height: 38, radius: 10)),
            const SizedBox(width: 10),
            NuruSkeleton.box(width: 44, height: 38, radius: 10),
          ]),
        ],
      ),
    );
  }
}

/// Glimpse-group placeholder: author header + horizontal row of preview tiles.
class _GlimpseGroupSkeletonCard extends StatelessWidget {
  const _GlimpseGroupSkeletonCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F0F4)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            NuruSkeleton.circle(size: 40),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NuruSkeleton.text(width: 120, height: 11),
                const SizedBox(height: 6),
                NuruSkeleton.text(width: 70, height: 9),
              ],
            )),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, __) => NuruSkeleton.box(width: 96, height: 140, radius: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Event detail screen skeleton: cover + title + meta + stats + tabs + list.
class NuruSkeletonEventDetail extends StatelessWidget {
  const NuruSkeletonEventDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return NuruSkeletonGroup(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Row(
                children: [
                  NuruSkeleton.box(width: 44, height: 44, radius: 22),
                  const Spacer(),
                  NuruSkeleton.text(width: 112, height: 16),
                  const Spacer(),
                  NuruSkeleton.box(width: 44, height: 44, radius: 22),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NuruSkeleton.box(width: 72, height: 72, radius: 14),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: NuruSkeleton.text(width: 180, height: 15)),
                            const SizedBox(width: 8),
                            NuruSkeleton.box(width: 62, height: 22, radius: 999),
                          ],
                        ),
                        const SizedBox(height: 10),
                        NuruSkeleton.text(width: 170, height: 11),
                        const SizedBox(height: 8),
                        NuruSkeleton.text(width: 210, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 7,
                separatorBuilder: (_, __) => const SizedBox(width: 20),
                itemBuilder: (_, i) => Center(
                  child: NuruSkeleton.text(width: 64 + (i % 3) * 10, height: 13),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  NuruSkeleton.text(width: 146, height: 15),
                  const SizedBox(height: 10),
                  NuruSkeleton.box(height: 118, radius: 16),
                  const SizedBox(height: 12),
                  NuruSkeleton.box(height: 76, radius: 16),
                  const SizedBox(height: 8),
                  Row(children: const [
                    Expanded(child: NuruSkeleton(height: 84, borderRadius: BorderRadius.all(Radius.circular(16)))),
                    SizedBox(width: 8),
                    Expanded(child: NuruSkeleton(height: 84, borderRadius: BorderRadius.all(Radius.circular(16)))),
                  ]),
                  const SizedBox(height: 20),
                  NuruSkeleton.text(width: 128, height: 15),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 78,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 4,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, __) => NuruSkeleton.box(width: 132, height: 78, radius: 14),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(children: const [
                    Expanded(child: NuruSkeleton(height: 238, borderRadius: BorderRadius.all(Radius.circular(18)))),
                    SizedBox(width: 10),
                    Expanded(child: NuruSkeleton(height: 238, borderRadius: BorderRadius.all(Radius.circular(18)))),
                  ]),
                  const SizedBox(height: 18),
                  NuruSkeleton.text(width: 118, height: 15),
                  const SizedBox(height: 12),
                  Row(children: const [
                    Expanded(child: NuruSkeleton(height: 86, borderRadius: BorderRadius.all(Radius.circular(14)))),
                    SizedBox(width: 10),
                    Expanded(child: NuruSkeleton(height: 86, borderRadius: BorderRadius.all(Radius.circular(14)))),
                    SizedBox(width: 10),
                    Expanded(child: NuruSkeleton(height: 86, borderRadius: BorderRadius.all(Radius.circular(14)))),
                    SizedBox(width: 10),
                    Expanded(child: NuruSkeleton(height: 86, borderRadius: BorderRadius.all(Radius.circular(14)))),
                  ]),
                  const SizedBox(height: 18),
                  NuruSkeleton.box(height: 112, radius: 16),
                  const SizedBox(height: 20),
                  NuruSkeleton.text(width: 132, height: 15),
                  const SizedBox(height: 10),
                  NuruSkeleton.box(height: 142, radius: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
