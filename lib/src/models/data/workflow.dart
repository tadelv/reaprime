import 'package:reaprime/src/models/data/profile.dart';

class Workflow {
  final String id;
  final String name;
  final String description;
  Profile profile;
  DoseData doseData;
  Workflow({
    required this.id,
    required this.name,
    this.description = '',
    required this.profile,
    required this.doseData,
  });
  factory Workflow.fromJson(Map<String, dynamic> json) {
    return Workflow(
        id: json['id'],
        name: json['name'],
        description: json['description'],
        profile: Profile.fromJson(json['profile']),
        doseData: DoseData.fromJson(json['doseData']));
  }
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'profile': profile.toJson(),
      'doseData': doseData.toJson(),
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
