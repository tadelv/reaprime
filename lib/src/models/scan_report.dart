import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';

enum ScanTerminationReason {
  completed,
  timedOut,
  cancelledByUser,
  adapterStateChanged
}

class ConnectionResult {
  final bool success;
  final String? error;

  const ConnectionResult.succeeded()
      : success = true,
        error = null;
  const ConnectionResult.failed(this.error) : success = false;
  const ConnectionResult.skipped()
      : success = false,
        error = null;
}

class MatchedDevice {
  final String deviceName;
  final String deviceId;
  final DeviceType deviceType;
  final bool connectionAttempted;
  final ConnectionResult? connectionResult;

  const MatchedDevice({
    required this.deviceName,
    required this.deviceId,
    required this.deviceType,
    required this.connectionAttempted,
    this.connectionResult,
  });
}

class ScanReport {
  final int totalBleDevicesSeen;
  final List<MatchedDevice> matchedDevices;
  final Duration scanDuration;
  final AdapterState adapterStateAtStart;
  final AdapterState adapterStateAtEnd;
  final ScanTerminationReason scanTerminationReason;
  final String? preferredMachineId;
  final String? preferredScaleId;

  const ScanReport({
    required this.totalBleDevicesSeen,
    required this.matchedDevices,
    required this.scanDuration,
    required this.adapterStateAtStart,
    required this.adapterStateAtEnd,
    required this.scanTerminationReason,
    this.preferredMachineId,
    this.preferredScaleId,
  });
}
