import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/utils.dart';
import 'package:uuid/uuid.dart';

class Workflow {
  final String id;
  final String name;
  final String description;
  final Profile profile;
  final DoseData doseData;
  final GrinderData? grinderData;
  final CoffeeData? coffeeData;
  final SteamSettings steamSettings;
  final HotWaterData hotWaterData;
  final RinseData rinseData;

  const Workflow({
    required this.id,
    required this.name,
    this.description = '',
    required this.profile,
    required this.doseData,
    this.grinderData,
    this.coffeeData,
    required this.steamSettings,
    required this.hotWaterData,
    required this.rinseData,
  });

  factory Workflow.fromJson(Map<String, dynamic> json) {
    return Workflow(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      profile: Profile.fromJson(json['profile']),
      doseData: DoseData.fromJson(json['doseData']),
      coffeeData:
          json['coffeeData'] != null
              ? CoffeeData.fromJson(json['coffeeData'])
              : null,
      grinderData:
          json['grinderData'] != null
              ? GrinderData.fromJson(json['grinderData'])
              : null,
      steamSettings:
          json['steamSettings'] != null
              ? SteamSettings.fromJson(json['steamSettings'])
              : SteamSettings.defaults(),
      hotWaterData:
          json['hotWaterData'] != null
              ? HotWaterData.fromJson(json['hotWaterData'])
              : HotWaterData.defaults(),
      rinseData:
          json['rinseData'] != null
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
      'doseData': doseData.toJson(),
      'coffeeData': coffeeData?.toJson(),
      'grinderData': grinderData?.toJson(),
      'steamSettings': steamSettings.toJson(),
      'hotWaterData': hotWaterData.toJson(),
      'rinseData': rinseData.toJson(),
    };
  }

  Workflow copyWith({
    String? name,
    String? description,
    Profile? profile,
    DoseData? doseData,
    GrinderData? grinderData,
    CoffeeData? coffeeData,
    SteamSettings? steamSettings,
    HotWaterData? hotWaterData,
    RinseData? rinseData,
  }) {
    return Workflow(
      id: Uuid().v4(),
      name: name ?? this.name,
      description: description ?? this.description,
      profile: profile ?? this.profile,
      doseData: doseData ?? this.doseData,
      grinderData: grinderData ?? this.grinderData,
      coffeeData: coffeeData ?? this.coffeeData,
      steamSettings: steamSettings ?? this.steamSettings,
      hotWaterData: hotWaterData ?? this.hotWaterData,
      rinseData: rinseData ?? this.rinseData,
    );
  }
}

class DoseData {
  // TODO: final?
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
