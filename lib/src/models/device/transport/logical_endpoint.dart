/// Wire-agnostic identifier for a DE1-family endpoint.
///
/// Capabilities target [LogicalEndpoint], never raw UUIDs or serial chars,
/// so the BLE/serial dispatch in `UnifiedDe1Transport` keeps working.
///
/// `uuid` is the BLE characteristic UUID; null means the endpoint has no
/// BLE wire support. `representation` is the single-character serial
/// command id; null means no serial wire support. At least one must be
/// non-null in any production endpoint.
abstract class LogicalEndpoint {
  String? get uuid;
  String? get representation;
}
