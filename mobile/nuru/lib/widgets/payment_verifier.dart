import 'dart:async';
import 'package:flutter/widgets.dart';
import '../core/services/api_base.dart';

/// PaymentVerifier - background poller (mirrors the web
/// `PaymentVerifierProvider`). Every 15s while the app is in the
/// foreground it asks the backend for stale (>30s) pending transactions
/// belonging to the current user, then touches each one's `/status`
/// endpoint so the gateway re-poll + credit path runs server-side.
///
/// Wrap the app's root widget with `PaymentVerifier(child: ...)`.
class PaymentVerifier extends StatefulWidget {
  final Widget child;
  final Duration interval;
  const PaymentVerifier({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 15),
  });

  @override
  State<PaymentVerifier> createState() => _PaymentVerifierState();
}

class _PaymentVerifierState extends State<PaymentVerifier>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _start() {
    _timer?.cancel();
    _tick(); // immediate
    _timer = Timer.periodic(widget.interval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final res = await ApiBase.get(
        '/payments/pending',
        fallbackError: '',
      );
      if (res['success'] != true) return;
      final list =
          (res['data']?['transactions'] as List?) ?? const [];
      for (final t in list.cast<Map<String, dynamic>>()) {
        final id = t['id']?.toString();
        if (id == null) continue;
        try {
          await ApiBase.get('/payments/$id/status', fallbackError: '');
        } catch (_) {
          // silent - try again next tick
        }
      }
    } catch (_) {
      // silent
    } finally {
      _inFlight = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
