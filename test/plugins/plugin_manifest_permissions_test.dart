import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';

void main() {
  test('parses manifest permission wire values', () {
    final manifest = PluginManifest.fromJson(<String, dynamic>{
      'id': 'test.plugin',
      'name': 'Test Plugin',
      'author': 'Test',
      'description': 'Test',
      'version': '1.0.0',
      'apiVersion': 1,
      'permissions': ['log', 'api', 'proxy.decent_api'],
      'settings': <String, dynamic>{},
      'api': <dynamic>[],
    });

    expect(manifest.permissions, contains(PluginPermissions.log));
    expect(manifest.permissions, contains(PluginPermissions.api));
    expect(manifest.permissions, contains(PluginPermissions.proxyDecentApi));
  });

  test('serializes permissions using manifest wire values', () {
    final manifest = PluginManifest(
      id: 'test.plugin',
      name: 'Test Plugin',
      author: 'Test',
      description: 'Test',
      version: '1.0.0',
      apiVersion: 1,
      permissions: {
        PluginPermissions.api,
        PluginPermissions.pluginStorage,
        PluginPermissions.proxyDecentApi,
      },
      settings: {},
      api: PluginApi(endpoints: []),
    );

    expect(
      manifest.toJson()['permissions'],
      containsAll(['api', 'pluginStorage', 'proxy.decent_api']),
    );
  });
}
