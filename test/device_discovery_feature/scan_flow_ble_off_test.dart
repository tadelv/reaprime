import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/device_discovery_feature/scan_flow_view.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/mock_connection_manager.dart';
import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_device_scanner.dart';
import '../helpers/mock_scale_controller.dart';
import '../helpers/mock_settings_service.dart';
import '../helpers/test_de1.dart';

/// USB/serial discovery works with Bluetooth off, so the
/// adapter-off error may only replace the scan flow while nothing that
/// works WITHOUT Bluetooth is in flight. A wired-only setup must be able
/// to reach the skin.
void main() {
  late MockConnectionManager mockConnectionManager;
  late MockBleDiscoveryService mockBleService;
  late ScanStateGuardian scanStateGuardian;
  late SettingsController settingsController;
  late MockDeviceScanner mockDeviceScanner;

  setUp(() async {
    mockDeviceScanner = MockDeviceScanner();
    settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();

    mockConnectionManager = MockConnectionManager(
      deviceScanner: mockDeviceScanner,
      de1Controller: MockDe1Controller(controller: DeviceController([])),
      scaleController: MockScaleController(),
      settingsController: settingsController,
    );

    mockBleService = MockBleDiscoveryService();
    scanStateGuardian = ScanStateGuardian(bleService: mockBleService);
  });

  tearDown(() {
    mockConnectionManager.dispose();
    scanStateGuardian.dispose();
    mockBleService.dispose();
    mockDeviceScanner.dispose();
  });

  Widget buildSubject() {
    return ShadApp(
      home: ScanFlowView(
        connectionManager: mockConnectionManager,
        deviceController: DeviceController([]),
        settingsController: settingsController,
        scanStateGuardian: scanStateGuardian,
        onConnected: () {},
        onExit: () {},
      ),
    );
  }

  Future<void> turnAdapterOff(WidgetTester tester) async {
    mockBleService.setAdapterState(AdapterState.poweredOn);
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    mockBleService.setAdapterState(AdapterState.poweredOff);
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
  }

  testWidgets('adapter-off with nothing else in flight shows the error', (
    tester,
  ) async {
    await turnAdapterOff(tester);

    expect(find.text('Bluetooth Unavailable'), findsOneWidget);
    expect(
      find.textContaining('USB connections keep working'),
      findsOneWidget,
      reason: 'the error must tell wired users they are not blocked',
    );
  });

  testWidgets('adapter-off with a found (serial) machine keeps the flow '
      'visible', (tester) async {
    await turnAdapterOff(tester);
    expect(find.text('Bluetooth Unavailable'), findsOneWidget);

    // A serial machine found with Bluetooth off — e.g. the Bengle over
    // its USB port — must surface the normal flow, not the error.
    mockConnectionManager.emitStatus(
      ConnectionStatus(
        phase: ConnectionPhase.idle,
        foundMachines: [TestDe1()],
      ),
    );
    await tester.pump();

    expect(find.text('Bluetooth Unavailable'), findsNothing);
  });

  testWidgets('sticky adapter-off ConnectionError does not hide a found '
      'machine', (tester) async {
    await turnAdapterOff(tester);

    // The connection manager's sticky idle error (what the UI renders as
    // "Connection error: Bluetooth is turned off.") must not out-rank a
    // machine found over USB — the wired flow ends at the picker.
    mockConnectionManager.emitStatus(
      ConnectionStatus(
        phase: ConnectionPhase.idle,
        foundMachines: [TestDe1()],
        error: ConnectionError(
          kind: ConnectionErrorKind.adapterOff,
          severity: ConnectionErrorSeverity.error,
          timestamp: DateTime.now().toUtc(),
          message: 'Bluetooth is turned off.',
          suggestion: 'Turn Bluetooth on to scan for devices.',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Bluetooth Unavailable'), findsNothing);
    expect(
      find.textContaining('Bluetooth is turned off'),
      findsNothing,
      reason: 'the picker, not the error view, must be shown',
    );
  });

  testWidgets('adapter-off during a machine connect keeps the flow visible', (
    tester,
  ) async {
    mockBleService.setAdapterState(AdapterState.poweredOn);
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    mockConnectionManager.emitStatus(
      const ConnectionStatus(phase: ConnectionPhase.connectingMachine),
    );
    await tester.pump();

    mockBleService.setAdapterState(AdapterState.poweredOff);
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.text('Bluetooth Unavailable'), findsNothing);
  });
}
