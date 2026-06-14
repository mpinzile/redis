/// Default Nuru event preview image used when an event has no cover/primary
/// image set. Mirrors `src/lib/eventImage.ts` on web so both platforms render
/// the same branded fallback instead of a generic gray box.
const String kNuruEventDefaultAsset = 'assets/images/event-default.png';

/// Picks the best cover image URL for an event payload, returning ``null``
/// when no remote image is available - callers should then render the local
/// asset above.
String? resolveEventImageUrl(Map? ev) {
  if (ev == null) return null;
  String? pick(dynamic v) =>
      (v is String && v.trim().isNotEmpty) ? v : null;
  final direct = pick(ev['cover_image']) ??
      pick(ev['event_cover_image_url']) ??
      pick(ev['image']) ??
      pick(ev['primary_image']) ??
      pick(ev['image_url']);
  if (direct != null) return direct;
  final imgs = ev['images'];
  if (imgs is List) {
    final sorted = List.of(imgs)
      ..sort((a, b) {
        bool feat(dynamic x) =>
            x is Map && (x['is_featured'] == true || x['is_primary'] == true);
        return feat(a) ? -1 : (feat(b) ? 1 : 0);
      });
    for (final img in sorted) {
      if (img is String && img.trim().isNotEmpty) return img;
      if (img is Map) {
        final u = img['image_url']?.toString() ??
            img['url']?.toString() ??
            img['file_url']?.toString();
        if (u != null && u.isNotEmpty) return u;
      }
    }
  }
  return null;
}
