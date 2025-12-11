import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';

class MachineParser {
  static Future<Machine> machineFrom({required BLETransport transport}) async {
    Logger log = Logger("Machine parser");
    log.info("starting check");
    final StreamController<List<int>> mmrController =
        StreamController.broadcast();
    try {
      await transport.connect();

      final state = await transport.connectionState.firstWhere((e) => e);
      log.info("devices connected: $state");

      final services = await transport.discoverServices();
      final service = services.firstWhere((s) => s == de1ServiceUUID);

      transport.subscribe(service, Endpoint.readFromMMR.uuid, (data) {
        log.info("incoming data: ${data}");
        mmrController.add(data);
      });

      ByteData bytes = ByteData(20);
      bytes.setInt32(0, MMRItem.v13Model.address, Endian.big);
      var buffer = bytes.buffer.asUint8List();
      buffer[0] = (0 % 0xFF);
      log.info("writing read req");
      log.info('sending read req ${buffer.map(toHexString).toList()}');
      await transport.write(service, Endpoint.writeToMMR.uuid, buffer);

      // var result = await readMMR.read(timeout: Duration(seconds: 1));
      var result = await mmrController.stream
          .firstWhere((element) {
            log.info(
              "listen where event  ${element.map(toHexString).toList()}",
            );

            if (buffer[1] == element[1] &&
                buffer[2] == element[2] &&
                buffer[3] == element[3]) {
              return true;
            } else {
              return false;
            }
          }, orElse: () => [])
          .timeout(Duration(seconds: 5));
      log.info("result: ${result.toString()}");

      int model = _unpackMMRInt(result);
      log.info("model is $model");
      Machine m;
      if (model < 128) {
        // TODO: avoid reconnect in the De1 impl
        // m = De1.withDevice(device: device);
        m = De1.fromId(transport.id);
      } else {
        m = Bengle(deviceId: transport.id);
      }
      await transport.disconnect();
      // TODO: not sure if disconnect will mess up bluetooth on Android?
      await Future.delayed(Duration(milliseconds: 500));
      return m;
    } catch (e, st) {
      log.warning("failed to check:", e, st);
      await transport.disconnect();
      throw "Could not determine model";
    }
  }

  static int _unpackMMRInt(List<int> buffer) {
    ByteData bytes = ByteData(20);
    var i = 0;
    var list = bytes.buffer.asUint8List();
    for (var _ in list) {
      list[i] = buffer[i++];
    }
    return bytes.getInt32(4, Endian.little);
  }
}
