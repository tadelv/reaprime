part of 'de1.dart';

extension De1ReadWrite on De1 {
  Future<ByteData> _read(Endpoint e) async {
    if (await _device.connectionState.last !=
        BluetoothConnectionState.connected) {
      throw ("de1 not connected");
    }
    final characteristic = _service.characteristics
        .firstWhere((c) => c.characteristicUuid == Guid(e.uuid));
    var data = await characteristic.read();
    ByteData response = ByteData.sublistView(Uint8List.fromList(data));
    return response;
  }

  Future<void> _write(Endpoint e, Uint8List data) async {
    try {
      _log.info('about to write to ${e.name}');
      _log.info('payload: ${data.map((el) => toHexString(el))}');
      final characteristic = _service.characteristics
          .firstWhere((c) => c.characteristicUuid == Guid(e.uuid));

      await characteristic.write(
        data,
        withoutResponse: true,
      );
    } catch (e, st) {
      _log.severe("failed to write", e, st);
      rethrow;
    }
  }

  Future<void> _writeWithResponse(Endpoint e, Uint8List data) async {
    try {
      _log.info('about to write to ${e.name}');
      _log.info('payload: ${data.map((el) => toHexString(el))}');
      final characteristic = _service.characteristics
          .firstWhere((c) => c.characteristicUuid == Guid(e.uuid));

      await characteristic.write(
        data,
      );
    } catch (e, st) {
      _log.severe("failed to write", e, st);
      rethrow;
    }
  }
}
