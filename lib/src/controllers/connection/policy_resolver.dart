import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/scale.dart';

/// Action `ConnectionManager` should take for the machine phase of a
/// connect cycle, once the scan has completed.
///
/// Sealed so callers must handle every variant — there's no silent
/// default when a new case is added.
sealed class MachinePolicyAction {
  const MachinePolicyAction();
}

/// Auto-connect this specific machine.
final class ConnectMachineAction extends MachinePolicyAction {
  final De1Interface machine;
  const ConnectMachineAction(this.machine);
}

/// Present a picker so the user can choose which machine to connect.
final class MachinePickerAction extends MachinePolicyAction {
  const MachinePickerAction();
}

/// Nothing to do — either no machines were found or the preferred
/// machine wasn't discovered during the scan.
final class NoMachineAction extends MachinePolicyAction {
  /// Whether any machines were matched at all. Callers use this to
  /// decide between `phase: idle` with and without the
  /// `pendingAmbiguity: machinePicker` hint (preferred-set-but-
  /// not-found still surfaces the picker when there are other
  /// machines available).
  final bool hasOtherMachines;
  const NoMachineAction({required this.hasOtherMachines});
}

/// Decide what to do with the machine phase given the scan snapshot.
///
/// Rules:
///   - If `preferredMachineId` is set, early-connect would have
///     handled the happy path — reaching post-scan means the
///     preferred device wasn't discovered. Show a picker if any
///     other machines appeared, otherwise idle.
///   - If no preferred is set: auto-connect iff exactly one machine
///     was found; otherwise picker (>1) or idle (0).
MachinePolicyAction resolveMachinePolicy({
  required List<De1Interface> machines,
  required String? preferredMachineId,
}) {
  if (preferredMachineId != null) {
    if (machines.isNotEmpty) return const MachinePickerAction();
    return const NoMachineAction(hasOtherMachines: false);
  }
  if (machines.isEmpty) {
    return const NoMachineAction(hasOtherMachines: false);
  }
  if (machines.length == 1) return ConnectMachineAction(machines.first);
  return const MachinePickerAction();
}

/// Action `ConnectionManager` should take for the scale phase.
sealed class ScalePolicyAction {
  const ScalePolicyAction();
}

/// Auto-connect this specific scale.
final class ConnectScaleAction extends ScalePolicyAction {
  final Scale scale;
  const ConnectScaleAction(this.scale);
}

/// Present a picker so the user can choose which scale to connect.
final class ScalePickerAction extends ScalePolicyAction {
  const ScalePickerAction();
}

/// Nothing to do — no scales were found, or the preferred scale
/// wasn't discovered and no alternatives are available.
final class NoScaleAction extends ScalePolicyAction {
  const NoScaleAction();
}

/// Decide what to do with the scale phase given the scan snapshot.
///
/// Rules:
///   - If `preferredScaleId` is set and that exact id is in `scales`:
///     connect it. If preferred is set but not found, show a picker
///     when other scales exist; otherwise no action.
///   - If no preferred: auto-connect iff exactly one scale; picker
///     for >1; no action for 0.
ScalePolicyAction resolveScalePolicy({
  required List<Scale> scales,
  required String? preferredScaleId,
}) {
  if (preferredScaleId != null) {
    final match = scales
        .where((s) => s.deviceId == preferredScaleId)
        .firstOrNull;
    if (match != null) return ConnectScaleAction(match);
    if (scales.isNotEmpty) return const ScalePickerAction();
    return const NoScaleAction();
  }
  if (scales.length == 1) return ConnectScaleAction(scales.first);
  if (scales.length > 1) return const ScalePickerAction();
  return const NoScaleAction();
}
