import 'package:reaprime/src/models/data/profile.dart';
import 'package:uuid/uuid.dart';

class Workflow {
  final String id;
  final String name;
  final String description;
  final Profile profile;
  final DoseData doseData;
  final GrinderData? grinderData;
  final CoffeeData? coffeeData;

  const Workflow(
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

  Workflow copyWith({
    String? name,
    String? description,
    Profile? profile,
    DoseData? doseData,
    GrinderData? grinderData,
    CoffeeData? coffeeData,
  }) {
    return Workflow(
      id: Uuid().v4(),
      name: name ?? this.name,
      description: description ?? this.description,
      profile: profile ?? this.profile,
      doseData: doseData ?? this.doseData,
      grinderData: grinderData ?? this.grinderData,
      coffeeData: coffeeData ?? this.coffeeData,
    );
  }
}

class DoseData {
  // TODO: final?
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
    return DoseData(
      doseIn: double.parse(json['doseIn'].toString()),
      doseOut: double.parse(json['doseOut'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'doseIn': doseIn,
      'doseOut': doseOut,
    };
  }

  DoseData copyWith({
    double? doseIn,
    double? doseOut,
  }) {
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
    return {
      'setting': setting,
      'manufacturer': manufacturer,
      'model': model,
    };
  }

  GrinderData copyWith({
    String? setting,
    String? manufacturer,
    String? model,
  }) {
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

  CoffeeData copyWith({
    String? name,
    String? roaster,
  }) {
    return CoffeeData(
      name: name ?? this.name,
      roaster: roaster ?? this.roaster,
    );
  }
}
