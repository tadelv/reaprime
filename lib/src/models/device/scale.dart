import 'device.dart';

abstract class Scale extends Device {
  Stream<ScaleSnapshot> get currentSnapshot;

  Future<void> tare();

  /// Tell scale to go to sleep (turn off display)
  /// If scale doesn't support display control, should disconnect instead
  Future<void> sleepDisplay();

  /// Tell the scale to wake the display
  /// If scale doesn't support display control, this is a no-op
  Future<void> wakeDisplay();

  Future<void> startTimer() async {}
  Future<void> stopTimer() async {}
  Future<void> resetTimer() async {}
}

/// A scale that mutates its physical device on a normal [Device.disconnect]
/// (e.g. the BLE Decent Scale powers the scale OFF on disconnect), and can
/// instead release the connection WITHOUT that side effect.
///
/// The controller uses this when it hands the active-scale role to another
/// transport of the SAME physical scale — switching between the BLE/USB/WiFi
/// views of one Half Decent Scale. A plain disconnect there would power the
/// shared physical scale off mid-switch, defeating the switch. Scales without
/// a destructive disconnect don't need to implement this.
abstract interface class TransportHandoffScale {
  /// Drop the active connection without the disconnect-time power-off.
  Future<void> disconnectForHandoff();
}

class ScaleSnapshot {
  final DateTime timestamp;
  final double weight;
  final int batteryLevel;
  final Duration? timerValue;

  /// Flow rate in g/s **as computed by the device itself**, or `null` when the
  /// device cannot compute one.
  ///
  /// Almost every scale leaves this `null`: a BLE scale reports weight only, so
  /// the app must estimate flow from the weight series — that is what
  /// [ScaleController]'s estimators are for. A scale that derives flow
  /// on-hardware from the load cell it owns (the Bengle's integrated scale, via
  /// the `0xA013` `GFlow` field) reports it here, and [ScaleController] passes
  /// it through verbatim instead of re-deriving it. Re-estimating a number the
  /// device already computed is strictly worse — the estimators need roughly a
  /// second to converge on a value the device has correct at the first sample.
  final double? flow;

  ScaleSnapshot({
    required this.timestamp,
    required this.weight,
    required this.batteryLevel,
    this.timerValue,
    this.flow,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'weight': weight,
      'batteryLevel': batteryLevel,
      'timerValue': timerValue?.inMilliseconds,
    };
  }
}

