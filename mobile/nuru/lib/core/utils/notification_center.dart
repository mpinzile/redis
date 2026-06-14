import 'package:flutter/foundation.dart';

/// App-wide notification badge state.
///
/// Both the Home and Profile app bars (and any other future surface)
/// should read [unreadCount] via a `ValueListenableBuilder` and call
/// [setUnread] whenever they fetch a fresh count from the backend or
/// the user marks notifications as read. This keeps every badge in sync.
class NotificationCenter {
  NotificationCenter._();

  /// Live unread-notification count. Defaults to 0.
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Update the badge - no-op if [count] is null or already current.
  static void setUnread(int? count) {
    if (count == null) return;
    final clamped = count < 0 ? 0 : count;
    if (unreadCount.value != clamped) unreadCount.value = clamped;
  }

  /// Convenience for "mark all read" buttons.
  static void clear() => setUnread(0);

  /// Decrement by one (e.g. after marking a single notification as read).
  static void decrement() {
    if (unreadCount.value > 0) unreadCount.value = unreadCount.value - 1;
  }
}