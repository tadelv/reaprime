import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/device_discovery_feature/device_discovery_view.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'helpers/mock_device_discovery_service.dart';
import 'helpers/mock_settings_service.dart';
import 'helpers/test_scale.dart';

void main() {
  late MockDeviceDiscoveryService mockService;
  late DeviceController deviceController;
  late De1Controller de1Controller;
  late ScaleController scaleController;
  late SettingsController settingsController;
  late WebUIService webUIService;
  late WebUIStorage webUIStorage;

  setUp(() async {
    mockService = MockDeviceDiscoveryService();
    deviceController = DeviceController([mockService]);
    await deviceController.initialize();

    de1Controller = De1Controller(controller: deviceController);
    scaleController = ScaleController(controller: deviceController);
    settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();

    webUIService = WebUIService();
    webUIStorage = WebUIStorage(settingsController);
  });

  tearDown(() {
    deviceController.dispose();
    mockService.dispose();
  });

  Widget buildDiscoveryView() {
    return ShadApp(
      home: Scaffold(
        body: Center(
          child: DeviceDiscoveryView(
            deviceController: deviceController,
            de1controller: de1Controller,
            scaleController: scaleController,
            settingsController: settingsController,
            webUIService: webUIService,
            webUIStorage: webUIStorage,
            logger: Logger('test'),
          ),
        ),
      ),
    );
  }

  // All DeviceDiscoveryView tests use tester.runAsync because the view
  // creates real timers (Future.delayed for scan timeout) and relies on
  // stream propagation through microtasks.
  group('DeviceDiscoveryView', () {
    testWidgets('shows searching state on launch', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(buildDiscoveryView());
        await tester.pump();

        // The searching view shows a ShadProgress widget
        expect(find.byType(ShadProgress), findsOneWidget);
      });
    });

    testWidgets('shows discovered devices after scan', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(buildDiscoveryView());
        await tester.pump();

        // Add a machine — triggers DiscoveryState.foundMany via stream
        mockService.addDevice(MockDe1());
        // Allow microtasks to propagate: mock -> DeviceController -> widget
        await Future.delayed(Duration(milliseconds: 50));
        await tester.pump();

        // foundMany state shows "Machines" header and device list
        expect(find.text('Machines'), findsOneWidget);
        expect(find.text('MockDe1'), findsOneWidget);
      });
    });

    testWidgets('shows scales alongside machines in results view',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(buildDiscoveryView());
        await tester.pump();

        mockService.addDevice(MockDe1());
        mockService.addDevice(TestScale());
        await Future.delayed(Duration(milliseconds: 50));
        await tester.pump();

        // Both columns should be visible
        expect(find.text('Machines'), findsOneWidget);
        expect(find.text('Scales'), findsOneWidget);
        expect(find.text('MockDe1'), findsOneWidget);
        expect(find.text('Mock Scale'), findsOneWidget);
      });
    });

    testWidgets('shows no devices found after timeout', (tester) async {
      // Suppress layout overflow errors — the foundNone view's buttons may
      // overflow the default 800px test surface. We're testing state
      // transitions, not pixel-perfect layout.
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = origOnError);

      await tester.runAsync(() async {
        await tester.pumpWidget(buildDiscoveryView());
        await tester.pump();

        // Advance time past the 10-second timeout
        await Future.delayed(Duration(seconds: 11));
        await tester.pump();

        expect(find.text('No Decent Machines Found'), findsOneWidget);
        expect(find.text('Scan Again'), findsOneWidget);
      });
    });
  });
}
