import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_error.dart';

void main() {
  group('ConnectionError', () {
    test('toJson produces the documented shape', () {
      final err = ConnectionError(
        kind: ConnectionErrorKind.scaleConnectFailed,
        severity: ConnectionErrorSeverity.error,
        timestamp: DateTime.utc(2026, 4, 19, 7, 49, 29, 25),
        deviceId: '50:78:7D:1F:AE:E1',
        deviceName: 'Decent Scale',
        message: 'Scale connect timed out after 15s.',
        suggestion: 'Try toggling Bluetooth, then retry the scan.',
        details: {'fbp_code': 1},
      );

      expect(err.toJson(), {
        'kind': 'scaleConnectFailed',
        'severity': 'error',
        'timestamp': '2026-04-19T07:49:29.025Z',
        'deviceId': '50:78:7D:1F:AE:E1',
        'deviceName': 'Decent Scale',
        'message': 'Scale connect timed out after 15s.',
        'suggestion': 'Try toggling Bluetooth, then retry the scan.',
        'details': {'fbp_code': 1},
      });
    });

    test('toJson omits null optional fields', () {
      final err = ConnectionError(
        kind: ConnectionErrorKind.adapterOff,
        severity: ConnectionErrorSeverity.error,
        timestamp: DateTime.utc(2026, 4, 19),
        message: 'Bluetooth is turned off.',
      );

      final json = err.toJson();
      expect(json.containsKey('deviceId'), isFalse);
      expect(json.containsKey('deviceName'), isFalse);
      expect(json.containsKey('suggestion'), isFalse);
      expect(json.containsKey('details'), isFalse);
    });

    test('kind constants match the documented taxonomy', () {
      expect(ConnectionErrorKind.scaleConnectFailed, 'scaleConnectFailed');
      expect(ConnectionErrorKind.machineConnectFailed, 'machineConnectFailed');
      expect(ConnectionErrorKind.scaleDisconnected, 'scaleDisconnected');
      expect(ConnectionErrorKind.machineDisconnected, 'machineDisconnected');
      expect(ConnectionErrorKind.adapterOff, 'adapterOff');
      expect(ConnectionErrorKind.bluetoothPermissionDenied,
          'bluetoothPermissionDenied');
      expect(ConnectionErrorKind.scanFailed, 'scanFailed');
    });
  });
}
