import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/connection/disconnect_expectations.dart';
import 'package:reaprime/src/controllers/connection/status_publisher.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/connection_manager.dart'
    show ConnectionPhase;
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as device;

/// Watches the machine and scale connection streams for the
/// lifetime of a [ConnectionManager]. Tracks the latest observed state
/// of each device and emits an error (through [StatusPublisher]) when
/// a disconnect arrives that wasn't already announced by the app
/// (via [DisconnectExpectations]).
///
/// Also publishes `phase: idle` on machine disconnect so the UI can
/// react even if the caller didn't issue an explicit `connect()`.
///
/// Extracted from ConnectionManager as part of comms-harden Phase 4
/// (roadmap items 15 and 19).
class DisconnectSupervisor {
  static final _log = Logger('DisconnectSupervisor');

  final Stream<De1Interface?> _machineStream;
  final Stream<device.ConnectionState> _scaleStream;
  final StatusPublisher _statusPublisher;
  final DisconnectExpectations _expectations;
  final bool Function() _isConnectingMachine;
  final bool Function() _isConnectingScale;
  final String? Function() _scaleLastConnectedId;
  final String? Function() _preferredScaleId;

  De1Interface? _latestDe1;
  device.ConnectionState _latestScaleState =
      device.ConnectionState.discovered;
  String? _lastKnownMachineId;

  StreamSubscription<De1Interface?>? _machineSub;
  StreamSubscription<device.ConnectionState>? _scaleSub;

  DisconnectSupervisor({
    required Stream<De1Interface?> machineStream,
    required Stream<device.ConnectionState> scaleStream,
    required StatusPublisher statusPublisher,
    required DisconnectExpectations expectations,
    required bool Function() isConnectingMachine,
    required bool Function() isConnectingScale,
    required String? Function() scaleLastConnectedId,
    required String? Function() preferredScaleId,
  })  : _machineStream = machineStream,
        _scaleStream = scaleStream,
        _statusPublisher = statusPublisher,
        _expectations = expectations,
        _isConnectingMachine = isConnectingMachine,
        _isConnectingScale = isConnectingScale,
        _scaleLastConnectedId = scaleLastConnectedId,
        _preferredScaleId = preferredScaleId {
    _start();
  }

  /// `true` if the machine stream has last emitted a non-null
  /// `De1Interface`. Replaces the old `_machineConnected` flag —
  /// this is a live view of the stream, not parallel state.
  bool get isMachineConnected => _latestDe1 != null;

  /// `true` if the scale stream has last emitted `connected`.
  bool get isScaleConnected =>
      _latestScaleState == device.ConnectionState.connected;

  /// Pre-null the tracked de1 view so the next null emission from
  /// [machineStream] doesn't trigger the disconnect path. Used by
  /// [ConnectionManager.disconnectMachine] which publishes
  /// `phase: idle` itself and doesn't want a redundant emission from
  /// the supervisor.
  void markMachineOffline() {
    _latestDe1 = null;
  }

  void _start() {
    _machineSub = _machineStream.listen((de1) {
      final hadMachine = _latestDe1 != null;
      _latestDe1 = de1;
      if (de1 != null) {
        _lastKnownMachineId = de1.deviceId;
        return;
      }
      if (hadMachine && !_isConnectingMachine()) {
        _log.fine('Machine disconnected');
        _statusPublisher.publish(
          _statusPublisher.current.copyWith(phase: ConnectionPhase.idle),
        );
        final id = _lastKnownMachineId;
        if (id != null) {
          _handleMachineDisconnect(id);
        }
      }
    });

    _scaleSub = _scaleStream.listen((state) {
      final wasConnected =
          _latestScaleState == device.ConnectionState.connected;
      _latestScaleState = state;
      _log.fine('scale connection update: ${state.name}');
      if (wasConnected &&
          state == device.ConnectionState.disconnected &&
          !_isConnectingScale()) {
        final id = _scaleLastConnectedId() ?? _preferredScaleId();
        if (id != null) {
          _handleScaleDisconnect(id);
        }
      }
    });
  }

  void _handleMachineDisconnect(String deviceId) {
    if (_expectations.consume(deviceId)) {
      _log.fine('Machine $deviceId: expected disconnect, suppressing error');
      return;
    }
    _statusPublisher.emitError(ConnectionError(
      kind: ConnectionErrorKind.machineDisconnected,
      severity: ConnectionErrorSeverity.error,
      timestamp: DateTime.now().toUtc(),
      deviceId: deviceId,
      message: 'Machine disconnected unexpectedly.',
      suggestion:
          'Check the machine is powered on and in range, then reconnect.',
    ));
  }

  void _handleScaleDisconnect(String deviceId) {
    if (_expectations.consume(deviceId)) {
      _log.fine('Scale $deviceId: expected disconnect, suppressing error');
      return;
    }
    _statusPublisher.emitError(ConnectionError(
      kind: ConnectionErrorKind.scaleDisconnected,
      severity: ConnectionErrorSeverity.error,
      timestamp: DateTime.now().toUtc(),
      deviceId: deviceId,
      message: 'Scale disconnected unexpectedly.',
      suggestion:
          'The scale may have powered off or moved out of range. '
          'Wake the scale and reconnect.',
    ));
  }

  /// Drive the same error-emission path the stream listener would
  /// take when it sees an unexpected disconnect for [deviceId].
  /// Used by ConnectionManager's `@visibleForTesting` wrappers so
  /// tests can simulate disconnect events without touching the
  /// underlying streams.
  void notifyMachineDisconnected(String deviceId) =>
      _handleMachineDisconnect(deviceId);

  void notifyScaleDisconnected(String deviceId) =>
      _handleScaleDisconnect(deviceId);

  /// Cancel both stream subscriptions. Safe to call more than once.
  void dispose() {
    _machineSub?.cancel();
    _scaleSub?.cancel();
    _machineSub = null;
    _scaleSub = null;
  }
}
