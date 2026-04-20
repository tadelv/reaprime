import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/scan_report.dart' show ScanTerminationReason;

export 'package:reaprime/src/models/scan_report.dart' show ScanTerminationReason;

/// Result of a single scan cycle across all discovery services.
///
/// Completes when every service's scan has finished (success or failure).
/// Per-service failures are captured in [failedServices] rather than
/// thrown — one BLE permission denial does not torpedo a user who is
/// running serial-only, for example. Callers inspect [failedServices]
/// if they need to surface errors for individual transport classes.
///
/// A catastrophic, scan-wide failure (no services could even be
/// invoked) is still signalled by the Future rejecting, preserving the
/// existing classify-and-emit path in `ConnectionManager`.
class ScanResult {
  final List<Device> matchedDevices;
  final List<ServiceScanFailure> failedServices;
  final ScanTerminationReason terminationReason;
  final Duration duration;

  const ScanResult({
    required this.matchedDevices,
    required this.failedServices,
    required this.terminationReason,
    required this.duration,
  });
}

/// A single discovery-service failure surfaced through [ScanResult].
/// `serviceName` is the Dart runtime type of the failing
/// `DeviceDiscoveryService`, suitable for logs and debugging but not
/// part of any public contract.
class ServiceScanFailure {
  final String serviceName;
  final Object error;
  final StackTrace stackTrace;

  const ServiceScanFailure({
    required this.serviceName,
    required this.error,
    required this.stackTrace,
  });
}
