import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Tiny on-disk cache for remote audio files (voice notes, etc.).
///
/// Keeps downloads in the app's temporary directory keyed by a sanitized
/// version of the URL so that subsequent plays are instant - without this
/// the audio player re-downloads the file every time the conversation is
/// opened, which is what users notice as "slow voice notes".
class AudioFileCache {
  AudioFileCache._();

  static final Map<String, String> _memoryIndex = <String, String>{};
  static final Map<String, Future<String?>> _inflight = <String, Future<String?>>{};

  /// Returns a local file path for [url], downloading once if necessary.
  /// On failure, returns null and callers should fall back to the URL.
  static Future<String?> getLocalPath(String url) async {
    if (url.isEmpty) return null;

    final cached = _memoryIndex[url];
    if (cached != null && File(cached).existsSync()) return cached;

    // Coalesce parallel requests for the same URL.
    final pending = _inflight[url];
    if (pending != null) return pending;

    final fut = _download(url);
    _inflight[url] = fut;
    try {
      final path = await fut;
      if (path != null) _memoryIndex[url] = path;
      return path;
    } finally {
      _inflight.remove(url);
    }
  }

  static Future<String?> _download(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory('${dir.path}/audio_cache');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      final ext = _extOf(url);
      final name = url.hashCode.toUnsigned(32).toRadixString(16);
      final filePath = '${cacheDir.path}/$name$ext';

      final file = File(filePath);
      if (file.existsSync() && file.lengthSync() > 0) return filePath;

      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      await file.writeAsBytes(res.bodyBytes, flush: true);
      return filePath;
    } catch (_) {
      return null;
    }
  }

  static String _extOf(String url) {
    final clean = url.split('?').first.toLowerCase();
    final i = clean.lastIndexOf('.');
    if (i < 0 || i < clean.length - 6) return '';
    return clean.substring(i);
  }
}
