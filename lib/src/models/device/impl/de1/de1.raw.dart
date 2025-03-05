part of 'de1.dart';

extension De1Raw on De1 {
  initRawStream() {
    _rawInStream.stream.listen((data) async {
      if (data.operation == De1RawOperationType.notify) {
        _log.fine("Ignoring ${data.operation.name}");
        return;
      }
      var endpoint = Endpoint.fromUuid(data.characteristicUUID);
      if (endpoint == null) {
        _log.info("Ignoring unknown endpoint: ${data.characteristicUUID}");
        return;
      }
      try {
        switch (data.operation) {
          case De1RawOperationType.read:
            var response = await _read(endpoint);
            _rawOutStream.add(
              packToRaw(
                data.operation,
                data.characteristicUUID,
                response.buffer.asUint8List(),
              ),
            );
          case De1RawOperationType.write:
            var payload = Uint8List.fromList(data.payload.codeUnits);
            await _write(endpoint, payload);
            _rawOutStream.add(
              packToRaw(
                data.operation,
                data.characteristicUUID,
                Uint8List(0), // Empty response payload for write confirmation
              ),
            );
          case De1RawOperationType.notify:
        }
      } catch (e, st) {
        _log.severe("Failed to process raw: ", e, st);
      }
    });
  }

  notifyFrom(
    Endpoint e,
    Uint8List data,
  ) {
    _rawOutStream.add(
      packToRaw(
        De1RawOperationType.notify,
        e.uuid,
        data.buffer.asUint8List(),
      ),
    );
  }

  De1RawMessage packToRaw(
    De1RawOperationType operation,
    String characteristicUUID,
    Uint8List data,
  ) {
    return De1RawMessage(
      type: De1RawMessageType.response,
      operation: operation,
      characteristicUUID: characteristicUUID,
      payload: data.map((e) => e.toString()).join(),
    );
  }
}

