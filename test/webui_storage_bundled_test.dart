import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

import 'helpers/mock_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('skin_sources.json asset', () {
    test('can be loaded and parsed as a list of source configs', () async {
      // Load the real asset bundled in the project
      final configString =
          await rootBundle.loadString('skin_sources.json');
      final sources = (jsonDecode(configString) as List)
          .cast<Map<String, dynamic>>();

      expect(sources, isNotEmpty);

      // Each source should have a 'type' field
      for (final source in sources) {
        expect(source, contains('type'));
        expect(
          source['type'],
          anyOf('github_release', 'github_branch', 'url'),
        );
      }
    });
  });

  group('WebUIStorage appStoreMode', () {
    late SettingsController settingsController;

    setUp(() async {
      final settingsService = MockSettingsService();
      settingsController = SettingsController(settingsService);
      await settingsController.loadSettings();
    });

    test('constructor accepts appStoreMode parameter', () {
      // Should not throw
      final storage = WebUIStorage(settingsController, appStoreMode: true);
      expect(storage, isNotNull);
    });

    test('constructor defaults appStoreMode without parameter', () {
      // Should not throw — defaults to BuildInfo.appStore (false in tests)
      final storage = WebUIStorage(settingsController);
      expect(storage, isNotNull);
    });

    test('updateAllSkins returns early when appStoreMode is true', () async {
      final storage = WebUIStorage(settingsController, appStoreMode: true);
      // Should complete without error and without making any HTTP requests
      await storage.updateAllSkins();
    });
  });

  group('bundled_skins manifest', () {
    test('manifest.json can be loaded and contains skin IDs', () async {
      final manifestString = await rootBundle
          .loadString('assets/bundled_skins/manifest.json');
      final skinIds =
          (jsonDecode(manifestString) as List).cast<String>();

      expect(skinIds, isNotEmpty);
      for (final id in skinIds) {
        expect(id, isA<String>());
        expect(id, isNotEmpty);
      }
    });
  });
}
