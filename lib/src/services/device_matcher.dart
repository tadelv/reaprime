import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/skale/skale2_scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';

class DeviceMatcher {
  static Future<Device?> match({
    required BLETransport transport,
    required String advertisedName,
  }) async {
    final name = advertisedName;

    // Exact matches
    if (name == 'Decent Scale') return DecentScale(transport: transport);
    if (name == 'Skale2') return Skale2Scale(transport: transport);

    return null;
  }
}
