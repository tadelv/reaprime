part of 'de1.dart';

extension De1ReadWrite on De1 {
  Future<ByteData> _read(Endpoint e) async {
    if (_ble.status != BleStatus.ready) {
      throw ("de1 not connected ${_ble.status}");
    }
    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(de1ServiceUUID),
      characteristicId: Uuid.parse(e.uuid),
      deviceId: deviceId,
    );
    var data = await _ble.readCharacteristic(characteristic);
		ByteData response = ByteData.sublistView(Uint8List.fromList(data));
    return response;
  }

  Future<void> _write(Endpoint e, Uint8List data) async {
    try {
      final characteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(e.uuid),
        serviceId: Uuid.parse(de1ServiceUUID),
        deviceId: deviceId,
      );

      _ble.writeCharacteristicWithoutResponse(characteristic, value: data);
    } catch (e, st) {
      _log.severe("failed to write", e, st);
    }
  }

  Future<void> _writeWithResponse(Endpoint e, Uint8List data) async {
    try {
      final characteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(e.uuid),
        serviceId: Uuid.parse(de1ServiceUUID),
        deviceId: deviceId,
      );

      _ble.writeCharacteristicWithResponse(characteristic, value: data);
    } catch (e, st) {
      _log.severe("failed to write", e, st);
    }
  }
}
