part of "serial_de1.dart";

extension SerialDe1Firmware on SerialDe1 {
  Future<void> _updateFirmware(Uint8List fwImage, void Function(double) onProgress) async {
    _log.info("Starting firmware upgrade");

    await requestState(MachineState.sleeping);

    await _transport.writeCommand("<+I>");

    final eraseFWRequest = FWMapRequestData(
      windowIncrement: 0,
      firmwareToErase: 1,
      firmwareToMap: 1,
      error: Uint8List.fromList([0xff, 0xff, 0xff]),
    );

    await _transport.writeCommand(
        "<I>${eraseFWRequest.asData().buffer.asUint8List().map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");
    int count = 0;
    while (count < 10) {
      count += 1;
      _log.info("Waiting $count seconds on firmware to erase");
      await Future.delayed(Duration(seconds: 1));
    }

    _log.info("Starting write");
    await _uploadFW(fwImage, onProgress);

    _log.info("Done writing");

    _log.info("Send verify command");

    final verifyRequest = FWMapRequestData(
      windowIncrement: 0,
      firmwareToErase: 0,
      firmwareToMap: 1,
      error: Uint8List.fromList([0xff, 0xff, 0xff]),
    );
    await _transport.writeCommand(
        "<I>${verifyRequest.asData().buffer.asUint8List().map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");

		count = 5;
    while (count < 10) {
      count += 1;
      _log.info("Waiting $count seconds on firmware to verify");
      await Future.delayed(Duration(seconds: 1));
    }

		_log.info("Finished with fw upgrade");

  }

  Future<void> _uploadFW(Uint8List list, void Function(double) onProgress) async {
	final total = list.length;
    for (int i = 0; i < list.length; i += 16) {
      final chunkLength = (i + 16 <= list.length) ? 16 : list.length - i;
      final data = Uint8List(3 + chunkLength);
      final address = encodeU24P0(i);

      data[0] = address[0];
      data[1] = address[1];
      data[2] = address[2];

      data.setRange(3, 3 + chunkLength, list, i);

      await _transport.writeCommand(
          "<F>${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");
					await Future.delayed(Duration(milliseconds: 5));

			onProgress(min(i / total, 1.0));
    }
  }

  Future<void> _parseFWMapRequest(ByteData data) async {
    final request = FWMapRequestData.from(data);
    _log.fine(
        "FW map recv: ${request.windowIncrement}, ${request.firmwareToErase}, ${request.firmwareToMap}, "
        "err: 0x${request.error.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");
  }
}
