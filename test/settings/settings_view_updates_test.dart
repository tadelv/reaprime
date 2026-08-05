import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/presence_controller.dart';
import 'package:reaprime/src/services/android_updater.dart';
import 'package:reaprime/src/services/macos_updater.dart';
import 'package:reaprime/src/services/update_check_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/settings_view.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/mock_settings_service.dart';

/// The SettingsView branches on the host platform. The macOS Sparkle path is
/// only exercised when the test host is macOS; the Android dialog flow is
/// covered by the Android-only tests elsewhere.
final bool isMacOSHost = Platform.isMacOS;

class _NoopUpdater extends AndroidUpdater {
  _NoopUpdater() : super(owner: 'tadelv', repo: 'reaprime');
  @override
  Future<UpdateInfo?> checkForUpdate(
    String v, {
    UpdateChannel channel = UpdateChannel.stable,
  }) async => null;
  @override
  void dispose() {}
}

const _channel = MethodChannel('net.tadel.reaprime/macos_updater');

Future<UpdateCheckService> _pumpSettingsView(
  WidgetTester tester,
  List<MethodCall> calls,
) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return null;
      });

  final settingsController = SettingsController(MockSettingsService());
  await settingsController.loadSettings();

  final presenceController = PresenceController(
    de1Controller: De1Controller(controller: DeviceController(const [])),
    settingsController: settingsController,
  );
  final webUIStorage = WebUIStorage(settingsController);
  final updateCheckService = UpdateCheckService(
    settingsService: MockSettingsService(),
    webUIStorage: webUIStorage,
    updater: _NoopUpdater(),
    platformIsAndroid: false,
    platformIsMacOS: false,
  );

  await tester.pumpWidget(
    ShadApp(
      home: SettingsView(
        controller: settingsController,
        updateCheckService: updateCheckService,
        macosUpdater: MacOSUpdater(supported: isMacOSHost),
        presenceController: presenceController,
        webUIStorage: webUIStorage,
      ),
    ),
  );
  await tester.pumpAndSettle();

  addTearDown(() {
    updateCheckService.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  return updateCheckService;
}

void main() {
  group('SettingsView updates', () {
    testWidgets(
      'macOS manual check delegates to Sparkle without a Snackbar',
      (tester) async {
        final calls = <MethodCall>[];
        await _pumpSettingsView(tester, calls);

        await tester.tap(find.text('Check for updates'));
        await tester.pumpAndSettle();

        expect(calls.where((c) => c.method == 'checkForUpdates'), hasLength(1));
        expect(find.text('Checking for updates...'), findsNothing);
        expect(find.text('You are on the latest version'), findsNothing);
      },
      skip: !isMacOSHost,
    );

    testWidgets('macOS automatic-check toggle calls setAutomaticChecks', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      await _pumpSettingsView(tester, calls);

      await tester.tap(
        find.widgetWithText(ShadSwitch, 'Automatic update checks'),
      );
      await tester.pumpAndSettle();

      expect(
        calls.where((c) => c.method == 'setAutomaticChecks'),
        hasLength(1),
      );
      expect(
        (calls.lastWhere((c) => c.method == 'setAutomaticChecks').arguments
            as Map)['enabled'],
        isFalse,
      );
    }, skip: !isMacOSHost);

    testWidgets('macOS channel change calls setChannel', (tester) async {
      final calls = <MethodCall>[];
      await _pumpSettingsView(tester, calls);

      await tester.tap(find.text('Update channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(calls.where((c) => c.method == 'setChannel'), hasLength(1));
      expect(
        (calls.lastWhere((c) => c.method == 'setChannel').arguments
            as Map)['channel'],
        'beta',
      );
    }, skip: !isMacOSHost);

    testWidgets('non-macOS manual check keeps the existing Snackbar flow', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      await _pumpSettingsView(tester, calls);

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      // No Sparkle delegation on non-macOS hosts.
      expect(calls.where((c) => c.method == 'checkForUpdates'), isEmpty);
      // The fake updater reports no update, so the misleading-path is the
      // existing "latest version" Snackbar.
      expect(find.text('You are on the latest version'), findsOneWidget);
    }, skip: isMacOSHost);
  });
}
