import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/bengle_schedule_sync.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scan_filter.dart';
import 'package:reaprime/src/models/wake_schedule.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/sleep_timeout_safety.dart';
import 'package:rxdart/subjects.dart';

import '../helpers/mock_settings_service.dart';

/// `BengleScheduleSync`: the app writing the schedule registers so the
/// machine runs its scheduler with NO tablet connected.
///
/// The contract these tests defend:
///  * SAFETY — the app never writes an `InactivitySleepTimeout` that disables
///    the machine's autonomous sleep, and never leaves a wake schedule armed
///    when the user has turned auto-wake off (see the safety group below);
///  * the WRITE ORDER on connect (clock, then timeout, then control 0 ->
///    entries -> control 1) — the firmware clears the table on control 0 and
///    ignores an enabled table while its clock is invalid;
///  * the DIFF (an unrelated settings change must not re-push the table — a
///    re-push re-arms the firmware's rising-edge wake and would re-wake a
///    machine the user had just slept);
///  * BENGLE-GATING — a plain DE1 must see not one write.

/// Records every write the sync makes, in order, as a flat wire log.
class _RecordingBengle implements BengleInterface {
  _RecordingBengle({this.failWritesUntil = 0});

  /// Fail the first N *write* calls, to exercise the retry path.
  int failWritesUntil;
  int _writeCount = 0;

  /// The wire log: `clock:<sec>`, `timeout:<min>`, `control:<0|1>`,
  /// `entry:0x<hex>`.
  final List<String> log = [];

  /// Simulated firmware state (RAM-only, exactly like the real registers).
  int clockEcho = 0;
  int scheduleControl = 0;

  void _maybeFail() {
    _writeCount++;
    if (_writeCount <= failWritesUntil) {
      throw StateError('simulated MMR write failure #$_writeCount');
    }
  }

  @override
  Future<void> setLocalTimeOfWeek(int secondsOfWeek) async {
    _maybeFail();
    log.add('clock:$secondsOfWeek');
    clockEcho = secondsOfWeek;
  }

  @override
  Future<void> setInactivitySleepTimeout(int minutes) async {
    _maybeFail();
    log.add('timeout:$minutes');
  }

  @override
  Future<void> pushWakeSchedule(List<int> packedWindows) async {
    _maybeFail();
    log.add('control:0');
    scheduleControl = 0;
    if (packedWindows.isEmpty) return;
    for (final p in packedWindows) {
      log.add('entry:0x${p.toRadixString(16).toUpperCase().padLeft(8, '0')}');
    }
    log.add('control:1');
    scheduleControl = 1;
  }

  @override
  Future<int> readLocalTimeOfWeekEcho() async => clockEcho;

  @override
  Future<int> readScheduleControl() async => scheduleControl;

  /// Simulate a power-cycle: the clock and the table are RAM-only.
  void reboot() {
    clockEcho = 0;
    scheduleControl = 0;
  }

  @override
  String get deviceId => 'rec-bengle';
  @override
  String get name => 'Bengle-rec';
  @override
  DeviceType get type => DeviceType.machine;
  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.connected);
  @override
  Stream<bool> get ready => Stream<bool>.value(false);
  @override
  Stream<De1ShotSettings> get shotSettings => const Stream.empty();
  @override
  Future<void> onConnect() async {}
  @override
  Future<void> disconnect() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A non-Bengle DE1 that records ANY method call. The Bengle-gating test
/// asserts this log stays empty: nothing at all may reach a plain DE1.
class _RecordingDe1 implements De1Interface {
  final List<Symbol> calls = [];

  @override
  String get deviceId => 'plain-de1';
  @override
  String get name => 'DE1';
  @override
  DeviceType get type => DeviceType.machine;
  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.connected);
  @override
  Stream<bool> get ready => Stream<bool>.value(false);
  @override
  Stream<De1ShotSettings> get shotSettings => const Stream.empty();
  @override
  Future<void> onConnect() async {}
  @override
  Future<void> disconnect() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    return null;
  }
}

class _FakeDiscoveryService implements DeviceDiscoveryService {
  @override
  Stream<List<Device>> get devices => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> scanForDevices({ScanFilter? filter}) async {}
  @override
  void stopScan() {}
}

/// De1Controller with a directly-drivable machine stream.
class _TestDe1Controller extends De1Controller {
  _TestDe1Controller({required super.controller});

  final BehaviorSubject<De1Interface?> _subject =
      BehaviorSubject<De1Interface?>.seeded(null);

  @override
  Stream<De1Interface?> get de1 => _subject.stream;

  void setDe1(De1Interface? device) => _subject.add(device);
}

void main() {
  late _TestDe1Controller de1Controller;
  late SettingsController settings;

  // 2026-07-14 is a Tuesday. 07:20:00 local = 2*86400 + 7*3600 + 20*60 =
  // 199200 seconds of week (the spec's worked example).
  DateTime now = DateTime(2026, 7, 14, 7, 20, 0);
  const int nowSecOfWeek = 199200;

  // Ben's schedule: Mon-Fri 05:30, keep awake 90 min.
  final benSchedule = WakeSchedule(
    id: 'ben',
    hour: 5,
    minute: 30,
    daysOfWeek: const {1, 2, 3, 4, 5},
    enabled: true,
    keepAwakeFor: 90,
  );
  const benEntries = [
    'entry:0x004A51A4',
    'entry:0x008A51A4',
    'entry:0x00CA51A4',
    'entry:0x010A51A4',
    'entry:0x014A51A4',
  ];

  setUp(() async {
    now = DateTime(2026, 7, 14, 7, 20, 0);
    de1Controller = _TestDe1Controller(
      controller: DeviceController([_FakeDiscoveryService()]),
    );
    settings = SettingsController(MockSettingsService());
    await settings.loadSettings();
  });

  BengleScheduleSync makeSync() => BengleScheduleSync(
        de1Controller: de1Controller,
        settingsController: settings,
        clock: () => now,
        retryDelays: const [Duration(seconds: 3)],
      );

  test('Bengle connect: clock -> timeout -> control(0) -> entries -> control(1)',
      () {
    fakeAsync((async) {
      settings.setSleepTimeoutMinutes(30);
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final bengle = _RecordingBengle();
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();

      // Spec §5.1, verbatim: the clock FIRST (the firmware ignores an enabled
      // table while its clock is invalid), then the persisted sleep timeout,
      // then the clear -> entries -> enable sequence.
      expect(bengle.log, [
        'clock:$nowSecOfWeek',
        'timeout:30',
        'control:0',
        ...benEntries,
        'control:1',
      ]);

      sync.dispose();
    });
  });

  test('a non-Bengle DE1 gets NOTHING — not one call', () {
    fakeAsync((async) {
      settings.setSleepTimeoutMinutes(30);
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final de1 = _RecordingDe1();
      de1Controller.setDe1(de1);
      async.flushMicrotasks();

      // And a settings edit while it is connected still writes nothing.
      settings.setSleepTimeoutMinutes(60);
      async.elapse(const Duration(minutes: 40)); // past a clock-resync tick

      expect(
        de1.calls,
        isEmpty,
        reason: 'these registers do not exist on a stock DE1 — the whole '
            'feature is Bengle-gated',
      );

      sync.dispose();
    });
  });

  test('no enabled schedules: control(0) only — no entries, no enable', () {
    fakeAsync((async) {
      settings.setWakeSchedules(WakeSchedule.serializeList([
        benSchedule.copyWith(enabled: false),
      ]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final bengle = _RecordingBengle();
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();

      expect(bengle.log.where((e) => e.startsWith('entry:')), isEmpty);
      expect(bengle.log, contains('control:0'));
      expect(
        bengle.log,
        isNot(contains('control:1')),
        reason: 'an enabled EMPTY table is a lie; clear + disable is the state',
      );

      sync.dispose();
    });
  });

  test('an unrelated settings change does NOT re-push the table', () {
    fakeAsync((async) {
      settings.setSleepTimeoutMinutes(30);
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final bengle = _RecordingBengle();
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();
      bengle.log.clear();

      // SettingsController.addListener fires on ANY settings write. A re-push
      // clears the table, which drops the firmware's WasInAwakeWindow edge and
      // would re-wake a machine the user just slept — so the diff must hold.
      settings.setLowBatteryBrightnessLimit(true);
      async.flushMicrotasks();

      expect(bengle.log, isEmpty);

      sync.dispose();
    });
  });

  test('editing a schedule re-pushes the whole table', () {
    fakeAsync((async) {
      settings.setSleepTimeoutMinutes(30);
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final bengle = _RecordingBengle();
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();
      bengle.log.clear();

      // Drop Friday.
      settings.setWakeSchedules(WakeSchedule.serializeList([
        benSchedule.copyWith(daysOfWeek: const {1, 2, 3, 4}),
      ]));
      async.flushMicrotasks();

      expect(bengle.log, [
        'control:0',
        ...benEntries.take(4),
        'control:1',
      ]);
      // The clock and the timeout are unchanged, so they are NOT re-written.
      expect(bengle.log.where((e) => e.startsWith('clock:')), isEmpty);
      expect(bengle.log.where((e) => e.startsWith('timeout:')), isEmpty);

      sync.dispose();
    });
  });

  test('editing the sleep timeout writes the timeout ONLY — no table churn',
      () {
    fakeAsync((async) {
      settings.setSleepTimeoutMinutes(30);
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final bengle = _RecordingBengle();
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();
      bengle.log.clear();

      settings.setSleepTimeoutMinutes(90);
      async.flushMicrotasks();

      expect(bengle.log, ['timeout:90']);

      sync.dispose();
    });
  });

  /// SAFETY. `InactivitySleepTimeout` is the machine's thermal cut-out for when
  /// this tablet is gone — dead battery, crashed app, blackout. The firmware
  /// treats `<= 0` as "never sleep", and the value is PERSISTED TO FLASH and
  /// reloaded at every boot, so a single `0` from this app leaves the machine
  /// hot forever, across power cycles, and less safe than one that never met
  /// the app at all (the firmware's own default is 60 min).
  ///
  /// These tests exist to make sure nobody ever "restores" that behaviour.
  /// If one of them fails, do not relax it — the machine is the thing at stake.
  group('never disables the machine\'s inactivity safety net', () {
    /// Every timeout this app has ever written to the machine.
    List<int> timeoutsWritten(_RecordingBengle b) => b.log
        .where((e) => e.startsWith('timeout:'))
        .map((e) => int.parse(e.split(':')[1]))
        .toList();

    test('arms the FW schedule so the machine wakes and sleeps autonomously '
        'without a tablet', () {
      fakeAsync((async) {
        // THE INTENDED BEHAVIOUR, and it must not be broken by the safety work:
        // with the tablet gone, the FIRMWARE wakes the machine at the window
        // start, holds it awake for the window (`checkSchedule` calls
        // its user-present hook every tick inside it, re-arming the idle clock),
        // and then — once the window closes and that stops — the inactivity
        // timer runs down and sleeps it. Wake AND sleep, no tablet involved.
        //
        // That needs BOTH halves armed, so assert both:
        settings.setUserPresenceEnabled(true);
        settings.setSleepTimeoutMinutes(30);
        settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
        async.flushMicrotasks();

        final sync = makeSync()..initialize();
        final bengle = _RecordingBengle();
        de1Controller.setDe1(bengle);
        async.flushMicrotasks();

        // 1. the table is armed (entries + ScheduleControl=1) — this is what
        //    lets the machine wake ITSELF at 05:30 with no tablet present, and
        //    it is deliberately NOT gated on tablet connectivity;
        expect(bengle.log.where((e) => e.startsWith('entry:')), hasLength(5));
        expect(bengle.log.last, 'control:1');
        expect(bengle.scheduleControl, 1);

        // 2. a NON-ZERO inactivity timeout — this is what lets it sleep again
        //    after the window closes. A 0 here (the old behaviour) would leave
        //    it awake and hot forever after the first scheduled wake.
        expect(timeoutsWritten(bengle), [30]);
        expect(bengle.log, isNot(contains('timeout:0')));

        sync.dispose();
      });
    });

    test('presence OFF: protective floor is written, and the wake table is '
        'EMPTY + disabled', () {
      fakeAsync((async) {
        settings.setSleepTimeoutMinutes(30);
        settings.setUserPresenceEnabled(false);
        // A schedule the user configured while the toggle was still on.
        settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
        async.flushMicrotasks();

        final sync = makeSync()..initialize();
        final bengle = _RecordingBengle();
        de1Controller.setDe1(bengle);
        async.flushMicrotasks();

        // The master toggle governs whether the TABLET sleeps the machine. It
        // is not licence to disarm the MACHINE.
        expect(timeoutsWritten(bengle), [kSafetySleepFloorMinutes]);
        expect(bengle.log, isNot(contains('timeout:0')));

        // ...and the machine must not be left waking ITSELF every morning with
        // a dead tablet and nobody there. Cleared (control:0) and NOT enabled.
        expect(bengle.log.where((e) => e.startsWith('entry:')), isEmpty);
        expect(bengle.log, contains('control:0'));
        expect(
          bengle.log,
          isNot(contains('control:1')),
          reason: 'the UI hides the schedule section when the master toggle is '
              'off, so the user believes wake is off — it must BE off',
        );
        expect(bengle.scheduleControl, 0);

        sync.dispose();
      });
    });

    test('dropdown "Disabled" (0): protective floor is written, not 0', () {
      fakeAsync((async) {
        settings.setUserPresenceEnabled(true);
        settings.setSleepTimeoutMinutes(0); // literally the "Disabled" item
        async.flushMicrotasks();

        final sync = makeSync()..initialize();
        final bengle = _RecordingBengle();
        de1Controller.setDe1(bengle);
        async.flushMicrotasks();

        // The user is disabling the APP's idle timer. They are not being
        // offered — and would not understand — a choice to disable the
        // machine's blackout backstop.
        expect(timeoutsWritten(bengle), [kSafetySleepFloorMinutes]);
        expect(bengle.log, isNot(contains('timeout:0')));

        sync.dispose();
      });
    });

    test('a valid user setting is honoured exactly (30 stays 30)', () {
      fakeAsync((async) {
        settings.setUserPresenceEnabled(true);
        settings.setSleepTimeoutMinutes(30);
        async.flushMicrotasks();

        final sync = makeSync()..initialize();
        final bengle = _RecordingBengle();
        de1Controller.setDe1(bengle);
        async.flushMicrotasks();

        // The floor must not override a deliberate, safe user choice — not even
        // one BELOW the floor. 30 min is safer than 60, not less safe.
        expect(timeoutsWritten(bengle), [30]);

        sync.dispose();
      });
    });

    test('rogue values from ANY entry point never write 0 or an out-of-range '
        'timeout', () {
      // The REST API (`POST /api/v1/presence/settings`), an imported settings
      // blob and the de1app TDB importer all funnel through
      // `setSleepTimeoutMinutes`. Drive the poison in there and watch the WIRE.
      for (final rogue in [0, -1, -999, 999, 100000]) {
        fakeAsync((async) {
          settings.setUserPresenceEnabled(true);
          settings.setSleepTimeoutMinutes(rogue);
          async.flushMicrotasks();

          final sync = makeSync()..initialize();
          final bengle = _RecordingBengle();
          de1Controller.setDe1(bengle);
          async.flushMicrotasks();

          final written = timeoutsWritten(bengle);
          expect(written, hasLength(1),
              reason: 'rogue input $rogue: the machine is always told a value');
          expect(
            written.single,
            inInclusiveRange(
                kMinMachineSleepTimeoutMinutes, kMaxSleepTimeoutMinutes),
            reason: 'rogue input $rogue must land in the firmware\'s 1..240 — '
                'never 0 (= never sleep), never a value the FW would reject',
          );

          sync.dispose();
        });
      }
    });

    test('every Bengle connect is left at least as safe as it was found', () {
      fakeAsync((async) {
        // A user who has never opened the presence page at all: whatever the
        // machine held before (a 0 burned into flash by an older build, say),
        // simply connecting must restore a protective value.
        final sync = makeSync()..initialize();
        final bengle = _RecordingBengle();
        de1Controller.setDe1(bengle);
        async.flushMicrotasks();

        final written = timeoutsWritten(bengle);
        expect(written, hasLength(1),
            reason: 'the timeout is pushed PROACTIVELY on every connect, not '
                'only when the user has configured something');
        expect(written.single, greaterThan(0));
        expect(written.single,
            inInclusiveRange(kMinMachineSleepTimeoutMinutes, kMaxSleepTimeoutMinutes));

        sync.dispose();
      });
    });
  });

  test('the 15-minute tick re-writes the clock and NOTHING else', () {
    fakeAsync((async) {
      settings.setSleepTimeoutMinutes(30);
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final bengle = _RecordingBengle();
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();
      bengle.log.clear();

      now = now.add(const Duration(minutes: 15));
      async.elapse(const Duration(minutes: 15));
      async.flushMicrotasks();

      expect(bengle.log, ['clock:${nowSecOfWeek + 15 * 60}']);
      expect(
        bengle.log.where((e) => e.startsWith('control:')),
        isEmpty,
        reason: 'a table re-push on a timer would re-arm the firmware wake '
            'edge every 15 minutes',
      );

      sync.dispose();
    });
  });

  test('reboot detected on the verify poll (clock echoes 0) => full re-push',
      () {
    fakeAsync((async) {
      settings.setSleepTimeoutMinutes(30);
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final bengle = _RecordingBengle();
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();
      bengle.log.clear();

      // The machine power-cycles without the link dropping (possible on USB
      // serial). Its clock and table are RAM-only and are gone.
      bengle.reboot();

      now = now.add(const Duration(minutes: 15));
      async.elapse(const Duration(minutes: 15));
      async.flushMicrotasks();

      expect(bengle.log, [
        'clock:${nowSecOfWeek + 15 * 60}',
        'timeout:30',
        'control:0',
        ...benEntries,
        'control:1',
      ]);

      sync.dispose();
    });
  });

  test('ScheduleControl echoing 0 while a schedule is expected => re-push', () {
    fakeAsync((async) {
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final bengle = _RecordingBengle();
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();
      bengle.log.clear();

      // Another client cleared the table (clock intact, so this is the only
      // signal we get).
      bengle.scheduleControl = 0;

      async.elapse(const Duration(minutes: 15));
      async.flushMicrotasks();

      expect(bengle.log.where((e) => e.startsWith('entry:')), hasLength(5));
      expect(bengle.log.last, 'control:1');

      sync.dispose();
    });
  });

  test('reconnect re-pushes everything (device state is never assumed)', () {
    fakeAsync((async) {
      settings.setSleepTimeoutMinutes(30);
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final first = _RecordingBengle();
      de1Controller.setDe1(first);
      async.flushMicrotasks();
      expect(first.log, isNotEmpty);

      // Link drops, then the same schedule, a fresh machine instance.
      de1Controller.setDe1(null);
      async.flushMicrotasks();

      final second = _RecordingBengle();
      de1Controller.setDe1(second);
      async.flushMicrotasks();

      expect(second.log, [
        'clock:$nowSecOfWeek',
        'timeout:30',
        'control:0',
        ...benEntries,
        'control:1',
      ]);

      sync.dispose();
    });
  });

  test('disconnect cancels the clock timer', () {
    fakeAsync((async) {
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final bengle = _RecordingBengle();
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();

      de1Controller.setDe1(null);
      async.flushMicrotasks();
      bengle.log.clear();

      async.elapse(const Duration(hours: 1));
      expect(bengle.log, isEmpty);
      expect(async.periodicTimerCount, 0);

      sync.dispose();
    });
  });

  test('a failed write is retried, not crashed on, and the order still holds',
      () {
    fakeAsync((async) {
      settings.setSleepTimeoutMinutes(30);
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      // The very first write (the clock) fails: nothing may be stamped as
      // pushed, and the connect flow must survive it.
      final bengle = _RecordingBengle(failWritesUntil: 1);
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();
      expect(bengle.log, isEmpty);

      async.elapse(const Duration(seconds: 3)); // the retry delay
      async.flushMicrotasks();

      expect(bengle.log, [
        'clock:$nowSecOfWeek',
        'timeout:30',
        'control:0',
        ...benEntries,
        'control:1',
      ]);

      sync.dispose();
    });
  });

  test('dispose cancels everything and stops listening to settings', () {
    fakeAsync((async) {
      settings.setWakeSchedules(WakeSchedule.serializeList([benSchedule]));
      async.flushMicrotasks();

      final sync = makeSync()..initialize();
      final bengle = _RecordingBengle();
      de1Controller.setDe1(bengle);
      async.flushMicrotasks();
      bengle.log.clear();

      sync.dispose();

      settings.setSleepTimeoutMinutes(120);
      async.elapse(const Duration(hours: 1));

      expect(bengle.log, isEmpty);
      expect(async.periodicTimerCount, 0);
    });
  });
}
