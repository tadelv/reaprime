/// Caches the last resolved IP for a WiFi scale hostname.
///
/// The HDS firmware authors note that repeated mDNS lookups fail intermittently
/// under load, and that AAAA (IPv6) lookups block before falling back to IPv4.
/// So we resolve a `.local` host once, cache the IPv4 address, and reconnect
/// against the cached IP — re-resolving only when the cached IP stops working.
/// The cache self-heals: a fresh successful resolution overwrites a stale entry.
///
/// Pure data structure — no network. The discovery service feeds it resolved
/// addresses (from bonsoir) and consults [connectHostFor] when building a
/// transport.
class WifiIpCache {
  final Map<String, String> _hostToIp = {};

  /// Record the IP a [host] most recently resolved to. Overwrites any prior
  /// entry (self-heal on re-resolve). Ignores empty values.
  void record(String host, String ip) {
    if (host.isEmpty || ip.isEmpty) return;
    _hostToIp[host] = ip;
  }

  /// The cached IP for [host], or null if none is known.
  String? cachedIp(String host) => _hostToIp[host];

  /// The address to connect to for [host]: the cached IP if known, otherwise
  /// the host itself (so an unresolved `.local` name or a manually-entered IP
  /// is used directly).
  String connectHostFor(String host) => _hostToIp[host] ?? host;

  /// Drop the cached IP for [host] after it fails, so the next connect falls
  /// back to re-resolving the hostname.
  void invalidate(String host) => _hostToIp.remove(host);

  void clear() => _hostToIp.clear();
}
