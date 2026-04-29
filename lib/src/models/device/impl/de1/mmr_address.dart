/// Documents the value shape stored at a given MMR address.
///
/// Capability mixins use this to pick the right read/write helper.
/// Helpers validate against [kind] and throw on mismatch — catches
/// "wrong helper for this address" mistakes at runtime.
enum MmrValueKind {
  int32, // signed 32-bit int
  int16, // signed 16-bit int
  scaledFloat, // int with read/write scale (current _MMRConfig usage)
  boolean, // 0/1 int treated as bool
  bytes, // raw bytes, no decoding
  string, // null-terminated or length-prefixed string
}

/// Wire-agnostic identifier for a single MMR slot.
///
/// DE1's [MMRItem] implements this; capability mixins ship their own
/// enums (e.g. `BengleCupWarmerMmr`) that also implement it.
abstract class MmrAddress {
  int get address;
  int get length;
  String get name;
  MmrValueKind get kind;
}
