import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/scan_report.dart';

/// Mutable tracker used during a scan to accumulate connection-attempt
/// results before building the immutable [MatchedDevice].
///
/// Public within the `lib/src/controllers/connection/` module so tests
/// can construct one directly; not part of the public
/// `ConnectionManager` API.
class MatchedDeviceTracker {
  final String deviceName;
  final String deviceId;
  final DeviceType deviceType;
  bool connectionAttempted = false;
  ConnectionResult? connectionResult;

  MatchedDeviceTracker({
    required this.deviceName,
    required this.deviceId,
    required this.deviceType,
  });

  MatchedDevice toMatchedDevice() => MatchedDevice(
        deviceName: deviceName,
        deviceId: deviceId,
        deviceType: deviceType,
        connectionAttempted: connectionAttempted,
        connectionResult: connectionResult,
      );
}

/// Accumulates per-device connection-attempt results over the lifetime
/// of one scan and builds the final [ScanReport] from them.
///
/// Idempotent `seed` so the early-connect path and the post-scan
/// snapshot can share one builder without clobbering each other.
///
/// Extracted from ConnectionManager as part of comms-harden Phase 4
/// (roadmap item 15 — god-class split).
class ScanReportBuilder {
  final DateTime scanStartTime;
  final Map<String, MatchedDeviceTracker> _trackers = {};

  /// Adapter state captured at scan start. Set by the orchestrator
  /// via [recordAdapterStateAtStart]; used by [build] so callers
  /// don't have to thread it through a separate arg.
  AdapterState _adapterStateAtStart = AdapterState.unknown;

  ScanReportBuilder({required this.scanStartTime});

  /// Record the adapter state sampled at scan start. The end state is
  /// supplied to [build] so the builder captures a true start/end pair
  /// around the whole scan+connect window (comms-harden #27).
  void recordAdapterStateAtStart(AdapterState state) {
    _adapterStateAtStart = state;
  }

  /// Ensure a tracker exists for [d]. Does not clobber an existing
  /// entry — `putIfAbsent` semantics so recorded attempt results
  /// survive a second seed call.
  void seed(Device d) {
    _trackers.putIfAbsent(
      d.deviceId,
      () => MatchedDeviceTracker(
        deviceName: d.name,
        deviceId: d.deviceId,
        deviceType: d.type,
      ),
    );
  }

  /// Mark that a connection attempt was started for [deviceId]. No-op
  /// if no tracker exists for that id (shouldn't happen in practice
  /// since connect paths seed before attempting).
  void markAttempted(String deviceId) {
    _trackers[deviceId]?.connectionAttempted = true;
  }

  /// Record the outcome of a connect attempt for [deviceId]. No-op if
  /// no tracker exists.
  void recordResult(String deviceId, ConnectionResult result) {
    _trackers[deviceId]?.connectionResult = result;
  }

  /// Build the immutable [ScanReport]. Does not clear the builder —
  /// safe to call again, but typically called once per scan cycle.
  ScanReport build({
    required String? preferredMachineId,
    required String? preferredScaleId,
    required ScanTerminationReason terminationReason,
    required AdapterState adapterStateAtEnd,
  }) {
    final matchedDevices =
        _trackers.values.map((t) => t.toMatchedDevice()).toList();
    return ScanReport(
      totalBleDevicesSeen: matchedDevices.length,
      matchedDevices: matchedDevices,
      scanDuration: DateTime.now().difference(scanStartTime),
      adapterStateAtStart: _adapterStateAtStart,
      adapterStateAtEnd: adapterStateAtEnd,
      scanTerminationReason: terminationReason,
      preferredMachineId: preferredMachineId,
      preferredScaleId: preferredScaleId,
    );
  }

  /// Render a multi-line human-readable summary for logs.
  static String format(ScanReport report) {
    final buf = StringBuffer('Scan report: ');
    buf.write('${report.matchedDevices.length} devices matched, ');
    buf.write('duration=${report.scanDuration.inMilliseconds}ms, ');
    buf.write('termination=${report.scanTerminationReason.name}');

    if (report.preferredMachineId != null) {
      final found = report.matchedDevices
          .any((d) => d.deviceId == report.preferredMachineId);
      buf.write(
        ', preferred machine ${report.preferredMachineId} '
        '${found ? "found" : "NOT found"}',
      );
    }
    if (report.preferredScaleId != null) {
      final found = report.matchedDevices
          .any((d) => d.deviceId == report.preferredScaleId);
      buf.write(
        ', preferred scale ${report.preferredScaleId} '
        '${found ? "found" : "NOT found"}',
      );
    }

    for (final d in report.matchedDevices) {
      buf.write('\n  ${d.deviceName} (${d.deviceId}, ${d.deviceType.name})');
      if (d.connectionAttempted) {
        final result = d.connectionResult;
        if (result == null) {
          buf.write(' — connection attempted, no result');
        } else if (result.success) {
          buf.write(' — connected');
        } else if (result.error != null) {
          buf.write(' — connection failed: ${result.error}');
        } else {
          buf.write(' — skipped');
        }
      }
    }

    return buf.toString();
  }
}
