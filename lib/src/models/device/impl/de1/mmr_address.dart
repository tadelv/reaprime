/// Documents the value shape stored at a given MMR address.
///
/// Capability mixins use this to pick the right read/write helper.
/// Helpers validate against [kind] and throw on mismatch — catches
/// "wrong helper for this address" mistakes at runtime.
///
/// Kinds are extended as new value shapes appear (e.g. `uint32`,
/// `bitmask`, `float32` for raw IEEE floats). `scaledFloat` is the only
/// one with helper-side semantics today; the rest are documentation.
/// DE1 itself doesn't yet consume `kind` — Task 3 adds the protected
/// helper surface that validates against it.
enum MmrValueKind {
  /// signed 32-bit int
  int32,

  /// signed 16-bit int
  int16,

  /// int with read/write scale (see [MmrAddress.readScale] / [MmrAddress.writeScale])
  scaledFloat,

  /// 0/1 int treated as bool
  boolean,

  /// raw bytes, no decoding
  bytes,

  /// null-terminated or length-prefixed string
  string,
}

/// Wire-agnostic identifier for a single MMR slot.
///
/// DE1's [MMRItem] implements this; capability mixins ship their own
/// enums (e.g. `BengleCupWarmerMmr`) that also implement it.
///
/// Scaling/clamp config travels with the address itself: [readScale],
/// [writeScale], [min], [max] default to "no transform" so addresses
/// without scaling don't have to declare anything. Addresses that need
/// non-default values override the relevant getter (or pass via the
/// constructor on enum implementers like [MMRItem]).
abstract class MmrAddress {
  int get address;
  int get length;
  String get name;
  MmrValueKind get kind;

  /// Multiplier applied when reading a `scaledFloat`. 1.0 means "the
  /// raw int is the value as-is." Ignored for non-scaledFloat kinds.
  double get readScale => 1.0;

  /// Multiplier applied (then truncated to int) when writing a
  /// `scaledFloat`. 1.0 means "the int is the value as-is."
  double get writeScale => 1.0;

  /// Optional minimum bound; null means no lower clamp.
  int? get min => null;

  /// Optional maximum bound; null means no upper clamp.
  int? get max => null;
}
