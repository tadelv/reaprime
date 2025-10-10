part of 'de1.dart';

extension De1ReadWrite on De1 {
  Future<ByteData> _read(Endpoint e) async {
    if (!await _device.isConnected ) {
      throw ("de1 not connected");
    }
    final characteristic = _service.characteristics.firstWhere((c) => c.uuid == BleUuidParser.string(e.uuid));
    var data = await characteristic.read();
    ByteData response = ByteData.sublistView(Uint8List.fromList(data));
    return response;
  }

  Future<void> _write(Endpoint e, Uint8List data) async {
    try {
      _log.fine('about to write to ${e.name}');
      _log.fine('payload: ${data.map((el) => toHexString(el))}');
      final characteristic = _service.characteristics
          .firstWhere((c) => c.uuid == BleUuidParser.string(e.uuid));

      await characteristic.write(
        data,
        //withoutResponse: true,
      );
    } catch (e, st) {
      _log.severe("failed to write", e, st);
      rethrow;
    }
  }

  Future<void> _writeWithResponse(Endpoint e, Uint8List data) async {
    try {
      _log.fine('about to write with response to ${e.name}');
      _log.fine('payload: ${data.map((el) => toHexString(el))}');
      final characteristic = _service.characteristics
          .firstWhere((c) => c.uuid == BleUuidParser.string(e.uuid));

      await characteristic.write(
        data,
      );
    } catch (e, st) {
      _log.severe("failed to write", e, st);
      rethrow;
    }
  }
}
