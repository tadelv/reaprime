import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/settings_service.dart';

import '../helpers/mock_settings_service.dart';

// Note: Full HTTP handler integration tests for SettingsHandler require
// WebServerService setup (SettingsHandler is `part of webserver_service.dart`),
// which brings in many dependencies. The tests below verify controller logic
// and the validation building blocks (enum parsing, type checks) that the
// handler relies on. The handler validation itself (returning 400 for bad
// input) is best verified via MCP smoke tests against a running app.

void main() {
  late MockSettingsService mockService;
  late SettingsController controller;

  setUp(() async {
    mockService = MockSettingsService();
    controller = SettingsController(mockService);
    await controller.loadSettings();
  });

  group('simulatedDevices', () {
    test('defaults to empty set', () {
      expect(controller.simulatedDevices, isEmpty);
    });

    test('can set simulated devices', () async {
      await controller.setSimulatedDevices({
        SimulatedDevicesTypes.machine,
        SimulatedDevicesTypes.scale,
      });
      expect(controller.simulatedDevices, {
        SimulatedDevicesTypes.machine,
        SimulatedDevicesTypes.scale,
      });
    });

    test('SimulatedDevicesTypes names match expected values', () {
      expect(SimulatedDevicesTypes.machine.name, 'machine');
      expect(SimulatedDevicesTypes.scale.name, 'scale');
      expect(SimulatedDevicesTypes.sensor.name, 'sensor');
    });

    test('SimulatedDevicesTypesFromString parses valid names', () {
      expect(
        SimulatedDevicesTypesFromString.fromString('machine'),
        SimulatedDevicesTypes.machine,
      );
      expect(
        SimulatedDevicesTypesFromString.fromString('scale'),
        SimulatedDevicesTypes.scale,
      );
      expect(
        SimulatedDevicesTypesFromString.fromString('sensor'),
        SimulatedDevicesTypes.sensor,
      );
    });

    test('SimulatedDevicesTypesFromString returns null for invalid names', () {
      expect(SimulatedDevicesTypesFromString.fromString('invalid'), isNull);
      expect(SimulatedDevicesTypesFromString.fromString(''), isNull);
    });

    test('simulatedDevices serializes to name list', () {
      controller.setSimulatedDevices({
        SimulatedDevicesTypes.machine,
        SimulatedDevicesTypes.sensor,
      });
      final nameList =
          controller.simulatedDevices.map((e) => e.name).toList();
      expect(nameList, containsAll(['machine', 'sensor']));
      expect(nameList.length, 2);
    });
  });

  group('themeMode', () {
    test('defaults to system', () {
      expect(controller.themeMode, ThemeMode.system);
    });

    test('can update theme mode to dark', () async {
      await controller.updateThemeMode(ThemeMode.dark);
      expect(controller.themeMode, ThemeMode.dark);
    });

    test('can update theme mode to light', () async {
      await controller.updateThemeMode(ThemeMode.light);
      expect(controller.themeMode, ThemeMode.light);
    });

    test('ignores null theme mode', () async {
      await controller.updateThemeMode(ThemeMode.dark);
      await controller.updateThemeMode(null);
      expect(controller.themeMode, ThemeMode.dark);
    });

    test('themeMode name matches expected values', () {
      expect(ThemeMode.system.name, 'system');
      expect(ThemeMode.light.name, 'light');
      expect(ThemeMode.dark.name, 'dark');
    });

    test('themeMode serializes to name string', () async {
      await controller.updateThemeMode(ThemeMode.dark);
      expect(controller.themeMode.name, 'dark');
    });

    test('ThemeMode lookup returns null for invalid name', () {
      final mode =
          ThemeMode.values.where((e) => e.name == 'invalid').firstOrNull;
      expect(mode, isNull);
    });
  });
}
