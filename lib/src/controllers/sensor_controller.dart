import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/sensor.dart';

/// Aggregates sensors from two sources:
///
/// 1. [DeviceController] discovery — `Sensor` instances picked up via
///    BLE/USB scans (e.g. SensorBasket).
/// 2. Bridge-registered — `Sensor` adapters wrapping a non-discoverable
///    signal source (e.g. `BengleMilkProbe`, which is a probe jack on
///    the machine, not a discoverable BLE peripheral).
///
/// When the same `deviceId` appears in both sources, the
/// bridge-registered instance wins — it carries fuller signal
/// (probe-attach state, latest reading), where the discovered entry
/// only knows BLE presence. See `BengleProbeBridge` for the canonical
/// caller.
class SensorController {
  final DeviceController _deviceController;

  final Map<String, Sensor> _discovered = {};
  final Map<String, Sensor> _bridgeRegistered = {};

  final Logger _log = Logger("SensorController");

  StreamSubscription<List<Device>>? _deviceStreamSubscription;

  SensorController({required DeviceController controller})
    : _deviceController = controller {
    _deviceStreamSubscription = _deviceController.deviceStream.listen(
      _processDevices,
    );
  }

  Future<void> _processDevices(List<Device> devices) async {
    final sensors = devices.whereType<Sensor>().toList();
    _log.info("received sensors: $sensors");
    _discovered
      ..clear()
      ..addEntries(sensors.map((s) => MapEntry(s.deviceId, s)));
    await Future.wait(sensors.map((s) => s.onConnect()));
  }

  /// Register a sensor not surfaced by [DeviceController] (e.g. an
  /// adapter wrapping a machine-integrated probe). The adapter's
  /// `onConnect` is invoked so it can attach to its underlying signal
  /// source. If a sensor with the same `deviceId` was already
  /// bridge-registered it is replaced after disconnecting the previous
  /// instance.
  Future<void> register(Sensor sensor) async {
    final id = sensor.deviceId;
    final existing = _bridgeRegistered[id];
    if (existing != null && !identical(existing, sensor)) {
      await existing.disconnect();
    }
    _bridgeRegistered[id] = sensor;
    if (!identical(existing, sensor)) {
      await sensor.onConnect();
    }
  }

  /// Remove a bridge-registered sensor and disconnect it. No-op on
  /// `DeviceController`-sourced entries — those are owned by their
  /// discovery service and removed when the device stream drops them.
  Future<void> unregister(String deviceId) async {
    final removed = _bridgeRegistered.remove(deviceId);
    if (removed != null) {
      await removed.disconnect();
    }
  }

  /// Merged view of bridge-registered + discovered sensors. Bridge
  /// entries take precedence on `deviceId` collisions.
  Map<String, Sensor> get sensors => {
    ..._discovered,
    ..._bridgeRegistered,
  };

  /// Pick the sensor to drive steam stop or shot recording.
  ///
  /// Precedence (FR-M2/M3): bridge-registered match on [preferredId],
  /// then any connected sensor with that id, then the first registered
  /// sensor in [sensors] (discovered first, bridge-only entries after).
  Sensor? resolvePreferred(String? preferredId) {
    if (preferredId != null) {
      final bridge = _bridgeRegistered[preferredId];
      if (bridge != null) {
        return bridge;
      }
      final preferred = sensors[preferredId];
      if (preferred != null) {
        return preferred;
      }
    }

    final registered = sensors;
    if (registered.isEmpty) {
      return null;
    }
    return registered.values.first;
  }

  void dispose() {
    _deviceStreamSubscription?.cancel();
    _deviceStreamSubscription = null;
  }
}
