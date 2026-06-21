/// Nuru mobile performance instrumentation — Stage 1.
///
/// Usage on a screen:
///
///   final span = PerfTracer.tap('checkin_scan');
///   final res = await CheckinFastService.scan(...);
///   span.screenUpdated();          // call after setState / provider notify
///
/// Background refresh:
///
///   final span = PerfTracer.bgStart('checkin_stats_refresh');
///   await CheckinFastService.stats(...);
///   span.bgEnd();
///
/// HTTP timing is captured automatically by ApiBase via [tracedHttp].
///
/// Disable globally by setting PerfTracer.enabled = false at app boot.
library;

import 'dart:convert';
import 'dart:developer' as developer;

class PerfTracer {
  PerfTracer._();

  static bool enabled = true;

  static PerfSpan tap(String action, {Map<String, Object?>? meta}) {
    final span = PerfSpan._(action: action, kind: 'tap');
    _emit(<String, Object?>{
      'evt': 'tap',
      'action': action,
      'ts': span._startMicros,
      ...?meta,
    });
    return span;
  }

  static PerfSpan bgStart(String action, {Map<String, Object?>? meta}) {
    final span = PerfSpan._(action: action, kind: 'bg');
    _emit(<String, Object?>{
      'evt': 'bg_start',
      'action': action,
      'ts': span._startMicros,
      ...?meta,
    });
    return span;
  }

  static void _emit(Map<String, Object?> record) {
    if (!enabled) return;
    try {
      developer.log(jsonEncode(record), name: 'nuru.perf');
    } catch (_) {
      // Logging must never break the app.
    }
  }
}

class PerfSpan {
  PerfSpan._({required this.action, required this.kind})
      : _startMicros = DateTime.now().microsecondsSinceEpoch;

  final String action;
  final String kind; // 'tap' or 'bg'
  final int _startMicros;
  bool _closed = false;

  int get _elapsedMs =>
      ((DateTime.now().microsecondsSinceEpoch - _startMicros) / 1000).round();

  void screenUpdated({Map<String, Object?>? meta}) {
    if (!PerfTracer.enabled || _closed) return;
    _closed = true;
    PerfTracer._emit(<String, Object?>{
      'evt': 'rendered',
      'action': action,
      'waited_ms': _elapsedMs,
      ...?meta,
    });
  }

  void bgEnd({Map<String, Object?>? meta}) {
    if (!PerfTracer.enabled || _closed) return;
    _closed = true;
    PerfTracer._emit(<String, Object?>{
      'evt': 'bg_end',
      'action': action,
      'waited_ms': _elapsedMs,
      ...?meta,
    });
  }
}

/// Wraps an HTTP send so the request/response timing, payload bytes, status,
/// and X-Request-ID header are emitted as one perf line. Used from ApiBase.
///
/// The function signature returns whatever [send] returns; we observe the
/// status / headers via the supplied [statusOf] / [headersOf] / [bytesOf]
/// extractors so this helper is agnostic of http.Response vs StreamedResponse.
Future<T> tracedHttp<T>({
  required String method,
  required String endpoint,
  required Future<T> Function() send,
  int Function(T)? statusOf,
  String? Function(T)? requestIdOf,
  int Function(T)? bytesOf,
}) async {
  if (!PerfTracer.enabled) return send();
  final start = DateTime.now().microsecondsSinceEpoch;
  int status = 0;
  String? rid;
  int bytes = 0;
  try {
    final res = await send();
    if (statusOf != null) status = statusOf(res);
    if (requestIdOf != null) rid = requestIdOf(res);
    if (bytesOf != null) bytes = bytesOf(res);
    return res;
  } finally {
    final durMs =
        ((DateTime.now().microsecondsSinceEpoch - start) / 1000).round();
    PerfTracer._emit(<String, Object?>{
      'evt': 'fetch',
      'method': method,
      'endpoint': endpoint,
      'status': status,
      'bytes': bytes,
      'dur_ms': durMs,
      'rid': rid,
    });
  }
}
