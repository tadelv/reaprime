import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:collection/collection.dart';

/// Spy settings service that tracks calls to setSimulatedDevices.
class _SpySettingsService implements SettingsService {
  int setSimulatedDevicesCallCount = 0;
  Set<SimulatedDevicesTypes> _simulatedDevices = {};

  @override
  Future<Set<SimulatedDevicesTypes>> simulateDevices() async => _simulatedDevices;
  @override
  Future<void> setSimulatedDevices(Set<SimulatedDevicesTypes> value) async {
    setSimulatedDevicesCallCount++;
    _simulatedDevices = value;
  }

  // Unused stubs — only testing simulated devices path.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SettingsController.enableSimulatedDevicesForSession', () {
    test('sets simulatedDevices in memory', () {
      final spy = _SpySettingsService();
      final controller = SettingsController(spy);

      controller.enableSimulatedDevicesForSession(
        {SimulatedDevicesTypes.machine, SimulatedDevicesTypes.scale},
      );

      expect(
        controller.simulatedDevices,
        {SimulatedDevicesTypes.machine, SimulatedDevicesTypes.scale},
      );
    });

    test('notifies listeners', () {
      final spy = _SpySettingsService();
      final controller = SettingsController(spy);
      var notified = false;
      controller.addListener(() => notified = true);

      controller.enableSimulatedDevicesForSession({SimulatedDevicesTypes.machine});

      expect(notified, isTrue);
    });

    test('does NOT call setSimulatedDevices on the service (no persist)', () {
      final spy = _SpySettingsService();
      final controller = SettingsController(spy);

      controller.enableSimulatedDevicesForSession({SimulatedDevicesTypes.scale});

      expect(spy.setSimulatedDevicesCallCount, 0);
    });

    test('overwrites previous in-memory value', () {
      final spy = _SpySettingsService();
      final controller = SettingsController(spy);

      controller.enableSimulatedDevicesForSession({SimulatedDevicesTypes.machine});
      controller.enableSimulatedDevicesForSession({SimulatedDevicesTypes.scale});

      expect(controller.simulatedDevices, {SimulatedDevicesTypes.scale});
    });

    test('can clear simulated devices', () {
      final spy = _SpySettingsService();
      final controller = SettingsController(spy);

      controller.enableSimulatedDevicesForSession(
        {SimulatedDevicesTypes.machine, SimulatedDevicesTypes.scale},
      );
      controller.enableSimulatedDevicesForSession({});

      expect(controller.simulatedDevices, isEmpty);
    });
  });
}
