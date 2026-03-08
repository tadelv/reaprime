import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/rxdart.dart';

enum ConnectionPhase {
  idle,
  scanning,
  connectingMachine,
  connectingScale,
  ready,
}

enum AmbiguityReason {
  machinePicker,
  scalePicker,
}

class ConnectionStatus {
  final ConnectionPhase phase;
  final List<De1Interface> foundMachines;
  final List<Scale> foundScales;
  final AmbiguityReason? pendingAmbiguity;
  final String? error;

  const ConnectionStatus({
    this.phase = ConnectionPhase.idle,
    this.foundMachines = const [],
    this.foundScales = const [],
    this.pendingAmbiguity,
    this.error,
  });

  ConnectionStatus copyWith({
    ConnectionPhase? phase,
    List<De1Interface>? foundMachines,
    List<Scale>? foundScales,
    AmbiguityReason? Function()? pendingAmbiguity,
    String? Function()? error,
  }) {
    return ConnectionStatus(
      phase: phase ?? this.phase,
      foundMachines: foundMachines ?? this.foundMachines,
      foundScales: foundScales ?? this.foundScales,
      pendingAmbiguity:
          pendingAmbiguity != null ? pendingAmbiguity() : this.pendingAmbiguity,
      error: error != null ? error() : this.error,
    );
  }
}

class ConnectionManager {
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final ScaleController scaleController;
  final SettingsController settingsController;

  final BehaviorSubject<ConnectionStatus> _statusSubject =
      BehaviorSubject.seeded(const ConnectionStatus());

  Stream<ConnectionStatus> get status => _statusSubject.stream;
  ConnectionStatus get currentStatus => _statusSubject.value;

  bool _isConnectingMachine = false;
  bool _isConnectingScale = false;

  ConnectionManager({
    required this.deviceController,
    required this.de1Controller,
    required this.scaleController,
    required this.settingsController,
  });

  Future<void> connectMachine(De1Interface machine) async {
    if (_isConnectingMachine) return;
    _isConnectingMachine = true;

    _statusSubject.add(currentStatus.copyWith(
      phase: ConnectionPhase.connectingMachine,
      error: () => null,
    ));

    try {
      await de1Controller.connectToDe1(machine);
      await settingsController.setPreferredMachineId(machine.deviceId);
      _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.ready));
    } catch (e) {
      _statusSubject.add(currentStatus.copyWith(
        phase: ConnectionPhase.idle,
        error: () => e.toString(),
      ));
      rethrow;
    } finally {
      _isConnectingMachine = false;
    }
  }

  Future<void> connectScale(Scale scale) async {
    if (_isConnectingScale) return;
    _isConnectingScale = true;

    _statusSubject.add(currentStatus.copyWith(
      phase: ConnectionPhase.connectingScale,
      error: () => null,
    ));

    try {
      await scaleController.connectToScale(scale);
      await settingsController.setPreferredScaleId(scale.deviceId);
      _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.ready));
    } catch (e) {
      // Scale failure is non-blocking — stay at ready if machine connected, else idle
      _statusSubject.add(currentStatus.copyWith(
        phase: ConnectionPhase.ready,
        error: () => null,
      ));
    } finally {
      _isConnectingScale = false;
    }
  }

  void dispose() {
    _statusSubject.close();
  }
}
