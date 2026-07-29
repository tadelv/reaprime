import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_scale.dart';
import 'package:reaprime/src/models/device/impl/atomheart/atomheart_scale.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/blackcoffee/blackcoffee_scale.dart';
import 'package:reaprime/src/models/device/impl/bookoo/miniscale.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale_serial.dart';
import 'package:reaprime/src/models/device/impl/decent_temp/temperature.dart';
import 'package:reaprime/src/models/device/impl/difluid/difluid_r2_sensor.dart';
import 'package:reaprime/src/models/device/impl/difluid/difluid_scale.dart';
import 'package:reaprime/src/models/device/impl/eureka/eureka_scale.dart';
import 'package:reaprime/src/models/device/impl/felicita/arc.dart';
import 'package:reaprime/src/models/device/impl/hiroia/hiroia_scale.dart';
import 'package:reaprime/src/models/device/impl/sensor/debug_port.dart';
import 'package:reaprime/src/models/device/impl/sensor/sensor_basket.dart';
import 'package:reaprime/src/models/device/impl/skale/skale2_scale.dart';
import 'package:reaprime/src/models/device/impl/smartchef/smartchef_scale.dart';
import 'package:reaprime/src/models/device/impl/varia/varia_aku_scale.dart';
import 'package:reaprime/src/models/device/impl/weighmaster/weighmaster_scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/device/transport/serial_port.dart';

/// Maps [DeviceImplementation] to the concrete [Device] constructor.
/// Used by [DeviceDiscoveryService.tryQuickConnect] to construct a device
/// from persisted metadata without name-matching or port-probing.
///
/// BLE and serial are separate methods because the constructor signatures
/// differ by transport type. WiFi ([HDSWifi]) has a bespoke constructor
/// (host + transport factory) and is constructed by the WiFi discovery
/// service directly, not through this factory.
class DeviceFactory {
  DeviceFactory._();

  /// Create a BLE-connected device from its [implementation] and an
  /// already-connected [transport]. Returns null if [implementation] is
  /// not a BLE device (serial-only or WiFi-only).
  static Device? createBle(
    DeviceImplementation implementation,
    BLETransport transport,
  ) {
    return switch (implementation) {
      DeviceImplementation.unifiedDe1 => UnifiedDe1(transport: transport),
      DeviceImplementation.bengle => Bengle(transport: transport),
      DeviceImplementation.decentScale => DecentScale(transport: transport),
      DeviceImplementation.skale2 => Skale2Scale(transport: transport),
      DeviceImplementation.acaiaScale => AcaiaScale(transport: transport),
      DeviceImplementation.felicitaArc => FelicitaArc(transport: transport),
      DeviceImplementation.blackCoffeeScale => BlackCoffeeScale(
        transport: transport,
      ),
      DeviceImplementation.bookooScale => BookooScale(transport: transport),
      DeviceImplementation.eurekaScale => EurekaScale(transport: transport),
      DeviceImplementation.smartChefScale => SmartChefScale(
        transport: transport,
      ),
      DeviceImplementation.variaAkuScale => VariaAkuScale(transport: transport),
      DeviceImplementation.difluidScale => DifluidScale(transport: transport),
      DeviceImplementation.hiroiaScale => HiroiaScale(transport: transport),
      DeviceImplementation.atomheartScale => AtomheartScale(
        transport: transport,
      ),
      DeviceImplementation.weighMasterScale => WeighMasterScale(
        transport: transport,
      ),
      DeviceImplementation.decentTemp => DecentTemp(transport: transport),
      DeviceImplementation.difluidR2Sensor => DifluidR2Sensor(
        transport: transport,
      ),
      DeviceImplementation.hdsSerial => null,
      DeviceImplementation.hdsWifi => null,
      DeviceImplementation.debugPort => null,
      DeviceImplementation.sensorBasket => null,
    };
  }

  /// Create a serial-connected device from its [implementation] and an
  /// already-open [transport]. Returns null if [implementation] is not a
  /// serial device.
  static Device? createSerial(
    DeviceImplementation implementation,
    SerialTransport transport,
  ) {
    return switch (implementation) {
      DeviceImplementation.hdsSerial => HDSSerial(transport: transport),
      DeviceImplementation.debugPort => DebugPort(transport: transport),
      DeviceImplementation.sensorBasket => SensorBasket(transport: transport),
      DeviceImplementation.unifiedDe1 => UnifiedDe1(transport: transport),
      _ => null,
    };
  }
}
