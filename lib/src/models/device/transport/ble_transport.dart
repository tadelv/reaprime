import 'dart:typed_data';
import 'package:reaprime/src/models/device/transport/data_transport.dart';

abstract class BLETransport extends DataTransport {
  Future<List<String>> discoverServices();

  void subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  );

  Future<Uint8List> read(String serviceUUID, String characteristicUUID);

  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = false,
  });
}
