import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_annotations.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/data/workflow_context.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:uuid/uuid.dart';

/// Holds a parsed [ShotRecord] plus extracted metadata strings for entity
/// extraction in later import stages.
class ParsedShot {
  final ShotRecord shot;
  final String? beanBrand;
  final String? beanType;
  final String? beanNotes;
  final String? roastDate;
  final String? roastLevel;
  final String? grinderModel;
  final String? grinderSetting;

  const ParsedShot({
    required this.shot,
    this.beanBrand,
    this.beanType,
    this.beanNotes,
    this.roastDate,
    this.roastLevel,
    this.grinderModel,
    this.grinderSetting,
  });
}

/// Parses de1app history_v2 JSON files into [ParsedShot] instances.
class ShotV2JsonParser {
  ShotV2JsonParser._();

  /// Parses a de1app history_v2 JSON map into a [ParsedShot].
  static ParsedShot parse(Map<String, dynamic> json) {
    final clock = json['clock'] as int;
    final baseTimestamp = DateTime.fromMillisecondsSinceEpoch(
      clock * 1000,
      isUtc: true,
    );

    // Flat settings from app.data.settings (fallback source)
    final settings = _extractSettings(json);

    // Structured meta block (primary source)
    final meta = json['meta'] as Map<String, dynamic>?;
    final metaBean = meta?['bean'] as Map<String, dynamic>?;
    final metaShot = meta?['shot'] as Map<String, dynamic>?;
    final metaGrinder = meta?['grinder'] as Map<String, dynamic>?;

    // --- Bean metadata ---
    final beanBrand =
        _str(metaBean?['brand']) ?? _str(settings['bean_brand']);
    final beanType =
        _str(metaBean?['type']) ?? _str(settings['bean_type']);
    final beanNotes =
        _str(metaBean?['notes']) ?? _str(settings['bean_notes']);
    final roastLevel =
        _str(metaBean?['roast_level']) ?? _str(settings['roast_level']);
    final roastDate =
        _str(metaBean?['roast_date']) ?? _str(settings['roast_date']);

    // --- Grinder metadata ---
    final grinderModel =
        _str(metaGrinder?['model']) ?? _str(settings['grinder_model']);
    final grinderSetting =
        _str(metaGrinder?['setting']) ?? _str(settings['grinder_setting']);

    // --- Shot annotations ---
    final doseWeight = _optDouble(meta?['in']) ??
        _parseOptDouble(settings['grinder_dose_weight']);
    final yieldWeight = _optDouble(meta?['out']) ??
        _parseOptDouble(settings['drink_weight']);
    final tds = _optDouble(metaShot?['tds']) ??
        _parseOptDouble(settings['drink_tds']);
    final ey = _optDouble(metaShot?['ey']) ??
        _parseOptDouble(settings['drink_ey']);
    final enjoyment = _optDouble(metaShot?['enjoyment']) ??
        _parseOptDouble(settings['espresso_enjoyment']);
    final espressoNotes =
        _str(metaShot?['notes']) ?? _str(settings['espresso_notes']);

    final annotations = ShotAnnotations(
      actualDoseWeight: doseWeight,
      actualYield: yieldWeight,
      drinkTds: tds,
      drinkEy: ey,
      enjoyment: enjoyment,
      espressoNotes: espressoNotes,
    );

    // --- Workflow context ---
    final context = WorkflowContext(
      targetDoseWeight: doseWeight,
      targetYield: yieldWeight,
      grinderModel: grinderModel,
      grinderSetting: grinderSetting,
      coffeeName: beanType,
      coffeeRoaster: beanBrand,
      baristaName: _str(settings['my_name']),
      drinkerName: _str(settings['drinker_name']),
    );

    // --- Profile ---
    final profile = Profile.fromJson(
      json['profile'] as Map<String, dynamic>,
    );

    // --- Workflow ---
    final workflow = Workflow(
      id: const Uuid().v4(),
      name: profile.title,
      profile: profile,
      context: context,
      steamSettings: SteamSettings.defaults(),
      hotWaterData: HotWaterData.defaults(),
      rinseData: RinseData.defaults(),
    );

    // --- Time-series snapshots ---
    final measurements = _parseSnapshots(json, baseTimestamp);

    // --- ShotRecord ---
    final shot = ShotRecord(
      id: 'de1app-$clock',
      timestamp: baseTimestamp,
      measurements: measurements,
      workflow: workflow,
      annotations: annotations,
    );

    return ParsedShot(
      shot: shot,
      beanBrand: beanBrand,
      beanType: beanType,
      beanNotes: beanNotes,
      roastDate: roastDate,
      roastLevel: roastLevel,
      grinderModel: grinderModel,
      grinderSetting: grinderSetting,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _extractSettings(Map<String, dynamic> json) {
    final app = json['app'] as Map<String, dynamic>?;
    final data = app?['data'] as Map<String, dynamic>?;
    return (data?['settings'] as Map<String, dynamic>?) ?? {};
  }

  static List<ShotSnapshot> _parseSnapshots(
    Map<String, dynamic> json,
    DateTime baseTimestamp,
  ) {
    final elapsed = (json['elapsed'] as List).cast<num>();

    final pressureData =
        (json['pressure']['pressure'] as List).cast<num>();
    final pressureGoal =
        (json['pressure']['goal'] as List).cast<num>();

    final flowData = (json['flow']['flow'] as List).cast<num>();
    final flowGoal = (json['flow']['goal'] as List).cast<num>();
    final flowByWeight = (json['flow']['by_weight'] as List).cast<num>();

    final tempBasket =
        (json['temperature']['basket'] as List).cast<num>();
    final tempMix = (json['temperature']['mix'] as List).cast<num>();
    final tempGoal = (json['temperature']['goal'] as List).cast<num>();

    final totalWeight = (json['totals']['weight'] as List).cast<num>();

    final snapshots = <ShotSnapshot>[];
    for (var i = 0; i < elapsed.length; i++) {
      final ts = baseTimestamp.add(
        Duration(milliseconds: (elapsed[i].toDouble() * 1000).round()),
      );

      final machineSnap = MachineSnapshot(
        timestamp: ts,
        state: const MachineStateSnapshot(
          state: MachineState.espresso,
          substate: MachineSubstate.pouring,
        ),
        flow: flowData[i].toDouble(),
        pressure: pressureData[i].toDouble(),
        targetFlow: flowGoal[i].toDouble(),
        targetPressure: pressureGoal[i].toDouble(),
        mixTemperature: tempMix[i].toDouble(),
        groupTemperature: tempBasket[i].toDouble(),
        targetMixTemperature: tempGoal[i].toDouble(),
        targetGroupTemperature: tempGoal[i].toDouble(),
        profileFrame: 0,
        steamTemperature: 0,
      );

      final weightSnap = WeightSnapshot(
        timestamp: ts,
        weight: totalWeight[i].toDouble(),
        weightFlow: flowByWeight[i].toDouble(),
      );

      snapshots.add(ShotSnapshot(machine: machineSnap, scale: weightSnap));
    }

    return snapshots;
  }

  /// Returns a non-null, non-empty string or null.
  static String? _str(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Coerces a dynamic value to double if it is already numeric.
  static double? _optDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return null;
  }

  /// Parses a string-encoded double (from settings map).
  static double? _parseOptDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final s = value.toString().trim();
    return s.isEmpty ? null : double.tryParse(s);
  }
}
