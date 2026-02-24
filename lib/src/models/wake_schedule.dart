import 'dart:convert';

import 'package:uuid/uuid.dart';

/// Represents a recurring machine wake schedule.
///
/// Used by PresenceController to determine when the machine should
/// automatically wake up, and by the REST API for CRUD operations.
class WakeSchedule {
  final String id;
  final int hour;
  final int minute;
  final Set<int> daysOfWeek;
  final bool enabled;

  /// Creates a new WakeSchedule.
  ///
  /// [hour] must be 0-23, [minute] must be 0-59.
  /// [daysOfWeek] uses ISO 8601 weekday numbers: 1=Monday through 7=Sunday.
  /// An empty set means every day.
  const WakeSchedule({
    required this.id,
    required this.hour,
    required this.minute,
    required this.daysOfWeek,
    required this.enabled,
  });

  /// Creates a new WakeSchedule with a generated UUID.
  factory WakeSchedule.create({
    required int hour,
    required int minute,
    Set<int> daysOfWeek = const {},
    bool enabled = true,
  }) {
    return WakeSchedule(
      id: const Uuid().v4(),
      hour: hour,
      minute: minute,
      daysOfWeek: daysOfWeek,
      enabled: enabled,
    );
  }

  /// Creates a WakeSchedule from a JSON map.
  ///
  /// Expected format:
  /// ```json
  /// {"id": "...", "time": "HH:MM", "daysOfWeek": [1,2,...], "enabled": true}
  /// ```
  factory WakeSchedule.fromJson(Map<String, dynamic> json) {
    final timeParts = (json['time'] as String).split(':');
    final days = (json['daysOfWeek'] as List).cast<int>();

    return WakeSchedule(
      id: json['id'] as String,
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
      daysOfWeek: days.toSet(),
      enabled: json['enabled'] as bool,
    );
  }

  /// Serializes this schedule to a JSON map.
  ///
  /// Time is formatted as a zero-padded "HH:MM" string.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time':
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      'daysOfWeek': daysOfWeek.toList()..sort(),
      'enabled': enabled,
    };
  }

  /// Returns true if this schedule matches the given [dateTime].
  ///
  /// A schedule matches when:
  /// - It is [enabled], AND
  /// - The hour and minute match, AND
  /// - The weekday is in [daysOfWeek] (or [daysOfWeek] is empty, meaning every day)
  bool matchesTime(DateTime dateTime) {
    if (!enabled) return false;
    if (dateTime.hour != hour || dateTime.minute != minute) return false;
    if (daysOfWeek.isNotEmpty && !daysOfWeek.contains(dateTime.weekday)) {
      return false;
    }
    return true;
  }

  /// Returns a copy of this schedule with the given fields replaced.
  WakeSchedule copyWith({
    String? id,
    int? hour,
    int? minute,
    Set<int>? daysOfWeek,
    bool? enabled,
  }) {
    return WakeSchedule(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Serializes a list of WakeSchedule objects to a JSON string.
  static String serializeList(List<WakeSchedule> schedules) {
    return jsonEncode(schedules.map((s) => s.toJson()).toList());
  }

  /// Deserializes a JSON string to a list of WakeSchedule objects.
  static List<WakeSchedule> deserializeList(String jsonString) {
    final list = jsonDecode(jsonString) as List;
    return list
        .map((item) => WakeSchedule.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
