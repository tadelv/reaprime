import 'package:reaprime/src/plugins/plugin_manager.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';
import 'package:reaprime/src/plugins/plugin_runtime.dart';

class PluginLoaderService {
  final PluginManager pluginManager = PluginManager();

  /// Add plugin to REA plugins folder
  Future<void> addPlugin(String filePath) async {}

  /// Load plugin into the runtime
  Future<void> loadPlugin(String pluginId) async {}

  Future<void> unloadPlugin(String pluginId) async {}

  /// Get a list of all the available plugins
  List<PluginManifest> get availablePlugins {
    return [];
  }

  /// Get a list of currently loaded plugins
  List<PluginRuntime> get loadedPlugins {
    return [];
  }
}
