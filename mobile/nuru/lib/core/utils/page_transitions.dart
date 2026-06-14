import 'package:flutter/material.dart';

/// Fade-through transition (200 ms) - matches the web's shared-axis feel
/// for tab content swaps and detail navigation.
class FadeThroughRoute<T> extends PageRouteBuilder<T> {
  FadeThroughRoute({required WidgetBuilder builder, RouteSettings? settings})
      : super(
          settings: settings,
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (ctx, anim, sec) => builder(ctx),
          transitionsBuilder: (ctx, anim, sec, child) {
            final fade = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            final scale = Tween(begin: 0.985, end: 1.0).animate(fade);
            return FadeTransition(
              opacity: fade,
              child: ScaleTransition(scale: scale, child: child),
            );
          },
        );
}
