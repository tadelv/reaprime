import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/remembered_device_sources.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/errors.dart';

class _FakeDevice implements Device {
  @override
  final String deviceId;
  @override
  final String name;
  @override
  final DeviceType type;
  _FakeDevice(this.deviceId, this.name, this.type);
  @override
  Stream<ConnectionState> get connectionState => const Stream.empty();
  @override
  Future<void> onConnect() async {}
  @override
  Future<void> disconnect() async {}
}

void main() {
  group('rememberedFromMachine', () {
    test('null machine → null', () {
      expect(rememberedFromMachine(null), isNull);
    });

    test('a connected machine → its record', () {
      final r =
          rememberedFromMachine(_FakeDevice('de1', 'DE1', DeviceType.machine));
      expect(r?.id, 'de1');
      expect(r?.type, DeviceType.machine);
    });
  });

  group('rememberedFromScaleState', () {
    final scale = _FakeDevice('s', 'Scale', DeviceType.scale);

    test('a non-connected state → null, without consulting the lookup', () {
      var called = false;
      final r = rememberedFromScaleState(ConnectionState.disconnected, () {
        called = true;
        return scale;
      });
      expect(r, isNull);
      expect(called, isFalse);
    });

    test('connected → the record from connectedScale()', () {
      final r = rememberedFromScaleState(ConnectionState.connected, () => scale);
      expect(r?.id, 's');
      expect(r?.type, DeviceType.scale);
    });

    test('the connected-then-nulled race (DeviceNotConnectedException) → null',
        () {
      final r = rememberedFromScaleState(
        ConnectionState.connected,
        () => throw const DeviceNotConnectedException.scale(),
      );
      expect(r, isNull);
    });

    test('any other exception surfaces (not swallowed)', () {
      expect(
        () => rememberedFromScaleState(
            ConnectionState.connected, () => throw StateError('boom')),
        throwsStateError,
      );
    });
  });
}
