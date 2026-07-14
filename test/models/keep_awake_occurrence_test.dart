import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/keep_awake_occurrence.dart';
import 'package:reaprime/src/models/wake_schedule.dart';

WakeSchedule schedule({
  String id = 'schedule',
  int hour = 7,
  int minute = 0,
  Set<int> daysOfWeek = const {},
  bool enabled = true,
  int? keepAwakeFor = 60,
}) => WakeSchedule(
  id: id,
  hour: hour,
  minute: minute,
  daysOfWeek: daysOfWeek,
  enabled: enabled,
  keepAwakeFor: keepAwakeFor,
);

void main() {
  group('activeKeepAwakeOccurrence', () {
    test('start is inclusive', () {
      final occurrence = activeKeepAwakeOccurrence(
        [schedule()],
        DateTime(2026, 1, 15, 7),
      );

      expect(occurrence?.start, DateTime(2026, 1, 15, 7));
      expect(occurrence?.end, DateTime(2026, 1, 15, 8));
    });

    test('end is exclusive', () {
      final occurrence = activeKeepAwakeOccurrence(
        [schedule()],
        DateTime(2026, 1, 15, 8),
      );

      expect(occurrence, isNull);
    });

    test('null and zero durations remain wake-only', () {
      expect(
        activeKeepAwakeOccurrence(
          [schedule(keepAwakeFor: null)],
          DateTime(2026, 1, 15, 7),
        ),
        isNull,
      );
      expect(
        activeKeepAwakeOccurrence(
          [schedule(keepAwakeFor: 0)],
          DateTime(2026, 1, 15, 7),
        ),
        isNull,
      );
    });

    test('checks the previous day for a duration crossing midnight', () {
      final occurrence = activeKeepAwakeOccurrence(
        [
          schedule(hour: 23, keepAwakeFor: 120, daysOfWeek: {3}),
        ],
        DateTime(2026, 1, 15, 0, 30),
      );

      expect(occurrence?.start, DateTime(2026, 1, 14, 23));
      expect(occurrence?.end, DateTime(2026, 1, 15, 1));
    });

    test('empty days means every day and explicit days are respected', () {
      final now = DateTime(2026, 1, 15, 7, 30);

      expect(activeKeepAwakeOccurrence([schedule()], now), isNotNull);
      expect(
        activeKeepAwakeOccurrence(
          [
            schedule(daysOfWeek: {DateTime.friday}),
          ],
          now,
        ),
        isNull,
      );
    });

    test('overlapping occurrences return the latest end', () {
      final occurrence = activeKeepAwakeOccurrence(
        [
          schedule(id: 'short', keepAwakeFor: 60),
          schedule(id: 'long', minute: 30, keepAwakeFor: 120),
        ],
        DateTime(2026, 1, 15, 7, 45),
      );

      expect(occurrence?.scheduleId, 'long');
      expect(occurrence?.end, DateTime(2026, 1, 15, 9, 30));
    });

    test('more than 32 occurrences do not affect app-side evaluation', () {
      final schedules = [
        for (var i = 0; i < 40; i++)
          schedule(id: '$i', minute: i, keepAwakeFor: 120),
      ];

      final occurrence = activeKeepAwakeOccurrence(
        schedules,
        DateTime(2026, 1, 15, 7, 45),
      );

      expect(occurrence?.scheduleId, '39');
      expect(occurrence?.end, DateTime(2026, 1, 15, 9, 39));
    });

    test('uses elapsed duration from the concrete start', () {
      final start = DateTime(2026, 1, 15, 7);
      final occurrence = activeKeepAwakeOccurrence(
        [schedule(keepAwakeFor: 90)],
        start,
      );

      expect(occurrence?.end, start.add(const Duration(minutes: 90)));
    });
  });

  group('keepAwakeSchedulesFromJson', () {
    test('malformed JSON produces no schedules and does not throw', () {
      expect(keepAwakeSchedulesFromJson('{not json'), isEmpty);
      expect(keepAwakeSchedulesFromJson('[{"id":"missing-fields"}]'), isEmpty);
    });

    test('valid stored schedule JSON remains readable', () {
      final json = WakeSchedule.serializeList([schedule()]);

      expect(keepAwakeSchedulesFromJson(json), hasLength(1));
    });
  });
}
