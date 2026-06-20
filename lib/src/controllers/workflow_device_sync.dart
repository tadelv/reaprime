import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/errors.dart';

/// Single writer of `setProfile` for both REST (`PUT /api/v1/workflow`)
/// and UI (`ProfileTile` picker) paths. Subscribes to
/// `WorkflowController` changes and pushes the profile to the DE1 on
/// value diff; equality is handled by `Profile`'s `Equatable`
/// implementation.
///
/// Without this, the profile was uploaded twice on every REST-driven
/// change: once directly from `WorkflowHandler._applyPendingUpdate`
/// and again from `ProfileTile._workflowChange` listening to the same
/// `WorkflowController.notifyListeners()` tick — overlapping BLE
/// frame writes and a profile-download race on the firmware side.
///
/// On DE1 disconnect the push is skipped silently; the existing
/// `De1Controller._setDe1Defaults` path uploads the current workflow's
/// profile on reconnect (see `defaultWorkflow` assignment in
/// `main.dart`).
class WorkflowDeviceSync {
  WorkflowDeviceSync({
    required WorkflowController workflowController,
    required De1Controller de1Controller,
  })  : _workflow = workflowController,
        _de1 = de1Controller {
    _lastPushedProfile = _workflow.currentWorkflow.profile;
    _workflow.addListener(_onChange);
  }

  final WorkflowController _workflow;
  final De1Controller _de1;
  final Logger _log = Logger('WorkflowDeviceSync');

  Profile? _lastPushedProfile;
  Profile? _pushingProfile;

  void _onChange() {
    final profile = _workflow.currentWorkflow.profile;
    if (profile == _lastPushedProfile) return; // already on the device
    if (profile == _pushingProfile) return; // already uploading this profile
    _pushingProfile = profile;
    _push(profile);
  }

  Future<void> _push(Profile profile) async {
    try {
      await _de1.connectedDe1().setProfile(profile);
      // Mark pushed ONLY after the upload lands. The old behaviour marked it
      // before the write, so a failed upload (e.g. a BLE write timeout on a
      // flaky link) was still recorded as pushed — re-applying the same profile
      // then short-circuited and the DE1 never received it.
      _lastPushedProfile = profile;
    } on DeviceNotConnectedException {
      _log.fine(
        'DE1 not connected; skipping profile push — will sync via '
        'defaultWorkflow on next connect',
      );
    } catch (e, st) {
      _log.warning('setProfile failed; will retry on next workflow change', e, st);
    } finally {
      // Clear the in-flight guard so the next change (including a retry of this
      // same profile after a failure) can push again.
      if (_pushingProfile == profile) _pushingProfile = null;
    }
  }

  void dispose() {
    _workflow.removeListener(_onChange);
  }
}
