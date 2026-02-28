import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/charging_mode.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/scale_power_mode.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/settings_export_section.dart';

import '../helpers/mock_settings_service.dart';

void main() {
  late MockSettingsService settingsService;
  late SettingsController controller;
  late SettingsExportSection section;

  setUp(() async {
    settingsService = MockSettingsService();
    controller = SettingsController(settingsService);
    await controller.loadSettings();
    section = SettingsExportSection(controller: controller);
  });

  tearDown(() {
    controller.dispose();
  });

  test('filename is settings.json', () {
    expect(section.filename, equals('settings.json'));
  });

  group('export', () {
    test('exports all settings as structured JSON', () async {
      final result = await section.export();
      expect(result, isA<Map<String, dynamic>>());
      final map = result as Map<String, dynamic>;

      // Top-level keys
      expect(map, contains('settings'));
      expect(map, contains('wakeSchedules'));
      expect(map, contains('devicePreferences'));

      // Settings object
      final settings = map['settings'] as Map<String, dynamic>;
      expect(settings['gatewayMode'], equals('disabled'));
      expect(settings['logLevel'], equals('INFO'));
      expect(settings['weightFlowMultiplier'], equals(1.0));
      expect(settings['volumeFlowMultiplier'], equals(0.3));
      expect(settings['scalePowerMode'], equals('disabled'));
      expect(settings['automaticUpdateCheck'], isTrue);
      expect(settings['chargingMode'], equals('balanced'));
      expect(settings['nightModeEnabled'], isFalse);
      expect(settings['nightModeSleepTime'], equals(1320));
      expect(settings['nightModeMorningTime'], equals(420));
      expect(settings['userPresenceEnabled'], isTrue);
      expect(settings['sleepTimeoutMinutes'], equals(30));

      // Wake schedules
      expect(map['wakeSchedules'], equals('[]'));

      // Device preferences
      final devicePrefs = map['devicePreferences'] as Map<String, dynamic>;
      expect(devicePrefs['preferredMachineId'], isNull);
      expect(devicePrefs['preferredScaleId'], isNull);
    });

    test('exports modified settings', () async {
      await controller.updateGatewayMode(GatewayMode.full);
      await controller.setWeightFlowMultiplier(2.5);
      await controller.setPreferredMachineId('DE1-ABC123');

      final result = await section.export();
      final map = result as Map<String, dynamic>;
      final settings = map['settings'] as Map<String, dynamic>;

      expect(settings['gatewayMode'], equals('full'));
      expect(settings['weightFlowMultiplier'], equals(2.5));

      final devicePrefs = map['devicePreferences'] as Map<String, dynamic>;
      expect(devicePrefs['preferredMachineId'], equals('DE1-ABC123'));
    });
  });

  group('import', () {
    test('imports settings from exported data', () async {
      await controller.updateGatewayMode(GatewayMode.full);
      await controller.setWeightFlowMultiplier(2.5);
      await controller.setNightModeEnabled(true);
      final exported = await section.export();

      // Reset to defaults
      await controller.updateGatewayMode(GatewayMode.disabled);
      await controller.setWeightFlowMultiplier(1.0);
      await controller.setNightModeEnabled(false);

      final result =
          await section.import(exported, ConflictStrategy.overwrite);

      expect(result.errors, isEmpty);
      expect(result.imported, greaterThan(0));
      expect(controller.gatewayMode, equals(GatewayMode.full));
      expect(controller.weightFlowMultiplier, equals(2.5));
      expect(controller.nightModeEnabled, isTrue);
    });

    test('imports device preferences', () async {
      final data = {
        'settings': <String, dynamic>{},
        'wakeSchedules': '[]',
        'devicePreferences': {
          'preferredMachineId': 'DE1-XYZ',
          'preferredScaleId': 'SCALE-ABC',
        },
      };

      final result =
          await section.import(data, ConflictStrategy.overwrite);

      expect(result.errors, isEmpty);
      expect(controller.preferredMachineId, equals('DE1-XYZ'));
      expect(controller.preferredScaleId, equals('SCALE-ABC'));
    });

    test('imports wake schedules', () async {
      final data = {
        'settings': <String, dynamic>{},
        'wakeSchedules': '[{"time": 420, "enabled": true}]',
        'devicePreferences': <String, dynamic>{},
      };

      final result =
          await section.import(data, ConflictStrategy.overwrite);

      expect(result.errors, isEmpty);
      expect(controller.wakeSchedules,
          equals('[{"time": 420, "enabled": true}]'));
    });

    test('reports errors for invalid enum values', () async {
      final data = {
        'settings': {
          'gatewayMode': 'invalid_mode',
          'scalePowerMode': 'bad_mode',
        },
        'wakeSchedules': '[]',
        'devicePreferences': <String, dynamic>{},
      };

      final result =
          await section.import(data, ConflictStrategy.overwrite);

      expect(result.errors, hasLength(2));
      expect(result.errors[0], contains('Invalid gatewayMode'));
      expect(result.errors[1], contains('Invalid scalePowerMode'));
    });

    test('returns error for completely invalid data', () async {
      final result = await section.import(
        'not a map',
        ConflictStrategy.overwrite,
      );

      expect(result.imported, equals(0));
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Failed to import settings'));
    });

    test('handles partial settings gracefully', () async {
      final data = {
        'settings': {
          'logLevel': 'FINE',
        },
      };

      final result =
          await section.import(data, ConflictStrategy.overwrite);

      expect(result.errors, isEmpty);
      expect(result.imported, equals(1));
      expect(controller.logLevel, equals('FINE'));
    });

    test('round-trips correctly', () async {
      await controller.updateGatewayMode(GatewayMode.tracking);
      await controller.setWeightFlowMultiplier(1.5);
      await controller.setScalePowerMode(ScalePowerMode.disconnect);
      await controller.setChargingMode(ChargingMode.longevity);
      await controller.setNightModeEnabled(true);
      await controller.setNightModeSleepTime(1380);
      await controller.setNightModeMorningTime(360);
      await controller.setSleepTimeoutMinutes(15);
      await controller.setPreferredMachineId('DE1-TEST');

      final exported = await section.export();

      // Reset
      await controller.loadSettings();

      final result =
          await section.import(exported, ConflictStrategy.overwrite);

      expect(result.errors, isEmpty);
      expect(controller.gatewayMode, equals(GatewayMode.tracking));
      expect(controller.weightFlowMultiplier, equals(1.5));
      expect(controller.scalePowerMode, equals(ScalePowerMode.disconnect));
      expect(controller.chargingMode, equals(ChargingMode.longevity));
      expect(controller.nightModeEnabled, isTrue);
      expect(controller.nightModeSleepTime, equals(1380));
      expect(controller.nightModeMorningTime, equals(360));
      expect(controller.sleepTimeoutMinutes, equals(15));
      expect(controller.preferredMachineId, equals('DE1-TEST'));
    });
  });
}
