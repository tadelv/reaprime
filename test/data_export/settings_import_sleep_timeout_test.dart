import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/settings_export_section.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/sleep_timeout_preference.dart';

import '../helpers/mock_settings_service.dart';
import 'streaming_test_helpers.dart';

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
      final result = await importSectionJson(
        section,
        jsonEncode({
          'settings': {'sleepTimeoutMinutes': 60},
        }),
        ConflictStrategy.overwrite,
      );
      expect(result.errors, isEmpty);
      expect(controller.sleepTimeoutMinutes, 60);
    });

    test('negative integer imports as 0', () async {
      final result = await importSectionJson(
        section,
        jsonEncode({
          'settings': {'sleepTimeoutMinutes': -10},
        }),
        ConflictStrategy.overwrite,
      );
      expect(result.errors, isEmpty);
      expect(controller.sleepTimeoutMinutes, kMinSleepTimeoutPreferenceMinutes);
    });

    test('oversized integer imports as 240', () async {
      final result = await importSectionJson(
        section,
        jsonEncode({
          'settings': {'sleepTimeoutMinutes': 9999},
        }),
        ConflictStrategy.overwrite,
      );
      expect(result.errors, isEmpty);
      expect(controller.sleepTimeoutMinutes, kMaxSleepTimeoutPreferenceMinutes);
    });
  });
}
