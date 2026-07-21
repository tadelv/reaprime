import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/device_discovery_feature/scan_flow_presentation.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';

import '../helpers/mock_connection_manager.dart';

void main() {
  final bluetoothOff = TransportCondition(
    transportType: TransportType.ble,
    affectedDeviceTypes: const {DeviceType.machine, DeviceType.scale},
    connectionError: ConnectionError(
      kind: ConnectionErrorKind.adapterOff,
      severity: ConnectionErrorSeverity.error,
      timestamp: DateTime.utc(2025),
      message: 'Bluetooth is turned off.',
    ),
  );
  final permissionDenied = TransportCondition(
    transportType: TransportType.ble,
    affectedDeviceTypes: const {DeviceType.machine, DeviceType.scale},
    connectionError: ConnectionError(
      kind: ConnectionErrorKind.bluetoothPermissionDenied,
      severity: ConnectionErrorSeverity.error,
      timestamp: DateTime.utc(2025),
      message: 'Bluetooth permission was denied.',
    ),
  );
  final serialMachine = FakeDe1(
    deviceId: 'usb-machine',
    transportType: TransportType.serial,
  );
  final bleMachine = FakeDe1(
    deviceId: 'ble-machine',
    transportType: TransportType.ble,
  );

  final cases =
      <
        ({
          String name,
          ConnectionStatus status,
          TransportConditionDisposition expected,
        })
      >[
        (
          name: 'BLE off while serial scan is active',
          status: ConnectionStatus(
            phase: ConnectionPhase.scanning,
            conditions: [bluetoothOff],
          ),
          expected: TransportConditionDisposition.notice,
        ),
        (
          name: 'BLE off after a serial machine is discovered',
          status: ConnectionStatus(
            phase: ConnectionPhase.scanning,
            foundMachines: [serialMachine],
            conditions: [bluetoothOff],
          ),
          expected: TransportConditionDisposition.notice,
        ),
        (
          name: 'BLE off with serial machine picker',
          status: ConnectionStatus(
            pendingAmbiguity: AmbiguityReason.machinePicker,
            foundMachines: [serialMachine],
            conditions: [bluetoothOff],
          ),
          expected: TransportConditionDisposition.notice,
        ),
        (
          name: 'BLE off with only BLE machines',
          status: ConnectionStatus(
            pendingAmbiguity: AmbiguityReason.machinePicker,
            foundMachines: [bleMachine],
            conditions: [bluetoothOff],
          ),
          expected: TransportConditionDisposition.blocking,
        ),
        (
          name: 'BLE off with mixed machine transports',
          status: ConnectionStatus(
            pendingAmbiguity: AmbiguityReason.machinePicker,
            foundMachines: [bleMachine, serialMachine],
            conditions: [bluetoothOff],
          ),
          expected: TransportConditionDisposition.notice,
        ),
        (
          name: 'BLE off while serial machine connects',
          status: ConnectionStatus(
            phase: ConnectionPhase.connectingMachine,
            activeTargetTransport: TransportType.serial,
            conditions: [bluetoothOff],
          ),
          expected: TransportConditionDisposition.notice,
        ),
        (
          name: 'BLE off after a serial machine is ready',
          status: ConnectionStatus(
            phase: ConnectionPhase.ready,
            conditions: [bluetoothOff],
          ),
          expected: TransportConditionDisposition.notice,
        ),
        (
          name: 'BLE permission denied with serial candidate',
          status: ConnectionStatus(
            pendingAmbiguity: AmbiguityReason.machinePicker,
            foundMachines: [serialMachine],
            conditions: [permissionDenied],
          ),
          expected: TransportConditionDisposition.notice,
        ),
        (
          name: 'BLE-only scale recovery is blocked',
          status: ConnectionStatus(
            phase: ConnectionPhase.scanning,
            intent: ConnectionIntent.scaleRecovery,
            conditions: [bluetoothOff],
          ),
          expected: TransportConditionDisposition.blocking,
        ),
        (
          name: 'serial connection failure keeps Bluetooth partial',
          status: ConnectionStatus(
            activeTargetTransport: TransportType.serial,
            error: ConnectionError(
              kind: ConnectionErrorKind.machineConnectFailed,
              severity: ConnectionErrorSeverity.error,
              timestamp: DateTime.utc(2025),
              message: 'USB machine failed to connect.',
            ),
            conditions: [bluetoothOff],
          ),
          expected: TransportConditionDisposition.notice,
        ),
      ];

  for (final testCase in cases) {
    test(testCase.name, () {
      expect(
        resolveTransportCondition(
          testCase.status,
          testCase.status.conditions.single,
        ),
        testCase.expected,
      );
    });
  }
}
