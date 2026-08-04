import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/services/storage/kv_store_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeKvStore implements KeyValueStoreService {
  final Map<String, Map<String, Object>> _store = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> set({
    String namespace = 'default',
    required String key,
    required Object value,
  }) async {
    _store.putIfAbsent(namespace, () => {})[key] = value;
  }

  @override
  Future<bool> delete({
    String namespace = 'default',
    required String key,
  }) async {
    return _store[namespace]?.remove(key) != null;
  }

  @override
  Future<Object?> get({
    String namespace = 'default',
    required String key,
  }) async {
    return _store[namespace]?[key];
  }

  @override
  Future<List<String>> keys({String namespace = 'default'}) async {
    return _store[namespace]?.keys.toList() ?? [];
  }

  @override
  List<String> get namespaces => _store.keys.toList();

  @override
  Future<Map<String, Object>> getAll({String namespace = 'default'}) async {
    return Map.from(_store[namespace] ?? {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PluginLoaderService App Store mode', () {
    late Directory tempDir;
    late PluginLoaderService service;
    var sourceCounter = 0;

    Directory makePluginSource(String id) {
      final dir = Directory('${tempDir.path}/source_${sourceCounter++}')
        ..createSync();
      File('${dir.path}/manifest.json').writeAsStringSync(
        jsonEncode({
          'id': id,
          'author': 'Test',
          'name': 'Test plugin',
          'description': 'Test plugin',
          'version': '1.0.0',
          'apiVersion': 1,
          'permissions': <String>[],
          'settings': <String, Object>{},
          'api': <Object>[],
        }),
      );
      File('${dir.path}/plugin.js').writeAsStringSync('''
function createPlugin() {
  return { id: "x", onLoad() {} };
}
''');
      return dir;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('plugin_appstore_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => tempDir.path,
          );
      service = PluginLoaderService(kvStore: FakeKvStore());
      await service.initialize();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('addPlugin installs a plugin from a real source directory', () async {
      const id = 'installed.reaplugin';
      final source = makePluginSource(id);

      await service.addPlugin(source.path);

      final pluginDir = Directory('${tempDir.path}/plugins/$id');
      expect(pluginDir.existsSync(), isTrue);
      expect(File('${pluginDir.path}/manifest.json').existsSync(), isTrue);
      expect(File('${pluginDir.path}/plugin.js').existsSync(), isTrue);
      expect(service.getPluginManifest(id), isNotNull);
      expect(service.availablePlugins.any((m) => m.id == id), isTrue);
    });

    test('removePlugin deletes the installed plugin directory', () async {
      const id = 'removable.reaplugin';
      await service.addPlugin(makePluginSource(id).path);

      final pluginDir = Directory('${tempDir.path}/plugins/$id');
      expect(pluginDir.existsSync(), isTrue);

      await service.removePlugin(id);

      expect(pluginDir.existsSync(), isFalse);
      expect(service.getPluginManifest(id), isNull);
    });

    const unsafeIds = [
      '',
      '.',
      '..',
      '../escape',
      'a/b',
      r'a\b',
      '/abs',
      r'\abs',
      'C:evil',
      r'\\server\share',
      'a?b',
      'trailing.',
      'trailing ',
    ];

    for (final id in unsafeIds) {
      test(
        'addPlugin rejects unsafe plugin id ${id.isEmpty ? '(empty)' : '"$id"'}',
        () async {
          final source = makePluginSource(id);

          await expectLater(
            service.addPlugin(source.path),
            throwsFormatException,
          );
          expect(
            service.availablePlugins.any((m) => m.id == id),
            isFalse,
            reason: 'unsafe id must not enter the registry',
          );
        },
      );
    }

    test(
      'rejected installs never create or delete directories outside plugins root',
      () async {
        final pluginsDir = Directory('${tempDir.path}/plugins');

        // ../escape resolves outside the plugins root.
        final escapeDir = Directory('${tempDir.path}/escape');
        if (escapeDir.existsSync()) escapeDir.deleteSync(recursive: true);
        await expectLater(
          service.addPlugin(makePluginSource('../escape').path),
          throwsFormatException,
        );
        expect(escapeDir.existsSync(), isFalse);

        // Nested ids must not create nested directories.
        final nested = Directory('${pluginsDir.path}/a/b');
        await expectLater(
          service.addPlugin(makePluginSource('a/b').path),
          throwsFormatException,
        );
        expect(nested.existsSync(), isFalse);

        // Absolute ids must not resolve under the plugins root.
        final absDir = Directory('${pluginsDir.path}/abs');
        if (absDir.existsSync()) absDir.deleteSync(recursive: true);
        await expectLater(
          service.addPlugin(makePluginSource('/abs').path),
          throwsFormatException,
        );
        expect(absDir.existsSync(), isFalse);

        // Windows-style separators are literal on POSIX hosts, but the id is
        // still rejected so nothing is created.
        final winSep = Directory('${pluginsDir.path}/a\\b');
        await expectLater(
          service.addPlugin(makePluginSource(r'a\b').path),
          throwsFormatException,
        );
        expect(winSep.existsSync(), isFalse);
      },
    );

    test(
      'removePlugin rejects an unsafe id before touching the filesystem',
      () async {
        await expectLater(
          service.removePlugin('../escape'),
          throwsFormatException,
        );
        expect(
          Directory('${tempDir.path}/escape').existsSync(),
          isFalse,
          reason: 'removePlugin must not resolve an unsafe id into a path',
        );
      },
    );

    test('getPluginDirectory rejects an unsafe id', () {
      expect(
        () => service.getPluginDirectory('../escape'),
        throwsFormatException,
      );
    });

    test('an unsafe manifest cannot enter the registry via scan', () async {
      final evilDir = Directory('${tempDir.path}/plugins/evil-dir')
        ..createSync(recursive: true);
      File('${evilDir.path}/manifest.json').writeAsStringSync(
        jsonEncode({
          'id': '../escape',
          'author': 'Test',
          'name': 'Evil',
          'description': 'Test plugin',
          'version': '1.0.0',
          'apiVersion': 1,
          'permissions': <String>[],
          'settings': <String, Object>{},
          'api': <Object>[],
        }),
      );
      File(
        '${evilDir.path}/plugin.js',
      ).writeAsStringSync('function createPlugin() {}');

      final fresh = PluginLoaderService(kvStore: FakeKvStore());
      await fresh.initialize();

      expect(fresh.getPluginManifest('../escape'), isNull);
      expect(
        fresh.availablePlugins.any((m) => m.id == '../escape'),
        isFalse,
        reason: 'an unsafe manifest id must not enter the registry',
      );
    });
  });
}
