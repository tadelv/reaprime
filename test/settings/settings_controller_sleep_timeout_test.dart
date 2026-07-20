import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/sleep_timeout_preference.dart';

import '../helpers/mock_settings_service.dart';

void main() {
  late MockSettingsService mockService;
  late SettingsController controller;

  group('setSleepTimeoutMinutes', () {
    setUp(() async {
      mockService = MockSettingsService();
      controller = SettingsController(mockService);
      await controller.loadSettings();
    });

    test('preserves values inside 0..240', () async {
      await controller.setSleepTimeoutMinutes(37);
      expect(controller.sleepTimeoutMinutes, 37);
      expect(await mockService.sleepTimeoutMinutes(), 37);
    });

    test('clamps negative values to 0', () async {
      await controller.setSleepTimeoutMinutes(-10);
      expect(controller.sleepTimeoutMinutes, 0);
      expect(await mockService.sleepTimeoutMinutes(), 0);
    });

    test('clamps oversized values to 240', () async {
      await controller.setSleepTimeoutMinutes(999);
      expect(controller.sleepTimeoutMinutes, 240);
      expect(await mockService.sleepTimeoutMinutes(), 240);
    });

    test('default is 30', () {
      expect(controller.sleepTimeoutMinutes, 30);
    });
  });

  group('loadSettings repairs persisted values', () {
    test('repairs oversized value to 240', () async {
      mockService = MockSettingsService();
      mockService.setRawSleepTimeoutMinutes(999);
      controller = SettingsController(mockService);
      await controller.loadSettings();

      expect(controller.sleepTimeoutMinutes, kMaxSleepTimeoutPreferenceMinutes);
      expect(
        await mockService.sleepTimeoutMinutes(),
        kMaxSleepTimeoutPreferenceMinutes,
      );
    });

    test('repairs negative value to 0', () async {
      mockService = MockSettingsService();
      mockService.setRawSleepTimeoutMinutes(-5);
      controller = SettingsController(mockService);
      await controller.loadSettings();

      expect(controller.sleepTimeoutMinutes, kMinSleepTimeoutPreferenceMinutes);
      expect(
        await mockService.sleepTimeoutMinutes(),
        kMinSleepTimeoutPreferenceMinutes,
      );
    });

    test('does not re-persist a valid value', () async {
      mockService = MockSettingsService();
      final initialWrites = mockService.sleepTimeoutWriteCount;
      controller = SettingsController(mockService);
      await controller.loadSettings();

      expect(controller.sleepTimeoutMinutes, 30);
      expect(mockService.sleepTimeoutWriteCount, initialWrites);
    });
  });
}
