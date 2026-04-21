import 'dart:async';

/// Tracks deviceIds the app is about to deliberately disconnect.
///
/// When a disconnect is about to be app-initiated (e.g., explicit
/// `disconnectMachine` call, scale-power-down from machine sleep),
/// callers [mark] the device's id first so the matching
/// `disconnected` event fires without emitting an error on
/// `ConnectionManager.status`.
///
/// A bounded TTL timer clears the mark if the expected disconnect
/// event never arrives — otherwise a stale mark would silently
/// suppress an unrelated real disconnect later.
///
/// Extracted from ConnectionManager as part of comms-harden Phase 4
/// (roadmap item 15 — god-class split).
class DisconnectExpectations {
  /// How long a `mark` stays valid if no matching disconnect event
  /// arrives. Matches the previous inline TTL in ConnectionManager.
  static const ttl = Duration(seconds: 10);

  final Set<String> _expecting = <String>{};
  final Map<String, Timer> _timers = <String, Timer>{};

  /// Mark [deviceId] as expecting a disconnect. The next matching
  /// `disconnected` event will be consumed silently by [consume].
  ///
  /// Idempotent: marking the same id twice resets the TTL without
  /// doubling up entries.
  void mark(String deviceId) {
    _expecting.add(deviceId);
    _timers[deviceId]?.cancel();
    _timers[deviceId] = Timer(ttl, () {
      _expecting.remove(deviceId);
      _timers.remove(deviceId);
    });
  }

  /// Consume an expectation for [deviceId]. Returns true if [deviceId]
  /// was marked (and was cleared as a side effect), false otherwise.
  bool consume(String deviceId) {
    final wasExpecting = _expecting.remove(deviceId);
    if (wasExpecting) {
      _timers.remove(deviceId)?.cancel();
    }
    return wasExpecting;
  }

  /// Cancel every pending TTL timer and clear all expectations.
  /// Safe to call more than once.
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _expecting.clear();
  }
}
