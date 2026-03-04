import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/utils.dart';
import 'package:reaprime/src/models/data/workflow_context.dart';
import 'package:uuid/uuid.dart';

class Workflow {
  final String id;
  final String name;
  final String description;
  final Profile profile;
  final WorkflowContext? context;
  final SteamSettings steamSettings;
  final HotWaterData hotWaterData;
  final RinseData rinseData;

  // Legacy fields kept for backward compatibility during migration.
  // These are stored privately and exposed via deprecated getters.
  final DoseData _doseData;
  final GrinderData? _grinderData;
  final CoffeeData? _coffeeData;

  Workflow({
    required this.id,
    required this.name,
    this.description = '',
    required this.profile,
    this.context,
    DoseData? doseData,
    GrinderData? grinderData,
    CoffeeData? coffeeData,
    required this.steamSettings,
    required this.hotWaterData,
    required this.rinseData,
  })  : _doseData = doseData ?? DoseData(
          doseIn: context?.targetDoseWeight ?? 16.0,
          doseOut: context?.targetYield ?? 36.0,
        ),
        _grinderData = grinderData ?? (context != null
            ? GrinderData(
                setting: context.grinderSetting ?? '',
                model: context.grinderModel,
              )
            : null),
        _coffeeData = coffeeData ?? (context != null
            ? CoffeeData(
                name: context.coffeeName ?? '',
                roaster: context.coffeeRoaster,
              )
            : null);

  /// Synthesized from context when available, otherwise from legacy field.
  @Deprecated('Use context?.targetDoseWeight and context?.targetYield instead')
  DoseData get doseData => _doseData;

  @Deprecated('Use context?.grinderModel and context?.grinderSetting instead')
  GrinderData? get grinderData => _grinderData;

  @Deprecated('Use context?.coffeeName and context?.coffeeRoaster instead')
  CoffeeData? get coffeeData => _coffeeData;

  factory Workflow.fromJson(Map<String, dynamic> json) {
    // Read context from new format, or synthesize from legacy fields
    WorkflowContext? ctx;
    if (json['context'] != null) {
      ctx = WorkflowContext.fromJson(json['context']);
    }

    // Backfill context from legacy fields when present (e.g. API deep-merge
    // updates grinderData/coffeeData but context only has dose fields).
    final dose = json['doseData'] as Map<String, dynamic>?;
    final grinder = json['grinderData'] as Map<String, dynamic>?;
    final coffee = json['coffeeData'] as Map<String, dynamic>?;

    if (ctx != null && (grinder != null || coffee != null || dose != null)) {
      ctx = ctx.copyWith(
        targetDoseWeight: ctx.targetDoseWeight ?? parseOptionalDouble(dose?['doseIn']),
        targetYield: ctx.targetYield ?? parseOptionalDouble(dose?['doseOut']),
        grinderSetting: ctx.grinderSetting ?? grinder?['setting'] as String?,
        grinderModel: ctx.grinderModel ?? grinder?['model'] as String?,
        coffeeName: ctx.coffeeName ?? coffee?['name'] as String?,
        coffeeRoaster: ctx.coffeeRoaster ?? coffee?['roaster'] as String?,
      );
    } else if (ctx == null && (dose != null || grinder != null || coffee != null)) {
      ctx = WorkflowContext.fromLegacyJson(json);
    }

    return Workflow(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      profile: Profile.fromJson(json['profile']),
      context: ctx,
      // Still parse legacy fields for backward compat with old callers
      doseData: json['doseData'] != null
          ? DoseData.fromJson(json['doseData'])
          : null,
      coffeeData: json['coffeeData'] != null
          ? CoffeeData.fromJson(json['coffeeData'])
          : null,
      grinderData: json['grinderData'] != null
          ? GrinderData.fromJson(json['grinderData'])
          : null,
      steamSettings: json['steamSettings'] != null
          ? SteamSettings.fromJson(json['steamSettings'])
          : SteamSettings.defaults(),
      hotWaterData: json['hotWaterData'] != null
          ? HotWaterData.fromJson(json['hotWaterData'])
          : HotWaterData.defaults(),
      rinseData: json['rinseData'] != null
          ? RinseData.fromJson(json['rinseData'])
          : RinseData.defaults(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'profile': profile.toJson(),
      if (context != null) 'context': context!.toJson(),
      // Write legacy fields too for backward compat with older app versions
      'doseData': _doseData.toJson(),
      'coffeeData': _coffeeData?.toJson(),
      'grinderData': _grinderData?.toJson(),
      'steamSettings': steamSettings.toJson(),
      'hotWaterData': hotWaterData.toJson(),
      'rinseData': rinseData.toJson(),
    };
  }

  Workflow copyWith({
    String? name,
    String? description,
    Profile? profile,
    WorkflowContext? context,
    DoseData? doseData,
    GrinderData? grinderData,
    CoffeeData? coffeeData,
    SteamSettings? steamSettings,
    HotWaterData? hotWaterData,
    RinseData? rinseData,
  }) {
    // When context is explicitly provided, don't carry forward stale legacy
    // fields — let the constructor re-synthesize them from the new context.
    final contextChanged = context != null;
    return Workflow(
      id: Uuid().v4(),
      name: name ?? this.name,
      description: description ?? this.description,
      profile: profile ?? this.profile,
      context: context ?? this.context,
      doseData: doseData ?? (contextChanged ? null : _doseData),
      grinderData: grinderData ?? (contextChanged ? null : _grinderData),
      coffeeData: coffeeData ?? (contextChanged ? null : _coffeeData),
      steamSettings: steamSettings ?? this.steamSettings,
      hotWaterData: hotWaterData ?? this.hotWaterData,
      rinseData: rinseData ?? this.rinseData,
    );
  }
}

class DoseData {
  double doseIn;
  double doseOut;

  DoseData({this.doseIn = 16.0, this.doseOut = 36.0});

  double get ratio => doseOut / doseIn;
  void setRatio(double ratio) {
    doseOut = doseIn * ratio;
  }

  factory DoseData.fromJson(Map<String, dynamic> json) {
    return DoseData(
      doseIn: double.parse(json['doseIn'].toString()),
      doseOut: double.parse(json['doseOut'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {'doseIn': doseIn, 'doseOut': doseOut};
  }

  DoseData copyWith({double? doseIn, double? doseOut}) {
    return DoseData(
      doseIn: doseIn ?? this.doseIn,
      doseOut: doseOut ?? this.doseOut,
    );
  }
}

class GrinderData {
  final String setting;
  final String? manufacturer;
  final String? model;

  const GrinderData({this.setting = "", this.manufacturer, this.model});

  factory GrinderData.fromJson(Map<String, dynamic> json) {
    return GrinderData(
      setting: json['setting'],
      manufacturer: json['manufacturer'],
      model: json['model'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'setting': setting, 'manufacturer': manufacturer, 'model': model};
  }

  GrinderData copyWith({String? setting, String? manufacturer, String? model}) {
    return GrinderData(
      model: model ?? this.model,
      manufacturer: manufacturer ?? this.manufacturer,
      setting: setting ?? this.setting,
    );
  }
}

class CoffeeData {
  final String? roaster;
  final String name;

  const CoffeeData({this.name = '', this.roaster});

  factory CoffeeData.fromJson(Map<String, dynamic> json) {
    return CoffeeData(name: json['name'], roaster: json['roaster']);
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'roaster': roaster};
  }

  CoffeeData copyWith({String? name, String? roaster}) {
    return CoffeeData(
      name: name ?? this.name,
      roaster: roaster ?? this.roaster,
    );
  }
}

class SteamSettings {
  int targetTemperature;
  int duration;
  double flow;

  SteamSettings({
    required this.targetTemperature,
    required this.duration,
    required this.flow,
  });

  SteamSettings copyWith({
    int? targetTemperature,
    int? duration,
    double? flow,
  }) {
    return SteamSettings(
      targetTemperature: targetTemperature ?? this.targetTemperature,
      duration: duration ?? this.duration,
      flow: flow ?? this.flow,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'targetTemperature': targetTemperature,
      'duration': duration,
      'flow': flow,
    };
  }

  factory SteamSettings.fromJson(Map<String, dynamic> json) {
    return SteamSettings(
      targetTemperature: parseInt(json['targetTemperature']),
      duration: parseInt(json['duration']),
      flow: parseDouble(json['flow']),
    );
  }

  factory SteamSettings.defaults() {
    return SteamSettings(targetTemperature: 150, duration: 50, flow: 0.8);
  }
}

class HotWaterData {
  int targetTemperature;
  int duration;
  int volume;
  double flow;

  HotWaterData({
    required this.targetTemperature,
    required this.duration,
    required this.volume,
    required this.flow,
  });

  HotWaterData copyWith({
    int? targetTemperature,
    int? duration,
    int? volume,
    double? flow,
  }) {
    return HotWaterData(
      targetTemperature: targetTemperature ?? this.targetTemperature,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      flow: flow ?? this.flow,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'targetTemperature': targetTemperature,
      'duration': duration,
      'volume': volume,
      'flow': flow,
    };
  }

  factory HotWaterData.fromJson(Map<String, dynamic> json) {
    return HotWaterData(
      targetTemperature: parseInt(json['targetTemperature']),
      duration: parseInt(json['duration']),
      volume: parseInt(json['volume']),
      flow: parseDouble(json['flow']),
    );
  }

  factory HotWaterData.defaults() {
    return HotWaterData(
      targetTemperature: 75,
      duration: 30,
      volume: 50,
      flow: 10,
    );
  }
}

class RinseData {
  int targetTemperature;
  int duration;
  double flow;

  RinseData({
    required this.targetTemperature,
    required this.duration,
    required this.flow,
  });

  Map<String, dynamic> toJson() {
    return {
      'targetTemperature': targetTemperature,
      'duration': duration,
      'flow': flow,
    };
  }

  factory RinseData.fromJson(Map<String, dynamic> json) {
    return RinseData(
      targetTemperature: parseInt( json['targetTemperature']),
      duration: parseInt( json['duration']),
      flow: parseDouble(json['flow']),
    );
  }

  factory RinseData.defaults() {
    return RinseData(targetTemperature: 90, duration: 10, flow: 6.0);
  }
}
