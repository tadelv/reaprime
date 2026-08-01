import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/errors.dart';

/// Reflects `SteamSettings.stopAtTemperature` into the connected
/// Bengle's `setStopAtTemperatureTarget` MMR endpoint. Mirrors
/// [BengleSawBridge] — same debounce + serialized latest-value drain +
/// re-assert on reconnect shape.
///
/// **Scaffolding.** While the FW MMR slot is stubbed
/// (`BengleSteamMmr.stopAtTemperatureTarget.address == 0x00000000`),
/// `Bengle.setStopAtTemperatureTarget` caches the value locally and
/// log-onces; this bridge keeps the cache consistent with the workflow
/// so the day FW lands, the write hits the wire automatically with no
/// app-side changes.
class BengleSteamStopBridge {
  BengleSteamStopBridge({
    required WorkflowController workflowController,
    required De1Controller de1Controller,
    this.debounce = const Duration(milliseconds: 250),
  }) : _workflow = workflowController,
       _de1 = de1Controller {
    _lastPushed = _currentTarget();
    _workflow.addListener(_onWorkflowChange);
    _de1Sub = _de1.de1.listen(_onDe1Change);
  }

  final WorkflowController _workflow;
  final De1Controller _de1;
  final Duration debounce;
  final Logger _log = Logger('BengleSteamStopBridge');

  StreamSubscription<De1Interface?>? _de1Sub;
  Timer? _debounceTimer;
  double? _lastPushed;
  double? _desired;
  double? _inFlight;
  bool _forcePush = false;
  bool _pushing = false;
  bool _disposed = false;

  double _currentTarget() =>
      _workflow.currentWorkflow.steamSettings.stopAtTemperature;

  void _onWorkflowChange() {
    final next = _currentTarget();
    _forcePush = false;
    if (next == _lastPushed && (_inFlight == null || _inFlight == next)) {
      _desired = null;
      _debounceTimer?.cancel();
      _debounceTimer = null;
      return;
    }
    _desired = next;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_drain());
    });
  }

  void _onDe1Change(De1Interface? device) {
    if (device is! BengleInterface) return;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _desired = _currentTarget();
    _forcePush = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_pushing || _disposed) return;
    _pushing = true;
    try {
      while (!_disposed) {
        final celsius = _desired;
        if (celsius == null || (!_forcePush && celsius == _lastPushed)) {
          _desired = null;
          _forcePush = false;
          return;
        }
        final machine = _de1.connectedDe1OrNull;
        if (machine is! BengleInterface) {
          _log.fine(
            'Steam-stop write skipped — connected machine is not Bengle',
          );
          return;
        }
        _inFlight = celsius;
        try {
          await machine.setStopAtTemperatureTarget(celsius);
          if (_disposed) return;
          _lastPushed = celsius;
          _forcePush = false;
          if (_desired == celsius) _desired = null;
          _log.info('Stop-at-temperature target written: $celsius°C');
        } on DeviceNotConnectedException {
          _log.fine(
            'Steam-stop write aborted — machine disconnected mid-call',
          );
          if (_desired == celsius) return;
        } catch (e, st) {
          _log.warning('Steam-stop write failed', e, st);
          if (_desired == celsius) return;
        } finally {
          _inFlight = null;
        }
      }
    } finally {
      _pushing = false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _workflow.removeListener(_onWorkflowChange);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _desired = null;
    await _de1Sub?.cancel();
    _de1Sub = null;
  }
}
