import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';

import 'helpers/mock_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebUIStorage install overwrite semantics', () {
    late Directory tmpRoot;
    late Directory webUIDir;
    late WebUIStorage storage;

    setUp(() async {
      tmpRoot = Directory.systemTemp.createTempSync('webui_storage_test');
      webUIDir = Directory('${tmpRoot.path}/web-ui');

      final settingsController = SettingsController(MockSettingsService());
      await settingsController.loadSettings();
      storage = WebUIStorage(settingsController, appStoreMode: true);
      storage.debugInitWithWebUIDir(webUIDir);
    });

    tearDown(() {
      if (tmpRoot.existsSync()) tmpRoot.deleteSync(recursive: true);
    });

    // Builds a source skin directory whose skin-manifest.json shares [id] but
    // carries a distinct [version], mimicking two builds of the same skin.
    Directory makeSkinSource(String version) {
      final dir = Directory('${tmpRoot.path}/src_$version');
      dir.createSync(recursive: true);
      File('${dir.path}/skin-manifest.json').writeAsStringSync(
        jsonEncode({
          'id': 'test.skin',
          'name': 'Test Skin',
          'version': version,
        }),
      );
      File('${dir.path}/index.html').writeAsStringSync('<html>$version</html>');
      return dir;
    }

    String installedVersion() {
      final manifest = File('${webUIDir.path}/test.skin/skin-manifest.json');
      final json =
          jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      return json['version'] as String;
    }

    test('overwriteIfExists:false leaves an existing skin untouched', () async {
      // Newer copy installed first (e.g. from a GitHub release).
      await storage.installFromPath(makeSkinSource('0.1.33').path);
      expect(installedVersion(), '0.1.33');

      // Bundled (older) copy must not clobber it — issue #250.
      await storage.installFromPath(
        makeSkinSource('0.1.31').path,
        overwriteIfExists: false,
      );
      expect(installedVersion(), '0.1.33');
    });

    test('overwriteIfExists:true replaces an existing skin', () async {
      await storage.installFromPath(makeSkinSource('0.1.31').path);
      expect(installedVersion(), '0.1.31');

      await storage.installFromPath(makeSkinSource('0.1.33').path);
      expect(installedVersion(), '0.1.33');
    });

    test('overwriteIfExists:false still installs when absent', () async {
      await storage.installFromPath(
        makeSkinSource('0.1.31').path,
        overwriteIfExists: false,
      );
      expect(installedVersion(), '0.1.31');
    });
  });
}
