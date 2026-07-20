import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/settings_export_section.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/sleep_timeout_preference.dart';

import '../helpers/mock_settings_service.dart';

void main() {
  late MockSettingsService mockService;
  late SettingsController controller;
  late SettingsExportSection section;

  setUp(() async {
    mockService = MockSettingsService();
    controller = SettingsController(mockService);
    await controller.loadSettings();
    section = SettingsExportSection(controller: controller);
  });

  group('sleepTimeoutMinutes import', () {
    test('valid integer imports normally', () async {
      final result = await section.import({
        'settings': {'sleepTimeoutMinutes': 60},
      }, ConflictStrategy.overwrite);

      expect(result.errors, isEmpty);
      expect(controller.sleepTimeoutMinutes, 60);
    });

    test('negative integer imports as 0', () async {
      final result = await section.import({
        'settings': {'sleepTimeoutMinutes': -10},
      }, ConflictStrategy.overwrite);

      expect(result.errors, isEmpty);
      expect(controller.sleepTimeoutMinutes, kMinSleepTimeoutPreferenceMinutes);
    });

    test('oversized integer imports as 240', () async {
      final result = await section.import({
        'settings': {'sleepTimeoutMinutes': 999},
      }, ConflictStrategy.overwrite);

      expect(result.errors, isEmpty);
      expect(controller.sleepTimeoutMinutes, kMaxSleepTimeoutPreferenceMinutes);
    });

    test('string is rejected with field-specific error', () async {
      final result = await section.import({
        'settings': {'sleepTimeoutMinutes': '30'},
      }, ConflictStrategy.overwrite);

      expect(result.errors, isNotEmpty);
      expect(
        result.errors.any((e) => e.contains('sleepTimeoutMinutes')),
        isTrue,
      );
      expect(controller.sleepTimeoutMinutes, 30);
    });

    test('double is rejected with field-specific error', () async {
      final result = await section.import({
        'settings': {'sleepTimeoutMinutes': 30.5},
      }, ConflictStrategy.overwrite);

      expect(result.errors, isNotEmpty);
      expect(
        result.errors.any((e) => e.contains('sleepTimeoutMinutes')),
        isTrue,
      );
      expect(controller.sleepTimeoutMinutes, 30);
    });

    test(
      'invalid timeout does not prevent another setting from importing',
      () async {
        final result = await section.import({
          'settings': {
            'sleepTimeoutMinutes': 'bad',
            'blockOnNoScale': true,
          },
        }, ConflictStrategy.overwrite);

        expect(result.errors, isNotEmpty);
        expect(controller.blockOnNoScale, true);
      },
    );

    test('invalid timeout does not increment imported count', () async {
      final result = await section.import({
        'settings': {'sleepTimeoutMinutes': 'bad'},
      }, ConflictStrategy.overwrite);

      expect(result.imported, 0);
    });

    test('invalid timeout leaves existing preference unchanged', () async {
      await controller.setSleepTimeoutMinutes(45);

      await section.import({
        'settings': {'sleepTimeoutMinutes': 'bad'},
      }, ConflictStrategy.overwrite);

      expect(controller.sleepTimeoutMinutes, 45);
    });
  });
}
