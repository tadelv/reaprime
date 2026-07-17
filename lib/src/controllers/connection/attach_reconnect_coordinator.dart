import 'dart:async';

import 'package:reaprime/src/models/device/device_attach_notifier.dart';

class AttachReconnectCoordinator {
  final Duration settleDelay;
  final bool Function() shouldAttempt;
  final Future<bool> Function() attempt;
  final FutureOr<void> Function() recover;

  late final StreamSubscription<DeviceAttachedEvent> _subscription;
  Timer? _settleTimer;
  bool _inFlight = false;
  bool _disposed = false;

  AttachReconnectCoordinator({
    required Stream<DeviceAttachedEvent> attachEvents,
    required this.settleDelay,
    required this.shouldAttempt,
    required this.attempt,
    required this.recover,
  }) {
    _subscription = attachEvents.listen(_onAttach);
  }

  void _onAttach(DeviceAttachedEvent _) {
    if (_disposed || _inFlight || _settleTimer != null || !shouldAttempt()) {
      return;
    }
    _settleTimer = Timer(settleDelay, () {
      _settleTimer = null;
      if (_disposed || _inFlight || !shouldAttempt()) return;
      _inFlight = true;
      unawaited(_runAttempt());
    });
  }

  Future<void> _runAttempt() async {
    var succeeded = false;
    try {
      succeeded = await attempt();
    } catch (_) {
      succeeded = false;
    } finally {
      _inFlight = false;
    }
    if (!_disposed && !succeeded && shouldAttempt()) {
      await recover();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _settleTimer?.cancel();
    _settleTimer = null;
    await _subscription.cancel();
  }
}
