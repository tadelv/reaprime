part of 'unified_de1.dart';

/// Wire endpoints for Bengle's front/back LED strip.
///
/// Both [uuid] and [representation] return `null` for now — the firmware
/// slots have not yet been published. The [LedStripCapability] mixin
/// treats null wires as "capability not yet wired" and silently no-ops
/// (with an info log). Once FW publishes the wire spec, fill these in
/// and the rest of the capability light up unchanged.
enum BengleLedEndpoint implements LogicalEndpoint {
  /// Write characteristic for front LED colour.
  front,

  /// Write characteristic for back LED colour.
  back;

  @override
  String? get uuid => null; // TBD with FW

  @override
  String? get representation => null; // TBD with FW

  @override
  String get name => (this as Enum).name;
}

/// Stateful capability for Bengle's front/back LED strip.
///
/// Owns the current [LedStripState] and exposes getter/setter. Lifecycle
/// is managed by the concrete `Bengle` device — call [initLedStrip] from
/// `onConnect`, [disposeLedStrip] from `onDisconnect`.
/// `UnifiedDe1.disconnect()` invokes `onDisconnect()` for the device, so
/// `disposeLedStrip()` runs on every real disconnect.
///
/// The capability is a no-op until firmware publishes the wire identifiers
/// (see [BengleLedEndpoint]); when that happens, replace the placeholder
/// bodies in [setLedStrip] and [getLedStripState].
mixin LedStripCapability on UnifiedDe1 {
  BehaviorSubject<LedStripState> _ledStripState =
      BehaviorSubject<LedStripState>.seeded(const LedStripState());

  /// Current LED strip state. Emits [LedStripState.allOff] while wires
  /// are unwired (FW TBD).
  Stream<LedStripState> get ledStripState => _ledStripState.stream;

  /// One-shot read of the current LED strip state.
  Future<LedStripState> getLedStripState() =>
      _ledStripState.first;

  /// Set the LED strip colour. No-op (with a single info log) while
  /// the endpoint wires are null.
  Future<void> setLedStrip(LedStripState state) async {
    final frontEndpoint = BengleLedEndpoint.front;
    final backEndpoint = BengleLedEndpoint.back;
    if (frontEndpoint.uuid == null && frontEndpoint.representation == null &&
        backEndpoint.uuid == null && backEndpoint.representation == null) {
      this.log.info('LedStripCapability: endpoints unwired; '
          'setLedStrip($state) ignored. Awaiting FW.');
      return;
    }
    // When wires are real:
    // await writeEndpoint(frontEndpoint,
    //     Uint8List.fromList(_encodeColor(state.frontRed, state.frontGreen, state.frontBlue)));
    // await writeEndpoint(backEndpoint,
    //     Uint8List.fromList(_encodeColor(state.backRed, state.backGreen, state.backBlue)));
    _ledStripState.add(state);
  }

  /// Re-init-safe: if a previous [disposeLedStrip] closed the subject,
  /// a fresh one is created here.
  Future<void> initLedStrip() async {
    if (_ledStripState.isClosed) {
      _ledStripState =
          BehaviorSubject<LedStripState>.seeded(const LedStripState());
    }
    final frontEndpoint = BengleLedEndpoint.front;
    final backEndpoint = BengleLedEndpoint.back;
    if (frontEndpoint.uuid == null && frontEndpoint.representation == null &&
        backEndpoint.uuid == null && backEndpoint.representation == null) {
      this.log.info('LedStripCapability: endpoints unwired; '
          'no write surface registered. Awaiting FW.');
      return;
    }
    // When wires are real: subscribe to notify endpoints if available,
    // otherwise hydrate cached value.
  }

  /// Cancel any subscriptions and close the subject.
  Future<void> disposeLedStrip() async {
    if (!_ledStripState.isClosed) {
      await _ledStripState.close();
    }
  }

  // Colour encoder placeholder — replaced once FW spec lands.
  // ignore: unused_element
  List<int> _encodeColor(int r, int g, int b) =>
      [r, g, b]; // FW spec TBD
}
