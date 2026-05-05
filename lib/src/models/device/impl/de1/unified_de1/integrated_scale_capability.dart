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
/// `onConnect`, [disposeIntegratedScale] from `onDisconnect`. The
/// capability is intentionally a no-op until firmware publishes the
/// wire identifiers (see [BengleScaleEndpoint]); when that happens, fill
/// in the enum and replace the placeholder parser/encoder bodies.
mixin IntegratedScaleCapability on UnifiedDe1 {
  final BehaviorSubject<ScaleSnapshot> _bengleWeight =
      BehaviorSubject<ScaleSnapshot>();
  StreamSubscription<ByteData>? _bengleWeightSub;

  /// Live weight stream from the integrated scale. Emits nothing while
  /// the wire identifiers in [BengleScaleEndpoint] are null (FW TBD).
  Stream<ScaleSnapshot> get weightSnapshot => _bengleWeight.stream;

  /// Subscribe to the integrated-scale weight notify endpoint. No-op
  /// (with a single info log) while the endpoint wires are null.
  Future<void> initIntegratedScale() async {
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
