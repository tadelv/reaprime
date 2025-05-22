part of 'de1.dart';

extension De1Firmware on De1 {
  Future<void> updateFirmware(Uint8List fwImage) async {
    _log.info("Starting firmware upgrade ...");

    await requestState(MachineState.sleeping);

    FWUpgradeState currentState = FWUpgradeState.erase;

    // notify from fwmap
    _subscribe(Endpoint.fwMapRequest, (ByteData data) {
      final request = FWMapRequestData.from(data);
      _log.fine(
          "FW map recv: ${request.window}, ${request.erase}, err: 0x${request.error.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");

      switch (currentState) {
        case FWUpgradeState.erase:
          // TODO: Handle this case.
          throw UnimplementedError();
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
          window: 1 as Uint8,
          erase: 1 as Uint8,
          error: Uint8List.fromList([0xff, 0xff, 0xff]),
        ).asData().buffer,
      ),
    );
  }

  Future<void> uploadFW(Uint8List list) async {
    int uploadedCount = 0;
    for (int i = 0; i < list.length; i++) {
      // TODO: write
    }
  }
}

enum FWUpgradeState { erase, upload, error, done }

final class FWMapRequestData {
  final Uint8 window;
  final Uint8 erase;
  final Uint8List error;

  FWMapRequestData(
      {required this.window, required this.erase, required this.error});

  factory FWMapRequestData.from(ByteData data) {
    final Uint8 window = data.getInt8(0) as Uint8;
    final erase = data.getInt8(1) as Uint8;
    final errorHi = data.getInt8(2);
    final errorMid = data.getInt8(3);
    final errorLow = data.getInt8(4);

    return FWMapRequestData(
      window: window,
      erase: erase,
      error: Uint8List.fromList(
        [errorHi, errorMid, errorLow],
      ),
    );
  }

  ByteData asData() {
    ByteData data = ByteData(5);
    data.setInt8(0, window as int);
    data.setInt8(1, erase as int);
    data.setInt8(2, error[0]);
    data.setInt8(3, error[1]);
    data.setInt8(4, error[2]);
    return data;
  }
}
