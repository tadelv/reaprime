part of 'de1.dart';

extension De1Firmware on De1 {
  Future<void> _updateFirmware(Uint8List fwImage) async {
    _log.info("Starting firmware upgrade ...");

    await requestState(MachineState.sleeping);

    final completer = Completer<void>();
    FWUpgradeState currentState = FWUpgradeState.erase;

    // TODO: should be refactored at some point, currently can not unsub in ble
    // late final StreamSubscription<ByteData> unsub;

    // unsub = _subscribe(Endpoint.fwMapRequest, (ByteData data) async {
    _subscribe(Endpoint.fwMapRequest, (ByteData data) async {
      final request = FWMapRequestData.from(data);
      _log.fine("FW map recv: ${request.window}, ${request.erase}, "
          "err: 0x${request.error.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");

      switch (currentState) {
        case FWUpgradeState.erase:
          if (request.erase == 0) {
            currentState = FWUpgradeState.upload;
            await uploadFW(fwImage);
            _log.info("Done uploading ${fwImage.length} bytes");
            currentState = FWUpgradeState.done;
            completer.complete();
            // unsub.cancel();
          } else {
            _log.warning(
                "Received fw upgrade notify while in erase state (erase != 0)");
          }
          break;

        case FWUpgradeState.upload:
          _log.warning("Unexpected notify during upload phase.");
          break;

        case FWUpgradeState.error:
          _log.severe("Firmware upgrade failed — error state entered.");
          if (!completer.isCompleted) {
            completer.completeError(Exception("Firmware upgrade failed"));
          }
          unsub.cancel();
          break;

        case FWUpgradeState.done:
          _log.info("Firmware upgrade already complete.");
          break;
      }
    });

    // Request firmware erase
    await _write(
      Endpoint.fwMapRequest,
      Uint8List.view(
        FWMapRequestData(
          window: 0,
          firmwareToErase: 0,
          erase: 1,
          error: Uint8List.fromList([0xff, 0xff, 0xff]),
        ).asData().buffer,
      ),
    );

    return completer.future;
  }

  Future<void> uploadFW(Uint8List list) async {
    for (int i = 0; i < list.length; i += 16) {
      final chunkLength = (i + 16 <= list.length) ? 16 : list.length - i;
      final data = Uint8List(3 + chunkLength);
      final address = encodeU24P0(i);

      data[0] = address[0];
      data[1] = address[1];
      data[2] = address[2];

      data.setRange(3, 3 + chunkLength, list, i);

      await _write(Endpoint.writeToMMR, data);
    }
  }

  Uint8List encodeU24P0(int value) {
    if (value < 0 || value > 0xFFFFFF) {
      throw ArgumentError(
          'Value must be between 0 and 0xFFFFFF (24-bit unsigned)');
    }
    return Uint8List.fromList([
      (value >> 16) & 0xFF, // high byte
      (value >> 8) & 0xFF, // mid byte
      value & 0xFF // low byte
    ]);
  }
}

enum FWUpgradeState { erase, upload, error, done }

final class FWMapRequestData {
  final int window;
  final int firmwareToErase;
  final int erase;
  final Uint8List error;

  FWMapRequestData({
    required this.window,
    required this.firmwareToErase,
    required this.erase,
    required this.error,
  });

  factory FWMapRequestData.from(ByteData data) {
    final int window = data.getInt8(0);
    final int firmwareToErase = data.getInt8(1);
    final int erase = data.getInt8(2);
    final int errorHi = data.getInt8(3);
    final int errorMid = data.getInt8(4);
    final int errorLow = data.getInt8(5);

    return FWMapRequestData(
      window: window,
      firmwareToErase: firmwareToErase,
      erase: erase,
      error: Uint8List.fromList([errorHi, errorMid, errorLow]),
    );
  }

  ByteData asData() {
    final data = ByteData(6);
    data.setInt8(0, window);
    data.setInt8(1, firmwareToErase);
    data.setInt8(2, erase);
    data.setInt8(3, error[0]);
    data.setInt8(4, error[1]);
    data.setInt8(5, error[2]);
    return data;
  }
}
