import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/errors.dart';

/// Single writer of `setProfile` for both REST (`PUT /api/v1/workflow`)
/// and UI (`ProfileTile` picker) paths. Subscribes to
/// `WorkflowController` changes and pushes the profile to the DE1 on
/// value diff; equality is handled by `Profile`'s `Equatable`
/// implementation.
///
/// Uploads are strictly serialized and coalesced (queue-with-coalesce):
/// a profile upload is a stateful BLE multi-write sequence (header
/// declaring N frames, then each frame), so two concurrent uploads
/// interleave on the BLE queue and wedge the firmware's profile-receive
/// state machine. While an upload is in flight, later workflow changes
/// only update the desired profile; when the upload finishes, the latest
/// desired profile is pushed and intermediates are skipped.
///
/// A failed upload (e.g. a GATT write timeout on a flaky link) is retried
/// automatically with capped backoff ([retryDelays]) until it lands, is
/// superseded, or the machine disconnects — a fresh upload restarts the
/// firmware receive state machine from the header, so the machine can
/// never stay wedged while connected. Retries are deliberately not gated
/// on machine state: pushes mid-shot are already possible today, and a
/// wedged machine is strictly worse.
///
/// On DE1 disconnect pending retries are cancelled and the push is
/// skipped; the existing `De1Controller._setDe1Defaults` path uploads the
/// current workflow's profile on reconnect (see `defaultWorkflow`
/// assignment in `main.dart`).
class WorkflowDeviceSync {
  WorkflowDeviceSync({
    required WorkflowController workflowController,
    required De1Controller de1Controller,
    this.retryDelays = const [
      Duration(seconds: 3),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
  })  : _workflow = workflowController,
        _de1 = de1Controller {
    _lastPushedProfile = _workflow.currentWorkflow.profile;
    _workflow.addListener(_onChange);
    _de1Sub = _de1.de1.listen(_onDe1Change);
  }

  final WorkflowController _workflow;
  final De1Controller _de1;
  final Logger _log = Logger('WorkflowDeviceSync');

  /// Backoff schedule for upload retries; the last entry repeats as the cap.
  final List<Duration> retryDelays;

  /// What the device is known to hold. Stamped only after a successful
  /// upload; cleared when an upload fails, since a mid-sequence failure
  /// leaves the device profile state unknown (comms-harden #1).
  Profile? _lastPushedProfile;

  /// Latest profile the device should end up with. Overwritten freely by
  /// workflow changes while an upload is in flight (latest wins).
  Profile? _desiredProfile;

  bool _uploading = false;
  Timer? _retryTimer;
  int _attempt = 0;

  /// Past the ramp, only every Nth failed attempt logs at WARNING.
  static const int _retryLogHeartbeat = 10;

  /// Bumped on disconnect and dispose; in-flight drains and pending retry
  /// timers capture it and bail when it changes.
  int _generation = 0;

  StreamSubscription<De1Interface?>? _de1Sub;

  void _onChange() {
    // Record the desired profile and let the drain loop decide — comparing
    // against `_lastPushedProfile` here would go stale when an upload is in
    // flight (e.g. reverting to the last-pushed profile while a newer one
    // uploads: once that lands, the device holds the newer one and the
    // revert must still be pushed).
    final next = _workflow.currentWorkflow.profile;
    if (next == _desiredProfile) {
      // Not a profile change (a non-profile workflow edit, or a re-select
      // of the same content): leave a pending retry's backoff undisturbed
      // rather than resetting a failing upload to the floor delay.
      return;
    }
    _desiredProfile = next;
    _attempt = 0;
    _cancelRetry(); // a fresh change replaces any pending retry
    unawaited(_drain());
  }

  /// Uploads the latest desired profile, one upload at a time, until the
  /// device is in sync. Concurrent calls collapse into the running loop.
  Future<void> _drain() async {
    if (_uploading) return;
    _uploading = true;
    final generation = _generation;
    try {
      while (generation == _generation) {
        final profile = _desiredProfile;
        if (profile == null || profile == _lastPushedProfile) {
          _desiredProfile = null;
          return;
        }
        try {
          await _de1.connectedDe1().setProfile(profile);
          if (generation != _generation) return;
          _lastPushedProfile = profile;
          _attempt = 0;
          // Loop again: if the desired profile advanced mid-upload, the
          // next iteration pushes it; otherwise the guard above exits.
        } on DeviceNotConnectedException {
          _log.fine(
            'DE1 not connected; skipping profile push — will sync via '
            'defaultWorkflow on next connect',
          );
          return;
        } catch (e, st) {
          if (generation != _generation) return;
          // The upload died mid-sequence: the device profile state is
          // unknown (possibly wedged mid-receive), so forget what was
          // last pushed — even a revert to it must re-upload.
          _lastPushedProfile = null;
          final delay = _scheduleRetry(generation);
          final message =
              'setProfile failed (attempt $_attempt); retrying in '
              '${delay.inMilliseconds}ms';
          // Retries are unbounded, so a persistent fault would otherwise
          // emit a stack-trace WARNING every capped delay forever. Warn
          // while the backoff ramps and on a periodic heartbeat after
          // that; log the rest quietly.
          if (_attempt <= retryDelays.length ||
              _attempt % _retryLogHeartbeat == 0) {
            _log.warning(message, e, st);
          } else {
            _log.fine(message, e);
          }
          return;
        }
      }
    } finally {
      _uploading = false;
    }
  }

  /// Arms the retry timer with the next backoff delay and returns it.
  Duration _scheduleRetry(int generation) {
    final delay = retryDelays[min(_attempt, retryDelays.length - 1)];
    _attempt++;
    _retryTimer = Timer(delay, () {
      if (generation != _generation) return;
      unawaited(_drain());
    });
    return delay;
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _onDe1Change(De1Interface? device) {
    if (device != null) return;
    // Machine gone: cancel retries and forget desired state. The reconnect
    // path re-uploads the current workflow profile via defaultWorkflow.
    _generation++;
    _cancelRetry();
    _desiredProfile = null;
    _attempt = 0;
  }

  void dispose() {
    _workflow.removeListener(_onChange);
    _generation++;
    _cancelRetry();
    _de1Sub?.cancel();
    _de1Sub = null;
  }
}
