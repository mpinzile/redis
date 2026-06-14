import 'package:flutter/material.dart';

/// Soft single-wave footer used at the bottom of auth screens.
/// Matches the reference: one cream wave that dips low on the left and
/// rises smoothly toward the right, full-bleed to the bottom edge.
class AuthSkyline extends StatelessWidget {
  final Color color;
  final double height;
  final double opacity;

  const AuthSkyline({
    super.key,
    required this.color,
    this.height = 200,
    this.opacity = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavePainter(color: color, opacity: opacity),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color color;
  final double opacity;
  _WavePainter({required this.color, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Single soft wave matching the reference.
    // Starts low-left, dips slightly, then rises smoothly to upper-right.
    final path = Path()
      ..moveTo(0, h * 0.55)
      ..cubicTo(
        w * 0.18, h * 0.30,   // first control - gentle hump on the left
        w * 0.45, h * 0.95,   // second control - deep trough mid
        w * 0.78, h * 0.45,   // end of first curve
      )
      ..cubicTo(
        w * 0.90, h * 0.18,   // pull up toward the right
        w * 0.97, h * 0.05,
        w, h * 0.10,          // end at top-right area
      )
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = color.withOpacity(opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.color != color || old.opacity != opacity;
}

/// Top-right organic curved shape used as a corner decoration.
/// Matches the reference: a fluid form starting from the top edge (~30% in),
/// flowing down and hugging the right edge, with a softer outer layer.
class AuthCornerBlob extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;
  final Alignment alignment;

  const AuthCornerBlob({
    super.key,
    required this.color,
    this.size = 260,
    this.opacity = 0.55,
    this.alignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CornerWavePainter(color: color, opacity: opacity),
        ),
      ),
    );
  }
}

class _CornerWavePainter extends CustomPainter {
  final Color color;
  final double opacity;
  _CornerWavePainter({required this.color, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Outer (lighter) layer ──
    final outer = Path()
      ..moveTo(w * 0.20, 0)
      ..cubicTo(
        w * 0.45, h * 0.05,
        w * 0.55, h * 0.30,
        w * 0.78, h * 0.45,
      )
      ..cubicTo(
        w * 0.95, h * 0.58,
        w * 1.02, h * 0.78,
        w, h * 0.95,
      )
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(
      outer,
      Paint()..color = color.withOpacity(opacity * 0.45),
    );

    // ── Inner (richer) layer - tighter to the corner ──
    final inner = Path()
      ..moveTo(w * 0.42, 0)
      ..cubicTo(
        w * 0.60, h * 0.08,
        w * 0.72, h * 0.22,
        w * 0.88, h * 0.38,
      )
      ..cubicTo(
        w * 1.00, h * 0.50,
        w * 1.05, h * 0.65,
        w, h * 0.78,
      )
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(
      inner,
      Paint()..color = color.withOpacity(opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _CornerWavePainter old) =>
      old.color != color || old.opacity != opacity;
}
