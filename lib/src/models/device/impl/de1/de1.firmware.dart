part of 'de1.dart';

extension De1Firmware on De1 {
  Future<void> _updateFirmware(Uint8List fwImage) async {
    _log.info("Starting firmware upgrade ...");

    await requestState(MachineState.sleeping);

    FWUpgradeState currentState = FWUpgradeState.erase;

    // notify from fwmap
    _subscribe(Endpoint.fwMapRequest, (ByteData data) async {
      final request = FWMapRequestData.from(data);
      _log.fine(
          "FW map recv: ${request.window}, ${request.erase}, err: 0x${request.error.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");

      switch (currentState) {
        case FWUpgradeState.erase:
          if (request.erase == 0) {
            currentState = FWUpgradeState.upload;
            await uploadFW(fwImage);
						_log.info("Done uploading ${fwImage.length} bytes");
						// TODO: check for errors
						currentState = FWUpgradeState.done;
          } else {
            _log.warning(
                "Received fw upgrade notify while in erase state which is not erase == 0");
          }
        case FWUpgradeState.upload:
          // TODO: Handle this case.
          throw UnimplementedError();
        case FWUpgradeState.error:
          // TODO: Handle this case.
          throw UnimplementedError();
        case FWUpgradeState.done:
          // TODO: Handle this case.
          throw UnimplementedError();
      }
    });
    // requsst firmware erase
    await _write(
      Endpoint.fwMapRequest,
      Uint8List.view(
        FWMapRequestData(
          window: 0 as Uint8,
					firmwareToErase: 0 as Uint8,
          erase: 1 as Uint8,
          error: Uint8List.fromList([0xff, 0xff, 0xff]),
        ).asData().buffer,
      ),
    );
  }

  Future<void> uploadFW(Uint8List list) async {
    for (int i = 0; i < list.length; i += 16) {
      final chunkLength = (i + 16 <= list.length) ? 16 : list.length - i;
      final data = Uint8List(3 + chunkLength);
      final address = encodeU24P0(i);

      data[0] = address[0];
      data[1] = address[1];
      data[2] = address[2];

      for (int j = 0; j < chunkLength; j++) {
        data[3 + j] = list[i + j];
      }

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
  final Uint8 window;
	final Uint8 firmwareToErase;
  final Uint8 erase;
  final Uint8List error;

  FWMapRequestData(
      {required this.window, required this.firmwareToErase, required this.erase, required this.error});

  factory FWMapRequestData.from(ByteData data) {
    final Uint8 window = data.getInt8(0) as Uint8;
		final firmwareToErase = data.getInt8(1) as Uint8;
    final erase = data.getInt8(2) as Uint8;
    final errorHi = data.getInt8(3);
    final errorMid = data.getInt8(4);
    final errorLow = data.getInt8(5);

    return FWMapRequestData(
      window: window,
			firmwareToErase: firmwareToErase,
      erase: erase,
      error: Uint8List.fromList(
        [errorHi, errorMid, errorLow],
      ),
    );
  }

  ByteData asData() {
    ByteData data = ByteData(5);
    data.setInt8(0, window as int);
		data.setInt8(1, firmwareToErase as int);
    data.setInt8(2, erase as int);
    data.setInt8(3, error[0]);
    data.setInt8(4, error[1]);
    data.setInt8(5, error[2]);
    return data;
  }
}
