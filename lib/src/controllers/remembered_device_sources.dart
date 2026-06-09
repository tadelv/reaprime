import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';
import 'package:reaprime/src/models/errors.dart';

/// Pure mappers that turn the `De1Controller.de1` / `ScaleController`
/// connection signals into the `RememberedDevice?` stream values the
/// [RememberedDevicesController] consumes. Extracted from `main.dart` so the
/// "what gets remembered" decision is unit-testable without the full wiring.

/// A connected machine → its remembered record; `null` when none is connected.
RememberedDevice? rememberedFromMachine(Device? machine) =>
    machine == null ? null : RememberedDevice.fromDevice(machine);

/// A scale `connectionState` transition → a remembered record, or `null` unless
/// the state is `connected`.
///
/// [connectedScale] is the scale lookup (`ScaleController.connectedScale`),
/// passed as a thunk so this stays testable without a real controller. The
/// `state.name` compare avoids the `material.dart` `ConnectionState` import
/// clash. A `DeviceNotConnectedException` is the benign race where the stream
/// reports `connected` but a disconnect already nulled the scale — any other
/// exception is a real defect and is allowed to surface.
RememberedDevice? rememberedFromScaleState(
  ConnectionState state,
  Device Function() connectedScale,
) {
  if (state.name != 'connected') return null;
  try {
    return RememberedDevice.fromDevice(connectedScale());
  } on DeviceNotConnectedException {
    return null;
  }
}
