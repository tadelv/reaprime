/// Trying to imitate the common v2 profile as close as reasonable
class Profile {
  final String? version;
  final String title;
  final String notes;
  final String author;
  final BeverageType beverageType;
  final List<ProfileStep> steps;
  final double? targetVolume;
  final double? targetWeight;
  final int targetVolumeCountStart;
  final double tankTemperature;

  Profile({
    required this.version,
    required this.title,
    required this.notes,
    required this.author,
    required this.beverageType,
    required this.steps,
    this.targetVolume,
    this.targetWeight,
    required this.targetVolumeCountStart,
    required this.tankTemperature,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      version: json['version'],
      title: json['title'],
      notes: json['notes'],
      author: json['author'],
      beverageType: BeverageType.values.byName(json['beverage_type']),
      steps:
          (json['steps'] as List)
              .map((step) => ProfileStep.fromJson(step))
              .toList(),
      targetVolume: json['target_volume'],
      targetWeight: json['target_weight'],
      targetVolumeCountStart: json['target_volume_count_start'],
      tankTemperature: json['tank_temperature'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'title': title,
      'notes': notes,
      'author': author,
      'beverage_type': beverageType.name,
      'steps': steps.map((step) => step.toJson()).toList(),
      'target_volume': targetVolume,
      'target_weight': targetWeight,
      'target_volume_count_start': targetVolumeCountStart,
      'tank_temperature': tankTemperature,
    };
  }
}

enum BeverageType { espresso, calibrate, cleaning, manual, pourover }

enum TransitionType { fast, smooth }

enum TemperatureSensor { coffee, water }

enum ExitType { pressure, flow }

enum ExitCondition { over, under }

class ProfileStep {
  final String name;
  final TransitionType transition;
  final StepExitCondition? exit;
  final double volume;
  final double seconds;
  final double? weight;
  final double temperature;
  final TemperatureSensor sensor;

  ProfileStep({
    required this.name,
    required this.transition,
    this.exit,
    required this.volume,
    required this.seconds,
    this.weight,
    required this.temperature,
    required this.sensor,
  });

  factory ProfileStep.fromJson(Map<String, dynamic> json) {
    return ProfileStep(
      name: json['name'],
      transition: TransitionType.values.byName(json['transition']),
      exit:
          json['exit'] != null
              ? StepExitCondition.fromJson(json['exit'])
              : null,
      volume: json['volume'],
      seconds: json['seconds'],
      weight: json['weight'],
      temperature: json['temperature'],
      sensor: TemperatureSensor.values.byName(json['sensor']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'transition': transition.name,
      'exit': exit?.toJson(),
      'volume': volume,
      'seconds': seconds,
      'weight': weight,
      'temperature': temperature,
      'sensor': sensor.name,
    };
  }
}

class ProfileStepPressure extends ProfileStep {
  final double pressure;

  ProfileStepPressure({
    required super.name,
    required super.transition,
    super.exit,
    required super.volume,
    required super.seconds,
    super.weight,
    required super.temperature,
    required super.sensor,
    required this.pressure,
  });

  factory ProfileStepPressure.fromJson(Map<String, dynamic> json) {
    return ProfileStepPressure(
      name: json['name'],
      transition: TransitionType.values.byName(json['transition']),
      exit:
          json['exit'] != null
              ? StepExitCondition.fromJson(json['exit'])
              : null,
      volume: json['volume'],
      seconds: json['seconds'],
      weight: json['weight'],
      temperature: json['temperature'],
      sensor: TemperatureSensor.values.byName(json['sensor']),
      pressure: json['pressure'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = super.toJson();
    data['pressure'] = pressure;
    return data;
  }
}

class ProfileStepFlow extends ProfileStep {
  final double flow;

  ProfileStepFlow({
    required super.name,
    required super.transition,
    super.exit,
    required super.volume,
    required super.seconds,
    super.weight,
    required super.temperature,
    required super.sensor,
    required this.flow,
  });

  factory ProfileStepFlow.fromJson(Map<String, dynamic> json) {
    return ProfileStepFlow(
      name: json['name'],
      transition: TransitionType.values.byName(json['transition']),
      exit:
          json['exit'] != null
              ? StepExitCondition.fromJson(json['exit'])
              : null,
      volume: json['volume'],
      seconds: json['seconds'],
      weight: json['weight'],
      temperature: json['temperature'],
      sensor: TemperatureSensor.values.byName(json['sensor']),
      flow: json['flow'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = super.toJson();
    data['flow'] = flow;
    return data;
  }
}

class StepExitCondition {
  final ExitType type;
  final ExitCondition condition;
  final double value;

  StepExitCondition({
    required this.type,
    required this.condition,
    required this.value,
  });

  factory StepExitCondition.fromJson(Map<String, dynamic> json) {
    return StepExitCondition(
      type: ExitType.values.byName(json['type']),
      condition: ExitCondition.values.byName(json['condition']),
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'type': type.name, 'condition': condition.name, 'value': value};
  }
}
