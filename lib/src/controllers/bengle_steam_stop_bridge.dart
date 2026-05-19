import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/errors.dart';

/// Reflects `SteamSettings.stopAtTemperature` into the connected
/// Bengle's `setStopAtTemperatureTarget` MMR endpoint. Mirrors
/// [BengleSawBridge] — same debounce + generation-token + re-assert on
/// reconnect shape.
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
  })  : _workflow = workflowController,
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
  int _generation = 0;
  double? _lastPushed;

  double _currentTarget() =>
      _workflow.currentWorkflow.steamSettings.stopAtTemperature;

  void _onWorkflowChange() {
    final next = _currentTarget();
    if (next == _lastPushed) return;
    _debounceTimer?.cancel();
    final generation = ++_generation;
    _debounceTimer = Timer(debounce, () => _push(next, generation));
  }

  void _onDe1Change(De1Interface? device) {
    if (device is! BengleInterface) return;
    final next = _currentTarget();
    final generation = ++_generation;
    _push(next, generation);
  }

  Future<void> _push(double celsius, int generation) async {
    if (generation != _generation) {
      _log.fine('Steam-stop write superseded '
          '(gen=$generation, current=$_generation)');
      return;
    }
    final machine = _de1.connectedDe1OrNull;
    if (machine is! BengleInterface) {
      _log.fine('Steam-stop write skipped — connected machine is not Bengle');
      return;
    }
    try {
      await machine.setStopAtTemperatureTarget(celsius);
      if (generation == _generation) {
        _lastPushed = celsius;
      }
      _log.info('Stop-at-temperature target written: $celsius°C');
    } on DeviceNotConnectedException {
      _log.fine('Steam-stop write aborted — machine disconnected mid-call');
    } catch (e, st) {
      _log.warning('Steam-stop write failed', e, st);
    }
  }

  Future<void> dispose() async {
    _workflow.removeListener(_onWorkflowChange);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _de1Sub?.cancel();
    _de1Sub = null;
  }
}
