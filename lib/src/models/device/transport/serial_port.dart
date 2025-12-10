import 'package:flutter/foundation.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';

abstract class SerialTransport extends DataTransport {
  Future<void> writeCommand(String command);
  Future<void> writeHexCommand(Uint8List command);
  Stream<String> get readStream;
  Stream<Uint8List> get rawStream;
}
