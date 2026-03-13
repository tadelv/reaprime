import 'package:reaprime/src/models/data/utils.dart';

/// Replaces DoseData, GrinderData, CoffeeData with a single composite.
/// All fields nullable — supports minimal (dose only), standard (display strings),
/// and full (entity IDs) usage tiers.
class WorkflowContext {
  // Dose & Yield
  final double? targetDoseWeight;
  final double? targetYield;

  // Grinder (ID + display string pattern)
  final String? grinderId;
  final String? grinderModel;
  final String? grinderSetting;

  // Coffee (ID + display strings pattern)
  final String? beanBatchId;
  final String? coffeeName;
  final String? coffeeRoaster;

  // Beverage
  final String? finalBeverageType;

  // People
  final String? baristaName;
  final String? drinkerName;

  // Plugin data channel
  final Map<String, dynamic>? extras;

  const WorkflowContext({
    this.targetDoseWeight,
    this.targetYield,
    this.grinderId,
    this.grinderModel,
    this.grinderSetting,
    this.beanBatchId,
    this.coffeeName,
    this.coffeeRoaster,
    this.finalBeverageType,
    this.baristaName,
    this.drinkerName,
    this.extras,
  });

  double? get ratio =>
      (targetDoseWeight != null &&
              targetDoseWeight != 0 &&
              targetYield != null)
          ? targetYield! / targetDoseWeight!
          : null;

  /// Deserializes from JSON. Handles both new format and legacy format
  /// (DoseData/GrinderData/CoffeeData embedded in a parent Workflow JSON).
  factory WorkflowContext.fromJson(Map<String, dynamic> json) {
    return WorkflowContext(
      targetDoseWeight: parseOptionalDouble(json['targetDoseWeight']),
      targetYield: parseOptionalDouble(json['targetYield']),
      grinderId: json['grinderId'] as String?,
      grinderModel: json['grinderModel'] as String?,
      grinderSetting: json['grinderSetting'] as String?,
      beanBatchId: json['beanBatchId'] as String?,
      coffeeName: json['coffeeName'] as String?,
      coffeeRoaster: json['coffeeRoaster'] as String?,
      finalBeverageType: json['finalBeverageType'] as String?,
      baristaName: json['baristaName'] as String?,
      drinkerName: json['drinkerName'] as String?,
      extras: json['extras'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (targetDoseWeight != null) 'targetDoseWeight': targetDoseWeight,
      if (targetYield != null) 'targetYield': targetYield,
      if (grinderId != null) 'grinderId': grinderId,
      if (grinderModel != null) 'grinderModel': grinderModel,
      if (grinderSetting != null) 'grinderSetting': grinderSetting,
      if (beanBatchId != null) 'beanBatchId': beanBatchId,
      if (coffeeName != null) 'coffeeName': coffeeName,
      if (coffeeRoaster != null) 'coffeeRoaster': coffeeRoaster,
      if (finalBeverageType != null) 'finalBeverageType': finalBeverageType,
      if (baristaName != null) 'baristaName': baristaName,
      if (drinkerName != null) 'drinkerName': drinkerName,
      if (extras != null) 'extras': extras,
    };
  }

  WorkflowContext clearGrinder() => WorkflowContext(
    targetDoseWeight: targetDoseWeight,
    targetYield: targetYield,
    grinderId: null,
    grinderModel: null,
    grinderSetting: grinderSetting,
    beanBatchId: beanBatchId,
    coffeeName: coffeeName,
    coffeeRoaster: coffeeRoaster,
    finalBeverageType: finalBeverageType,
    baristaName: baristaName,
    drinkerName: drinkerName,
    extras: extras,
  );

  WorkflowContext clearBeanBatch() => WorkflowContext(
    targetDoseWeight: targetDoseWeight,
    targetYield: targetYield,
    grinderId: grinderId,
    grinderModel: grinderModel,
    grinderSetting: grinderSetting,
    beanBatchId: null,
    coffeeName: null,
    coffeeRoaster: null,
    finalBeverageType: finalBeverageType,
    baristaName: baristaName,
    drinkerName: drinkerName,
    extras: extras,
  );

  WorkflowContext copyWith({
    double? targetDoseWeight,
    double? targetYield,
    String? grinderId,
    String? grinderModel,
    String? grinderSetting,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    String? finalBeverageType,
    String? baristaName,
    String? drinkerName,
    Map<String, dynamic>? extras,
  }) {
    return WorkflowContext(
      targetDoseWeight: targetDoseWeight ?? this.targetDoseWeight,
      targetYield: targetYield ?? this.targetYield,
      grinderId: grinderId ?? this.grinderId,
      grinderModel: grinderModel ?? this.grinderModel,
      grinderSetting: grinderSetting ?? this.grinderSetting,
      beanBatchId: beanBatchId ?? this.beanBatchId,
      coffeeName: coffeeName ?? this.coffeeName,
      coffeeRoaster: coffeeRoaster ?? this.coffeeRoaster,
      finalBeverageType: finalBeverageType ?? this.finalBeverageType,
      baristaName: baristaName ?? this.baristaName,
      drinkerName: drinkerName ?? this.drinkerName,
      extras: extras ?? this.extras,
    );
  }

  @override
  String toString() => 'WorkflowContext('
      'dose: $targetDoseWeight→$targetYield, '
      'grinder: $grinderModel/$grinderSetting, '
      'coffee: $coffeeName by $coffeeRoaster)';
}
