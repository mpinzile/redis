import 'package:flutter/material.dart';

/// Returns an origin rect for the iOS share sheet popover.
///
/// share_plus on iPad (and increasingly on iPhone too) throws
/// `PlatformException(error, sharePositionOrigin: argument must be set...)`
/// when `sharePositionOrigin` is null or zero-sized. We compute it from the
/// caller's [BuildContext] when possible and fall back to a 1x1 rect at the
/// top-left so the sheet still opens instead of crashing.
Rect sharePositionOrigin(BuildContext context) {
  try {
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize && !ro.size.isEmpty) {
      final offset = ro.localToGlobal(Offset.zero);
      final rect = offset & ro.size;
      if (rect.width > 0 && rect.height > 0) return rect;
    }
  } catch (_) {}
  // Safe fallback - non-zero rect inside the screen so iOS accepts it.
  return const Rect.fromLTWH(0, 0, 1, 1);
}
