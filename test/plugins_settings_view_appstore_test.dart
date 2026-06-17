import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';
import 'package:reaprime/src/settings/plugins_settings_view.dart';

/// A fake PluginLoaderService that avoids creating a real PluginManager/JS runtime.
class FakePluginLoaderService extends Fake implements PluginLoaderService {
  FakePluginLoaderService({this.plugins = const []});

  final List<PluginManifest> plugins;

  @override
  List<PluginManifest> get availablePlugins => plugins;

  @override
  bool isPluginLoaded(String pluginId) => false;

  @override
  Future<bool> shouldAutoLoad(String pluginId) async => false;
}

void main() {
  late FakePluginLoaderService fakePluginLoaderService;

  setUp(() {
    fakePluginLoaderService = FakePluginLoaderService();
  });

  group('PluginsSettingsView install button visibility', () {
    testWidgets('shows install button when allowInstall is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        ShadApp(
          home: PluginsSettingsView(
            pluginLoaderService: fakePluginLoaderService,
            allowInstall: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byTooltip('Install Plugin'), findsOneWidget);
      expect(find.byTooltip('Refresh Plugins'), findsOneWidget);
    });

    testWidgets('hides install button when allowInstall is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        ShadApp(
          home: PluginsSettingsView(
            pluginLoaderService: fakePluginLoaderService,
            allowInstall: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byTooltip('Install Plugin'), findsNothing);
      // Refresh button should still be present
      expect(find.byTooltip('Refresh Plugins'), findsOneWidget);
    });
  });

  testWidgets('renders manifest permission wire names', (tester) async {
    final manifest = PluginManifest(
      id: 'proxy.reaplugin',
      name: 'Proxy Plugin',
      author: 'Test',
      description: 'Test plugin',
      version: '1.0.0',
      apiVersion: 1,
      permissions: {PluginPermissions.proxyDecentApi},
      settings: {},
      api: PluginApi(endpoints: []),
    );

    fakePluginLoaderService = FakePluginLoaderService(plugins: [manifest]);

    await tester.pumpWidget(
      ShadApp(
        home: PluginsSettingsView(
          pluginLoaderService: fakePluginLoaderService,
          allowInstall: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('proxy.decent_api'), findsOneWidget);
    expect(find.text('proxyDecentApi'), findsNothing);
  });
}
