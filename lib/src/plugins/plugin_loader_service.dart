import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/services/storage/kv_store_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reaprime/src/plugins/plugin_manager.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';
import 'package:reaprime/src/plugins/plugin_runtime.dart';
import 'package:reaprime/src/services/account/decent_proxy_service.dart';
import 'package:reaprime/src/util/safe_path.dart';

class PluginSettingsValidationException implements Exception {
  final String message;
  PluginSettingsValidationException(this.message);

  @override
  String toString() => message;
}

class PluginLoaderService {
  static const _loadTimeout = Duration(seconds: 1);
  static const _maxConsecutiveLoadFailures = 3;
  static const _loadingPluginKey = 'plugin.watchdog.loading';

  final PluginManager pluginManager;
  final _log = Logger('PluginLoaderService');

  late Directory _pluginsDir;
  late SharedPreferences _prefs;
  final Map<String, PluginManifest> _availablePluginsCache = {};
  Future<void> _pluginLoadQueue = Future.value();

  PluginLoaderService({
    required KeyValueStoreService kvStore,
    DecentProxyService? decentProxyService,
  }) : pluginManager = PluginManager(
         kvStore: kvStore,
         decentProxyService: decentProxyService,
       );

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      _log.fine('PluginLoaderService already initialized');
      return;
    }

    final appDocDir = await getApplicationDocumentsDirectory();
    _pluginsDir = Directory('${appDocDir.path}/plugins');

    _prefs = await SharedPreferences.getInstance();
    await _recoverInterruptedPluginLoad();

    if (!_pluginsDir.existsSync()) {
      _pluginsDir.createSync(recursive: true);
      _log.info('Created plugins directory: ${_pluginsDir.path}');
    }

    await _copyBundledPlugins();

    await _scanAvailablePlugins();

    await _loadAutoLoadPlugins();

    _initialized = true;
  }

  Future<void> addPlugin(String sourcePath) async {
    final source = File(sourcePath);
    final sourceDir = Directory(sourcePath);

    Directory sourceDirectory;
    File manifestFile;

    if (source.existsSync()) {
      throw Exception(
        'File-based plugin installation not yet implemented. Please provide a directory path.',
      );
    } else if (sourceDir.existsSync()) {
      sourceDirectory = sourceDir;
      manifestFile = File('${sourceDirectory.path}/manifest.json');
      if (!manifestFile.existsSync()) {
        throw Exception('manifest.json not found in plugin directory');
      }
    } else {
      throw Exception('Source does not exist: $sourcePath');
    }

    final manifestJson = jsonDecode(await manifestFile.readAsString());
    final manifest = PluginManifest.fromJson(manifestJson);

    if (!isSafePathComponent(manifest.id)) {
      throw FormatException(
        'Unsafe plugin id "${manifest.id}": must be a single safe path component',
      );
    }

    final pluginDir = Directory('${_pluginsDir.path}/${manifest.id}');
    if (pluginDir.existsSync()) {
      throw Exception('Plugin already installed: ${manifest.id}');
    }

    pluginDir.createSync(recursive: true);

    await _copyDirectory(sourceDirectory, pluginDir);

    _availablePluginsCache[manifest.id] = manifest;

    _log.info('Plugin installed: ${manifest.id}');
  }

  Future<void> removePlugin(String pluginId) async {
    if (!isSafePathComponent(pluginId)) {
      throw FormatException(
        'Unsafe plugin id "$pluginId": must be a single safe path component',
      );
    }

    if (isPluginLoaded(pluginId)) {
      await unloadPlugin(pluginId);
    }

    _availablePluginsCache.remove(pluginId);

    final pluginDir = Directory('${_pluginsDir.path}/$pluginId');
    if (pluginDir.existsSync()) {
      await pluginDir.delete(recursive: true);
      _log.info('Plugin removed: $pluginId');
    }

    await _prefs.remove('plugin.autoload.$pluginId');

    await _prefs.remove('plugin.settings.$pluginId');
    await _prefs.remove(_loadFailureKey(pluginId));
    if (_prefs.getString(_loadingPluginKey) == pluginId) {
      await _prefs.remove(_loadingPluginKey);
    }
  }

  Future<void> loadPlugin(String pluginId) {
    final load = _pluginLoadQueue.then((_) => _loadPlugin(pluginId));
    _pluginLoadQueue = load.then<void>((_) {}, onError: (_, _) {});
    return load;
  }

  Future<void> _loadPlugin(String pluginId) async {
    if (!_availablePluginsCache.containsKey(pluginId)) {
      throw Exception('Plugin not found: $pluginId');
    }

    final manifest = _availablePluginsCache[pluginId]!;
    final pluginDir = Directory('${_pluginsDir.path}/$pluginId');

    await _prefs.setString(_loadingPluginKey, pluginId);
    try {
      final pluginFile = File('${pluginDir.path}/plugin.js');
      if (!pluginFile.existsSync()) {
        throw Exception('plugin.js not found for plugin: $pluginId');
      }

      final jsCode = await pluginFile.readAsString();
      final settings = await pluginSettings(pluginId);

      await pluginManager
          .loadPlugin(
            id: pluginId,
            manifest: manifest,
            jsCode: jsCode,
            settings: settings,
          )
          .timeout(_loadTimeout);
    } catch (_) {
      await _prefs.remove(_loadingPluginKey);
      await _recordLoadFailure(pluginId);
      rethrow;
    }

    await _prefs.remove(_loadingPluginKey);
    await _prefs.remove(_loadFailureKey(pluginId));
    _log.info('Plugin loaded: $pluginId');
  }

  Future<void> unloadPlugin(String pluginId) async {
    await pluginManager.unloadPlugin(pluginId);
    _log.info('Plugin unloaded: $pluginId');
  }

  Future<void> reloadPlugin(String pluginId) async {
    if (!isPluginLoaded(pluginId)) {
      throw Exception('Plugin not loaded: $pluginId');
    }

    _log.info('Reloading plugin: $pluginId');

    await unloadPlugin(pluginId);

    await loadPlugin(pluginId);

    _log.info('Plugin reloaded: $pluginId');
  }

  Future<void> setPluginAutoLoad(String pluginId, bool enabled) async {
    if (enabled) {
      await _prefs.remove(_loadFailureKey(pluginId));
      if (_prefs.getString(_loadingPluginKey) == pluginId) {
        await _prefs.remove(_loadingPluginKey);
      }
    }
    await _prefs.setBool('plugin.autoload.$pluginId', enabled);
  }

  Future<bool> shouldAutoLoad(String pluginId) async {
    return _prefs.getBool('plugin.autoload.$pluginId') ?? false;
  }

  Future<Map<String, dynamic>> pluginSettings(String pluginId) async {
    final settingsJson = _prefs.getString('plugin.settings.$pluginId');
    if (settingsJson == null) {
      return {};
    }

    try {
      return Map<String, dynamic>.from(jsonDecode(settingsJson));
    } catch (e) {
      _log.warning('Failed to parse settings for plugin $pluginId', e);
      return {};
    }
  }

  Future<void> savePluginSettings(
    String pluginId,
    Map<String, dynamic> settings,
  ) async {
    if (!_availablePluginsCache.containsKey(pluginId)) {
      throw Exception('Plugin not found: $pluginId');
    }

    final manifest = _availablePluginsCache[pluginId]!;

    _validateSettings(manifest, settings);

    await _prefs.setString('plugin.settings.$pluginId', jsonEncode(settings));

    _log.fine('Settings saved for plugin: $pluginId');
  }

  List<PluginManifest> get availablePlugins {
    return _availablePluginsCache.values.toList();
  }

  PluginManifest? getPluginManifest(String pluginId) {
    return _availablePluginsCache[pluginId];
  }

  bool isPluginLoaded(String pluginId) {
    return pluginManager.loadedPlugins.any(
      (plugin) => plugin.pluginId == pluginId,
    );
  }

  String getPluginDirectory(String pluginId) {
    if (!isSafePathComponent(pluginId)) {
      throw FormatException(
        'Unsafe plugin id "$pluginId": must be a single safe path component',
      );
    }
    if (!_availablePluginsCache.containsKey(pluginId)) {
      throw Exception('Plugin not found: $pluginId');
    }
    return '${_pluginsDir.path}/$pluginId';
  }

  Future<bool> isPluginBundled(String pluginId) async {
    final bundledPlugins = await _getBundledPluginPaths();
    for (final pluginPath in bundledPlugins) {
      final pluginName = pluginPath.split('/').last;
      if (pluginName == pluginId) {
        return true;
      }
    }
    return false;
  }

  List<PluginRuntime> get loadedPlugins {
    return pluginManager.loadedPlugins;
  }

  String _loadFailureKey(String pluginId) =>
      'plugin.watchdog.loadFailures.$pluginId';

  Future<void> _recordLoadFailure(String pluginId) async {
    final failureKey = _loadFailureKey(pluginId);
    final failures = (_prefs.getInt(failureKey) ?? 0) + 1;
    await _prefs.setInt(failureKey, failures);
    if (failures < _maxConsecutiveLoadFailures) return;

    await _prefs.setBool('plugin.autoload.$pluginId', false);
    _log.warning(
      'Disabled auto-load for plugin $pluginId after $failures consecutive load failures',
    );
  }

  Future<void> _recoverInterruptedPluginLoad() async {
    final pluginId = _prefs.getString(_loadingPluginKey);
    if (pluginId == null) return;

    await _prefs.setInt(_loadFailureKey(pluginId), _maxConsecutiveLoadFailures);
    await _prefs.setBool('plugin.autoload.$pluginId', false);
    await _prefs.remove(_loadingPluginKey);
    _log.warning(
      'Disabled auto-load for plugin $pluginId after an interrupted load',
    );
  }

  Future<void> _copyBundledPlugins() async {
    final bundledPlugins = await _getBundledPluginPaths();

    for (final pluginPath in bundledPlugins) {
      try {
        final pluginName = pluginPath.split('/').last;
        final destDir = Directory('${_pluginsDir.path}/$pluginName');

        final isNewPlugin = !destDir.existsSync() || destDir.listSync().isEmpty;

        if (isNewPlugin) {
          destDir.createSync(recursive: true);

          final manifestAsset = await rootBundle.loadString(
            '$pluginPath/manifest.json',
          );
          File(
            '${destDir.path}/manifest.json',
          ).writeAsStringSync(manifestAsset);

          final pluginAsset = await rootBundle.loadString(
            '$pluginPath/plugin.js',
          );
          File('${destDir.path}/plugin.js').writeAsStringSync(pluginAsset);

          _log.fine('Copied bundled plugin: $pluginName');
          continue;
        }

        final manifestAsset = await rootBundle.loadString(
          '$pluginPath/manifest.json',
        );
        if (kReleaseMode) {
          final newManifest = PluginManifest.fromJson(
            jsonDecode(manifestAsset),
          );
          final existingManifestFile = File('${destDir.path}/manifest.json');
          final existingManifest = PluginManifest.fromJson(
            jsonDecode(await existingManifestFile.readAsString()),
          );
          if (_compareVersions(newManifest.version, existingManifest.version) <=
              0) {
            _log.fine(
              "not overriding bundled plugin: [bundled: ${newManifest.version}], [existing: ${existingManifest.version}]",
            );
            continue;
          }
        }
        File('${destDir.path}/manifest.json').writeAsStringSync(manifestAsset);

        final pluginAsset = await rootBundle.loadString(
          '$pluginPath/plugin.js',
        );
        File('${destDir.path}/plugin.js').writeAsStringSync(pluginAsset);

        _log.fine('Updated bundled plugin: $pluginName');
      } catch (e) {
        _log.warning('Failed to copy bundled plugins', e);
      }
    }
  }

  static int _compareVersions(String a, String b) {
    final partsA = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final partsB = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < len; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

  Future<List<String>> _getBundledPluginPaths() async {
    return [
      'assets/plugins/time-to-ready.reaplugin',
      'assets/plugins/visualizer.reaplugin',
      'assets/plugins/settings.reaplugin',
      'assets/plugins/dye2.reaplugin',
      'assets/plugins/decent-profile.reaplugin',
      'assets/plugins/shot-upload.reaplugin',
    ];
  }

  Future<void> _scanAvailablePlugins() async {
    _availablePluginsCache.clear();

    if (!_pluginsDir.existsSync()) {
      return;
    }

    final directories = _pluginsDir.listSync().whereType<Directory>();

    for (final dir in directories) {
      try {
        final manifestFile = File('${dir.path}/manifest.json');
        if (!manifestFile.existsSync()) {
          continue;
        }

        final manifestJson = jsonDecode(await manifestFile.readAsString());
        final manifest = PluginManifest.fromJson(manifestJson);

        if (!isSafePathComponent(manifest.id)) {
          _log.warning(
            'Skipping plugin with unsafe id "${manifest.id}" at ${dir.path}',
          );
          continue;
        }

        _availablePluginsCache[manifest.id] = manifest;
        _log.fine('Found plugin: ${manifest.id}');
      } catch (e) {
        _log.warning('Failed to load plugin manifest from ${dir.path}', e);
      }
    }
  }

  Future<void> _loadAutoLoadPlugins() async {
    await _ensureBundledPluginsAutoLoadEnabled();

    for (final pluginId in _availablePluginsCache.keys) {
      final shouldLoad = await shouldAutoLoad(pluginId);
      if (shouldLoad) {
        try {
          await loadPlugin(pluginId);
        } catch (e) {
          _log.warning('Failed to auto-load plugin $pluginId', e);
        }
      }
    }
  }

  Future<void> _ensureBundledPluginsAutoLoadEnabled() async {
    try {
      final bundledPlugins = await _getBundledPluginPaths();

      for (final pluginPath in bundledPlugins) {
        final pluginName = pluginPath.split('/').last;
        final pluginDir = Directory('${_pluginsDir.path}/$pluginName');

        if (!pluginDir.existsSync()) {
          continue;
        }

        final manifestFile = File('${pluginDir.path}/manifest.json');
        if (!manifestFile.existsSync()) {
          continue;
        }

        final manifestJson = jsonDecode(await manifestFile.readAsString());
        final manifest = PluginManifest.fromJson(manifestJson);

        final autoLoadKey = 'plugin.autoload.${manifest.id}';
        if (!_prefs.containsKey(autoLoadKey)) {
          await _prefs.setBool(autoLoadKey, true);
          _log.info(
            'Set auto-load enabled by default for bundled plugin: ${manifest.id}',
          );
        }
      }
    } catch (e) {
      _log.warning('Failed to ensure bundled plugins auto-load enabled', e);
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list(recursive: false)) {
      if (entity is File) {
        final newFile = File(
          '${destination.path}/${entity.path.split('/').last}',
        );
        await entity.copy(newFile.path);
      } else if (entity is Directory) {
        final newDir = Directory(
          '${destination.path}/${entity.path.split('/').last}',
        );
        newDir.createSync(recursive: true);
        await _copyDirectory(entity, newDir);
      }
    }
  }

  void _validateSettings(
    PluginManifest manifest,
    Map<String, dynamic> settings,
  ) {
    final manifestSettings = manifest.settings;

    if (manifestSettings.isEmpty) {
      return;
    }

    for (final key in settings.keys) {
      if (!manifestSettings.containsKey(key)) {
        throw PluginSettingsValidationException(
          'Setting "$key" not defined in plugin manifest',
        );
      }
    }
  }

  Future<void> reset() async {
    for (var plugin in availablePlugins) {
      final path = getPluginDirectory(plugin.id);
      final dir = Directory(path);
      await dir.delete(recursive: true);
    }
  }
}
