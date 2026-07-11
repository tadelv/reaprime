part of 'unified_de1.dart';

/// Bengle LED palette MMR registers.
/// Each holds a raw `0x00RRGGBB` int32 (little-endian on the wire, no scaling).
/// The FW auto-applies the awake/sleep palette on state transitions — and
/// immediately if the machine is already in that state — so a palette write
/// both previews live and stores it (`PERM_RWD`). There is NO switch-LED
/// register: the physical switch light mirrors the front strip in firmware, so
/// [LedStripState]'s `frontSwitch` zone has no wire and is ignored on write.
enum BengleLedMmr implements MmrAddress {
  frontAwake(0x00803898, 'FrontLEDAwake'),
  frontSleep(0x008038A0, 'FrontLEDSleep'),
  rearAwake(0x0080389C, 'RearLEDAwake'),
  rearSleep(0x008038A4, 'RearLEDSleep'),

  /// Live/preview colour registers (`F_LEDStripColor`): writing pushes to the
  /// strip immediately regardless of awake/sleep state, without touching the
  /// stored palette. Used to preview a colour (e.g. the sleep colour) while the
  /// machine is awake.
  frontLive(0x00803890, 'FrontLEDColor'),
  rearLive(0x00803894, 'RearLEDColor');

  const BengleLedMmr(this.address, this.description);

  @override
  final int address;
  final String description;
  @override
  int get length => 4;
  @override
  MmrValueKind get kind => MmrValueKind.int32;
  @override
  double get readScale => 1.0;
  @override
  double get writeScale => 1.0;
  @override
  int? get min => null;
  @override
  int? get max => null;
  @override
  String get name => (this as Enum).name;
}

/// Stateful capability for Bengle's LED strip — front and rear strips, each
/// with a sleeping/awake palette colour. ([LedStripState] also carries a
/// `frontSwitch` zone for API symmetry, but the switch LED is not independently
/// controllable — it mirrors the front strip.)
///
/// Owns the current [LedStripState] and exposes getter/setter plus
/// [commitLedStrip] and [resetLedStrip]. Lifecycle is managed by the concrete
/// `Bengle` device — call [initLedStrip] from `onConnect`, [disposeLedStrip]
/// from `onDisconnect`.
mixin LedStripCapability on UnifiedDe1 {
  BehaviorSubject<LedStripState> _ledStripState =
      BehaviorSubject<LedStripState>.seeded(const LedStripState());

  /// Current LED strip state (cached in SB; reflects the connect-time
  /// hydration and the last write / reset).
  Stream<LedStripState> get ledStripState => _ledStripState.stream;

  /// One-shot read of the current cached LED strip state.
  Future<LedStripState> getLedStripState() => _ledStripState.first;

  /// Write the full palette to the FW and cache. Front strip →
  /// Front{Awake,Sleep}, rear strip → Rear{Awake,Sleep}; the front-switch zone
  /// has no register and is ignored. Because the palette registers are
  /// `PERM_RWD` the write also persists — there is no separate live/commit
  /// split on the wire.
  Future<void> setLedStrip(LedStripState state) async {
    await _writeLedColor(BengleLedMmr.frontAwake, state.frontStrip.awake);
    await _writeLedColor(BengleLedMmr.frontSleep, state.frontStrip.sleeping);
    await _writeLedColor(BengleLedMmr.rearAwake, state.backStrip.awake);
    await _writeLedColor(BengleLedMmr.rearSleep, state.backStrip.sleeping);
    _ledStripState.add(state);
  }

  /// The palette registers persist on write and the FW exposes no separate
  /// commit register, so a write is already the commit. Kept for API symmetry —
  /// re-asserts the current cache to the FW.
  Future<void> commitLedStrip() => setLedStrip(_ledStripState.value);

  /// Push a live colour to the strip immediately (`FrontLEDColor`/`RearLEDColor`),
  /// regardless of awake/sleep state and WITHOUT changing the stored palette or
  /// the cache — used to preview a colour (e.g. the sleep colour) while the
  /// machine is awake. Call [clearLedPreview] to restore the awake palette.
  Future<void> previewLedColor(Color16 front, Color16 back) async {
    await _writeLedColor(BengleLedMmr.frontLive, front);
    await _writeLedColor(BengleLedMmr.rearLive, back);
  }

  /// Restore the strip to the cached awake palette after a [previewLedColor].
  Future<void> clearLedPreview() async {
    final s = _ledStripState.value;
    await _writeLedColor(BengleLedMmr.frontLive, s.frontStrip.awake);
    await _writeLedColor(BengleLedMmr.rearLive, s.backStrip.awake);
  }

  /// Reload the cache from the FW palette registers, dropping local edits.
  Future<void> resetLedStrip() async {
    _ledStripState.add(await _readLedStrip());
  }

  /// Read the four palette registers into a [LedStripState]; the front-switch
  /// zone mirrors the front strip.
  Future<LedStripState> _readLedStrip() async {
    final front = ZoneLedState(
      awake: await _readLedColor(BengleLedMmr.frontAwake),
      sleeping: await _readLedColor(BengleLedMmr.frontSleep),
    );
    return LedStripState(
      frontStrip: front,
      backStrip: ZoneLedState(
        awake: await _readLedColor(BengleLedMmr.rearAwake),
        sleeping: await _readLedColor(BengleLedMmr.rearSleep),
      ),
      frontSwitch: front,
    );
  }

  Future<void> _writeLedColor(BengleLedMmr reg, Color16 color) => _mmrWriteRaw(
    reg.address,
    _packMMRInt(_color16ToPacked(color)),
    label: reg.description,
  );

  Future<Color16> _readLedColor(BengleLedMmr reg) async => _packedToColor16(
    _unpackMMRInt(await _mmrReadRaw(reg.address, label: reg.description)),
  );

  /// 16-bit-per-channel [Color16] → FW `0x00RRGGBB` (high byte of each channel).
  int _color16ToPacked(Color16 c) =>
      (((c.red >> 8) & 0xFF) << 16) |
      (((c.green >> 8) & 0xFF) << 8) |
      ((c.blue >> 8) & 0xFF);

  /// FW `0x00RRGGBB` → [Color16], byte-replicating each 8-bit channel to 16-bit
  /// (`0xAB → 0xABAB`) so a round-trip is lossless for 8-bit sources.
  Color16 _packedToColor16(int v) {
    int up(int x) => (x << 8) | x;
    return Color16(up((v >> 16) & 0xFF), up((v >> 8) & 0xFF), up(v & 0xFF));
  }

  /// Re-init-safe: if a previous [disposeLedStrip] closed the subject, a fresh
  /// one is created here — then the cache is hydrated from the machine's four
  /// stored palette registers so a GET right after connect serves the real
  /// stored colours instead of all-off (and [clearLedPreview] restores the
  /// machine's true awake palette, not black). Hydration is read-only: it
  /// never touches the live/preview registers. Failure-tolerant: a failed
  /// read leaves the cache seeded all-off (the pre-hydration behavior) and
  /// never fails the connect.
  Future<void> initLedStrip() async {
    if (_ledStripState.isClosed) {
      _ledStripState = BehaviorSubject<LedStripState>.seeded(
        const LedStripState(),
      );
    }
    try {
      _ledStripState.add(await _readLedStrip());
    } catch (e) {
      // `this.` disambiguates the protected Logger getter from dart:math's
      // top-level `log`, which shadows it in this library's lexical scope.
      this.log.warning('Could not hydrate LED palette on connect: $e');
    }
  }

  /// Cancel any subscriptions and close the subject.
  Future<void> disposeLedStrip() async {
    if (!_ledStripState.isClosed) {
      await _ledStripState.close();
    }
  }
}
