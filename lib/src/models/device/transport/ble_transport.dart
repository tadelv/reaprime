import 'dart:typed_data';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';

abstract class BLETransport extends DataTransport {
  Future<List<String>> discoverServices();

  /// Query the platform BLE stack for the live connection state of
  /// the underlying peripheral. Unlike the [connectionState] stream
  /// this is a point-in-time read and survives transport-instance
  /// teardown — useful for detecting an already-live connection
  /// when reconnecting through a fresh transport.
  Future<ConnectionState> getConnectionState();

  Future<void> subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  );

  Future<Uint8List> read(
    String serviceUUID,
    String characteristicUUID, {
    Duration? timeout,
  });

  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  });

  Future<void> setTransportPriority(bool prioritized);
}
