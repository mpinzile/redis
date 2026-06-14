/// Simple in-memory caches for the messages screen so that re-opening a
/// conversation feels instant (WhatsApp-style) instead of showing a spinner
/// while the network round-trip completes.
///
/// Two layers:
///   * [MessagesCache.conversations] - the last-known list of conversations,
///     used as a seed when the Messages screen mounts before the network
///     fetch returns.
///   * [MessagesCache.messages] - per-conversation message arrays seeded by
///     the prefetcher when a card scrolls into view, and updated by the
///     ChatDetailScreen after every successful load.
///
/// Caches live for the duration of the process - they are cleared on logout
/// via [MessagesCache.reset].
class MessagesCache {
  MessagesCache._();

  static List<dynamic>? conversations;

  // conversationId -> { messages: [...], calls: [...] }
  static final Map<String, _ConvCache> _byConv = <String, _ConvCache>{};

  static List<dynamic>? getMessages(String convId) =>
      _byConv[convId]?.messages;

  static List<dynamic>? getCalls(String convId) => _byConv[convId]?.calls;

  static void putMessages(String convId, List<dynamic> messages) {
    final cur = _byConv[convId] ?? _ConvCache();
    cur.messages = List<dynamic>.from(messages);
    _byConv[convId] = cur;
  }

  static void putCalls(String convId, List<dynamic> calls) {
    final cur = _byConv[convId] ?? _ConvCache();
    cur.calls = List<dynamic>.from(calls);
    _byConv[convId] = cur;
  }

  static void reset() {
    conversations = null;
    _byConv.clear();
  }
}

class _ConvCache {
  List<dynamic> messages = const [];
  List<dynamic> calls = const [];
}
