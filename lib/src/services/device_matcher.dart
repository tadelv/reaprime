import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_pyxis_scale.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_scale.dart';
import 'package:reaprime/src/models/device/impl/atomheart/atomheart_scale.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/blackcoffee/blackcoffee_scale.dart';
import 'package:reaprime/src/models/device/impl/bookoo/miniscale.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/difluid/difluid_scale.dart';
import 'package:reaprime/src/models/device/impl/eureka/eureka_scale.dart';
import 'package:reaprime/src/models/device/impl/felicita/arc.dart';
import 'package:reaprime/src/models/device/impl/hiroia/hiroia_scale.dart';
import 'package:reaprime/src/models/device/impl/skale/skale2_scale.dart';
import 'package:reaprime/src/models/device/impl/smartchef/smartchef_scale.dart';
import 'package:reaprime/src/models/device/impl/varia/varia_aku_scale.dart';
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

    // DE1 family — check before generic prefix matches
    if (name == 'DE1' || name == 'nRF5x' || nameLower.startsWith('de1')) {
      return UnifiedDe1(transport: transport);
    }
    if (name == 'Bengle') return Bengle(transport: transport);

    // Prefix matches
    if (nameLower.startsWith('felicita')) {
      return FelicitaArc(transport: transport);
    }
    if (nameLower.startsWith('black')) {
      return BlackCoffeeScale(transport: transport);
    }

    // Contains matches — check specific before generic
    if (nameLower.contains('acaia')) {
      if (nameLower.contains('pyxis')) {
        return AcaiaPyxisScale(transport: transport);
      }
      return AcaiaScale(transport: transport);
    }

    if (nameLower.contains('eureka') || nameLower.contains('precisa') ||
        nameLower.contains('cfs-9002')) {
      return EurekaScale(transport: transport);
    }
    if (nameLower.contains('solo barista') || nameLower.contains('lsj-001')) {
      return EurekaScale(transport: transport);
    }

    if (nameLower.contains('smartchef')) {
      return SmartChefScale(transport: transport);
    }
    if (nameLower.contains('aku') || nameLower.contains('varia')) {
      return VariaAkuScale(transport: transport);
    }
    if (nameLower.contains('hiroia') || nameLower.contains('jimmy')) {
      return HiroiaScale(transport: transport);
    }
    if (nameLower.contains('difluid')) {
      return DifluidScale(transport: transport);
    }
    if (nameLower.contains('atomheart') || nameLower.contains('eclair')) {
      return AtomheartScale(transport: transport);
    }
    if (nameLower.contains('bookoo')) {
      return BookooScale(transport: transport);
    }

    return null;
  }
}
