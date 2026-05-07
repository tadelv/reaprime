import 'dart:async';

import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/led_strip.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/rxdart.dart';

/// Simulated Bengle. Reuses [MockDe1]'s state machine — Bengle's behavior
/// today is functionally identical to a DE1 plus the FW-prelude hook
/// (which mocks bypass entirely, since `MockDe1.updateFirmware` is faked
/// at the public level rather than going through the `_updateFirmware`
/// template that calls `beforeFirmwareUpload`).
///
/// Capability surfaces (cup warmer, integrated scale, LED, milk probe)
/// land in steps 4–7; mirror them on this mock as they're added.
class MockBengle extends MockDe1 implements BengleInterface {
  MockBengle({super.deviceId = 'MockBengle'});

  @override
  String get name => 'MockBengle';

  // --- cup warmer ---
  double _cupWarmerTemp = 0.0;

  @override
  Future<void> setCupWarmerTemperature(double celsius) async {
    _cupWarmerTemp = celsius.clamp(0.0, 80.0).toDouble();
  }

  @override
  Future<double> getCupWarmerTemperature() async => _cupWarmerTemp;

  // --- LED strip ---
  /// Cache of the last-set config (not necessarily committed to NVM).
  final BehaviorSubject<LedStripState> _ledState =
      BehaviorSubject<LedStripState>.seeded(const LedStripState());

  /// Simulated "FW NVM" — written by commit, read by reset.
  LedStripState _committedLedState = const LedStripState();

  @override
  Stream<LedStripState> get ledStripState => _ledState.stream;

  @override
  Future<LedStripState> getLedStripState() async => _ledState.value;

  @override
  Future<void> setLedStrip(LedStripState state) async {
    _ledState.add(state);
  }

  @override
  Future<void> commitLedStrip() async {
    _committedLedState = _ledState.value;
    // In mock: no actual FW NVM write.
  }

  @override
  Future<void> resetLedStrip() async {
    _ledState.add(_committedLedState);
  }

  // --- integrated scale ---
  // Synthesises weight by integrating MockDe1's simulated flow stream:
  // weight = ∫ flow dt. Tare snapshots `_accumulatedWeight` into
  // `_tareOffset` so subsequent emits read ~0.
  // BehaviorSubject so a late subscriber (e.g. WS client connecting
  // mid-shot) immediately gets the current weight without waiting for
  // the next flow sample. Closed on onDisconnect; existing subscribers
  // receive `done`.
  final BehaviorSubject<ScaleSnapshot> _weight = BehaviorSubject();
  StreamSubscription<MachineSnapshot>? _flowSub;
  double _accumulatedWeight = 0.0;
  double _tareOffset = 0.0;
  DateTime? _lastSampleTime;

  @override
  Stream<ScaleSnapshot> get weightSnapshot => _weight.stream;

  @override
  Future<void> tareIntegratedScale() async {
    _tareOffset = _accumulatedWeight;
    _emit();
  }

  void _emit() {
    if (_weight.isClosed) return;
    _weight.add(ScaleSnapshot(
      timestamp: DateTime.now(),
      weight: _accumulatedWeight - _tareOffset,
      batteryLevel: 100,
    ));
  }

  @override
  Future<void> onConnect() async {
    if (_ledState.isClosed) {
      _ledState.add(const LedStripState());
    }
    await super.onConnect();
    _accumulatedWeight = 0.0;
    _tareOffset = 0.0;
    _lastSampleTime = null;
    _emit();
    _flowSub = currentSnapshot.listen(_integrateFlow);
  }

  void _integrateFlow(MachineSnapshot s) {
    final now = s.timestamp;
    final last = _lastSampleTime;
    _lastSampleTime = now;
    if (last == null) return;
    final dtSec = now.difference(last).inMilliseconds / 1000.0;
    if (dtSec <= 0) return;
    _accumulatedWeight += s.flow * dtSec;
    _emit();
  }

  @override
  Future<void> onDisconnect() async {
    await _flowSub?.cancel();
    _flowSub = null;
    if (!_ledState.isClosed) {
      await _ledState.close();
    }
    if (!_weight.isClosed) {
      await _weight.close();
    }
    await super.onDisconnect();
  }

  @override
  MachineInfo get machineInfo => MachineInfo(
        version: '1.0',
        model: 'Bengle',
        serialNumber: '110010101',
        groupHeadControllerPresent: true,
        extra: {'voltage': 220, 'refillKit': false},
      );
}
