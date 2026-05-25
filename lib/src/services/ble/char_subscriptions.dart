import 'dart:async';

/// Tracks one active characteristic-notification [StreamSubscription] per
/// characteristic UUID and guarantees re-subscribing replaces rather than
/// stacks.
///
/// The BLE transports re-run `subscribe()` for every characteristic on each
/// `connect()`. When `connect()` is a no-op because the device was still
/// connected at the platform layer ("Already connected, skipping connect"),
/// no disconnect fired, so `cancelWhenDisconnected` never cancelled the prior
/// listeners. Without cancel-before-replace the callbacks stack, every
/// notification is delivered twice, and downstream state streams emit
/// duplicates.
class CharSubscriptions {
  final Map<String, StreamSubscription> _subs = {};

  /// Stores [sub] for [characteristicUUID], cancelling any subscription
  /// previously registered for the same UUID.
  Future<void> add(String characteristicUUID, StreamSubscription sub) async {
    await _subs.remove(characteristicUUID)?.cancel();
    _subs[characteristicUUID] = sub;
  }

  /// Cancels and forgets every tracked subscription. Idempotent.
  Future<void> cancelAll() async {
    final pending = _subs.values.toList();
    _subs.clear();
    for (final sub in pending) {
      await sub.cancel();
    }
  }
}
