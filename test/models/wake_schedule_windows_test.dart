import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/wake_schedule.dart';
import 'package:reaprime/src/models/wake_schedule_windows.dart';

/// The wake-window derivation (spec §2, §5) — the single source of truth
/// for BOTH the firmware schedule table and the app's idle-sleep suppression.
///
/// The load-bearing fact under test: the firmware `dow` field is a day INDEX
/// (0 = Sunday .. 6 = Saturday) that it compares for EQUALITY, NOT a bitmask.
/// Packing a Mon–Fri day set as a bitmask (0b0111110 = 62) would decode in the
/// firmware to `62 & 0x7 == 6` — one window, on Saturday — and nothing would
/// report an error. The byte-exact goldens below are what catch that.

/// Mirrors the firmware decoder verbatim, so the tests
/// can assert that every value the app emits is one the firmware ACCEPTS.
({int dow, int startMin, int endMin}) fwDecode(int packed) => (
      dow: (packed >> 22) & 0x7,
      startMin: (packed >> 11) & 0x7FF,
      endMin: packed & 0x7FF,
    );

/// The firmware's own accept test (`scheduleAddEntry`): anything else is
/// SILENTLY dropped.
bool fwAccepts(int packed) {
  final d = fwDecode(packed);
  return d.dow <= 6 && d.startMin < d.endMin && d.endMin <= 1440;
}

WakeSchedule schedule({
  String id = 's',
  int hour = 5,
  int minute = 30,
  Set<int> days = const {},
  bool enabled = true,
  int? keepAwakeFor,
}) =>
    WakeSchedule(
      id: id,
      hour: hour,
      minute: minute,
      daysOfWeek: days,
      enabled: enabled,
      keepAwakeFor: keepAwakeFor,
    );

void main() {
  group('fwDayOfWeek (ISO -> firmware day index)', () {
    test('maps every ISO weekday; Sunday 7 wraps to 0', () {
      // ISO: 1=Mon..7=Sun.  FW: 0=Sun..6=Sat.
      expect(fwDayOfWeek(1), 1, reason: 'Monday');
      expect(fwDayOfWeek(2), 2, reason: 'Tuesday');
      expect(fwDayOfWeek(3), 3, reason: 'Wednesday');
      expect(fwDayOfWeek(4), 4, reason: 'Thursday');
      expect(fwDayOfWeek(5), 5, reason: 'Friday');
      expect(fwDayOfWeek(6), 6, reason: 'Saturday');
      expect(fwDayOfWeek(7), 0, reason: 'Sunday is 0 in the firmware');
    });

    test('agrees with DateTime.weekday for a known week', () {
      // 2026-07-12 is a Sunday.
      expect(fwDayOfWeek(DateTime(2026, 7, 12).weekday), 0);
      expect(fwDayOfWeek(DateTime(2026, 7, 13).weekday), 1); // Mon
      expect(fwDayOfWeek(DateTime(2026, 7, 18).weekday), 6); // Sat
    });
  });

  group('packWakeWindow', () {
    test('weekday schedule: Mon-Fri 05:30 for 90 min — byte-exact goldens', () {
      // Spec §5.1. startMin = 330 (0x14A), endMin = 420 (0x1A4).
      // Low half, common to all five: (330 << 11) | 420 = 0x000A51A4.
      final windows = expandWindows([
        schedule(hour: 5, minute: 30, days: {1, 2, 3, 4, 5}, keepAwakeFor: 90),
      ]);

      expect(
        windows.map((w) => w.packed).toList(),
        [
          0x004A51A4, // Mon (dow 1) 05:30-07:00
          0x008A51A4, // Tue (dow 2)
          0x00CA51A4, // Wed (dow 3)
          0x010A51A4, // Thu (dow 4)
          0x014A51A4, // Fri (dow 5)
        ],
        reason: 'five separate entries, one per day — NOT one bitmask entry',
      );
      // Decimal, as the spec's table states them.
      expect(windows.first.packed, 4870564);
      expect(windows.last.packed, 21647780);
    });

    test('the bitmask trap: a Mon-Fri bitmask would decode to Saturday only',
        () {
      // Documents WHY the goldens above are per-day. 0b0111110 = 62.
      const bitmask = 62;
      expect((bitmask >> 22) & 0x7, 0, reason: 'the days vanish entirely');
      // And if a caller shifted the bitmask into the dow field:
      final packedMask = (bitmask << 22) | (330 << 11) | 420;
      expect(fwDecode(packedMask).dow, 6,
          reason: 'the firmware would schedule Saturday, silently');
    });

    test('every emitted entry round-trips through the firmware decoder', () {
      final windows = expandWindows([
        schedule(id: 'a', hour: 0, minute: 0, keepAwakeFor: 1),
        schedule(id: 'b', hour: 23, minute: 59, keepAwakeFor: 1),
        schedule(id: 'c', hour: 23, minute: 0, days: {6}, keepAwakeFor: 120),
        schedule(id: 'd', hour: 12, minute: 0, days: {3}, keepAwakeFor: 720),
      ]);
      expect(windows, isNotEmpty);
      for (final w in windows) {
        expect(fwAccepts(w.packed), isTrue,
            reason: '$w packs to 0x${w.packed.toRadixString(16)} which the '
                'firmware would silently DROP');
        final d = fwDecode(w.packed);
        expect(d.dow, w.dow);
        expect(d.startMin, w.startMin);
        expect(d.endMin, w.endMin);
      }
    });

    test('the last minute of the day packs to a legal window', () {
      final windows = expandWindows([
        schedule(hour: 23, minute: 59, days: {1}, keepAwakeFor: 1),
      ]);
      expect(windows.single, const WakeWindow(dow: 1, startMin: 1439, endMin: 1440));
      expect(fwAccepts(windows.single.packed), isTrue);
    });
  });

  group('expandWindows — window derivation', () {
    test('keepAwakeFor == null gets the 30-minute default window', () {
      final windows = expandWindows([
        schedule(hour: 7, minute: 0, days: {1}),
      ]);
      expect(windows.single,
          const WakeWindow(dow: 1, startMin: 420, endMin: 450));
    });

    test('keepAwakeFor at both bounds (1 and 720)', () {
      expect(
        expandWindows([schedule(hour: 6, minute: 0, days: {2}, keepAwakeFor: 1)])
            .single,
        const WakeWindow(dow: 2, startMin: 360, endMin: 361),
      );
      expect(
        expandWindows(
                [schedule(hour: 6, minute: 0, days: {2}, keepAwakeFor: 720)])
            .single,
        const WakeWindow(dow: 2, startMin: 360, endMin: 1080),
      );
    });

    test('empty daysOfWeek means every day: 7 entries, dow 0..6', () {
      // Spec §5.3: 07:00 for 45 min.
      final windows = expandWindows([
        schedule(hour: 7, minute: 0, days: const {}, keepAwakeFor: 45),
      ]);
      expect(windows.map((w) => w.dow).toList(), [0, 1, 2, 3, 4, 5, 6]);
      expect(
        windows.map((w) => w.packed).toList(),
        [
          0x000D21D1,
          0x004D21D1,
          0x008D21D1,
          0x00CD21D1,
          0x010D21D1,
          0x014D21D1,
          0x018D21D1,
        ],
      );
    });

    test('disabled schedules contribute nothing', () {
      expect(
        expandWindows([
          schedule(id: 'off', hour: 7, minute: 0, days: {1}, enabled: false),
        ]),
        isEmpty,
      );
    });

    test('no schedules at all yields no windows', () {
      expect(expandWindows(const []), isEmpty);
    });

    test('midnight crossing splits into two entries on consecutive days', () {
      // Spec §5.2: Saturday 23:00, keep awake 2 h.
      final windows = expandWindows([
        schedule(hour: 23, minute: 0, days: {6}, keepAwakeFor: 120),
      ]);
      expect(windows, hasLength(2));
      // Sorted by (dow, startMin): Sunday (dow 0) sorts before Saturday (6).
      expect(windows, contains(const WakeWindow(dow: 6, startMin: 1380, endMin: 1440)));
      expect(windows, contains(const WakeWindow(dow: 0, startMin: 0, endMin: 60)));
      final packed = windows.map((w) => w.packed).toSet();
      expect(packed, containsAll(<int>[0x01AB25A0, 0x0000003C]));
      expect(packed, containsAll(<int>[27993504, 60]));
    });

    test('Saturday wraps to Sunday, not to a dow of 7', () {
      final windows = expandWindows([
        schedule(hour: 23, minute: 30, days: {6}, keepAwakeFor: 60),
      ]);
      expect(windows.map((w) => w.dow).toSet(), {0, 6});
      for (final w in windows) {
        expect(fwAccepts(w.packed), isTrue);
      }
    });

    test('endMinRaw == 1440 exactly makes ONE entry, not a zero-length second',
        () {
      final windows = expandWindows([
        schedule(hour: 23, minute: 0, days: {3}, keepAwakeFor: 60),
      ]);
      expect(windows.single,
          const WakeWindow(dow: 3, startMin: 1380, endMin: 1440));
    });
  });

  group('mergeWindows', () {
    test('overlapping windows on the same day merge into one', () {
      final windows = expandWindows([
        schedule(id: 'a', hour: 7, minute: 0, days: {1}, keepAwakeFor: 60),
        schedule(id: 'b', hour: 7, minute: 30, days: {1}, keepAwakeFor: 60),
      ]);
      expect(windows.single,
          const WakeWindow(dow: 1, startMin: 420, endMin: 510));
    });

    test('touching windows (end == start) merge too', () {
      final windows = expandWindows([
        schedule(id: 'a', hour: 7, minute: 0, days: {1}, keepAwakeFor: 60),
        schedule(id: 'b', hour: 8, minute: 0, days: {1}, keepAwakeFor: 60),
      ]);
      expect(windows.single,
          const WakeWindow(dow: 1, startMin: 420, endMin: 540));
    });

    test('a fully-contained window does not shrink its container', () {
      expect(
        mergeWindows(const [
          WakeWindow(dow: 2, startMin: 400, endMin: 600),
          WakeWindow(dow: 2, startMin: 420, endMin: 450),
        ]).single,
        const WakeWindow(dow: 2, startMin: 400, endMin: 600),
      );
    });

    test('windows on different days never merge', () {
      final windows = expandWindows([
        schedule(id: 'a', hour: 7, minute: 0, days: {1}, keepAwakeFor: 60),
        schedule(id: 'b', hour: 7, minute: 0, days: {2}, keepAwakeFor: 60),
      ]);
      expect(windows, hasLength(2));
    });

    test('non-overlapping windows on one day stay separate, sorted', () {
      final windows = expandWindows([
        schedule(id: 'pm', hour: 17, minute: 0, days: {1}, keepAwakeFor: 30),
        schedule(id: 'am', hour: 7, minute: 0, days: {1}, keepAwakeFor: 30),
      ]);
      expect(windows, [
        const WakeWindow(dow: 1, startMin: 420, endMin: 450),
        const WakeWindow(dow: 1, startMin: 1020, endMin: 1050),
      ]);
    });
  });

  group('cap at kMaxWakeWindows (the firmware silently drops the 33rd)', () {
    test('every-day schedules with a midnight split cap at exactly 32', () {
      // 5 every-day schedules, one of them crossing midnight, all disjoint so
      // nothing merges: 4 x 7 + 7 x 2 = 42 raw windows for a 32-slot table.
      final schedules = [
        schedule(id: 'a', hour: 22, minute: 0, keepAwakeFor: 180), // 22:00-01:00
        schedule(id: 'b', hour: 6, minute: 0, keepAwakeFor: 30),
        schedule(id: 'c', hour: 9, minute: 0, keepAwakeFor: 30),
        schedule(id: 'd', hour: 12, minute: 0, keepAwakeFor: 30),
        schedule(id: 'e', hour: 15, minute: 0, keepAwakeFor: 30),
      ];
      final windows = expandWindows(schedules);
      expect(windows, hasLength(kMaxWakeWindows));
      // 6 windows per day survive the merge, so the 32-slot table holds days
      // 0..4 whole plus 2 of day 5, and day 6 is dropped entirely — the cap
      // really bit (the firmware would have dropped these silently).
      expect(windows.where((w) => w.dow == 0), hasLength(6));
      expect(windows.where((w) => w.dow == 5), hasLength(2));
      expect(windows.where((w) => w.dow == 6), isEmpty);

      // Deterministic order: sorted by (dow, startMin).
      for (var i = 1; i < windows.length; i++) {
        final prev = windows[i - 1];
        final cur = windows[i];
        expect(
          prev.dow < cur.dow ||
              (prev.dow == cur.dow && prev.startMin < cur.startMin),
          isTrue,
          reason: 'windows must be sorted by (dow, startMin): $prev then $cur',
        );
      }
      // And every surviving entry is one the firmware will accept.
      for (final w in windows) {
        expect(fwAccepts(w.packed), isTrue);
      }
    });

    test('a table that fits is not truncated', () {
      final windows = expandWindows([
        schedule(hour: 5, minute: 30, days: {1, 2, 3, 4, 5}, keepAwakeFor: 90),
      ]);
      expect(windows, hasLength(5));
    });
  });

  group('localSecondsOfWeek', () {
    test('Sunday 00:00:00 reports 1, never 0 (the reboot sentinel)', () {
      // 2026-07-12 is a Sunday.
      expect(localSecondsOfWeek(DateTime(2026, 7, 12, 0, 0, 0)), 1);
    });

    test('Saturday 23:59:59 is 604799 (the firmware rejects >= 604800)', () {
      // 2026-07-18 is a Saturday.
      expect(localSecondsOfWeek(DateTime(2026, 7, 18, 23, 59, 59)), 604799);
      expect(localSecondsOfWeek(DateTime(2026, 7, 18, 23, 59, 59)),
          lessThan(kSecondsPerWeek));
    });

    test('the spec\'s Tuesday 07:20:00 example is 199200', () {
      // 2026-07-14 is a Tuesday. 2*86400 + 7*3600 + 20*60 = 199200.
      expect(localSecondsOfWeek(DateTime(2026, 7, 14, 7, 20, 0)), 199200);
    });

    test('a day rollover advances by exactly 86400', () {
      final satLate = DateTime(2026, 7, 11, 23, 59, 59); // Saturday
      final sunEarly = DateTime(2026, 7, 12, 0, 0, 1); // Sunday
      expect(localSecondsOfWeek(satLate), 604799);
      // Sunday is day 0 — the week wraps, it does not keep counting up.
      expect(localSecondsOfWeek(sunEarly), 1);

      final monMidnight = DateTime(2026, 7, 13, 0, 0, 0); // Monday
      final sunMidnight = DateTime(2026, 7, 12, 0, 0, 30);
      expect(localSecondsOfWeek(monMidnight) - localSecondsOfWeek(sunMidnight),
          86400 - 30);
    });

    test('every minute of a week stays in the writable range', () {
      var t = DateTime(2026, 7, 12); // Sunday 00:00
      for (var i = 0; i < 7 * 24 * 60; i += 7) {
        final s = localSecondsOfWeek(t.add(Duration(minutes: i)));
        expect(s, greaterThanOrEqualTo(1));
        expect(s, lessThanOrEqualTo(604799));
      }
    });
  });

  group('isWithinWindow', () {
    final windows = expandWindows([
      schedule(hour: 5, minute: 30, days: {1, 2, 3, 4, 5}, keepAwakeFor: 90),
    ]);
    // 2026-07-13 is a Monday.

    test('start is inclusive', () {
      expect(isWithinWindow(windows, DateTime(2026, 7, 13, 5, 30)), isTrue);
    });

    test('inside the window', () {
      expect(isWithinWindow(windows, DateTime(2026, 7, 13, 6, 0)), isTrue);
      expect(isWithinWindow(windows, DateTime(2026, 7, 13, 6, 59, 59)), isTrue);
    });

    test('end is exclusive', () {
      expect(isWithinWindow(windows, DateTime(2026, 7, 13, 7, 0)), isFalse);
    });

    test('before the window', () {
      expect(isWithinWindow(windows, DateTime(2026, 7, 13, 5, 29)), isFalse);
    });

    test('a day not in the schedule never matches', () {
      // 2026-07-12 Sunday, 2026-07-18 Saturday.
      expect(isWithinWindow(windows, DateTime(2026, 7, 12, 6, 0)), isFalse);
      expect(isWithinWindow(windows, DateTime(2026, 7, 18, 6, 0)), isFalse);
    });

    test('no windows never matches', () {
      expect(isWithinWindow(const [], DateTime(2026, 7, 13, 6, 0)), isFalse);
    });

    test('the midnight-split pair covers both sides of midnight', () {
      final split = expandWindows([
        schedule(hour: 23, minute: 0, days: {6}, keepAwakeFor: 120),
      ]);
      // Saturday 2026-07-18 23:30 -> in the (dow 6, 1380..1440) half.
      expect(isWithinWindow(split, DateTime(2026, 7, 18, 23, 30)), isTrue);
      // Sunday 2026-07-19 00:30 -> in the (dow 0, 0..60) half.
      expect(isWithinWindow(split, DateTime(2026, 7, 19, 0, 30)), isTrue);
      // Sunday 01:00 -> past the end (exclusive).
      expect(isWithinWindow(split, DateTime(2026, 7, 19, 1, 0)), isFalse);
      // Saturday 22:59 -> before the start.
      expect(isWithinWindow(split, DateTime(2026, 7, 18, 22, 59)), isFalse);
    });
  });

  group('windowEnd', () {
    test('reports the wall-clock end of the open window', () {
      final windows = expandWindows([
        schedule(hour: 5, minute: 30, days: {1}, keepAwakeFor: 90),
      ]);
      expect(
        windowEnd(windows, DateTime(2026, 7, 13, 6, 0)),
        DateTime(2026, 7, 13, 7, 0),
      );
    });

    test('null outside any window', () {
      final windows = expandWindows([
        schedule(hour: 5, minute: 30, days: {1}, keepAwakeFor: 90),
      ]);
      expect(windowEnd(windows, DateTime(2026, 7, 13, 8, 0)), isNull);
      expect(windowEnd(const [], DateTime(2026, 7, 13, 6, 0)), isNull);
    });

    test('chains across a midnight split to the real end', () {
      final windows = expandWindows([
        schedule(hour: 23, minute: 0, days: {6}, keepAwakeFor: 120),
      ]);
      // Saturday 23:30 -> the user's window really ends Sunday 01:00, not at
      // the internal 24:00 split boundary.
      expect(
        windowEnd(windows, DateTime(2026, 7, 18, 23, 30)),
        DateTime(2026, 7, 19, 1, 0),
      );
      // And from the far side of midnight.
      expect(
        windowEnd(windows, DateTime(2026, 7, 19, 0, 30)),
        DateTime(2026, 7, 19, 1, 0),
      );
    });

    // The schedule is WALL-CLOCK (so is the firmware's), so the end must be
    // built from calendar components. Building it as `startOfDay + Duration`
    // adds ABSOLUTE elapsed time, which on a DST-transition day lands an hour
    // off: a 05:30–07:00 window would report 08:00 on a spring-forward Sunday
    // and 06:00 on a fall-back one.
    //
    // These two tests only DISCRIMINATE when the host zone observes DST (in
    // UTC they hold trivially either way) — but they never flake, and in any
    // DST zone they fail on the Duration form.
    test('reports wall-clock end across a DST transition', () {
      final windows = expandWindows([
        // Sunday 05:30 +90 -> 07:00. Every DST transition below happens
        // overnight on a Sunday, BEFORE the window opens.
        schedule(hour: 5, minute: 30, days: {7}, keepAwakeFor: 90),
      ]);
      const transitionSundays = [
        (2026, 3, 8), // US spring forward
        (2026, 3, 29), // EU spring forward
        (2026, 10, 25), // EU fall back
        (2026, 11, 1), // US fall back
      ];
      for (final (y, m, d) in transitionSundays) {
        expect(
          windowEnd(windows, DateTime(y, m, d, 6, 0)),
          DateTime(y, m, d, 7, 0),
          reason: 'wall-clock 07:00 on $y-$m-$d, not 07:00 of elapsed time',
        );
      }
    });

    test('end is on the wall clock on every day of the year', () {
      final windows = expandWindows([
        schedule(hour: 5, minute: 30, days: {1, 2, 3, 4, 5, 6, 7}, keepAwakeFor: 90),
      ]);
      // Whatever the host zone, and whichever day it shifts on, an open
      // 05:30–07:00 window always closes at wall-clock 07:00.
      for (var day = DateTime(2026, 1, 1);
          day.year == 2026;
          day = DateTime(2026, day.month, day.day + 1)) {
        final end = windowEnd(windows, DateTime(day.year, day.month, day.day, 6, 0));
        expect(end, isNotNull, reason: '$day');
        expect(end!.hour, 7, reason: '$day');
        expect(end.minute, 0, reason: '$day');
      }
    });
  });

  group('windowsFromSettingsJson', () {
    test('parses the settings blob', () {
      final json = WakeSchedule.serializeList([
        schedule(hour: 5, minute: 30, days: {1, 2, 3, 4, 5}, keepAwakeFor: 90),
      ]);
      expect(windowsFromSettingsJson(json), hasLength(5));
    });

    test('empty / "[]" blob yields no windows', () {
      expect(windowsFromSettingsJson(''), isEmpty);
      expect(windowsFromSettingsJson('[]'), isEmpty);
    });

    test('a malformed blob yields no windows instead of throwing', () {
      // This runs inside a timer callback and a connect flow — it must never
      // throw.
      expect(windowsFromSettingsJson('{not json'), isEmpty);
      expect(windowsFromSettingsJson('[{"id":"x"}]'), isEmpty);
    });
  });
}
