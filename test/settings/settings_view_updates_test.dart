import 'package:flutter/material.dart';
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

/// The SettingsView branches on the injected `macosUpdater.isSupported`
/// capability, so both the macOS (Sparkle) and the Dart-service paths run on
/// every test host. The harness's Dart service uses `platformIsMacOS: false`
/// so its reactions (immediate checks, timers) stay observable.
class _RecordingUpdater extends AndroidUpdater {
  _RecordingUpdater() : super(owner: 'tadelv', repo: 'reaprime');
  int checkCalls = 0;

  @override
  Future<UpdateInfo?> checkForUpdate(
    String v, {
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    checkCalls++;
    return null;
  }

  @override
  void dispose() {}
}

const _channel = MethodChannel('net.tadel.reaprime/macos_updater');

Future<(UpdateCheckService, _RecordingUpdater)> _pumpSettingsView(
  WidgetTester tester,
  List<MethodCall> calls, {
  required bool macos,
  bool initializeService = false,
}) async {
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
  final updater = _RecordingUpdater();
  final updateCheckService = UpdateCheckService(
    settingsService: MockSettingsService(),
    webUIStorage: webUIStorage,
    updater: updater,
    platformIsAndroid: false,
    platformIsMacOS: false,
  );
  if (initializeService) {
    await updateCheckService.initialize();
  }

  // ShadApp provides no ScaffoldMessenger (WidgetsApp-based); SettingsView's
  // own Scaffold supplies the Material ancestor, so only the messenger needs
  // wrapping here.
  await tester.pumpWidget(
    ShadApp(
      home: ScaffoldMessenger(
        child: SettingsView(
          controller: settingsController,
          updateCheckService: updateCheckService,
          macosUpdater: MacOSUpdater(supported: macos),
          presenceController: presenceController,
          webUIStorage: webUIStorage,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  addTearDown(() {
    updateCheckService.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  return (updateCheckService, updater);
}

void main() {
  group('SettingsView updates', () {
    testWidgets('macOS manual check delegates to Sparkle without a Snackbar', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      await _pumpSettingsView(tester, calls, macos: true);

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(calls.where((c) => c.method == 'checkForUpdates'), hasLength(1));
      expect(find.text('Checking for updates...'), findsNothing);
      expect(find.text('You are on the latest version'), findsNothing);
    });

    testWidgets('macOS automatic-check toggle calls setAutomaticChecks', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      await _pumpSettingsView(tester, calls, macos: true);

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
    });

    testWidgets('macOS channel change calls setChannel', (tester) async {
      final calls = <MethodCall>[];
      await _pumpSettingsView(tester, calls, macos: true);

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
    });

    testWidgets('macOS toggle after initialization drives Sparkle and the Dart '
        'skin scheduler', (tester) async {
      final calls = <MethodCall>[];
      final (_, updater) = await _pumpSettingsView(
        tester,
        calls,
        macos: true,
        initializeService: true,
      );

      // initialize() with automatic checks on ran one immediate check.
      expect(updater.checkCalls, 1);

      // Toggle OFF: Sparkle scheduling stops AND the Dart timer must stop.
      await tester.tap(
        find.widgetWithText(ShadSwitch, 'Automatic update checks'),
      );
      await tester.pump();
      expect(
        (calls.lastWhere((c) => c.method == 'setAutomaticChecks').arguments
            as Map)['enabled'],
        isFalse,
      );
      await tester.pump(const Duration(hours: 13));
      expect(updater.checkCalls, 1); // no periodic check after disable

      // Toggle ON: both surfaces update and the Dart timer restarts. No
      // immediate check (the last one is fresh); the timer firing at +13h is
      // the proof the periodic scheduler is back.
      await tester.tap(
        find.widgetWithText(ShadSwitch, 'Automatic update checks'),
      );
      await tester.pump();
      expect(
        (calls.lastWhere((c) => c.method == 'setAutomaticChecks').arguments
            as Map)['enabled'],
        isTrue,
      );
      expect(updater.checkCalls, 1);
      await tester.pump(const Duration(hours: 13));
      expect(updater.checkCalls, 2); // periodic timer ran

      // Toggle OFF again so no timer is left pending.
      await tester.tap(
        find.widgetWithText(ShadSwitch, 'Automatic update checks'),
      );
      await tester.pump(const Duration(hours: 13));
      expect(updater.checkCalls, 2);
    });

    testWidgets('non-macOS manual check keeps the existing Snackbar flow', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      await _pumpSettingsView(tester, calls, macos: false);

      await tester.tap(find.text('Check for updates'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Checking for updates...'), findsOneWidget);

      // No Sparkle delegation without the capability.
      expect(calls.where((c) => c.method == 'checkForUpdates'), isEmpty);

      // The fake updater reports no update; the "latest version" Snackbar is
      // queued behind the "checking" one. Let the first expire, then the
      // second becomes visible.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('You are on the latest version'), findsOneWidget);

      // Let the second Snackbar expire so no timer is left pending.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
