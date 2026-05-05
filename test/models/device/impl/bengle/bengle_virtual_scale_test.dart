import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_virtual_scale.dart';

void main() {
  group('BengleVirtualScale', () {
    late MockBengle bengle;
    late BengleVirtualScale scale;

    setUp(() async {
      bengle = MockBengle();
      scale = BengleVirtualScale(bengle);
      await bengle.onConnect();
    });

    tearDown(() async {
      await bengle.onDisconnect();
    });

    test('proxies the machine weightSnapshot stream', () async {
      final snap = await scale.currentSnapshot.first
          .timeout(const Duration(seconds: 2));
      expect(snap.batteryLevel, 100);
    });

    test('tare delegates to machine.tareIntegratedScale', () async {
      await bengle.requestState(MachineState.espresso);
      await Future.delayed(const Duration(seconds: 1));
      await bengle.requestState(MachineState.idle);

      await scale.currentSnapshot.first;
      await scale.tare();
      final next = await scale.currentSnapshot.first
          .timeout(const Duration(seconds: 2));
      expect(next.weight.abs(), lessThan(0.01));
    });

    test('deviceId is derived from the machine', () {
      expect(scale.deviceId, 'bengle-internal-${bengle.deviceId}');
    });

    test('name is "Bengle scale"', () {
      expect(scale.name, 'Bengle scale');
    });

    test('type is DeviceType.scale', () {
      expect(scale.type, DeviceType.scale);
    });

    test('connectionState mirrors machine connectionState', () async {
      final state = await scale.connectionState.first
          .timeout(const Duration(seconds: 1));
      expect(state, isA<ConnectionState>());
      final mState = await bengle.connectionState.first
          .timeout(const Duration(seconds: 1));
      expect(state, mState);
    });

    test('display + timer methods are no-ops and resolve', () async {
      await scale.sleepDisplay();
      await scale.wakeDisplay();
      await scale.startTimer();
      await scale.stopTimer();
      await scale.resetTimer();
    });

    test('onConnect and disconnect on the adapter are no-ops', () async {
      await scale.onConnect();
      await scale.disconnect();
    });
  });
}
