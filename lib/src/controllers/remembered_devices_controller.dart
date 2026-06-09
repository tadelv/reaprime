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

  /// Load the persisted registry and start observing connections.
  Future<void> initialize() async {
    for (final d in RememberedDevice.decodeList(await _settings.rememberedDevices())) {
      _registry[d.id] = d;
    }
    _log.info('loaded ${_registry.length} remembered device(s)');
    _emit();
    _subs.add(_machineConnections.listen((d) {
      if (d != null) _remember(d);
    }));
    _subs.add(_scaleConnections.listen((d) {
      if (d != null) _remember(d);
    }));
  }

  Future<void> _remember(RememberedDevice device) async {
    final existing = _registry[device.id];
    if (existing != null &&
        existing.name == device.name &&
        existing.type == device.type) {
      return; // already remembered with the same metadata
    }
    _registry[device.id] = device;
    _log.info('remembering $device');
    await _persist();
    _emit();
  }

  /// Forget a remembered device. No-op if it isn't remembered.
  Future<void> forget(String id) async {
    if (_registry.remove(id) == null) return;
    _log.info('forgot $id');
    await _persist();
    _emit();
  }

  Future<void> _persist() async {
    await _settings.setRememberedDevices(
        RememberedDevice.encodeList(_registry.values));
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
