import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
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
  late ConnectionManager connectionManager;
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

    connectionManager = ConnectionManager(
      deviceController: deviceController,
      de1Controller: de1Controller,
      scaleController: scaleController,
      settingsController: settingsController,
    );

    webUIService = WebUIService();
    webUIStorage = WebUIStorage(settingsController);
  });

  tearDown(() {
    connectionManager.dispose();
    deviceController.dispose();
    mockService.dispose();
  });

  Widget buildDiscoveryView() {
    // Use a large surface to avoid overflow issues with the card-based views
    return MediaQuery(
      data: MediaQueryData(size: Size(1024, 768)),
      child: ShadApp(
        home: Scaffold(
          body: Center(
            child: DeviceDiscoveryView(
              connectionManager: connectionManager,
              deviceController: deviceController,
              settingsController: settingsController,
              webUIService: webUIService,
              webUIStorage: webUIStorage,
              logger: Logger('test'),
            ),
          ),
        ),
      ),
    );
  }

  // All DeviceDiscoveryView tests use tester.runAsync because the
  // ConnectionManager.connect() runs real async operations and relies on
  // stream propagation through microtasks.
  group('DeviceDiscoveryView', () {
    testWidgets('shows no devices found when scan finds nothing', (tester) async {
      // Suppress overflow errors for this test
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed') ||
            details.toString().contains('deactivated')) return;
        origOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = origOnError);

      await tester.runAsync(() async {
        await tester.pumpWidget(buildDiscoveryView());
        await tester.pump();

        // Allow ConnectionManager.connect() to complete with no devices
        await Future.delayed(Duration(milliseconds: 500));
        await tester.pump();

        expect(find.text('No Decent Machines Found'), findsOneWidget);
        expect(find.text('Scan Again'), findsOneWidget);
      });
    });

    testWidgets('shows device picker when multiple machines found', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed') ||
            details.toString().contains('deactivated')) return;
        origOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = origOnError);

      await tester.runAsync(() async {
        // Add two machines so ConnectionManager shows picker (ambiguity)
        mockService.addDevice(MockDe1());
        mockService.addDevice(MockDe1(deviceId: 'mock-de1-2'));

        await tester.pumpWidget(buildDiscoveryView());

        // Allow ConnectionManager.connect() to scan and resolve
        await Future.delayed(Duration(milliseconds: 500));
        await tester.pump();

        // machinePicker ambiguity shows "Machines" header and device list
        expect(find.text('Machines'), findsOneWidget);
        expect(find.text('MockDe1'), findsWidgets);
      });
    });

    testWidgets('shows scales alongside machines in results view',
        (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed') ||
            details.toString().contains('deactivated')) return;
        origOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = origOnError);

      await tester.runAsync(() async {
        // Add two machines to trigger picker, plus a scale
        mockService.addDevice(MockDe1());
        mockService.addDevice(MockDe1(deviceId: 'mock-de1-2'));
        mockService.addDevice(TestScale());

        await tester.pumpWidget(buildDiscoveryView());

        await Future.delayed(Duration(milliseconds: 500));
        await tester.pump();

        // Both columns should be visible
        expect(find.text('Machines'), findsOneWidget);
        expect(find.text('Scales'), findsOneWidget);
        expect(find.text('MockDe1'), findsWidgets);
        expect(find.text('Mock Scale'), findsOneWidget);
      });
    });
  });
}
