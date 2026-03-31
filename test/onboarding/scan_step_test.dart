import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/scale.dart' as device_scale;
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';
import 'package:reaprime/src/onboarding_feature/steps/scan_step.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_device_scanner.dart';
import '../helpers/mock_scale_controller.dart';
import '../helpers/mock_settings_service.dart';

/// A [ConnectionManager] subclass that gives tests direct control over the
/// status stream and records `connect()` calls, without requiring real
/// device scanning infrastructure.
class MockConnectionManager extends ConnectionManager {
  final _statusOverride = BehaviorSubject<ConnectionStatus>.seeded(
    const ConnectionStatus(phase: ConnectionPhase.scanning),
  );

  int connectCallCount = 0;

  MockConnectionManager({
    required super.deviceScanner,
    required super.de1Controller,
    required super.scaleController,
    required super.settingsController,
  });

  @override
  Stream<ConnectionStatus> get status => _statusOverride.stream;

  @override
  ConnectionStatus get currentStatus => _statusOverride.value;

  void emitStatus(ConnectionStatus status) => _statusOverride.add(status);

  @override
  Future<void> connect({bool scaleOnly = false}) async {
    connectCallCount++;
  }

  @override
  Future<void> connectMachine(De1Interface machine) async {}

  @override
  Future<void> connectScale(device_scale.Scale scale) async {}

  @override
  void dispose() {
    _statusOverride.close();
    super.dispose();
  }
}

class _TrackingOnboardingController extends OnboardingController {
  int advanceCallCount = 0;

  _TrackingOnboardingController()
      : super(steps: [
          OnboardingStep(
            id: 'scan',
            shouldShow: () async => true,
            builder: (_) => const SizedBox(),
          ),
          OnboardingStep(
            id: 'next',
            shouldShow: () async => true,
            builder: (_) => const SizedBox(),
          ),
        ]);

  @override
  void advance() {
    advanceCallCount++;
    super.advance();
  }
}

void main() {
  late MockConnectionManager mockConnectionManager;
  late MockBleDiscoveryService mockBleService;
  late ScanStateGuardian scanStateGuardian;
  late _TrackingOnboardingController onboardingController;
  late SettingsController settingsController;
  late MockDeviceScanner mockDeviceScanner;
  late MockDe1Controller mockDe1Controller;
  late MockScaleController mockScaleController;

  setUp(() async {
    mockDeviceScanner = MockDeviceScanner();
    mockDe1Controller =
        MockDe1Controller(controller: DeviceController([]));
    mockScaleController = MockScaleController();
    settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();

    mockConnectionManager = MockConnectionManager(
      deviceScanner: mockDeviceScanner,
      de1Controller: mockDe1Controller,
      scaleController: mockScaleController,
      settingsController: settingsController,
    );

    mockBleService = MockBleDiscoveryService();
    scanStateGuardian = ScanStateGuardian(bleService: mockBleService);

    onboardingController = _TrackingOnboardingController();
    await onboardingController.initialize();
  });

  tearDown(() {
    mockConnectionManager.dispose();
    scanStateGuardian.dispose();
    mockBleService.dispose();
    mockDeviceScanner.dispose();
  });

  Widget buildSubject() {
    return ShadApp(
      home: Scaffold(
        body: ScanStepView(
          onboardingController: onboardingController,
          connectionManager: mockConnectionManager,
          deviceController: DeviceController([]),
          settingsController: settingsController,
          scanStateGuardian: scanStateGuardian,
        ),
      ),
    );
  }

  group('scanning phase', () {
    testWidgets('shows progress indicator during scanning', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      expect(find.byType(ShadProgress), findsOneWidget);
    });

    testWidgets('does not show "taking too long" button initially',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      // The text exists in the tree but is invisible (opacity 0)
      expect(find.text('This is taking a while...'), findsOneWidget);
      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(animatedOpacity.opacity, 0.0);
    });

    testWidgets('shows "taking too long" button after 8 seconds',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      // Advance past the threshold
      await tester.pump(ScanStepView.scanTooLongThreshold);
      // Let the animation complete
      await tester.pump(const Duration(milliseconds: 500));

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(animatedOpacity.opacity, 1.0);
    });
  });

  group('taking too long bottom sheet', () {
    testWidgets('opens bottom sheet with 3 options', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      // Advance past threshold so button is visible
      await tester.pump(ScanStepView.scanTooLongThreshold);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('This is taking a while...'));
      // Use pump() with duration instead of pumpAndSettle() because
      // ShadProgress has an ongoing animation that prevents settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Re-start scan'), findsOneWidget);
      expect(find.text('Export logs'), findsOneWidget);
      expect(find.text('Continue to Dashboard'), findsOneWidget);
    });

    testWidgets('Re-start scan calls connectionManager.connect',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      await tester.pump(ScanStepView.scanTooLongThreshold);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('This is taking a while...'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final before = mockConnectionManager.connectCallCount;
      await tester.tap(find.text('Re-start scan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(mockConnectionManager.connectCallCount, before + 1);
    });

    testWidgets('Continue to Dashboard calls advance', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      await tester.pump(ScanStepView.scanTooLongThreshold);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('This is taking a while...'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final before = onboardingController.advanceCallCount;
      await tester.tap(find.text('Continue to Dashboard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(onboardingController.advanceCallCount, before + 1);
    });
  });

  group('connecting phase', () {
    testWidgets('shows "Connecting to your machine..." for connectingMachine',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      mockConnectionManager.emitStatus(
        const ConnectionStatus(phase: ConnectionPhase.connectingMachine),
      );
      await tester.pump();

      expect(find.text('Connecting to your machine...'), findsOneWidget);
      expect(find.byType(ShadProgress), findsOneWidget);
    });

    testWidgets('shows "Connecting to your scale..." for connectingScale',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      mockConnectionManager.emitStatus(
        const ConnectionStatus(phase: ConnectionPhase.connectingScale),
      );
      await tester.pump();

      expect(find.text('Connecting to your scale...'), findsOneWidget);
    });
  });

  group('ready phase', () {
    testWidgets('calls onboardingController.advance() on ready',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      mockConnectionManager.emitStatus(
        const ConnectionStatus(phase: ConnectionPhase.ready),
      );
      await tester.pump();

      expect(onboardingController.advanceCallCount, 1);
    });

    testWidgets('only advances once even if ready emitted multiple times',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      mockConnectionManager.emitStatus(
        const ConnectionStatus(phase: ConnectionPhase.ready),
      );
      await tester.pump();

      mockConnectionManager.emitStatus(
        const ConnectionStatus(phase: ConnectionPhase.ready),
      );
      await tester.pump();

      expect(onboardingController.advanceCallCount, 1);
    });
  });

  group('error states', () {
    testWidgets('shows error view with retry on connection error',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      mockConnectionManager.emitStatus(
        const ConnectionStatus(
          phase: ConnectionPhase.idle,
          error: 'Connection timed out',
        ),
      );
      await tester.pump();

      expect(find.text('Connection Error'), findsOneWidget);
      expect(find.text('Connection timed out'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('retry button calls connect', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      mockConnectionManager.emitStatus(
        const ConnectionStatus(
          phase: ConnectionPhase.idle,
          error: 'Connection timed out',
        ),
      );
      await tester.pump();

      final before = mockConnectionManager.connectCallCount;
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(mockConnectionManager.connectCallCount, before + 1);
    });
  });

  group('no devices found', () {
    testWidgets('shows no devices view when idle with no machines',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      mockConnectionManager.emitStatus(
        const ConnectionStatus(phase: ConnectionPhase.idle),
      );
      await tester.pump();

      expect(find.text('No Devices Found'), findsOneWidget);
      expect(find.text('Scan Again'), findsOneWidget);
      expect(find.text('Continue to Dashboard'), findsOneWidget);
    });

    testWidgets('Continue to Dashboard advances onboarding', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      mockConnectionManager.emitStatus(
        const ConnectionStatus(phase: ConnectionPhase.idle),
      );
      await tester.pump();

      await tester.tap(find.text('Continue to Dashboard'));
      await tester.pump();

      expect(onboardingController.advanceCallCount, 1);
    });
  });

  group('ScanStateGuardian integration', () {
    testWidgets('shows adapter error when BLE adapter turns off',
        (tester) async {
      // Set initial state to poweredOn before building widget,
      // so the guardian sees the transition to poweredOff.
      mockBleService.setAdapterState(AdapterState.poweredOn);
      // Allow guardian subscription to process
      await tester.runAsync(() => Future.delayed(Duration.zero));

      await tester.pumpWidget(buildSubject());
      await tester.pump();

      // Turn off adapter — ScanStateGuardian will emit adapterTurnedOff
      mockBleService.setAdapterState(AdapterState.poweredOff);
      // Allow stream events to propagate
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.text('Bluetooth Unavailable'), findsOneWidget);
      expect(find.text('Bluetooth was turned off'), findsOneWidget);
    });

    testWidgets('clears adapter error when BLE adapter turns back on',
        (tester) async {
      mockBleService.setAdapterState(AdapterState.poweredOn);
      await tester.runAsync(() => Future.delayed(Duration.zero));

      await tester.pumpWidget(buildSubject());
      await tester.pump();

      // Turn off
      mockBleService.setAdapterState(AdapterState.poweredOff);
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('Bluetooth Unavailable'), findsOneWidget);

      // Turn back on
      mockBleService.setAdapterState(AdapterState.poweredOn);
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('Bluetooth Unavailable'), findsNothing);
    });
  });

  group('createScanStep factory', () {
    test('creates step with id "scan" that always shows', () async {
      final step = createScanStep(
        connectionManager: mockConnectionManager,
        deviceController: DeviceController([]),
        settingsController: settingsController,
        scanStateGuardian: scanStateGuardian,
      );

      expect(step.id, 'scan');
      expect(await step.shouldShow(), isTrue);
    });
  });
}
