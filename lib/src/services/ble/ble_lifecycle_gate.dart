import 'dart:async';

String normalizeBleDeviceId(String deviceId) => deviceId.toLowerCase();

class BleLifecycleGate {
  final Map<String, Future<void>> _pending = {};

  Future<T> run<T>(String deviceId, Future<T> Function() operation) async {
    final key = normalizeBleDeviceId(deviceId);
    final previous = _pending[key] ?? Future<void>.value();
    final done = Completer<void>();
    _pending[key] = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
      if (identical(_pending[key], done.future)) _pending.remove(key);
    }
  }
}
