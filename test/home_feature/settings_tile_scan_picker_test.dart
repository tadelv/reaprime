import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/tiles/settings_tile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/fake_connection_manager.dart';
import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_scanner.dart';
import '../helpers/mock_scale_controller.dart';
import '../helpers/mock_settings_service.dart';
import '../helpers/test_de1.dart';

/// FakeConnectionManager variant that mimics the post-scan state the
/// real ConnectionManager would publish when the scan ends with
/// MachinePickerAction: `pendingAmbiguity = machinePicker`, machines
/// populated on `foundMachines`.
class _AmbiguousMachineFakeCM extends FakeConnectionManager {
  final List<De1Interface> machines;
  int connectMachineCalls = 0;
  De1Interface? lastConnectMachineArg;

  _AmbiguousMachineFakeCM._({
    required this.machines,
    required super.deviceScanner,
    required super.de1Controller,
    required super.scaleController,
    required super.settingsController,
  }) : super.forSubclass();

  factory _AmbiguousMachineFakeCM(List<De1Interface> machines) {
    final scanner = MockDeviceScanner();
    final de1 = MockDe1Controller(controller: DeviceController(const []));
    final scale = MockScaleController();
    final settings = SettingsController(MockSettingsService());
    return _AmbiguousMachineFakeCM._(
      machines: machines,
      deviceScanner: scanner,
      de1Controller: de1,
      scaleController: scale,
      settingsController: settings,
    );
  }

  @override
  Future<void> connect({bool scaleOnly = false}) async {
    await super.connect(scaleOnly: scaleOnly);
    emitStatus(
      currentStatus.copyWith(
        phase: ConnectionPhase.idle,
        foundMachines: machines,
        pendingAmbiguity: () => AmbiguityReason.machinePicker,
      ),
    );
  }

  @override
  Future<void> connectMachine(De1Interface machine) async {
    connectMachineCalls++;
    lastConnectMachineArg = machine;
  }
}

Widget _wrap(Widget child) =>
    ShadApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets(
    'tapping Scan when preferred machine is missing shows a picker '
    'dialog (comms-harden dashboard #2)',
    (tester) async {
      final m1 = TestDe1(deviceId: 'DE1-AA', name: 'DE1-Left');
      final m2 = TestDe1(deviceId: 'DE1-BB', name: 'DE1-Right');
      final cm = _AmbiguousMachineFakeCM([m1, m2]);
      final de1Controller = MockDe1Controller(
        controller: DeviceController(const []),
      );

      await tester.pumpWidget(_wrap(SettingsTile(
        controller: de1Controller,
        connectionManager: cm,
      )));
      await tester.pump();

      expect(find.text('Scan'), findsOneWidget);
      await tester.tap(find.text('Scan'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Select Machine'), findsOneWidget,
          reason: 'picker dialog must appear when connect() returns '
              'with pendingAmbiguity.machinePicker');
      expect(find.text('DE1-AA'), findsOneWidget);
      expect(find.text('DE1-BB'), findsOneWidget);

      await tester.tap(find.text('DE1-AA'));
      await tester.pump();

      expect(cm.connectMachineCalls, 1);
      expect(cm.lastConnectMachineArg, m1);
    },
  );

  testWidgets(
    'tapping Scan without ambiguity (machine found & connected) shows '
    'no picker dialog',
    (tester) async {
      final cm = FakeConnectionManager(); // default: connect() no-ops
      final de1Controller = MockDe1Controller(
        controller: DeviceController(const []),
      );

      await tester.pumpWidget(_wrap(SettingsTile(
        controller: de1Controller,
        connectionManager: cm,
      )));
      await tester.pump();

      await tester.tap(find.text('Scan'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Select Machine'), findsNothing);
    },
  );
}
