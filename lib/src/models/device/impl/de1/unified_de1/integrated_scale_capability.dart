part of 'unified_de1.dart';

// NOTE: the integrated scale is NOT a separate BLE characteristic —
// weight rides on the 0xA013 BengleShotSample stream, already net of tare in
// firmware. The early `BengleScaleEndpoint` null-UUID scaffolding that assumed
// dedicated weight/control endpoints was the wrong model and has been dropped.

/// MMR addresses for the integrated scale.
///
/// Co-located with [IntegratedScaleCapability] so the mixin owns its
/// wire identifiers (mirrors how `LedStripCapability` owns
/// [BengleLedEndpoint]). Address is stubbed `0x00000000` — FW slot
/// TBD. While stubbed the capability is a logged no-op; once FW
/// publishes the address, fill it in and the rest lights up.
enum BengleScaleMmr implements MmrAddress {
  /// Stop-at-weight target in grams. `0.0` disables autonomous SAW
  /// (mirrors cup-warmer `0.0 = off`). Encoded as `scaledFloat` with
  /// scale factor 10 — decigrams on the wire.
  stopAtWeightTarget(
    0x00000000, // TBD with FW
    4,
    MmrValueKind.scaledFloat,
    'StopAtWeightTarget',
    min: 0,
    max: 5000, // 500.0 g
    readScale: 0.1,
    writeScale: 10.0,
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

  /// Count of stub-related info logs emitted this session (avoids
  /// spam — same pattern as `LedStripCapability._stubWarningsEmitted`).
  int _sawStubWarningsEmitted = 0;

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

  /// Tare the integrated scale. Logged no-op until the `ScaleTare` MMR
  /// write-trigger lands (stop-at-weight/tare branch). Note the
  /// `0xA013` Weight already arrives net of the firmware's own tare state,
  /// so bridged weights stay correct meanwhile.
  Future<void> tareIntegratedScale() async {
    this.log.info(
      'IntegratedScaleCapability: tare is not yet wired — the ScaleTare '
      'MMR trigger lands.',
    );
  }

  /// Write the autonomous SAW target (grams) to FW. `0.0` disables
  /// SAW. Range `0.0..500.0`; out-of-range values are clamped.
  ///
  /// While [BengleScaleMmr.stopAtWeightTarget] is stubbed
  /// (`address == 0x00000000`) this is a logged no-op on the wire —
  /// the value is still cached so [stopAtWeightTarget] subscribers
  /// see the intent. Mirrors `LedStripCapability.setLedStrip`'s
  /// stub-friendly behaviour.
  Future<void> setStopAtWeightTarget(double grams) async {
    final clamped = grams.clamp(0.0, 500.0).toDouble();
    if (!_sawTarget.isClosed) {
      _sawTarget.add(clamped);
    }
    final addr = BengleScaleMmr.stopAtWeightTarget;
    if (addr.address == 0x00000000) {
      _logSawStubOnce('setStopAtWeightTarget($clamped) ignored. Awaiting FW.');
      return;
    }
    await writeMmrScaled(addr, clamped);
  }

  /// Read the SAW target from cache. While the MMR slot is stubbed
  /// the cache is authoritative; once FW publishes the address this
  /// hydrates from the wire on first call.
  Future<double> getStopAtWeightTarget() async {
    final addr = BengleScaleMmr.stopAtWeightTarget;
    if (addr.address == 0x00000000) {
      return _sawTarget.value;
    }
    final value = await readMmrScaled(addr);
    if (!_sawTarget.isClosed) {
      _sawTarget.add(value);
    }
    return value;
  }

  void _logSawStubOnce(String msg) {
    if (_sawStubWarningsEmitted < 1) {
      this.log.info('IntegratedScaleCapability: SAW endpoint unwired; $msg');
      _sawStubWarningsEmitted++;
    }
  }

  /// Bridge a 0xA013 frame's integrated-scale weight into the scale pipeline
  ///. Weight (offset 20, U16P5 ÷32) arrives already tare-netted, so
  /// we trust it directly. GFlow (gravimetric flow) and milk temp travel on
  /// the [MachineSnapshot] (see `_parseStateAndBengleShotSample`); the Scale
  /// surface carries weight only ([ScaleSnapshot] has no flow field).
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
      ),
    );
  }
}
