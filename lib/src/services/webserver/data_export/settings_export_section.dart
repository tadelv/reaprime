import 'package:reaprime/src/settings/charging_mode.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/scale_power_mode.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class SettingsExportSection implements DataExportSection {
  final SettingsController _controller;

  SettingsExportSection({required SettingsController controller})
      : _controller = controller;

  @override
  String get filename => 'settings.json';

  @override
  Future<dynamic> export() async {
    return {
      'settings': {
        'gatewayMode': _controller.gatewayMode.name,
        'logLevel': _controller.logLevel,
        'themeMode': _controller.themeMode.name,
        'weightFlowMultiplier': _controller.weightFlowMultiplier,
        'volumeFlowMultiplier': _controller.volumeFlowMultiplier,
        'scalePowerMode': _controller.scalePowerMode.name,
        'defaultSkinId': _controller.defaultSkinId,
        'automaticUpdateCheck': _controller.automaticUpdateCheck,
        'chargingMode': _controller.chargingMode.name,
        'nightModeEnabled': _controller.nightModeEnabled,
        'nightModeSleepTime': _controller.nightModeSleepTime,
        'nightModeMorningTime': _controller.nightModeMorningTime,
        'userPresenceEnabled': _controller.userPresenceEnabled,
        'sleepTimeoutMinutes': _controller.sleepTimeoutMinutes,
      },
      'wakeSchedules': _controller.wakeSchedules,
      'devicePreferences': {
        'preferredMachineId': _controller.preferredMachineId,
        'preferredScaleId': _controller.preferredScaleId,
      },
    };
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    final errors = <String>[];
    int imported = 0;

    try {
      final map = data as Map<String, dynamic>;

      // Import settings
      final settings = map['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        if (settings.containsKey('gatewayMode')) {
          final mode =
              GatewayModeFromString.fromString(settings['gatewayMode']);
          if (mode != null) {
            await _controller.updateGatewayMode(mode);
            imported++;
          } else {
            errors.add(
                'Invalid gatewayMode: ${settings['gatewayMode']}');
          }
        }

        if (settings.containsKey('logLevel')) {
          await _controller.updateLogLevel(settings['logLevel'] as String);
          imported++;
        }

        if (settings.containsKey('weightFlowMultiplier')) {
          final value = settings['weightFlowMultiplier'];
          if (value is num) {
            await _controller.setWeightFlowMultiplier(value.toDouble());
            imported++;
          } else {
            errors.add('Invalid weightFlowMultiplier: $value');
          }
        }

        if (settings.containsKey('volumeFlowMultiplier')) {
          final value = settings['volumeFlowMultiplier'];
          if (value is num) {
            await _controller.setVolumeFlowMultiplier(value.toDouble());
            imported++;
          } else {
            errors.add('Invalid volumeFlowMultiplier: $value');
          }
        }

        if (settings.containsKey('scalePowerMode')) {
          final mode = ScalePowerModeFromString.fromString(
              settings['scalePowerMode']);
          if (mode != null) {
            await _controller.setScalePowerMode(mode);
            imported++;
          } else {
            errors.add(
                'Invalid scalePowerMode: ${settings['scalePowerMode']}');
          }
        }

        if (settings.containsKey('defaultSkinId')) {
          await _controller
              .setDefaultSkinId(settings['defaultSkinId'] as String);
          imported++;
        }

        if (settings.containsKey('automaticUpdateCheck')) {
          await _controller
              .setAutomaticUpdateCheck(settings['automaticUpdateCheck'] as bool);
          imported++;
        }

        if (settings.containsKey('chargingMode')) {
          final mode =
              ChargingModeFromString.fromString(settings['chargingMode']);
          if (mode != null) {
            await _controller.setChargingMode(mode);
            imported++;
          } else {
            errors.add(
                'Invalid chargingMode: ${settings['chargingMode']}');
          }
        }

        if (settings.containsKey('nightModeEnabled')) {
          await _controller
              .setNightModeEnabled(settings['nightModeEnabled'] as bool);
          imported++;
        }

        if (settings.containsKey('nightModeSleepTime')) {
          await _controller
              .setNightModeSleepTime(settings['nightModeSleepTime'] as int);
          imported++;
        }

        if (settings.containsKey('nightModeMorningTime')) {
          await _controller
              .setNightModeMorningTime(settings['nightModeMorningTime'] as int);
          imported++;
        }

        if (settings.containsKey('userPresenceEnabled')) {
          await _controller
              .setUserPresenceEnabled(settings['userPresenceEnabled'] as bool);
          imported++;
        }

        if (settings.containsKey('sleepTimeoutMinutes')) {
          await _controller
              .setSleepTimeoutMinutes(settings['sleepTimeoutMinutes'] as int);
          imported++;
        }
      }

      // Import wake schedules
      if (map.containsKey('wakeSchedules')) {
        await _controller.setWakeSchedules(map['wakeSchedules'] as String);
        imported++;
      }

      // Import device preferences
      final devicePrefs = map['devicePreferences'] as Map<String, dynamic>?;
      if (devicePrefs != null) {
        if (devicePrefs.containsKey('preferredMachineId')) {
          await _controller
              .setPreferredMachineId(devicePrefs['preferredMachineId'] as String?);
          imported++;
        }
        if (devicePrefs.containsKey('preferredScaleId')) {
          await _controller
              .setPreferredScaleId(devicePrefs['preferredScaleId'] as String?);
          imported++;
        }
      }
    } catch (e) {
      errors.add('Failed to import settings: $e');
    }

    return SectionImportResult(imported: imported, errors: errors);
  }
}
