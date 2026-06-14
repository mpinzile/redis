import 'package:nuru/core/utils/money_format.dart' show getActiveCurrency;
import 'package:flutter/material.dart';
import '../core/services/wallet_service.dart';

/// WalletProvider - single source of truth for the user's wallet, ledger,
/// and recent transactions. Screens listen to this and call refresh() after
/// payments/top-ups complete.
class WalletProvider extends ChangeNotifier {
  Map<String, dynamic>? _wallet;
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = false;
  String? _error;

  Map<String, dynamic>? get wallet => _wallet;
  List<Map<String, dynamic>> get ledger => _ledger;
  List<Map<String, dynamic>> get transactions => _transactions;
  bool get loading => _loading;
  String? get error => _error;

  String get currency => (_wallet?['currency_code'] ?? getActiveCurrency()).toString();
  num get availableBalance => (_wallet?['available_balance'] ?? 0) as num;
  num get pendingBalance => (_wallet?['pending_balance'] ?? 0) as num;
  num get reservedBalance => (_wallet?['reserved_balance'] ?? 0) as num;

  /// Load wallet + ledger + recent transactions in parallel.
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        WalletService.listWallets(),
        WalletService.history(limit: 20),
      ]);
      final walletsRes = results[0];
      final txRes = results[1];

      if (walletsRes['success'] == true) {
        final list = (walletsRes['data']?['wallets'] as List?) ?? const [];
        _wallet = list.isNotEmpty ? Map<String, dynamic>.from(list.first) : null;
      }
      if (txRes['success'] == true) {
        _transactions = ((txRes['data']?['transactions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
      }

      if (_wallet != null) {
        final ledgerRes = await WalletService.getLedger(
          _wallet!['id'] as String,
          limit: 20,
        );
        if (ledgerRes['success'] == true) {
          _ledger = ((ledgerRes['data']?['entries'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
