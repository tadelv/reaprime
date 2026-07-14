import 'package:logging/logging.dart';
import 'package:reaprime/src/models/wake_schedule.dart';

/// Derivation of concrete wake WINDOWS from the app's [WakeSchedule] list,
/// in the firmware's own semantics.
///
/// **This is the single source of truth for "when is a wake window open".**
/// It suppresses the app's own idle-sleep timer
/// (`PresenceController._onSleepTimeout`), and it is the derivation any
/// machine-side scheduler should pack its own schedule table from — one
/// derivation, so an autonomous scheduler and the app's sleep logic can never
/// disagree about when a window is open.
///
/// Pure Dart: no Flutter, no device, no I/O. Everything here is testable
/// against the firmware decoder.

final Logger _log = Logger('WakeScheduleWindows');

/// Window length used for a schedule with no `keepAwakeFor` ("wake-only").
///
/// The firmware cannot express "wake, then hand straight back to the idle
/// timer" — it rejects `startMin >= endMin`, so a window must have real
/// length. 30 minutes matches the app's default sleep timeout: the machine
/// wakes on the window's rising edge, is held awake for 30 min, then
/// `InactivitySleepTimeout` governs again. (A 1-minute window is
/// semantically purer but a fragile target against any firmware-clock
/// error, and a missed window means the machine never wakes at all.)
const int kDefaultWakeWindowMinutes = 30;

/// Firmware table capacity. The
/// firmware SILENTLY drops the 33rd entry, so the app merges and caps
/// (see [expandWindows]) rather than inheriting that behaviour.
const int kMaxWakeWindows = 32;

/// Minutes in a day. `endMin == kMinutesPerDay` (1440) is legal and means
/// "up to, but not including, midnight" (`endMin` is exclusive).
const int kMinutesPerDay = 1440;

/// Seconds in a week. The firmware rejects `secOfWeek >= 604800`
///, so the largest writable value is 604799.
const int kSecondsPerWeek = 604800;

/// Maps an ISO-8601 weekday (`DateTime.weekday`: 1 = Monday … 7 = Sunday)
/// onto the firmware's day INDEX (0 = Sunday … 6 = Saturday).
///
/// The firmware compares the day for EQUALITY against
/// `getLocalSecOfWeek() / 86400`, which is 0 on Sunday — it is NOT a
/// bitmask. See [packWakeWindow].
int fwDayOfWeek(int isoWeekday) => isoWeekday % 7;

/// One firmware wake window, in firmware semantics.
///
/// [dow] is a day INDEX (0 = Sunday … 6 = Saturday), [startMin] is
/// inclusive, [endMin] is exclusive, both minutes after LOCAL midnight.
class WakeWindow {
  const WakeWindow({
    required this.dow,
    required this.startMin,
    required this.endMin,
  });

  /// Day index, 0 = Sunday … 6 = Saturday (NOT a bitmask).
  final int dow;

  /// Minutes after local midnight, inclusive. 0…1439.
  final int startMin;

  /// Minutes after local midnight, exclusive. 1…1440.
  final int endMin;

  /// This window packed for the `ScheduleEntry` register.
  int get packed =>
      packWakeWindow(dow: dow, startMin: startMin, endMin: endMin);

  @override
  bool operator ==(Object other) =>
      other is WakeWindow &&
      other.dow == dow &&
      other.startMin == startMin &&
      other.endMin == endMin;

  @override
  int get hashCode => Object.hash(dow, startMin, endMin);

  @override
  String toString() => 'WakeWindow(dow: $dow, $startMin..$endMin)';
}

/// Packs one wake window for the firmware `ScheduleEntry` register:
/// `(dow << 22) | (startMin << 11) | endMin`.
///
/// **`dow` is a DAY INDEX (0 = Sunday … 6 = Saturday), NOT a bitmask.**
/// The firmware does `(packed >> 22) & 0x7` and then compares the result
/// for equality against today's day index, so a
/// "Mon–Fri" schedule is five separate entries. Packing the ISO day set as
/// a bitmask (`0b0111110` = 62) would decode to `62 & 7 == 6` — one window,
/// on Saturday — and the firmware would report no error.
///
/// The firmware silently drops an entry with `dow > 6`,
/// `startMin >= endMin` (so zero-length and midnight-crossing windows are
/// impossible — the caller must split them) or `endMin > 1440`.
int packWakeWindow({
  required int dow,
  required int startMin,
  required int endMin,
}) {
  assert(dow >= 0 && dow <= 6, 'dow is a day index 0..6, not a bitmask');
  assert(startMin >= 0 && startMin < endMin, 'firmware rejects start >= end');
  assert(endMin <= kMinutesPerDay, 'firmware rejects endMin > 1440');
  return (dow << 22) | (startMin << 11) | endMin;
}

/// Expands the app's [schedules] into the firmware's wake windows:
/// one entry PER DAY, midnight-crossing windows split across two days,
/// overlapping/touching windows merged, capped at [kMaxWakeWindows],
/// deterministically ordered by `(dow, startMin)`.
///
/// Disabled schedules contribute nothing. An empty `daysOfWeek` means
/// "every day" (7 entries). A schedule without `keepAwakeFor` gets a
/// [kDefaultWakeWindowMinutes] window.
List<WakeWindow> expandWindows(List<WakeSchedule> schedules) {
  final raw = <WakeWindow>[];

  for (final schedule in schedules) {
    if (!schedule.enabled) continue;
    final startMin = schedule.hour * 60 + schedule.minute;
    if (startMin < 0 || startMin >= kMinutesPerDay) {
      _log.warning('Skipping schedule ${schedule.id}: start minute $startMin '
          'is outside 0..1439');
      continue;
    }
    // WakeSchedule already normalises `0` to null; clamp defensively so a
    // hand-edited settings blob can never emit an entry the firmware drops.
    final windowMinutes =
        (schedule.keepAwakeFor ?? kDefaultWakeWindowMinutes).clamp(1, 720);
    final endMinRaw = startMin + windowMinutes;

    final isoDays = schedule.daysOfWeek.isEmpty
        ? const <int>{1, 2, 3, 4, 5, 6, 7} // empty set = every day
        : schedule.daysOfWeek;

    for (final iso in isoDays) {
      if (iso < 1 || iso > 7) {
        _log.warning('Skipping day $iso of schedule ${schedule.id}: not an '
            'ISO weekday (1..7)');
        continue;
      }
      final dow = fwDayOfWeek(iso);
      if (endMinRaw <= kMinutesPerDay) {
        raw.add(WakeWindow(dow: dow, startMin: startMin, endMin: endMinRaw));
      } else {
        // Midnight crossing: the firmware rejects startMin >= endMin, so the
        // app splits the window across two consecutive day indices. Saturday
        // wraps to Sunday — the table is a weekly repeat, so "next Sunday"
        // and "this Sunday" are the same slot.
        raw.add(WakeWindow(
          dow: dow,
          startMin: startMin,
          endMin: kMinutesPerDay,
        ));
        raw.add(WakeWindow(
          dow: (dow + 1) % 7,
          startMin: 0,
          endMin: endMinRaw - kMinutesPerDay,
        ));
      }
    }
  }

  final merged = mergeWindows(raw);
  if (merged.length <= kMaxWakeWindows) return merged;

  _log.warning(
    'Wake schedule produces ${merged.length} windows but the firmware table '
    'holds $kMaxWakeWindows; dropping the last ${merged.length - kMaxWakeWindows}. '
    'Reduce the number of schedules or merge overlapping ones.',
  );
  return merged.sublist(0, kMaxWakeWindows);
}

/// Merges overlapping OR touching windows within each day and returns them
/// sorted by `(dow, startMin)`. Touching (`next.startMin == current.endMin`)
/// windows merge too: two adjacent windows are one window, and every entry
/// saved is a firmware table slot saved.
List<WakeWindow> mergeWindows(List<WakeWindow> windows) {
  final byDay = <int, List<WakeWindow>>{};
  for (final w in windows) {
    byDay.putIfAbsent(w.dow, () => <WakeWindow>[]).add(w);
  }

  final merged = <WakeWindow>[];
  final days = byDay.keys.toList()..sort();
  for (final dow in days) {
    final day = byDay[dow]!..sort((a, b) {
      final byStart = a.startMin.compareTo(b.startMin);
      return byStart != 0 ? byStart : a.endMin.compareTo(b.endMin);
    });
    var start = day.first.startMin;
    var end = day.first.endMin;
    for (final w in day.skip(1)) {
      if (w.startMin <= end) {
        // Overlapping or touching — union them.
        if (w.endMin > end) end = w.endMin;
      } else {
        merged.add(WakeWindow(dow: dow, startMin: start, endMin: end));
        start = w.startMin;
        end = w.endMin;
      }
    }
    merged.add(WakeWindow(dow: dow, startMin: start, endMin: end));
  }
  return merged;
}

/// Whether [now] falls inside any of [windows]. Start inclusive, end
/// exclusive — the same comparison the firmware makes
///.
bool isWithinWindow(List<WakeWindow> windows, DateTime now) {
  final dow = fwDayOfWeek(now.weekday);
  final minute = now.hour * 60 + now.minute;
  for (final w in windows) {
    if (w.dow == dow && minute >= w.startMin && minute < w.endMin) return true;
  }
  return false;
}

/// The wall-clock instant the window containing [now] closes, or `null` if
/// [now] is not inside a window.
///
/// Chains across a midnight split: a window ending at 24:00 whose successor
/// day starts at 00:00 reports the successor's end, so the caller sees the
/// user's real "keep awake until" rather than the internal split boundary.
///
/// Component-based on purpose, like [isWithinWindow] and [localSecondsOfWeek]:
/// the schedule is wall-clock, so the end must be built from calendar fields.
/// Adding a [Duration] instead would add *absolute* elapsed time, and across a
/// DST transition that lands an hour off the wall clock the user (and the
/// firmware) actually schedules against — a 05:30–07:00 window on a
/// spring-forward day would report 08:00.
DateTime? windowEnd(List<WakeWindow> windows, DateTime now) {
  final minute = now.hour * 60 + now.minute;
  var dow = fwDayOfWeek(now.weekday);

  WakeWindow? active;
  for (final w in windows) {
    if (w.dow == dow && minute >= w.startMin && minute < w.endMin) {
      active = w;
      break;
    }
  }
  if (active == null) return null;

  var dayOffset = 0;
  var end = active.endMin;
  // Follow midnight-split chains (bounded by the 7 days in the table, so a
  // pathological all-day-every-day table cannot spin here).
  for (var hop = 0; hop < 7 && end == kMinutesPerDay; hop++) {
    final nextDow = (dow + 1) % 7;
    WakeWindow? next;
    for (final w in windows) {
      if (w.dow == nextDow && w.startMin == 0) {
        next = w;
        break;
      }
    }
    if (next == null) break;
    dow = nextDow;
    dayOffset++;
    end = next.endMin;
  }

  // `end` may be kMinutesPerDay (a 24:00 close with no successor to chain to);
  // DateTime normalises hour 24 to 00:00 of the following day, which is the
  // instant we mean.
  return DateTime(
    now.year,
    now.month,
    now.day + dayOffset,
    end ~/ 60,
    end % 60,
  );
}

/// LOCAL seconds since Sunday 00:00:00, for the firmware `SetLocalTimeOfWeek`
/// register.
///
/// Component-based on purpose: epoch arithmetic breaks across a DST
/// transition, and the firmware clock is a LOCAL wall-clock, not UTC.
///
/// Clamped to `1..604799`: the firmware rejects `>= 604800` outright, and the
/// app never writes `0` because a read-back of `0` is the "rebooted, never
/// synced" sentinel (the register is RAM-only with initval 0). Sunday
/// 00:00:00 therefore reports 1 — a ≤ 1 s lie once a week, in exchange for an
/// unambiguous reboot signal.
int localSecondsOfWeek(DateTime now) {
  final seconds = fwDayOfWeek(now.weekday) * 86400 +
      now.hour * 3600 +
      now.minute * 60 +
      now.second;
  return seconds.clamp(1, kSecondsPerWeek - 1);
}

/// Parses the settings blob (`SettingsController.wakeSchedules`) into
/// windows, tolerating a malformed blob (logs and returns no windows rather
/// than throwing into a connect flow or a timer callback).
List<WakeWindow> windowsFromSettingsJson(String json) {
  if (json.isEmpty || json == '[]') return const <WakeWindow>[];
  try {
    return expandWindows(WakeSchedule.deserializeList(json));
  } catch (e) {
    _log.warning('Failed to parse wake schedules; treating as none', e);
    return const <WakeWindow>[];
  }
}
