import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/led_strip.dart';
import 'package:reaprime/src/models/device/scale.dart';

/// Marker interface for Bengle-specific machine API. Currently empty —
/// Bengle inherits the full DE1 surface unchanged.
///
/// **Future capability methods land here.** When a Bengle capability
/// (cup warmer, integrated scale, LED strip, milk probe) needs a public
/// API method, add it to this interface and implement it on `Bengle`.
/// Capability-internal state and helpers belong in their own
/// `Capability` mixins on `UnifiedDe1` (see the protected surface in
/// `UnifiedDe1` for the contract: `readMmrInt`, `readMmrScaled`,
/// `writeMmrInt`, `writeMmrScaled`, `notificationsFor`, etc.).
abstract class BengleInterface extends De1Interface {
  /// Set the cup-warmer mat target temperature in °C. Range 0.0–80.0.
  /// `0.0` turns the mat off — there is no separate enable flag in FW.
  /// Implementations clamp out-of-range values before writing.
  Future<void> setCupWarmerTemperature(double celsius);

  /// Read the current cup-warmer mat setpoint in °C.
  Future<double> getCupWarmerTemperature();

  /// Live snapshot stream from the integrated scale.
  ///
  /// Real `Bengle` wires this to `IntegratedScaleCapability.weightSnapshot`
  /// (notify endpoint TBD with FW; lands in Task 7). `MockBengle` synthesises
  /// weight by integrating `MockDe1`'s simulated flow.
  Stream<ScaleSnapshot> get weightSnapshot;

  /// Tare the integrated scale. Subsequent snapshots have weight relative
  /// to this zero.
  Future<void> tareIntegratedScale();

  /// Current LED strip state stream.
  Stream<LedStripState> get ledStripState;

  /// One-shot read of the current LED strip state.
  Future<LedStripState> getLedStripState();

  /// Set the front/back LED strip colour. All channels 0–255.
  Future<void> setLedStrip(LedStripState state);
}
