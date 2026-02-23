import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_pyxis_scale.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_scale.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/felicita/arc.dart';
import 'package:reaprime/src/models/device/impl/skale/skale2_scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';

class DeviceMatcher {
  static Future<Device?> match({
    required BLETransport transport,
    required String advertisedName,
  }) async {
    final name = advertisedName;
    final nameLower = name.toLowerCase();

    // Exact matches
    if (name == 'Decent Scale') return DecentScale(transport: transport);
    if (name == 'Skale2') return Skale2Scale(transport: transport);

    // Prefix matches
    if (nameLower.startsWith('felicita')) {
      return FelicitaArc(transport: transport);
    }

    // Contains matches (check specific before generic)
    if (nameLower.contains('acaia')) {
      if (nameLower.contains('pyxis')) {
        return AcaiaPyxisScale(transport: transport);
      }
      return AcaiaScale(transport: transport);
    }

    return null;
  }
}
