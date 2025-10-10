import 'package:collection/collection.dart';

enum GatewayMode {
  full, // bypass everything, no shot controller, no chart
  tracking, // shot controller only
  disabled
}

extension GatewayModeFromString on GatewayMode {
  static GatewayMode? fromString(String mode) {
    return GatewayMode.values.firstWhereOrNull((t) => t.name == mode);
  }
}
