import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/simulated_device.dart';

/// Lightweight, persistable record of a device the user has connected to or
/// preferred. Metadata only — it is NOT a live [Device] (no transport, no
/// connectionState). The API surfaces a remembered device that isn't currently
/// present as `available: false`.
class RememberedDevice {
  final String id;
  final String name;
  final DeviceType type;

  const RememberedDevice({
    required this.id,
    required this.name,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
      };

  /// Build a record from a live [Device], or null if the device is simulated
  /// (a [SimulatedDevice] is governed by the simulate setting, not real
  /// discovery, so it is never remembered). This is the point that keeps mocks
  /// out of the remembered registry.
  static RememberedDevice? fromDevice(Device device) {
    if (device is SimulatedDevice) return null;
    return RememberedDevice(
        id: device.deviceId, name: device.name, type: device.type);
  }

  /// Parse one record. Returns null for malformed input or an unknown type.
  static RememberedDevice? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final typeName = json['type'];
    if (id is! String || name is! String || typeName is! String) return null;
    final type =
        DeviceType.values.firstWhereOrNull((t) => t.name == typeName);
    if (type == null) return null;
    return RememberedDevice(id: id, name: name, type: type);
  }

  /// Encode a list to the JSON string persisted in settings.
  static String encodeList(Iterable<RememberedDevice> devices) =>
      jsonEncode(devices.map((d) => d.toJson()).toList());

  /// Decode the persisted JSON string. Malformed entries are skipped; a fully
  /// malformed string yields an empty list (never throws).
  static List<RememberedDevice> decodeList(String json) {
    dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((m) => RememberedDevice.fromJson(Map<String, dynamic>.from(m)))
        .whereType<RememberedDevice>()
        .toList();
  }

  /// Identity is the device id (one remembered entry per device).
  @override
  bool operator ==(Object other) =>
      other is RememberedDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RememberedDevice($id, $name, ${type.name})';
}
