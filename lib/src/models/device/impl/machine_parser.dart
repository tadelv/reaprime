import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:universal_ble/universal_ble.dart';

class MachineParser {
  static Future<Machine> machineFrom({required String deviceId}) async {
    Logger log = Logger("Machine parser");
    log.info("starting check");
    final StreamController<List<int>> mmrController =
        StreamController.broadcast();
    final device = BleDevice(deviceId: deviceId, name: "Decent Machine");
    try {
      await device.connect();

      final state = await device.isConnected;
      log.info("devices connected: $state");

      await device.discoverServices(timeout: Duration(seconds: 3));
      final service = await device.getService(de1ServiceUUID);
      final readMMR = service.getCharacteristic(Endpoint.readFromMMR.uuid);
      final writeMMR = service.getCharacteristic(Endpoint.writeToMMR.uuid);
      await readMMR.notifications.subscribe(timeout: Duration(seconds: 3));
      final readSubscription = readMMR.onValueReceived.listen((Uint8List data) {
        log.info("incoming data: ${data}");
        mmrController.add(data);
      });

      ByteData bytes = ByteData(20);
      bytes.setInt32(0, MMRItem.v13Model.address, Endian.big);
      var buffer = bytes.buffer.asUint8List();
      buffer[0] = (0 % 0xFF);
      log.info("writing read req");
      log.info('sending read req ${buffer.map(toHexString).toList()}');
      await readMMR.write(buffer, withResponse: true);

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
        m = De1.fromId(deviceId);
      } else {
        m = Bengle(deviceId: deviceId);
      }
      readSubscription.cancel();
      await device.disconnect();
      // TODO: not sure if disconnect will mess up bluetooth on Android?
      await Future.delayed(Duration(milliseconds: 500));
      return m;
    } catch (e, st) {
      log.warning("failed to check:", e, st);
      await device.disconnect();
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
