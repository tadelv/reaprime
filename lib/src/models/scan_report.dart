import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';

enum ScanTerminationReason {
  completed,
  timedOut,
  cancelledByUser,
  adapterStateChanged,
}

enum ConnectionOutcome {
  connected,
  alreadyConnected,
  conflict,
  failed,
  timedOut,
}

class ConnectionResult {
  final ConnectionOutcome outcome;
  final String? error;

  const ConnectionResult.succeeded()
    : outcome = ConnectionOutcome.connected,
      error = null;
  const ConnectionResult.alreadyConnected()
    : outcome = ConnectionOutcome.alreadyConnected,
      error = null;
  const ConnectionResult.conflict()
    : outcome = ConnectionOutcome.conflict,
      error = null;
  const ConnectionResult.failed(this.error)
    : outcome = ConnectionOutcome.failed;
  const ConnectionResult.timedOut(this.error)
    : outcome = ConnectionOutcome.timedOut;

  bool get success =>
      outcome == ConnectionOutcome.connected ||
      outcome == ConnectionOutcome.alreadyConnected;
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
