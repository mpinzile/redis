import 'package:flutter/foundation.dart';

/// Global controller for the Home shell's bottom-navigation index.
///
/// Lets any screen - even one pushed on top of Home via MaterialPageRoute -
/// switch the active bottom-nav tab without needing a BuildContext that
/// reaches the HomeScreen's State.
///
/// HomeScreen listens to [index] and, when it changes, pops back to itself
/// (so any pushed routes are removed) and calls setState on the new tab.
class HomeTabController {
  HomeTabController._();

  /// Bottom-nav indices (mirror HomeScreen):
  /// 0 Home · 1 Events · 2 Create (action) · 3 Tickets · 4 Profile
  static const int home = 0;
  static const int events = 1;
  static const int tickets = 3;
  static const int profile = 4;

  /// Monotonically increasing counter so HomeScreen reacts even when the
  /// requested tab is the same as the current one (e.g. user on Tickets
  /// taps "My Tickets" again - we still want to pop pushed routes).
  static final ValueNotifier<int> requestSeq = ValueNotifier<int>(0);

  /// Last requested tab. Read by HomeScreen on each [requestSeq] tick.
  static int requestedTab = home;

  /// When non-null, HomeScreen also switches the Events sub-tab
  /// (0 My Events · 1 Invited · 2 Committee · 3 My Contributions).
  static int? requestedEventsSubTab;

  static void openTickets() => _request(tickets);
  static void openHome() => _request(home);
  static void openProfile() => _request(profile);
  static void openEvents() => _request(events);

  /// Open Events tab pinned to the My Events sub-tab.
  static void openMyEvents() { requestedEventsSubTab = 0; _request(events); }
  /// Open Events tab pinned to the Invited sub-tab.
  static void openInvitations() { requestedEventsSubTab = 1; _request(events); }
  /// Open Events tab pinned to the Committee sub-tab.
  static void openCommitteeEvents() { requestedEventsSubTab = 2; _request(events); }
  /// Open Events tab pinned to the My Contributions sub-tab.
  static void openMyContributions() { requestedEventsSubTab = 3; _request(events); }

  static void _request(int tab) {
    requestedTab = tab;
    requestSeq.value = requestSeq.value + 1;
  }
}