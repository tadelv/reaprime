import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/errors.dart';

/// Reflects `WorkflowContext.targetYield` into the connected
/// `BengleInterface`'s autonomous stop-at-weight MMR. Bengle FW stops
/// the shot when its integrated scale reaches the target — the app
/// only has to keep FW informed.
///
/// Two listeners:
/// 1. `WorkflowController.addListener` — debounced writes after the
///    user (or REST) edits the target yield. Same single-writer shape
///    as `lib/src/controllers/workflow_device_sync.dart` (profile
///    push), plus a debounce because target-yield edits can come from
///    a slider drag.
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

  StreamSubscription<De1Interface?>? _de1Sub;
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

  void _onDe1Change(De1Interface? device) {
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
      // Re-check the generation after the await: a workflow edit
      // landing while the write was in flight bumped it and scheduled
      // a newer debounce. Updating `_lastPushed` here would stamp the
      // stale value and could short-circuit the next change-equality
      // check in `_onWorkflowChange`.
      if (generation == _generation) {
        _lastPushed = grams;
      }
      _log.info('SAW target written: ${grams}g');
    } on DeviceNotConnectedException {
      // `_lastPushed` deliberately not updated — on Bengle reconnect
      // `_onDe1Change` re-applies the current target, so the failed
      // write self-recovers without needing an explicit retry.
      _log.fine('SAW write aborted — machine disconnected mid-call');
    } catch (e, st) {
      // Same recovery story as DeviceNotConnectedException: leave
      // `_lastPushed` alone so the next workflow edit (different
      // value) or reconnect re-attempts. Identical-value retries
      // after a transient failure are not handled — the bar for SAW
      // is "FW eventually learns the target before the next shot",
      // not "every write succeeds".
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
