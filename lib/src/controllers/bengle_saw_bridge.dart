import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/errors.dart';

/// Reflects `WorkflowContext.targetYield` into the connected
/// `BengleInterface`'s autonomous stop-at-weight MMR. Bengle FW stops
/// the shot when its integrated scale reaches the target — the app
/// only has to keep FW informed.
///
/// Two listeners:
/// 1. `WorkflowController.addListener` — debounced writes after the
///    user (or REST) edits the target yield. Mirrors
///    `WorkflowDeviceSync` for the profile push.
/// 2. `De1Controller.de1` stream — re-applies the current target the
///    moment a `BengleInterface` machine becomes connected (covers a
///    Bengle reboot or a late connect after the app has been editing
///    the workflow).
///
/// Generation-token + cancellable Timer pattern mirrors
/// `De1Controller._shotSettingsDebounce` (comms-harden #5) so a
/// disconnect during the debounce window cleanly drops the pending
/// write instead of throwing on a stale `connectedDe1()`.
class BengleSawBridge {
  BengleSawBridge({
    required WorkflowController workflowController,
    required De1Controller de1Controller,
    this.debounce = const Duration(milliseconds: 250),
  })  : _workflow = workflowController,
        _de1 = de1Controller {
    _lastPushed = _currentTargetYield();
    _workflow.addListener(_onWorkflowChange);
    _de1Sub = _de1.de1.listen(_onDe1Change);
  }

  final WorkflowController _workflow;
  final De1Controller _de1;
  final Duration debounce;
  final Logger _log = Logger('BengleSawBridge');

  StreamSubscription? _de1Sub;
  Timer? _debounceTimer;
  int _generation = 0;
  double? _lastPushed;

  double _currentTargetYield() =>
      _workflow.currentWorkflow.context?.targetYield ?? 0.0;

  void _onWorkflowChange() {
    final next = _currentTargetYield();
    if (next == _lastPushed) return;
    _debounceTimer?.cancel();
    final generation = ++_generation;
    _debounceTimer = Timer(debounce, () => _push(next, generation));
  }

  void _onDe1Change(dynamic device) {
    if (device is! BengleInterface) return;
    // New Bengle connected — re-assert the current target so a Bengle
    // reboot or late connect doesn't leave FW at its default.
    final next = _currentTargetYield();
    final generation = ++_generation;
    _push(next, generation);
  }

  Future<void> _push(double grams, int generation) async {
    if (generation != _generation) {
      _log.fine('SAW write superseded (gen=$generation, current=$_generation)');
      return;
    }
    final machine = _de1.connectedDe1OrNull;
    if (machine is! BengleInterface) {
      _log.fine('SAW write skipped — connected machine is not Bengle');
      return;
    }
    try {
      await machine.setStopAtWeightTarget(grams);
      _lastPushed = grams;
      _log.info('SAW target written: ${grams}g');
    } on DeviceNotConnectedException {
      _log.fine('SAW write aborted — machine disconnected mid-call');
    } catch (e, st) {
      _log.warning('SAW write failed', e, st);
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
