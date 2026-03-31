import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/scan_report.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';

void main() {
  test('ScanReport stores scan telemetry', () {
    final report = ScanReport(
      totalBleDevicesSeen: 5,
      matchedDevices: [],
      scanDuration: Duration(seconds: 15),
      adapterStateAtStart: AdapterState.poweredOn,
      adapterStateAtEnd: AdapterState.poweredOn,
      scanTerminationReason: ScanTerminationReason.completed,
      preferredMachineId: 'machine-123',
      preferredScaleId: null,
    );

    expect(report.totalBleDevicesSeen, 5);
    expect(report.scanTerminationReason, ScanTerminationReason.completed);
    expect(report.preferredMachineId, 'machine-123');
    expect(report.preferredScaleId, isNull);
  });

  test('MatchedDevice tracks connection result', () {
    final matched = MatchedDevice(
      deviceName: 'DE1',
      deviceId: 'abc123',
      deviceType: DeviceType.machine,
      connectionAttempted: true,
      connectionResult: ConnectionResult.failed('timeout'),
    );

    expect(matched.connectionAttempted, isTrue);
    expect(matched.connectionResult!.success, isFalse);
    expect(matched.connectionResult!.error, 'timeout');
  });
}
