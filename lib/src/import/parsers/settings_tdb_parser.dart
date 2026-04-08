import 'package:reaprime/src/import/parsers/tcl_parser.dart';

/// Parsed result from a de1app `settings.tdb` file.
///
/// All fields are nullable — only present if the key existed in the file
/// and had a meaningful value.
class SettingsTdbResult {
  // Wake schedule
  final bool? wakeScheduleEnabled;
  final int? wakeHour;
  final int? wakeMinute;
  final int? keepAwakeForMinutes;

  // Settings
  final bool? keepScaleOn;
  final int? sleepTimeoutMinutes;

  // Workflow context
  final double? doseWeight;
  final String? grinderSetting;
  final String? grinderModel;
  final double? targetYield;

  // Steam
  final int? steamTemperature;
  final int? steamDuration;

  // Hot water
  final int? hotWaterTemperature;
  final int? hotWaterVolume;

  // Rinse
  final double? rinseFlow;
  final int? rinseDuration;

  const SettingsTdbResult({
    this.wakeScheduleEnabled,
    this.wakeHour,
    this.wakeMinute,
    this.keepAwakeForMinutes,
    this.keepScaleOn,
    this.sleepTimeoutMinutes,
    this.doseWeight,
    this.grinderSetting,
    this.grinderModel,
    this.targetYield,
    this.steamTemperature,
    this.steamDuration,
    this.hotWaterTemperature,
    this.hotWaterVolume,
    this.rinseFlow,
    this.rinseDuration,
  });

  /// True when no meaningful settings were extracted.
  ///
  /// [wakeScheduleEnabled] alone doesn't count if [wakeHour]/[wakeMinute]
  /// are null, since a bare enable flag without times is not actionable.
  bool get isEmpty =>
      wakeHour == null &&
      wakeMinute == null &&
      keepAwakeForMinutes == null &&
      keepScaleOn == null &&
      sleepTimeoutMinutes == null &&
      doseWeight == null &&
      grinderSetting == null &&
      grinderModel == null &&
      targetYield == null &&
      steamTemperature == null &&
      steamDuration == null &&
      hotWaterTemperature == null &&
      hotWaterVolume == null &&
      rinseFlow == null &&
      rinseDuration == null;
}

/// Parses a de1app `settings.tdb` file into a [SettingsTdbResult].
///
/// The settings.tdb file is written by de1app's `save_array_to_file` —
/// each line is `{key} {value}\n`. We delegate the low-level parsing to
/// [TclParser.parse] which returns a flat `Map<String, dynamic>`.
class SettingsTdbParser {
  static SettingsTdbResult parse(String content) {
    final data = TclParser.parse(content);

    // Wake schedule
    final wakeSeconds = _parseInt(data['scheduler_wake']);
    final sleepSeconds = _parseInt(data['scheduler_sleep']);

    int? wakeHour;
    int? wakeMinute;
    if (wakeSeconds != null) {
      wakeHour = wakeSeconds ~/ 3600;
      wakeMinute = (wakeSeconds % 3600) ~/ 60;
    }

    int? keepAwakeFor;
    if (wakeSeconds != null && sleepSeconds != null) {
      var diff = sleepSeconds - wakeSeconds;
      if (diff < 0) diff += 86400;
      keepAwakeFor = diff ~/ 60;
    }

    // Screen saver delay: seconds -> minutes, ceil, clamp >= 1
    int? sleepTimeoutMinutes;
    final screenSaverSeconds = _parseInt(data['screen_saver_delay']);
    if (screenSaverSeconds != null) {
      final minutes = (screenSaverSeconds / 60).ceil();
      sleepTimeoutMinutes = minutes < 1 ? 1 : minutes;
    }

    // Dose weight: null if 0 or missing
    final doseRaw = _parseDouble(data['grinder_dose_weight']);
    final doseWeight = (doseRaw != null && doseRaw != 0) ? doseRaw : null;

    // Target yield: null if 0 or missing
    final yieldRaw =
        _parseDouble(data['final_desired_shot_weight_advanced']);
    final targetYield = (yieldRaw != null && yieldRaw != 0) ? yieldRaw : null;

    // Grinder setting: null if "0" or empty
    final grinderSettingRaw = _nonEmpty(data['grinder_setting']?.toString());
    final grinderSetting =
        (grinderSettingRaw != null && grinderSettingRaw != '0')
            ? grinderSettingRaw
            : null;

    // Grinder model: null if empty
    final grinderModel = _nonEmpty(data['grinder_model']?.toString());

    return SettingsTdbResult(
      wakeScheduleEnabled: _parseBool(data['scheduler_enable']),
      wakeHour: wakeHour,
      wakeMinute: wakeMinute,
      keepAwakeForMinutes: keepAwakeFor,
      keepScaleOn: _parseBool(data['keep_scale_on']),
      sleepTimeoutMinutes: sleepTimeoutMinutes,
      doseWeight: doseWeight,
      grinderSetting: grinderSetting,
      grinderModel: grinderModel,
      targetYield: targetYield,
      steamTemperature: _parseInt(data['steam_temperature']),
      steamDuration: _parseInt(data['steam_max_time']),
      hotWaterTemperature: _parseInt(data['water_temperature']),
      hotWaterVolume: _parseInt(data['water_volume']),
      rinseFlow: _parseDouble(data['flush_flow']),
      rinseDuration: _parseInt(data['flush_seconds']),
    );
  }

  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    return value.toString() == '1';
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  /// Returns [value] if non-null and non-empty, otherwise null.
  static String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
