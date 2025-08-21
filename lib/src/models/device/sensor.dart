import 'dart:typed_data';

import 'device.dart';

abstract class Sensor extends Device {
  Stream<Uint8List> get data;

  // TODO: cmd interface
  Future<void> tare();
}
