import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/scale_calibration.dart';

void main() {
  group('MockBengle', () {
    test('implements BengleInterface', () {
      final m = MockBengle();
      expect(m, isA<BengleInterface>());
    });

    test('still implements De1Interface (so existing scan paths consume it)',
        () {
      final m = MockBengle();
      expect(m, isA<De1Interface>());
    });

    test('extends MockDe1 to reuse the simulated state machine', () {
      final m = MockBengle();
      expect(m, isA<MockDe1>());
    });

    test('default deviceId is "MockBengle"', () {
      final m = MockBengle();
      expect(m.deviceId, equals('MockBengle'));
    });

    test('default name is "MockBengle" (matches MockDe1 convention)', () {
      final m = MockBengle();
      expect(m.name, equals('MockBengle'));
    });

    test('deviceId can be overridden via constructor', () {
      final m = MockBengle(deviceId: 'CustomBengleId');
      expect(m.deviceId, equals('CustomBengleId'));
    });
  });

  group('MockBengle SAW', () {
    test('initial target is 0.0 (off)', () async {
      final m = MockBengle();
      expect(await m.getStopAtWeightTarget(), 0.0);
    });

    test('setStopAtWeightTarget stores the value', () async {
      final m = MockBengle();
      await m.setStopAtWeightTarget(30.0);
      expect(await m.getStopAtWeightTarget(), 30.0);
    });

    test('clamps over-range values to 10000.0', () async {
      final m = MockBengle();
      await m.setStopAtWeightTarget(20000.0);
      expect(await m.getStopAtWeightTarget(), 10000.0);
    });

    test('clamps negative values to 0.0', () async {
      final m = MockBengle();
      await m.setStopAtWeightTarget(-10.0);
      expect(await m.getStopAtWeightTarget(), 0.0);
    });

    test('stopAtWeightTarget stream emits cached value', () async {
      final m = MockBengle();
      await m.setStopAtWeightTarget(36.0);
      expect(await m.stopAtWeightTarget.first, 36.0);
    });
  });

  group('MockBengle scale calibration', () {
    test('calibrateScaleZero completes successfully', () async {
      final m = MockBengle();
      final r = await m.calibrateScaleZero();
      expect(r.success, isTrue);
      expect(r.finalStep, ScaleCalStep.complete);
    });

    test('two-point weight cal completes and emits progress', () async {
      final m = MockBengle();
      final seen = <ScaleCalStatus>[];
      final sub = m.scaleCalibrationProgress.listen(seen.add);
      final left = await m.calibrateScaleWeightLeft(500.0);
      final right = await m.calibrateScaleWeightRight(500.0);
      await pumpEventQueue();
      await sub.cancel();
      expect(left.success, isTrue);
      expect(left.pointStatus, ScaleCalPointStatus.incomplete);
      expect(right.success, isTrue);
      expect(right.pointStatus, ScaleCalPointStatus.ok);
      expect(seen.last.isComplete, isTrue);
    });
  });

  group('MockBengle cup warmer', () {
    test('initial setpoint is 0.0 (off)', () async {
      final m = MockBengle();
      expect(await m.getCupWarmerTemperature(), 0.0);
    });

    test('setCupWarmerTemperature stores the value', () async {
      final m = MockBengle();
      await m.setCupWarmerTemperature(60.0);
      expect(await m.getCupWarmerTemperature(), 60.0);
    });

    test('clamps over-range values to 80.0', () async {
      final m = MockBengle();
      await m.setCupWarmerTemperature(120.0);
      expect(await m.getCupWarmerTemperature(), 80.0);
    });

    test('clamps negative values to 0.0', () async {
      final m = MockBengle();
      await m.setCupWarmerTemperature(-10.0);
      expect(await m.getCupWarmerTemperature(), 0.0);
    });
  });

  group('MockBengle scheduled pre-warm', () {
    test('defaults match the firmware: off, 30 min lead, not active', () async {
      final m = MockBengle();
      final prewarm = await m.getCupWarmerPrewarm();
      expect(prewarm, const CupWarmerPrewarm(enabled: false, leadMinutes: 30));
      expect(await m.getCupWarmerPrewarmActive(), isFalse);
    });

    test('setCupWarmerPrewarm stores the pair', () async {
      final m = MockBengle();
      await m.setCupWarmerPrewarm(true, 45);
      expect(await m.getCupWarmerPrewarm(),
          const CupWarmerPrewarm(enabled: true, leadMinutes: 45));
    });

    test('clamps the lead at both ends (-5 → 0, 999 → 120)', () async {
      final m = MockBengle();
      await m.setCupWarmerPrewarm(true, -5);
      expect((await m.getCupWarmerPrewarm())!.leadMinutes, 0);
      await m.setCupWarmerPrewarm(true, 999);
      expect((await m.getCupWarmerPrewarm())!.leadMinutes, 120);
    });

    test('the settings are PERSISTED — they survive a reboot', () async {
      final m = MockBengle();
      await m.setCupWarmerPrewarm(true, 45);
      m.simulateReboot();
      expect(await m.getCupWarmerPrewarm(),
          const CupWarmerPrewarm(enabled: true, leadMinutes: 45),
          reason: 'MatPreheatEnable/LeadMin are PERM_RWD — unlike the RAM-only '
              'CupWarmerMode, surviving a reboot is the point');
      expect(m.wakeScheduleTable, isEmpty,
          reason: 'the wake table, by contrast, is RAM-only and is lost');
    });

    test('prewarmActive is firmware-driven, not settable through the API',
        () async {
      final m = MockBengle();
      await m.setCupWarmerPrewarm(true, 30);
      expect(await m.getCupWarmerPrewarmActive(), isFalse,
          reason: 'enabling pre-warm does not mean the schedule is driving the '
              'mat right now');
      m.setCupWarmerPrewarmActive(true); // the FW scheduler fires
      expect(await m.getCupWarmerPrewarmActive(), isTrue);
    });

    test('firmware without the registers: reads null, writes inert', () async {
      final m = MockBengle()..setPrewarmSupported(false);
      await m.setCupWarmerPrewarm(true, 45); // silently inert, must not throw
      expect(await m.getCupWarmerPrewarm(), isNull);
      expect(await m.getCupWarmerPrewarmActive(), isNull);
      expect(m.prewarmEnabled, isFalse);
    });
  });
}
