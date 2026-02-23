import 'package:collection/collection.dart';

enum ChargingMode {
  disabled,
  longevity,
  balanced,
  highAvailability,
}

extension ChargingModeFromString on ChargingMode {
  static ChargingMode? fromString(String mode) {
    return ChargingMode.values.firstWhereOrNull((t) => t.name == mode);
  }
}
