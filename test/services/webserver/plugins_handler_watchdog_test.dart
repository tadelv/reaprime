import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/plugins/plugin_manager.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:shelf_plus/shelf_plus.dart';

class _FakePluginManager extends Fake implements PluginManager {}

class _FakePluginLoaderService extends Fake implements PluginLoaderService {
  static const pluginId = 'watchdog-test.reaplugin';

  final calls = <String>[];

  @override
  PluginManifest? getPluginManifest(String pluginId) => PluginManifest(
    id: pluginId,
    name: 'Watchdog test',
    author: 'Test',
    description: 'Test plugin',
    version: '1.0.0',
    apiVersion: 1,
    permissions: const {},
    settings: const {},
    api: null,
  );

  @override
  bool isPluginLoaded(String pluginId) => false;

  @override
  Future<void> loadPlugin(String pluginId) async {
    calls.add('load');
  }

  @override
  Future<void> setPluginAutoLoad(String pluginId, bool enabled) async {
    calls.add('autoLoad:$enabled');
  }
}

void main() {
  test('enable resets watchdog state before retrying plugin load', () async {
    final pluginService = _FakePluginLoaderService();
    final app = Router().plus;
    PluginsHandler(
      pluginManager: _FakePluginManager(),
      pluginService: pluginService,
    ).addRoutes(app);

    final response = await app.call(
      Request(
        'POST',
        Uri.parse(
          'http://localhost/api/v1/plugins/${_FakePluginLoaderService.pluginId}/enable',
        ),
      ),
    );

    expect(response.statusCode, 200);
    expect(pluginService.calls, ['autoLoad:true', 'load']);
  });
}
