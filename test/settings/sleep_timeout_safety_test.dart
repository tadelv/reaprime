import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/sleep_timeout_safety.dart';

import '../helpers/mock_settings_service.dart';

/// `sleepTimeoutMinutes` is reachable from `POST /api/v1/presence/settings` and
/// from an imported settings blob. Both are untrusted, and both used to be
/// hard-cast (`json['sleepTimeoutMinutes'] as int`) — so a string, a bool or a
/// wildly out-of-range number was either stored verbatim or thrown as a 500.
///
/// These pin what the app will accept and store.
void main() {
  group('sanitizeSleepTimeoutSetting: bounds untrusted REST/import input', () {
    test('rejects values that are not a number at all', () {
      expect(sanitizeSleepTimeoutSetting(null), isNull);
      expect(sanitizeSleepTimeoutSetting(true), isNull);
      expect(sanitizeSleepTimeoutSetting('abc'), isNull);
      expect(sanitizeSleepTimeoutSetting(<int>[30]), isNull);
    });

    test('clamps out-of-range numbers into the storable range', () {
      expect(sanitizeSleepTimeoutSetting(-1), kMinSleepTimeoutSetting);
      expect(sanitizeSleepTimeoutSetting(999), kMaxSleepTimeoutSetting);
      expect(sanitizeSleepTimeoutSetting(100000), kMaxSleepTimeoutSetting);
    });

    test('passes valid values through, including 0', () {
      // 0 is a legal preference — "the app will not sleep the machine".
      expect(sanitizeSleepTimeoutSetting(0), 0);
      expect(sanitizeSleepTimeoutSetting(30), 30);
      expect(sanitizeSleepTimeoutSetting(240), 240);
      expect(sanitizeSleepTimeoutSetting('45'), 45);
      expect(sanitizeSleepTimeoutSetting(30.4), 30);
    });

    test('isValidSleepTimeoutSetting gates what REST will accept', () {
      expect(isValidSleepTimeoutSetting(0), isTrue);
      expect(isValidSleepTimeoutSetting(30), isTrue);
      expect(isValidSleepTimeoutSetting(240), isTrue);
      expect(isValidSleepTimeoutSetting(-1), isFalse);
      expect(isValidSleepTimeoutSetting(241), isFalse);
    });
  });

  group('SettingsController.setSleepTimeoutMinutes bounds what it stores', () {
    late SettingsController controller;

    setUp(() async {
      controller = SettingsController(MockSettingsService());
      await controller.loadSettings();
    });

    test('clamps a rogue value rather than storing it', () async {
      await controller.setSleepTimeoutMinutes(999);
      expect(controller.sleepTimeoutMinutes, kMaxSleepTimeoutSetting);

      await controller.setSleepTimeoutMinutes(-1);
      expect(controller.sleepTimeoutMinutes, kMinSleepTimeoutSetting);
    });

    test('still accepts 0 — the dropdown\'s "Disabled" is a legal preference',
        () async {
      await controller.setSleepTimeoutMinutes(0);
      expect(controller.sleepTimeoutMinutes, 0);
    });

    test('the shipping default is 30 minutes', () {
      expect(controller.userPresenceEnabled, isTrue);
      expect(controller.sleepTimeoutMinutes, 30);
    });
  });
}
