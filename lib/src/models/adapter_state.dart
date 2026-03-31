/// Transport-agnostic adapter readiness state.
/// Used by BleDiscoveryService today; reusable for future
/// WifiDiscoveryService or other transport families.
enum AdapterState { poweredOn, poweredOff, unavailable, unknown }
