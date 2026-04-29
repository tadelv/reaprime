/// Wire-agnostic identifier for a DE1-family endpoint.
///
/// Capabilities target [LogicalEndpoint], never raw UUIDs or serial chars,
/// so the BLE/serial dispatch in `UnifiedDe1Transport` keeps working.
///
/// `uuid` is the BLE characteristic UUID; null means the endpoint has no
/// BLE wire support. `representation` is the single-character serial
/// command id; null means no serial wire support. At least one must be
/// non-null in any production endpoint. `name` is a human-readable
/// identifier used in logs and error messages.
///
/// **Note for enum implementers:** Dart's analyzer doesn't see the
/// synthesized `Enum.name` as satisfying this interface's `String get name`
/// getter. Add `@override String get name => (this as Enum).name;` to your
/// enum. See [Endpoint] for an example and fix-commit history
/// (553550d / b7b8ed7).
abstract class LogicalEndpoint {
  String? get uuid;
  String? get representation;
  String get name;
}
