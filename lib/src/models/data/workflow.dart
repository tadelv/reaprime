import 'package:reaprime/src/controllers/shot_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';

class Workflow {
  final String id;
  final String name;
  final String description;
  Profile profile;
  TargetShotParameters shotParameters;
  Workflow({
    required this.id,
    required this.name,
    this.description = '',
    required this.profile,
    this.shotParameters = const TargetShotParameters(targetWeight: 0.0),
  });
  factory Workflow.fromJson(Map<String, dynamic> json) {
    return Workflow(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      profile: Profile.fromJson(json['profile']),
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'profile': profile.toJson(),
    };
  }
}
