/// Marker for devices produced by `SimulatedDeviceService`.
///
/// A simulated device's presence is governed by the **simulate setting**, not
/// by real discovery — it is "live" exactly when the setting says so. Features
/// that track *real* devices must therefore exclude simulated ones. In
/// particular, remembered-devices does not remember a simulated device (it
/// makes no sense to show a mock as "unavailable" or to "forget" it — that's a
/// setting, not a remembered real device).
///
/// Mock device classes implement this marker; new mocks should too.
abstract interface class SimulatedDevice {}
