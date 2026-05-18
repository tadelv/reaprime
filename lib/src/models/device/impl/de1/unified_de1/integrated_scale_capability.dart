part of 'unified_de1.dart';

/// Wire endpoints for Bengle's integrated scale.
///
/// Both [uuid] and [representation] return `null` for now — the firmware
/// slots have not yet been published. The [IntegratedScaleCapability]
/// mixin treats null wires as "capability not yet wired" and silently
/// no-ops. Once FW publishes the wire spec, fill these in and the rest
/// of the capability light up unchanged.
enum BengleScaleEndpoint implements LogicalEndpoint {
  /// Notify characteristic carrying weight frames.
  weight,

  /// Write characteristic for tare and other scale commands.
  control;

  @override
  String? get uuid => null; // TBD with FW

  @override
  String? get representation => null; // TBD with FW

  @override
  String get name => (this as Enum).name;
}

/// Stateful capability for Bengle's integrated scale.
///
/// Owns the weight stream and tare endpoint. Lifecycle is managed by the
/// concrete `Bengle` device — call [initIntegratedScale] from
/// `onConnect`, [disposeIntegratedScale] from `onDisconnect`.
/// `UnifiedDe1.disconnect()` invokes `onDisconnect()` for the device, so
/// `disposeIntegratedScale()` runs on every real disconnect. The
/// capability is also re-init-safe: `initIntegratedScale()` recreates
/// `_bengleWeight` if a previous dispose closed it, so a reconnect on
/// the same instance restores a live stream. The capability is
/// intentionally a no-op until firmware publishes the wire identifiers
/// (see [BengleScaleEndpoint]); when that happens, fill in the enum and
/// replace the placeholder parser/encoder bodies.
mixin IntegratedScaleCapability on UnifiedDe1 {
  BehaviorSubject<ScaleSnapshot> _bengleWeight =
      BehaviorSubject<ScaleSnapshot>();
  StreamSubscription<ByteData>? _bengleWeightSub;

  /// Latest stop-at-weight target in grams as seen from the app's
  /// side. `0.0` means SAW is disabled (mirrors cup-warmer "0 = off").
  /// Seeded `0.0` so late subscribers immediately get a value rather
  /// than waiting for the first write.
  BehaviorSubject<double> _sawTarget = BehaviorSubject<double>.seeded(0.0);

  /// Live weight stream from the integrated scale. Emits nothing while
  /// the wire identifiers in [BengleScaleEndpoint] are null (FW TBD).
  Stream<ScaleSnapshot> get weightSnapshot => _bengleWeight.stream;

  /// Current stop-at-weight target in grams (`0.0` = SAW off).
  Stream<double> get stopAtWeightTarget => _sawTarget.stream;

  /// Subscribe to the integrated-scale weight notify endpoint. No-op
  /// (with a single info log) while the endpoint wires are null.
  ///
  /// Re-init-safe: if a previous [disposeIntegratedScale] closed the
  /// subject, a fresh one is created here so that listeners attaching
  /// after a reconnect see a live stream rather than an immediately-
  /// done one.
  Future<void> initIntegratedScale() async {
    if (_bengleWeight.isClosed) {
      _bengleWeight = BehaviorSubject<ScaleSnapshot>();
    }
    if (_sawTarget.isClosed) {
      _sawTarget = BehaviorSubject<double>.seeded(0.0);
    }
    final endpoint = BengleScaleEndpoint.weight;
    if (endpoint.uuid == null && endpoint.representation == null) {
      this.log.info('IntegratedScaleCapability: weight endpoint unwired; '
          'no notify subscription. Awaiting FW.');
      return;
    }
    // When wires are real:
    // _bengleWeightSub =
    //     notificationsFor(endpoint).listen(_handleWeightFrame);
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

  /// Tare the integrated scale. No-op (with a single info log) while
  /// the control endpoint wires are null.
  Future<void> tareIntegratedScale() async {
    final ctl = BengleScaleEndpoint.control;
    if (ctl.uuid == null && ctl.representation == null) {
      this.log.info('IntegratedScaleCapability: tare ignored — control '
          'endpoint unwired. Awaiting FW.');
      return;
    }
    // When wired:
    // await writeEndpoint(ctl, Uint8List.fromList(_encodeTareCommand()),
    //     withResponse: false);
  }

  /// Locally cached SAW target value (`0.0` = SAW off). Concrete
  /// devices (`Bengle`, `MockBengle`) read/write this through
  /// [notifyStopAtWeightTarget]; the MMR plumbing lives on the concrete
  /// class so that this mixin doesn't pull `BengleMmr` upward into
  /// `unified_de1` (matching the cup-warmer split).
  double get currentStopAtWeightTarget => _sawTarget.value;

  /// Pushes a SAW target value onto [stopAtWeightTarget] for UI / read
  /// subscribers. Called by the concrete `Bengle` after a successful
  /// MMR write and by `MockBengle` from its in-memory store.
  @protected
  void notifyStopAtWeightTarget(double grams) {
    if (!_sawTarget.isClosed) {
      _sawTarget.add(grams);
    }
  }

  // Frame parser placeholder — replaced once FW spec lands.
  // ignore: unused_element
  void _handleWeightFrame(ByteData frame) {
    this.log.warning('IntegratedScaleCapability: weight frame received but '
        'parser not yet implemented (FW spec TBD)');
  }

  // Tare command encoder placeholder — replaced once FW spec lands.
  // ignore: unused_element
  List<int> _encodeTareCommand() => const [];
}
