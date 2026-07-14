import 'dart:async';

import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';

/// Adapter that exposes a [BengleInterface]'s integrated scale to
/// `ScaleController` as a regular [Scale]. Lifecycle is owned by the
/// underlying machine — `onConnect` / `disconnect` on this adapter
/// are no-ops; the adapter is connect-by-construction.
///
/// Display and timer methods are no-ops: the integrated scale has no
/// independent display, and shot timing is owned by `ShotSequencer`.
class BengleVirtualScale extends Scale {
  final BengleInterface _machine;

  BengleVirtualScale(this._machine);

  @override
  String get deviceId => 'bengle-internal-${_machine.deviceId}';

  @override
  DeviceImplementation get implementation => DeviceImplementation.bengle;

  @override
  TransportType get transportType => _machine.transportType;

  @override
  String get name => 'Bengle scale';

  @override
  DeviceType get type => DeviceType.scale;

  @override
  Stream<ConnectionState> get connectionState => _machine.connectionState;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _machine.weightSnapshot;

  @override
  Future<void> tare() => _machine.tareIntegratedScale();

  @override
  Future<void> sleepDisplay() async {}

  @override
  Future<void> wakeDisplay() async {}

  @override
  Future<void> startTimer() async {}

  @override
  Future<void> stopTimer() async {}

  @override
  Future<void> resetTimer() async {}

  @override
  Future<void> onConnect() async {}

  @override
  Future<void> disconnect() async {}
}
