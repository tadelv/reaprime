/// Single source of truth for the WiFi Half Decent Scale's `deviceId` encoding.
///
/// The id is `wifi:<host>`, where `<host>` is the logical mDNS hostname (or a
/// manually-entered IP). The transport, the scale, and the discovery service
/// all agree on this format, and the discovery service reverse-parses it to
/// recover the host for reachability probing — so the encode/decode round-trip
/// is a real cross-type contract. Keeping it here means no layer hard-codes the
/// `wifi:` literal, and the round-trip can be tested in one place.
class WifiScaleId {
  static const String prefix = 'wifi:';

  /// `host` → `wifi:host`.
  static String forHost(String host) => '$prefix$host';

  /// `wifi:host` → `host`. Returns the input unchanged if it lacks the prefix
  /// (defensive — callers only pass ids this class produced).
  static String hostOf(String deviceId) => deviceId.startsWith(prefix)
      ? deviceId.substring(prefix.length)
      : deviceId;
}
