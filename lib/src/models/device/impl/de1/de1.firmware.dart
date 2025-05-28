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
      _log.fine(
          "FW map recv: ${request.windowIncrement}, ${request.firmwareToErase}, ${request.firmwareToMap}, "
          "err: 0x${request.error.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");

      switch (currentState) {
        case FWUpgradeState.erase:
          if (request.firmwareToMap == 0 &&
              request.error[0] == 0xff &&
              request.error[1] == 0xff &&
              request.error[2] == 0xfd) {
            currentState = FWUpgradeState.upload;
            await uploadFW(fwImage);
            _log.info("Done uploading ${fwImage.length} bytes");
            currentState = FWUpgradeState.done;
            completer.complete();
            // unsub.cancel();
          } else {
            _log.warning(
                "Received fw upgrade notify while in erase state (erase != 0)");
            completer.completeError(
                Exception("Unexpected error encountered in erase request"));
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
          // unsub.cancel();
          break;

        case FWUpgradeState.done:
          _log.info("Firmware upgrade already complete.");
          break;
      }
    });

    // Request firmware erase
    await _writeWithResponse(
      Endpoint.fwMapRequest,
      Uint8List.view(
        FWMapRequestData(
          windowIncrement: 0,
          firmwareToErase: 1,
          firmwareToMap: 1,
          error: Uint8List.fromList([0xff, 0xff, 0xff]),
        ).asData().buffer,
      ),
    );

    int count = 0;
    while (count < 10) {
      count += 1;
      _log.info("Waiting $count seconds on firmware to erase");
      sleep(Duration(seconds: 1));
    }

    await uploadFW(fwImage);
    _log.info("All done!");

		// verify crc?
    await _writeWithResponse(
      Endpoint.fwMapRequest,
      Uint8List.view(
        FWMapRequestData(
          windowIncrement: 0,
          firmwareToErase: 0,
          firmwareToMap: 1,
          error: Uint8List.fromList([0xff, 0xff, 0xff]),
        ).asData().buffer,
      ),
    );

    _log.info("Sent check for errors");
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
}

enum FWUpgradeState { erase, upload, error, done }

