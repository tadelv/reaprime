import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/serial/serial_service.dart';

/// Regression coverage for the iOS `libserialport.dylib` dlopen crashes
/// (Crashlytics issues `9d5fc4e9…`, `0f9ece6d…`, `39f895bc…`).
///
/// iOS can't load libserialport under the hardened runtime. The symptom
/// was three FATAL crashes with SIGNAL_EARLY (81% in the first second
/// of a session) because `SerialServiceDesktop.initialize()` called
/// `SerialPort.availablePorts` at app launch on every platform except
/// Android.
///
/// The fix routes iOS through `NoOpSerialService`. We can't flip
/// `Platform.isIOS` from a Dart VM test, so these tests pin the no-op
/// contract directly — a future change that makes it throw or stall
/// would still crash iOS at launch.

void main() {
  group('NoOpSerialService contract', () {
    test('initialize() completes without throwing', () async {
      final service = NoOpSerialService();
      await expectLater(service.initialize(), completes);
    });

    test('scanForDevices() completes without throwing', () async {
      final service = NoOpSerialService();
      await expectLater(service.scanForDevices(), completes);
    });

    test('stopScan() is a no-op', () {
      final service = NoOpSerialService();
      expect(service.stopScan, returnsNormally);
    });

    test(
      'devices stream emits an empty list synchronously on subscribe',
      () async {
        final service = NoOpSerialService();
        final first = await service.devices.first.timeout(
          const Duration(seconds: 2),
        );
        expect(
          first,
          isEmpty,
          reason: 'DeviceController seeds its per-service device map from '
              'the first emission — a silent stream stalls the controller',
        );
      },
    );
  });
}
