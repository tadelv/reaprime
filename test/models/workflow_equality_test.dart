import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/workflow.dart';

// These tests pin down the value-equality contract for the workflow
// settings classes. The workflow HTTP handler uses `!=` to decide
// whether to re-apply steam/hot-water/flush settings to the DE1; without
// value equality, every PUT re-applies everything, producing the
// redundant shot-settings writes reported on mock and real hardware.
//
// See also the race / redundant-emit tests in
// `test/webserver/workflow_handler_test.dart` — they depend on this
// contract holding.

void main() {
  group('SteamSettings equality', () {
    test('equal by value', () {
      final a = SteamSettings(targetTemperature: 150, duration: 50, flow: 2.1);
      final b = SteamSettings(targetTemperature: 150, duration: 50, flow: 2.1);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differ when duration differs', () {
      final a = SteamSettings(targetTemperature: 150, duration: 50, flow: 2.1);
      final b = SteamSettings(targetTemperature: 150, duration: 30, flow: 2.1);
      expect(a, isNot(equals(b)));
    });

    test('differ when flow differs', () {
      final a = SteamSettings(targetTemperature: 150, duration: 50, flow: 2.1);
      final b = SteamSettings(targetTemperature: 150, duration: 50, flow: 1.5);
      expect(a, isNot(equals(b)));
    });
  });

  group('HotWaterData equality', () {
    test('equal by value', () {
      final a = HotWaterData(
          targetTemperature: 75, duration: 30, volume: 50, flow: 10);
      final b = HotWaterData(
          targetTemperature: 75, duration: 30, volume: 50, flow: 10);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differ when any field differs', () {
      final base = HotWaterData(
          targetTemperature: 75, duration: 30, volume: 50, flow: 10);
      expect(base,
          isNot(equals(base.copyWith(duration: 31))));
      expect(base,
          isNot(equals(base.copyWith(targetTemperature: 76))));
      expect(base, isNot(equals(base.copyWith(volume: 51))));
      expect(base, isNot(equals(base.copyWith(flow: 9.9))));
    });
  });

  group('RinseData equality', () {
    test('equal by value', () {
      final a = RinseData(targetTemperature: 90, duration: 10, flow: 6.0);
      final b = RinseData(targetTemperature: 90, duration: 10, flow: 6.0);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differ when duration differs', () {
      final a = RinseData(targetTemperature: 90, duration: 10, flow: 6.0);
      final b = RinseData(targetTemperature: 90, duration: 11, flow: 6.0);
      expect(a, isNot(equals(b)));
    });
  });

  group('Workflow equality', () {
    // Workflow carries an id + profile; for workflow_handler's diff
    // checks the meaningful equivalence is "all the settings block
    // fields match by value". These tests pin down that contract.

    test('steamSettings equality survives fromJson round-trip', () {
      final original = SteamSettings(
          targetTemperature: 150, duration: 50, flow: 2.1);
      final roundTrip = SteamSettings.fromJson(original.toJson());
      expect(original, equals(roundTrip));
    });

    test('hotWaterData equality survives fromJson round-trip', () {
      final original = HotWaterData(
          targetTemperature: 75, duration: 30, volume: 50, flow: 10.0);
      final roundTrip = HotWaterData.fromJson(original.toJson());
      expect(original, equals(roundTrip));
    });

    test('rinseData equality survives fromJson round-trip', () {
      final original =
          RinseData(targetTemperature: 90, duration: 10, flow: 6.0);
      final roundTrip = RinseData.fromJson(original.toJson());
      expect(original, equals(roundTrip));
    });

    test(
        'default workflow fields equal to a freshly-constructed workflow with the same settings',
        () {
      final controller = WorkflowController();
      final wf = controller.currentWorkflow;
      // Re-deserialize via toJson round-trip (what WorkflowHandler does
      // on every PUT).
      final roundTrip = Workflow.fromJson(wf.toJson());
      expect(wf.steamSettings, equals(roundTrip.steamSettings));
      expect(wf.hotWaterData, equals(roundTrip.hotWaterData));
      expect(wf.rinseData, equals(roundTrip.rinseData));
    });
  });
}
