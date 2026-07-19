import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/device_discovery_feature/scan_flow_view.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'helpers/mock_connection_manager.dart';
import 'helpers/mock_de1_controller.dart';
import 'helpers/mock_device_discovery_service.dart';
import 'helpers/mock_device_scanner.dart';
import 'helpers/mock_scale_controller.dart';
import 'helpers/mock_settings_service.dart';
import 'helpers/test_scale.dart';

void main() {
  late MockConnectionManager mockCm;
  late MockDeviceScanner mockScanner;
  late DeviceController deviceController;
  late SettingsController settingsController;
  late ScanStateGuardian scanStateGuardian;

  setUp(() async {
    mockScanner = MockDeviceScanner();
    final de1 = MockDe1Controller(controller: DeviceController([]));
    final scale = MockScaleController();
    final settings = SettingsController(MockSettingsService());
    await settings.loadSettings();

    mockCm = MockConnectionManager(
      deviceScanner: mockScanner,
      de1Controller: de1,
      scaleController: scale,
      settingsController: settings,
    );

    final discovery = MockBleDiscoveryService();
    deviceController = DeviceController([discovery]);
    await deviceController.initialize();
    settingsController = settings;
    scanStateGuardian = ScanStateGuardian(bleService: discovery);
  });

  Widget buildView({VoidCallback? initialConnectionIntent}) {
    return ShadApp(
      home: ScanFlowView(
        connectionManager: mockCm,
        deviceController: deviceController,
        settingsController: settingsController,
        scanStateGuardian: scanStateGuardian,
        initialConnectionIntent: initialConnectionIntent,
        onConnected: () {},
        onExit: () {},
      ),
    );
  }

  group('initial connection intent', () {
    testWidgets('uses scanAndConnect when intent is provided', (tester) async {
      await tester.pumpWidget(buildView(
        initialConnectionIntent: () => mockCm.scanAndConnect(),
      ));
      await tester.pump();

      expect(mockCm.scanAndConnectCallCount, 1);
      expect(
        mockCm.connectCallCount - mockCm.scanAndConnectCallCount,
        0,
        reason: 'all connect calls should be scanAndConnect',
      );
    });

    testWidgets('uses connect when no intent is provided', (tester) async {
      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(mockCm.connectCallCount, 1);
      expect(mockCm.scanAndConnectCallCount, 0);
    });
  });

  group('picker selection', () {
    testWidgets('machine picker calls selectMachine', (tester) async {
      // Emit machinePicker state with one machine candidate.
      mockCm.emitStatus(ConnectionStatus(
        phase: ConnectionPhase.idle,
        pendingAmbiguity: AmbiguityReason.machinePicker,
        foundMachines: [
          FakeDe1(deviceId: 'm1', name: 'DE1 #1'),
        ],
      ));

      await tester.pumpWidget(buildView(
        initialConnectionIntent: () => mockCm.scanAndConnect(),
      ));
      await tester.pumpAndSettle();

      // Should see the machine name and Connect button.
      expect(find.text('DE1 #1'), findsOneWidget);

      // Tap the machine card to select it.
      await tester.tap(find.text('DE1 #1'));
      await tester.pump();

      // Tap Connect.
      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(mockCm.selectMachineCallCount, 1);
      expect(mockCm.scanAndConnectCallCount, 1,
          reason: 'scan count must not increase for a picker selection');
    });

    testWidgets('scale picker calls selectScale', (tester) async {
      mockCm.emitStatus(ConnectionStatus(
        phase: ConnectionPhase.idle,
        pendingAmbiguity: AmbiguityReason.scalePicker,
        foundScales: [
          TestScale(deviceId: 's1', name: 'Decent Scale'),
        ],
      ));

      await tester.pumpWidget(buildView(
        initialConnectionIntent: () => mockCm.scanAndConnect(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Decent Scale'), findsOneWidget);

      await tester.tap(find.text('Decent Scale'));
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(mockCm.selectScaleCallCount, 1);
      expect(mockCm.scanAndConnectCallCount, 1,
          reason: 'scan count must not increase for a picker selection');
    });

    testWidgets('machine picker transitions to scale picker after selection',
        (tester) async {
      // Phase 1: machinePicker
      mockCm.emitStatus(ConnectionStatus(
        phase: ConnectionPhase.idle,
        pendingAmbiguity: AmbiguityReason.machinePicker,
        foundMachines: [
          FakeDe1(deviceId: 'm1', name: 'DE1 #1'),
        ],
      ));

      await tester.pumpWidget(buildView(
        initialConnectionIntent: () => mockCm.scanAndConnect(),
      ));
      await tester.pumpAndSettle();

      // Select and connect the machine.
      await tester.tap(find.text('DE1 #1'));
      await tester.pump();
      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(mockCm.selectMachineCallCount, 1);

      // Phase 2: selectMachine emits scalePicker from the retained session.
      mockCm.emitStatus(ConnectionStatus(
        phase: ConnectionPhase.idle,
        pendingAmbiguity: AmbiguityReason.scalePicker,
        foundScales: [
          TestScale(deviceId: 's1', name: 'Decent Scale'),
        ],
      ));

      await tester.pumpAndSettle();

      // Now the scale picker should be visible.
      expect(find.text('Decent Scale'), findsOneWidget);
      expect(find.text('Scales'), findsOneWidget);

      // Select and connect the scale.
      await tester.tap(find.text('Decent Scale'));
      await tester.pump();
      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(mockCm.selectScaleCallCount, 1);

      // Scan count still hasn't increased.
      expect(mockCm.scanAndConnectCallCount, 1);
    });
  });
}
