import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Modern animated loader - replaces all CircularProgressIndicator usage.
/// Three morphing dots with a subtle wave animation.
class NuruLoader extends StatefulWidget {
  final double size;
  final Color? color;
  final bool inline;

  const NuruLoader({
    super.key,
    this.size = 32,
    this.color,
    this.inline = false,
  });

  @override
  State<NuruLoader> createState() => _NuruLoaderState();
}

class _NuruLoaderState extends State<NuruLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

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
  Widget build(BuildContext context) {
    final dotColor = widget.color ?? AppColors.primary;
    final dotSize = widget.size * 0.22;
    final spacing = widget.size * 0.06;
    // Total row width: 3*dot + 6*spacing  ≈ 3*0.22 + 6*0.06 = 1.02
    // Add small headroom so transient transforms never clip the SizedBox.
    final rowWidth = (dotSize * 3) + (spacing * 6) + 4;

    return SizedBox(
      width: rowWidth,
      height: widget.inline ? dotSize * 2.5 : widget.size * 0.5,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final delay = i * 0.18;
              final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);

              // Wave: scale up then down
              final scale = 0.5 + 0.5 * sin(t * pi);
              // Slight vertical offset for wave feel
              final dy = -dotSize * 0.5 * sin(t * pi);

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing),
                child: Transform.translate(
                  offset: Offset(0, dy),
                  child: Transform.scale(
                    scale: 0.6 + scale * 0.4,
                    child: Container(
                      width: dotSize,
                      height: dotSize,
                      decoration: BoxDecoration(
                        color: dotColor.withOpacity(0.4 + scale * 0.6),
                        borderRadius: BorderRadius.circular(dotSize * 0.35),
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// A full-page overlay loader with the Nuru logo breathing + loader dots.
class NuruFullLoader extends StatelessWidget {
  final String? message;

  const NuruFullLoader({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NuruLoader(size: 48),
          if (message != null) ...[
            const SizedBox(height: 20),
            Text(
              message!,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
