import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'api_base.dart';
import 'api_config.dart';

/// Status of a transfer task.
enum TransferStatus { queued, uploading, downloading, paused, done, error, cancelled }

enum TransferKind { upload, download }

class TransferTask extends ChangeNotifier {
  final String id;
  final TransferKind kind;
  final String name;
  int sizeBytes; // 0 if unknown (download)
  final String libraryId;
  final String? folderName;
  final String? sourcePath; // upload
  final String? remoteUrl; // download
  final String? mediaType; // photo|video
  final String? uploadCaption;
  final String? uploadAlbumName;
  final bool uploadIsHighlight;
  String? localResultPath; // for downloads
  String? remoteResultUrl; // for uploads
  Map<String, dynamic>? resultData;

  int _bytesProcessed = 0;
  TransferStatus _status = TransferStatus.queued;
  String? _error;
  bool _cancelRequested = false;
  bool _pauseRequested = false;

  TransferTask({
    required this.id,
    required this.kind,
    required this.name,
    required this.sizeBytes,
    required this.libraryId,
    this.folderName,
    this.sourcePath,
    this.remoteUrl,
    this.mediaType,
    this.uploadCaption,
    this.uploadAlbumName,
    this.uploadIsHighlight = false,
  });

  int get bytesProcessed => _bytesProcessed;
  TransferStatus get status => _status;
  String? get error => _error;
  double get progress {
    if (_status == TransferStatus.done) return 1.0;
    if (sizeBytes <= 0) return 0;
    return (_bytesProcessed / sizeBytes).clamp(0.0, 1.0);
  }

  bool get isActive =>
      _status == TransferStatus.uploading || _status == TransferStatus.downloading;

  void _setStatus(TransferStatus s, {String? error}) {
    _status = s;
    if (error != null) _error = error;
    notifyListeners();
    MediaTransferManager.instance._notifyOverall();
    MediaTransferManager.instance._syncNotification(this);
  }

  void _setProgress(int bytes) {
    _bytesProcessed = bytes;
    notifyListeners();
    MediaTransferManager.instance._syncNotification(this, throttle: true);
  }

  void pause() {
    if (isActive) {
      _pauseRequested = true;
    }
  }

  void cancel() {
    _cancelRequested = true;
    if (_status == TransferStatus.queued || _status == TransferStatus.paused) {
      _setStatus(TransferStatus.cancelled);
    }
  }
}

/// Global singleton managing uploads & downloads with live progress.
/// Tasks persist for the app lifetime so users can navigate away and return.
class MediaTransferManager extends ChangeNotifier {
  MediaTransferManager._();
  static final MediaTransferManager instance = MediaTransferManager._();

  final List<TransferTask> _tasks = [];
  List<TransferTask> get tasks => List.unmodifiable(_tasks);
  bool _uploadPumpRunning = false;

  // ─── OS background progress notifications ────────────────────────────
  // Piggy-back on `flutter_local_notifications` so users can see transfer
  // progress in the system tray when the app is backgrounded - and so
  // Android keeps the process alive longer (ongoing notifications act as a
  // soft foreground hint without needing a full ForegroundService).
  final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'nuru_transfers',
    'Media transfers',
    description: 'Upload and download progress for photo libraries.',
    importance: Importance.low,
    showBadge: false,
  );
  bool _notifReady = false;
  final Map<String, DateTime> _lastNotifTick = {};
  static const MethodChannel _mediaStoreChannel = MethodChannel('tz.nuru.app/media_store');

  Future<void> _ensureNotifReady() async {
    if (_notifReady) return;
    try {
      final androidPlugin = _notif
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_channel);
    } catch (_) {}
    _notifReady = true;
  }

  int _notifIdFor(TransferTask t) => 0x70000000 ^ (t.id.hashCode & 0x0FFFFFFF);

  void _syncNotification(TransferTask t, {bool throttle = false}) {
    if (throttle) {
      final now = DateTime.now();
      final last = _lastNotifTick[t.id];
      if (last != null && now.difference(last).inMilliseconds < 350) return;
      _lastNotifTick[t.id] = now;
    }
    _showOrUpdateNotif(t);
  }

  Future<void> _showOrUpdateNotif(TransferTask t) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _ensureNotifReady();
    final id = _notifIdFor(t);

    if (t.status == TransferStatus.cancelled) {
      try { await _notif.cancel(id); } catch (_) {}
      return;
    }

    final isUpload = t.kind == TransferKind.upload;
    String title;
    String body = t.name;
    bool ongoing = false;
    int progress = 0;
    bool indeterminate = false;

    switch (t.status) {
      case TransferStatus.queued:
        title = isUpload ? 'Queued upload' : 'Queued download';
        ongoing = true;
        indeterminate = true;
        break;
      case TransferStatus.uploading:
      case TransferStatus.downloading:
        title = isUpload ? 'Uploading' : 'Downloading';
        ongoing = true;
        if (t.sizeBytes > 0) {
          progress = (t.progress * 100).round();
        } else {
          indeterminate = true;
        }
        break;
      case TransferStatus.paused:
        title = isUpload ? 'Upload paused' : 'Download paused';
        ongoing = true;
        if (t.sizeBytes > 0) progress = (t.progress * 100).round();
        break;
      case TransferStatus.done:
        title = isUpload ? 'Upload complete' : 'Download complete';
        break;
      case TransferStatus.error:
        title = isUpload ? 'Upload failed' : 'Download failed';
        body = t.error ?? t.name;
        break;
      case TransferStatus.cancelled:
        return;
    }

    final android = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: ongoing,
      autoCancel: !ongoing,
      onlyAlertOnce: true,
      showProgress: ongoing,
      maxProgress: 100,
      progress: progress,
      indeterminate: ongoing && indeterminate,
      category: AndroidNotificationCategory.progress,
      visibility: NotificationVisibility.public,
    );
    final ios = DarwinNotificationDetails(
      presentAlert: t.status == TransferStatus.done || t.status == TransferStatus.error,
      presentBadge: false,
      presentSound: false,
    );

    try {
      await _notif.show(
        id, title, body,
        NotificationDetails(android: android, iOS: ios),
        payload: 'nuru-transfer:${t.libraryId}',
      );
    } catch (_) {}
  }

  List<TransferTask> tasksForLibrary(String libraryId) =>
      _tasks.where((t) => t.libraryId == libraryId).toList();

  void _notifyOverall() => notifyListeners();

  void remove(TransferTask t) {
    _tasks.remove(t);
    _lastNotifTick.remove(t.id);
    try { _notif.cancel(_notifIdFor(t)); } catch (_) {}
    notifyListeners();
  }

  void clearCompleted({String? libraryId}) {
    final removed = _tasks.where((t) =>
      (libraryId == null || t.libraryId == libraryId) &&
      (t.status == TransferStatus.done ||
       t.status == TransferStatus.cancelled ||
       t.status == TransferStatus.error)).toList();
    for (final t in removed) {
      try { _notif.cancel(_notifIdFor(t)); } catch (_) {}
      _lastNotifTick.remove(t.id);
    }
    _tasks.removeWhere((t) => removed.contains(t));
    notifyListeners();
  }

  // ─── Upload ──────────────────────────────────────────────────────────
  TransferTask queueUpload({
    required String libraryId,
    required String filePath,
    String? caption,
    String? albumName,
    bool isHighlight = false,
  }) {
    final file = File(filePath);
    final size = file.existsSync() ? file.lengthSync() : 0;
    final task = TransferTask(
      id: 'up-${DateTime.now().microsecondsSinceEpoch}-${_tasks.length}',
      kind: TransferKind.upload,
      name: p.basename(filePath),
      sizeBytes: size,
      libraryId: libraryId,
      folderName: null,
      sourcePath: filePath,
      mediaType: _isVideoExt(filePath) ? 'video' : 'photo',
      uploadCaption: caption,
      uploadAlbumName: albumName,
      uploadIsHighlight: isHighlight,
    );
    _tasks.add(task);
    notifyListeners();
    _startUploadPump();
    return task;
  }

  void _startUploadPump() {
    if (_uploadPumpRunning) return;
    unawaited(_runUploadQueue());
  }

  Future<void> _runUploadQueue() async {
    if (_uploadPumpRunning) return;
    _uploadPumpRunning = true;
    print('[LibraryUpload] upload queue started');
    try {
      while (true) {
        TransferTask? next;
        for (final t in _tasks) {
          if (t.kind == TransferKind.upload &&
              t.status == TransferStatus.queued &&
              !t._cancelRequested) {
            next = t;
            break;
          }
        }
        if (next == null) break;
        print('[LibraryUpload] queue running next task=${next.id} name=${next.name}');
        await _runUpload(
          next,
          caption: next.uploadCaption,
          albumName: next.uploadAlbumName,
          isHighlight: next.uploadIsHighlight,
        );
      }
    } finally {
      _uploadPumpRunning = false;
      print('[LibraryUpload] upload queue stopped');
    }
  }

  Future<void> _runUpload(TransferTask task, {String? caption, String? albumName, bool isHighlight = false}) async {
    if (task._cancelRequested) return;
    task._setStatus(TransferStatus.uploading);
    try {
      print('[LibraryUpload] starting task=${task.id} library=${task.libraryId} path=${task.sourcePath}');
      final file = File(task.sourcePath!);
      if (!file.existsSync()) {
        print('[LibraryUpload] file missing before API call path=${task.sourcePath}');
        task._setStatus(TransferStatus.error, error: 'File no longer exists');
        return;
      }
      final totalBytes = await file.length();
      final isVideo = _isVideoExt(task.sourcePath!);
      print('[LibraryUpload] file=${task.name} size=$totalBytes isVideo=$isVideo endpoint=/photo-libraries/${task.libraryId}/upload');

      // Hard client-side cap: photos stay small, videos may use the full
      // photo-library allowance like glimpses do instead of being blocked locally.
      final maxBytes = 10 * 1024 * 1024;
      if (totalBytes > maxBytes) {
        print('[LibraryUpload] blocked locally: size $totalBytes exceeds $maxBytes');
        task._setStatus(TransferStatus.error,
            error: '${isVideo ? "Video" : "File"} too large · max ${(maxBytes / (1024 * 1024)).round()}MB, yours is ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)}MB');
        return;
      }

      final fields = <String, String>{};
      if (caption != null) fields['caption'] = caption;
      if (albumName != null && albumName.trim().isNotEmpty) fields['album_name'] = albumName.trim();
      if (isHighlight) fields['is_highlight'] = 'true';
      print('[LibraryUpload] calling multipart API with fields=${fields.keys.toList()}');

      // Use the same multipart path as glimpses/moments. That path is already
      // proven on mobile networks and avoids the SocketBroken pipe failures
      // caused by the custom streaming request here.
      final decoded = await ApiBase.postMultipart(
        '/photo-libraries/${task.libraryId}/upload',
        fields: fields,
        files: [MapEntry('file', task.sourcePath!)],
        timeout: Duration(seconds: isVideo ? 180 : 60),
        onProgress: (progress) => task._setProgress((totalBytes * progress).round()),
      );
      final apiSuccess = decoded['success'];
      final apiMessage = decoded['message'];
      final apiDataType = decoded['data']?.runtimeType;
      print('[LibraryUpload] API result success=$apiSuccess message=$apiMessage dataType=$apiDataType');

      if (task._cancelRequested) {
        print('[LibraryUpload] task cancelled after API call task=${task.id}');
        task._setStatus(TransferStatus.cancelled);
        return;
      }

      if (decoded['success'] != false) {
        task._setProgress(totalBytes);
        task.resultData = decoded;
        final data = decoded['data'];
        if (data is Map && data['url'] != null) task.remoteResultUrl = data['url'].toString();
        task._setStatus(TransferStatus.done);
      } else {
        final msg = _messageFrom(decoded, fallback: 'Upload failed');
        print('[LibraryUpload] upload failed task=${task.id} error=$msg');
        task._setStatus(TransferStatus.error, error: msg);
      }
    } catch (e) {
      print('[LibraryUpload] exception task=${task.id}: ${e.runtimeType}: $e');
      task._setStatus(TransferStatus.error, error: e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _messageFrom(Map<String, dynamic> decoded, {required String fallback}) {
    final message = decoded['message']?.toString();
    if (message != null && message.isNotEmpty) return message;
    final data = decoded['data'];
    if (data is Map && data['message'] != null) return data['message'].toString();
    return fallback;
  }

  void retry(TransferTask task) {
    if (task.kind == TransferKind.upload) {
      task._cancelRequested = false;
      task._pauseRequested = false;
      task._bytesProcessed = 0;
      task._error = null;
      task._setStatus(TransferStatus.queued);
      _startUploadPump();
    } else {
      task._cancelRequested = false;
      task._pauseRequested = false;
      task._bytesProcessed = 0;
      task._error = null;
      _runDownload(task);
    }
  }

  void resume(TransferTask task) {
    task._pauseRequested = false;
    if (task.status == TransferStatus.paused) {
      task._setStatus(task.kind == TransferKind.upload
          ? TransferStatus.uploading
          : TransferStatus.downloading);
    }
  }

  // ─── Download ────────────────────────────────────────────────────────
  TransferTask queueDownload({
    required String libraryId,
    required String url,
    String? filename,
    String? mediaType,
    String? folderName,
  }) {
    final name = filename ?? p.basename(Uri.parse(url).path);
    final task = TransferTask(
      id: 'dn-${DateTime.now().microsecondsSinceEpoch}-${_tasks.length}',
      kind: TransferKind.download,
      name: name,
      sizeBytes: 0,
      libraryId: libraryId,
      folderName: folderName,
      remoteUrl: url,
      mediaType: mediaType ?? (_isVideoExt(name) ? 'video' : 'photo'),
    );
    _tasks.add(task);
    notifyListeners();
    _runDownload(task);
    return task;
  }

  Future<void> downloadAll({
    required String libraryId,
    required List<Map<String, dynamic>> media,
    String? folderName,
  }) async {
    for (final m in media) {
      final url = m['url']?.toString();
      if (url == null || url.isEmpty) continue;
      queueDownload(
        libraryId: libraryId,
        url: url,
        filename: m['original_name']?.toString(),
        mediaType: m['media_type']?.toString(),
        folderName: folderName,
      );
    }
  }

  Future<void> _runDownload(TransferTask task) async {
    if (task._cancelRequested) return;
    task._setStatus(TransferStatus.downloading);
    try {
      final dir = await _resolveDownloadDir(task.libraryId, folderName: task.folderName);
      final outPath = p.join(dir.path, _safeFilename(task.name));
      final out = File(outPath).openWrite();

      final req = http.Request('GET', Uri.parse(task.remoteUrl!));
      final response = await http.Client().send(req);
      final total = response.contentLength ?? 0;
      // mutate sizeBytes via reflection-free trick: we use bytesProcessed for progress;
      // if total is known we compute progress relative to it.
      int received = 0;
      await for (final chunk in response.stream) {
        if (task._cancelRequested) {
          await out.close();
          try { File(outPath).deleteSync(); } catch (_) {}
          task._setStatus(TransferStatus.cancelled);
          return;
        }
        while (task._pauseRequested && !task._cancelRequested) {
          task._setStatus(TransferStatus.paused);
          await Future.delayed(const Duration(milliseconds: 250));
        }
        if (task.status == TransferStatus.paused) {
          task._setStatus(TransferStatus.downloading);
        }
        out.add(chunk);
        received += chunk.length;
        task._setProgress(received);
        if (total > 0) {
          // hack: we expose progress via bytesProcessed/sizeBytes; sizeBytes is final.
          // store percent via _bytesProcessed scaled if size==0.
        }
      }
      await out.close();
      task.localResultPath = await _publishDownload(outPath, task) ?? outPath;
      task._setStatus(TransferStatus.done);
    } catch (e) {
      task._setStatus(TransferStatus.error, error: e.toString());
    }
  }

  Future<Directory> _resolveDownloadDir(String libraryId, {String? folderName}) async {
    Directory base;
    try {
      base = Platform.isAndroid ? await getTemporaryDirectory() : await getApplicationDocumentsDirectory();
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final lib = Directory(p.join(base.path, _safeFilename(folderName == null || folderName.isEmpty ? 'Library-$libraryId' : folderName)));
    if (!await lib.exists()) await lib.create(recursive: true);
    return lib;
  }

  Future<String?> _publishDownload(String sourcePath, TransferTask task) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _mediaStoreChannel.invokeMethod<String>('saveToDownloads', {
        'sourcePath': sourcePath,
        'fileName': _safeFilename(task.name),
        'folderName': _safeFilename(task.folderName == null || task.folderName!.isEmpty ? 'Library-${task.libraryId}' : task.folderName!),
        'mimeType': _contentTypeFor(task.name).toString(),
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  String _safeFilename(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  bool _isVideoExt(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.mp4' || ext == '.mov' || ext == '.m4v' || ext == '.3gp' || ext == '.avi' || ext == '.mkv' || ext == '.webm';
  }

  MediaType _contentTypeFor(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return MediaType('image', 'jpeg');
      case '.png':
        return MediaType('image', 'png');
      case '.webp':
        return MediaType('image', 'webp');
      case '.gif':
        return MediaType('image', 'gif');
      case '.avif':
        return MediaType('image', 'avif');
      case '.heic':
        return MediaType('image', 'heic');
      case '.heif':
        return MediaType('image', 'heif');
      case '.mp4':
        return MediaType('video', 'mp4');
      case '.mov':
        return MediaType('video', 'quicktime');
      case '.m4v':
        return MediaType('video', 'x-m4v');
      case '.3gp':
        return MediaType('video', '3gpp');
      case '.avi':
        return MediaType('video', 'x-msvideo');
      case '.mkv':
        return MediaType('video', 'x-matroska');
      case '.webm':
        return MediaType('video', 'webm');
      default:
        return MediaType('application', 'octet-stream');
    }
  }
}
