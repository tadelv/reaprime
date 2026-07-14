import 'package:reaprime/src/models/wake_schedule.dart';

class KeepAwakeOccurrence {
  const KeepAwakeOccurrence({
    required this.scheduleId,
    required this.start,
    required this.end,
  });

  final String scheduleId;
  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is KeepAwakeOccurrence &&
      other.scheduleId == scheduleId &&
      other.start == start;

  @override
  int get hashCode => Object.hash(scheduleId, start);
}

KeepAwakeOccurrence? activeKeepAwakeOccurrence(
  List<WakeSchedule> schedules,
  DateTime now,
) {
  KeepAwakeOccurrence? latest;

  for (final schedule in schedules) {
    final occurrence = _activeOccurrenceForSchedule(schedule, now);
    if (occurrence == null) continue;
    if (latest == null ||
        occurrence.end.isAfter(latest.end) ||
        (occurrence.end == latest.end &&
            occurrence.start.isAfter(latest.start))) {
      latest = occurrence;
    }
  }

  return latest;
}

List<WakeSchedule> keepAwakeSchedulesFromJson(String json) {
  if (json.isEmpty || json == '[]') return const [];
  try {
    return WakeSchedule.deserializeList(json);
  } catch (_) {
    return const [];
  }
}

KeepAwakeOccurrence? _activeOccurrenceForSchedule(
  WakeSchedule schedule,
  DateTime now,
) {
  final durationMinutes = schedule.keepAwakeFor;
  if (!schedule.enabled ||
      durationMinutes == null ||
      durationMinutes <= 0 ||
      schedule.hour < 0 ||
      schedule.hour > 23 ||
      schedule.minute < 0 ||
      schedule.minute > 59) {
    return null;
  }

  for (var daysAgo = 0; daysAgo <= 1; daysAgo++) {
    final day = DateTime(now.year, now.month, now.day - daysAgo);
    if (schedule.daysOfWeek.isNotEmpty &&
        !schedule.daysOfWeek.contains(day.weekday)) {
      continue;
    }

    final start = DateTime(
      day.year,
      day.month,
      day.day,
      schedule.hour,
      schedule.minute,
    );
    final end = start.add(Duration(minutes: durationMinutes));
    if (!now.isBefore(start) && now.isBefore(end)) {
      return KeepAwakeOccurrence(
        scheduleId: schedule.id,
        start: start,
        end: end,
      );
    }
  }

  return null;
}
