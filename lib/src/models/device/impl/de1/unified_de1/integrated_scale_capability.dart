part of 'unified_de1.dart';

// NOTE: the integrated scale is NOT a separate BLE characteristic —
// weight rides on the 0xA013 BengleShotSample stream, already net of tare in
// firmware. The early `BengleScaleEndpoint` null-UUID scaffolding that assumed
// dedicated weight/control endpoints was the wrong model and has been dropped.

/// MMR addresses for the integrated scale.
///
/// Co-located with [IntegratedScaleCapability] so the mixin owns its
/// wire identifiers (mirrors how `LedStripCapability` owns
/// [BengleLedEndpoint]) — the pattern rule: the capability owns the
/// registers it writes.
enum BengleScaleMmr implements MmrAddress {
  /// Autonomous stop-at-weight target in grams. Firmware
  /// `EndOfShotWeight` (`0x00803864`, RWD): the Bengle stops the shot
  /// when its integrated scale reaches this weight. `0.0` disables SAW
  /// (mirrors cup-warmer `0.0 = off`). Encoded as `scaledFloat` with
  /// scale factor 100 — centigrams on the wire (`round(g × 100)`, matching
  /// de1plus `int(round(weight × 100))`, `de1_comms.tcl:1164`). Max
  /// 10000 g (the firmware register table); the firmware never clamps Bengle registers
  ///, so reaprime is
  /// the sole guard.
  stopAtWeightTarget(
    0x00803864,
    4,
    MmrValueKind.scaledFloat,
    'EndOfShotWeight',
    min: 0,
    max: 1000000, // 10000.0 g × 100
    readScale: 0.01,
    writeScale: 100.0,
  ),

  /// Instant tare trigger. Firmware `ScaleTare` (`0x0080388C`, RWT):
  /// writing any value performs an immediate tare (de1plus writes
  /// `1`). Not a stored value — `int32` write-trigger; reading it
  /// returns 0. Confirm the tare by watching `Weight` drop toward 0,
  /// never the `0xA013` Flags bit (a `LastTARE` value proxy at best;
  /// older firmware hardcodes it to 0).
  scaleTare(
    0x0080388C,
    4,
    MmrValueKind.int32,
    'ScaleTare',
  );

  const BengleScaleMmr(
    this.address,
    this.length,
    this.kind,
    this.description, {
    this.readScale = 1.0,
    this.writeScale = 1.0,
    this.min,
    this.max,
  });

  @override
  final int address;
  @override
  final int length;
  @override
  final MmrValueKind kind;
  final String description;
  @override
  final double readScale;
  @override
  final double writeScale;
  @override
  final int? min;
  @override
  final int? max;

  @override
  String get name => (this as Enum).name;
}

/// Stateful capability for Bengle's integrated scale.
///
/// Bridges the `0xA013` BengleShotSample frame's integrated-scale Weight
/// into the standard scale pipeline. Lifecycle is managed by the
/// concrete `Bengle` device — call [initIntegratedScale] from
/// `onConnect`, [disposeIntegratedScale] from `onDisconnect`.
/// `UnifiedDe1.disconnect()` invokes `onDisconnect()` for the device, so
/// `disposeIntegratedScale()` runs on every real disconnect. The
/// capability is also re-init-safe: `initIntegratedScale()` recreates
/// `_bengleWeight` if a previous dispose closed it, so a reconnect on
/// the same instance restores a live stream.
mixin IntegratedScaleCapability on UnifiedDe1 {
  BehaviorSubject<ScaleSnapshot> _bengleWeight =
      BehaviorSubject<ScaleSnapshot>();
  StreamSubscription<ByteData>? _bengleWeightSub;

  /// App-side cache of the SAW target in grams. `0.0` = SAW off.
  /// Seeded so late subscribers see the current value immediately.
  BehaviorSubject<double> _sawTarget = BehaviorSubject<double>.seeded(0.0);

  /// Live weight stream from the integrated scale (one [ScaleSnapshot] per
  /// valid `0xA013` frame).
  Stream<ScaleSnapshot> get weightSnapshot => _bengleWeight.stream;

  /// Current stop-at-weight target in grams (`0.0` = SAW off).
  Stream<double> get stopAtWeightTarget => _sawTarget.stream;

  /// Start bridging `0xA013` Weight into the scale pipeline.
  ///
  /// The 0xA013 subscription itself is enabled by `UnifiedDe1.onConnect`
  ///; here we just listen to the transport's already-guarded frame
  /// stream. Re-init-safe: cancels any prior subscription first (a reconnect
  /// calls this again), and if a previous [disposeIntegratedScale] closed the
  /// subjects, fresh ones are created so that listeners attaching after a
  /// reconnect see a live stream rather than an immediately-done one.
  Future<void> initIntegratedScale() async {
    if (_bengleWeight.isClosed) {
      _bengleWeight = BehaviorSubject<ScaleSnapshot>();
    }
    if (_sawTarget.isClosed) {
      _sawTarget = BehaviorSubject<double>.seeded(0.0);
    }
    await _bengleWeightSub?.cancel();
    _bengleWeightSub = _transport.bengleShotSample.listen(
      _handleBengleShotSample,
    );
  }

  /// Cancel the weight subscription and close the snapshot subject.
  Future<void> disposeIntegratedScale() async {
    await _bengleWeightSub?.cancel();
    _bengleWeightSub = null;
    if (!_bengleWeight.isClosed) {
      await _bengleWeight.close();
    }
    if (!_sawTarget.isClosed) {
      await _sawTarget.close();
    }
  }

  /// Tare the integrated scale. Write-trigger to the firmware
  /// `ScaleTare` register — the value is ignored, so we send `1` (matching
  /// de1plus). The firmware performs an immediate tare; subsequent `0xA013`
  /// Weight arrives already net of the new zero.
  Future<void> tareIntegratedScale() async {
    await writeMmrInt(BengleScaleMmr.scaleTare, 1);
  }

  /// Write the autonomous SAW target (grams) to the firmware
  /// `EndOfShotWeight` register. `0.0` disables SAW. Range
  /// `0.0..10000.0`; out-of-range values are clamped client-side (the
  /// firmware does not clamp its Bengle registers). The scaled write
  /// rounds (`writeMmrScaled`), matching de1plus.
  Future<void> setStopAtWeightTarget(double grams) async {
    final clamped = grams.clamp(0.0, 10000.0).toDouble();
    if (!_sawTarget.isClosed) {
      _sawTarget.add(clamped);
    }
    await writeMmrScaled(BengleScaleMmr.stopAtWeightTarget, clamped);
  }

  /// Read the SAW target back from the firmware `EndOfShotWeight`
  /// register (grams) and hydrate the cache so [stopAtWeightTarget]
  /// subscribers see the wire truth.
  Future<double> getStopAtWeightTarget() async {
    final value = await readMmrScaled(BengleScaleMmr.stopAtWeightTarget);
    if (!_sawTarget.isClosed) {
      _sawTarget.add(value);
    }
    return value;
  }

  /// Bridge a 0xA013 frame's integrated-scale weight **and firmware-computed
  /// gravimetric flow** into the scale pipeline. Weight (offset 20,
  /// U16P5 ÷32) arrives already tare-netted, so we trust it directly.
  ///
  /// GFlow rides [ScaleSnapshot.flow] so the Scale surface carries the value
  /// the firmware computed on its own load cell, rather than having
  /// [ScaleController] re-estimate flow from the weight the firmware derived it
  /// from. The same GFlow also travels on the [MachineSnapshot] (see
  /// `_parseStateAndBengleShotSample`) — sourcing both surfaces from the frame
  /// is what keeps them from disagreeing.
  ///
  /// The **Flags** byte is deliberately ignored — bit0 is a `LastTARE` value
  /// proxy at best (older firmware hardcodes 0), so a tare must be confirmed
  /// by watching the weight, not the flag.
  void _handleBengleShotSample(ByteData frame) {
    final sample = parseBengleShotSample(frame);
    if (sample == null || _bengleWeight.isClosed) return;
    _bengleWeight.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: sample.weight,
        batteryLevel: 100, // integrated scale is mains-powered; report full
        flow: sample.gFlow,
      ),
    );
  }
}
