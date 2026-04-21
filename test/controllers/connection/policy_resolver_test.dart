import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection/policy_resolver.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';

class _FakeDe1 implements De1Interface {
  @override
  final String deviceId;

  _FakeDe1(this.deviceId);

  @override
  DeviceType get type => DeviceType.machine;

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeScale implements Scale {
  @override
  final String deviceId;

  _FakeScale(this.deviceId);

  @override
  DeviceType get type => DeviceType.scale;

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  group('resolveMachinePolicy', () {
    test('no preferred + no machines → idle (no others)', () {
      final result = resolveMachinePolicy(
        machines: const [],
        preferredMachineId: null,
      );
      expect(result, isA<NoMachineAction>());
    });

    test('no preferred + exactly one machine → connect', () {
      final m = _FakeDe1('a');
      final result = resolveMachinePolicy(
        machines: [m],
        preferredMachineId: null,
      );
      expect(result, isA<ConnectMachineAction>());
      expect((result as ConnectMachineAction).machine, same(m));
    });

    test('no preferred + two machines → picker', () {
      final result = resolveMachinePolicy(
        machines: [_FakeDe1('a'), _FakeDe1('b')],
        preferredMachineId: null,
      );
      expect(result, isA<MachinePickerAction>());
    });

    test('preferred set + no machines → idle', () {
      final result = resolveMachinePolicy(
        machines: const [],
        preferredMachineId: 'pref',
      );
      expect(result, isA<NoMachineAction>());
    });

    test(
        'preferred set but not discovered + other machines present → picker',
        () {
      // Early-connect would have handled the happy "preferred found"
      // path; reaching here with a non-empty list means the preferred
      // id wasn't among them.
      final result = resolveMachinePolicy(
        machines: [_FakeDe1('other')],
        preferredMachineId: 'pref',
      );
      expect(result, isA<MachinePickerAction>());
    });
  });

  group('resolveScalePolicy', () {
    test('no preferred + zero scales → no action', () {
      final result = resolveScalePolicy(
        scales: const [],
        preferredScaleId: null,
      );
      expect(result, isA<NoScaleAction>());
    });

    test('no preferred + exactly one scale → connect', () {
      final s = _FakeScale('a');
      final result = resolveScalePolicy(
        scales: [s],
        preferredScaleId: null,
      );
      expect(result, isA<ConnectScaleAction>());
      expect((result as ConnectScaleAction).scale, same(s));
    });

    test('no preferred + two scales → picker', () {
      final result = resolveScalePolicy(
        scales: [_FakeScale('a'), _FakeScale('b')],
        preferredScaleId: null,
      );
      expect(result, isA<ScalePickerAction>());
    });

    test('preferred scale found in list → connect that one', () {
      final target = _FakeScale('pref');
      final result = resolveScalePolicy(
        scales: [_FakeScale('other'), target, _FakeScale('other2')],
        preferredScaleId: 'pref',
      );
      expect(result, isA<ConnectScaleAction>());
      expect((result as ConnectScaleAction).scale, same(target));
    });

    test('preferred set but not in list + others present → picker', () {
      final result = resolveScalePolicy(
        scales: [_FakeScale('other')],
        preferredScaleId: 'pref',
      );
      expect(result, isA<ScalePickerAction>());
    });

    test('preferred set but no scales at all → no action', () {
      final result = resolveScalePolicy(
        scales: const [],
        preferredScaleId: 'pref',
      );
      expect(result, isA<NoScaleAction>());
    });
  });
}
