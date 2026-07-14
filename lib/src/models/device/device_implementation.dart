/// Identifies the concrete [Device] class that should be constructed for a
/// remembered device. Persisted as the wire contract (`.name` string) in
/// [RememberedDevice], mirroring the [DeviceType.name] convention.
///
/// Renaming a value would orphan stored records — same constraint as
/// `DeviceType.name`.
enum DeviceImplementation {
  unifiedDe1,
  bengle,
  decentScale,
  hdsSerial,
  hdsWifi,
  skale2,
  acaiaScale,
  felicitaArc,
  blackCoffeeScale,
  bookooScale,
  eurekaScale,
  smartChefScale,
  variaAkuScale,
  difluidScale,
  hiroiaScale,
  atomheartScale,
  weighMasterScale,
  decentTemp,
  difluidR2Sensor,
  debugPort,
  sensorBasket,
}