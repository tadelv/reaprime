import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
      storage = WebUIStorage(settingsController, appStoreMode: false);
      storage.debugInitWithWebUIDir(webUIDir);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tmpRoot.path,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      if (tmpRoot.existsSync()) tmpRoot.deleteSync(recursive: true);
    });

    // Builds a source skin directory whose skin-manifest.json shares [id] but
    // carries a distinct [version], mimicking two builds of the same skin.
    Directory makeSkinSource(String version) {
      final dir = Directory('${tmpRoot.path}/src_$version');
      dir.createSync(recursive: true);
      File('${dir.path}/skin-manifest.json').writeAsStringSync(jsonEncode({
        'id': 'test.skin',
        'name': 'Test Skin',
        'version': version,
      }));
      File('${dir.path}/index.html').writeAsStringSync('<html>$version</html>');
      return dir;
    }

    String installedVersion() {
      final manifest =
          File('${webUIDir.path}/test.skin/skin-manifest.json');
      final json = jsonDecode(manifest.readAsStringSync())
          as Map<String, dynamic>;
      return json['version'] as String;
    }

    List<int> makeGitHubArchive() {
      final archive = Archive()
        ..addFile(ArchiveFile.string(
          'passione-dist/skin-manifest.json',
          jsonEncode({
            'id': 'passione-dist',
            'name': 'Passione',
            'version': '1.0.0',
          }),
        ))
        ..addFile(ArchiveFile.string(
          'passione-dist/index.html',
          '<html></html>',
        ));
      return ZipEncoder().encode(archive);
    }

    test('GitHub branch install persists source metadata', () async {
      final archive = makeGitHubArchive();
      var branchHeadRequests = 0;
      var branchGetRequests = 0;
      late DateTime before;
      late DateTime after;

      await http.runWithClient(
        () async {
          await storage.installFromGitHub('tadelv/passione', branch: 'dist');
          before = storage
              .getSkin('passione-dist')!
              .reaMetadata!
              .lastChecked!;

          await storage.updateAllSkins();
          after = storage
              .getSkin('passione-dist')!
              .reaMetadata!
              .lastChecked!;
        },
        () => MockClient((request) async {
          if (request.url.toString() !=
              'https://github.com/tadelv/passione/archive/refs/heads/dist.zip') {
            return http.Response('', 404);
          }
          if (request.method == 'HEAD') {
            branchHeadRequests++;
            return http.Response('', 200, headers: {'etag': 'branch-etag'});
          }
          branchGetRequests++;
          return http.Response.bytes(archive, 200);
        }),
      );

      expect(branchHeadRequests, 2);
      expect(branchGetRequests, 1);
      expect(after.isAfter(before), isTrue);

      final metadata = storage.getSkin('passione-dist')!.reaMetadata!;
      expect(
        metadata.sourceUrl,
        'github_branch:tadelv/passione@dist',
      );

      final persisted = jsonDecode(
        File('${webUIDir.path}/.rea_metadata.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        persisted['passione-dist']['sourceUrl'],
        'github_branch:tadelv/passione@dist',
      );
      expect(
        DateTime.parse(persisted['passione-dist']['lastChecked']),
        after,
      );
    });

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
