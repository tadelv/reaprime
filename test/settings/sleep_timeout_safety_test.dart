import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/sleep_timeout_safety.dart';


/// SAFETY. The machine's `InactivitySleepTimeout` is what turns the heaters off
/// when this tablet is gone (dead battery, crashed app, blackout). The firmware
/// reads `<= 0` as "never sleep", and persists the value to flash — so a single
/// `0` from this app makes the machine hot-forever across power cycles, and
/// LESS safe than one that never met the app (the firmware default is 60 min).
///
/// `machineSleepTimeoutMinutes` is the one function standing between every
/// entry point (UI dropdown, REST, settings import, de1app TDB import) and that
/// register. These tests pin its contract. Do not relax them.
void main() {
  group('machineSleepTimeoutMinutes: never returns 0', () {
    test('presence OFF -> the protective floor, not 0', () {
      expect(
        machineSleepTimeoutMinutes(
          userPresenceEnabled: false,
          userTimeoutMinutes: 30,
        ),
        kSafetySleepFloorMinutes,
      );
    });

    test('dropdown "Disabled" (0) -> the protective floor, not 0', () {
      expect(
        machineSleepTimeoutMinutes(
          userPresenceEnabled: true,
          userTimeoutMinutes: 0,
        ),
        kSafetySleepFloorMinutes,
      );
    });

    test('the floor matches the FIRMWARE default, so the app can never make a '
        'machine less safe than a factory-fresh one', () {
      expect(kSafetySleepFloorMinutes, 60);
    });

    test('a valid user value is honoured exactly, including below the floor',
        () {
      for (final minutes in [1, 15, 30, 45, 60, 90, 120, 180, 240]) {
        expect(
          machineSleepTimeoutMinutes(
            userPresenceEnabled: true,
            userTimeoutMinutes: minutes,
          ),
          minutes,
          reason: '$minutes is a safe, deliberate choice — 30 min is SAFER '
              'than the 60 min floor, so the floor must not raise it',
        );
      }
    });

    test('every possible input pair lands in the firmware\'s 1..240, never 0',
        () {
      for (final enabled in [true, false]) {
        for (final minutes in [
          -100000, -241, -60, -1, 0, 1, 239, 240, 241, 100000,
        ]) {
          final result = machineSleepTimeoutMinutes(
            userPresenceEnabled: enabled,
            userTimeoutMinutes: minutes,
          );
          expect(
            result,
            inInclusiveRange(
                kMinMachineSleepTimeoutMinutes, kMaxSleepTimeoutMinutes),
            reason: 'presence=$enabled minutes=$minutes escaped the safe range',
          );
          expect(result, isNot(0),
              reason: 'presence=$enabled minutes=$minutes disabled the machine '
                  'safety net');
        }
      }
    });
  });
}
