import 'dart:async';

import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart' as device_scale;
import 'package:reaprime/src/models/scan_report.dart';
import 'package:rxdart/rxdart.dart';

/// Minimal [De1Interface] stub for testing.
class FakeDe1 implements De1Interface {
  @override
  final String deviceId;

  @override
  final String name;

  @override
  dev.DeviceType get type => dev.DeviceType.machine;

  @override
  Stream<dev.ConnectionState> get connectionState =>
      Stream.value(dev.ConnectionState.connected);

  FakeDe1({this.deviceId = 'fake-de1', String? name})
    : name = name ?? 'DE1-$deviceId';

  @override
  Stream<MachineSnapshot> get currentSnapshot => const Stream.empty();

  @override
  Stream<De1WaterLevels> get waterLevels => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A [ConnectionManager] subclass that gives tests direct control over the
/// status stream and records `connect()` calls, without requiring real
/// device scanning infrastructure.
class MockConnectionManager extends ConnectionManager {
  final _statusOverride = BehaviorSubject<ConnectionStatus>.seeded(
    const ConnectionStatus(phase: ConnectionPhase.scanning),
  );

  int connectCallCount = 0;
  ScanReport? _lastScanReport;

  MockConnectionManager({
    required super.deviceScanner,
    required super.de1Controller,
    required super.scaleController,
    required super.settingsController,
  });

  @override
  Stream<ConnectionStatus> get status => _statusOverride.stream;

  @override
  ConnectionStatus get currentStatus => _statusOverride.value;

  @override
  ScanReport? get lastScanReport => _lastScanReport;

  void setLastScanReport(ScanReport? report) => _lastScanReport = report;

  void emitStatus(ConnectionStatus status) => _statusOverride.add(status);

  @override
  Future<void> connect({bool scaleOnly = false}) async {
    connectCallCount++;
  }

  @override
  Future<void> connectMachine(De1Interface machine) async {}

  @override
  Future<void> connectScale(device_scale.Scale scale) async {}

  @override
  Future<void> dispose() async {
    _statusOverride.close();
    await super.dispose();
  }
}
