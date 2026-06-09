import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:rxdart/subjects.dart';

/// Owns the persistent registry of devices the user has connected to (the
/// "remembered" set). When a remembered device isn't currently present, the
/// API surfaces it as `available: false` instead of dropping it; the user can
/// [forget] it.
///
/// It is deliberately decoupled from the device interfaces: it consumes two
/// streams of [RememberedDevice] records (one per device kind), each emitting a
/// record when a device connects (and null on disconnect, which is ignored —
/// disconnecting does not forget). The field-reading from `De1Interface`/`Scale`
/// lives in the wiring, keeping this controller trivially testable.
class RememberedDevicesController {
  final SettingsService _settings;
  final Stream<RememberedDevice?> _machineConnections;
  final Stream<RememberedDevice?> _scaleConnections;
  final _log = Logger('RememberedDevices');

  /// id -> remembered record. One entry per device id.
  final Map<String, RememberedDevice> _registry = {};
  final BehaviorSubject<List<RememberedDevice>> _changes =
      BehaviorSubject.seeded(const []);
  final List<StreamSubscription> _subs = [];
  bool _initialized = false;

  RememberedDevicesController({
    required Stream<RememberedDevice?> machineConnections,
    required Stream<RememberedDevice?> scaleConnections,
    required SettingsService settings,
  })  : _machineConnections = machineConnections,
        _scaleConnections = scaleConnections,
        _settings = settings;

  /// Current remembered devices.
  List<RememberedDevice> get remembered =>
      List.unmodifiable(_registry.values);

  /// Emits the remembered list whenever it changes.
  Stream<List<RememberedDevice>> get changes => _changes.stream;

  /// Load the persisted registry and start observing connections. Idempotent —
  /// a second call is a no-op (avoids double-subscribing / double-loading).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final raw = await _settings.rememberedDevices();
    final loaded = RememberedDevice.decodeList(raw);
    for (final d in loaded) {
      _registry[d.id] = d;
    }
    // Surface dropped records (malformed, or an unknown type written by a newer
    // build) instead of letting a remembered device silently vanish.
    final stored = RememberedDevice.storedCount(raw);
    if (stored > loaded.length) {
      _log.warning(
          'dropped ${stored - loaded.length} unreadable remembered record(s)');
    }
    _log.info('loaded ${_registry.length} remembered device(s)');
    _emit();
    _subs.add(_machineConnections.listen(
      (d) { if (d != null) unawaited(_rememberFromStream(d)); },
      onError: (e, st) =>
          _log.warning('machine connection stream error', e, st),
    ));
    _subs.add(_scaleConnections.listen(
      (d) { if (d != null) unawaited(_rememberFromStream(d)); },
      onError: (e, st) => _log.warning('scale connection stream error', e, st),
    ));
  }

  /// `_remember` for the un-awaited stream path. A persist failure is already
  /// logged loudly in [_persist]; swallow the rejected future here so it doesn't
  /// surface as an unhandled async error — the registry self-heals on the next
  /// connect.
  Future<void> _rememberFromStream(RememberedDevice device) async {
    try {
      await _remember(device);
    } catch (_) {
      // Already logged at SEVERE in _persist.
    }
  }

  Future<void> _remember(RememberedDevice device) async {
    final existing = _registry[device.id];
    if (existing != null && existing.sameMetadata(device)) {
      return; // already remembered with the same metadata
    }
    _registry[device.id] = device;
    try {
      await _persist();
    } catch (_) {
      // Roll back so the in-memory registry stays consistent with disk on a
      // persist failure (which _persist has already logged at SEVERE).
      if (existing != null) {
        _registry[device.id] = existing;
      } else {
        _registry.remove(device.id);
      }
      rethrow;
    }
    _log.info('remembering $device');
    _emit();
  }

  /// Forget a remembered device. No-op if it isn't remembered.
  Future<void> forget(String id) async {
    final removed = _registry.remove(id);
    if (removed == null) return;
    try {
      await _persist();
    } catch (_) {
      _registry[id] = removed; // roll back: memory must match disk
      rethrow;
    }
    _log.info('forgot $id');
    _emit();
  }

  Future<void> _persist() async {
    try {
      await _settings.setRememberedDevices(
          RememberedDevice.encodeList(_registry.values));
    } catch (e, st) {
      // A persist failure means the in-memory registry changed but the change
      // won't survive a restart. Surface it loudly rather than dropping it
      // silently: the caller that can react (the forget handler) rethrows to a
      // 5xx; the connect-driven path logs and continues.
      _log.severe('failed to persist remembered devices', e, st);
      rethrow;
    }
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(remembered);
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    if (!_changes.isClosed) await _changes.close();
  }
}
