import 'package:reaprime/src/models/data/profile.dart';

class Workflow {
  final String id;
  final String name;
  final String description;
  Profile profile;
  DoseData doseData;
  GrinderData? grinderData;
  CoffeeData? coffeeData;
  Workflow(
      {required this.id,
      required this.name,
      this.description = '',
      required this.profile,
      required this.doseData,
      this.grinderData,
      this.coffeeData});
  factory Workflow.fromJson(Map<String, dynamic> json) {
    return Workflow(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      profile: Profile.fromJson(json['profile']),
      doseData: DoseData.fromJson(json['doseData']),
      coffeeData: json['coffeeData'] != null
          ? CoffeeData.fromJson(json['coffeeData'])
          : null,
      grinderData: json['grinderData'] != null
          ? GrinderData.fromJson(
              json['grinderData'],
            )
          : null,
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
    };
  }
}

class DoseData {
  double doseIn;
  double doseOut;

  DoseData({
    this.doseIn = 16.0,
    this.doseOut = 36.0,
  });

  double get ratio => doseOut / doseIn;
  void setRatio(double ratio) {
    doseOut = doseIn * ratio;
  }

  factory DoseData.fromJson(Map<String, dynamic> json) {
    return DoseData(doseIn: json['doseIn'], doseOut: json['doseOut']);
  }

  Map<String, dynamic> toJson() {
    return {
      'doseIn': doseIn,
      'doseOut': doseOut,
    };
  }
}

class GrinderData {
  String setting;
  String? manufacturer;
  String? model;

  GrinderData({this.setting = "", this.manufacturer, this.model});

  factory GrinderData.fromJson(Map<String, dynamic> json) {
    return GrinderData(
      setting: json['setting'],
      manufacturer: json['manufacturer'],
      model: json['model'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'setting': setting,
      'manufacturer': manufacturer,
      'model': model,
    };
  }
}

class CoffeeData {
  String? roaster;
  String name;

  CoffeeData({this.name = '', this.roaster});

  factory CoffeeData.fromJson(Map<String, dynamic> json) {
    return CoffeeData(
      name: json['name'],
      roaster: json['roaster'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'roaster': roaster,
    };
  }
}
