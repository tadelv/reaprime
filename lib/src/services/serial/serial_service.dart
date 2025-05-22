// export 'serial_service_desktop.dart'
//     if (Platform.isAndroid) 'serial_service_android.dart';
import 'dart:io';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/services/serial/serial_service_android.dart';
import 'package:reaprime/src/services/serial/serial_service_desktop.dart';

DeviceDiscoveryService createSerialService() {
  if (Platform.isAndroid) {
    return SerialServiceAndroid();
  }
  return SerialServiceDesktop();
}
