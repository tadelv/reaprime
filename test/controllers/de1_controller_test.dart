import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';

import '../helpers/mock_device_discovery_service.dart';
import '../helpers/test_de1.dart';

De1ShotSettings _emptyShotSettings() => De1ShotSettings(
      steamSetting: 0,
      targetSteamTemp: 0,
      targetSteamDuration: 0,
      targetHotWaterTemp: 0,
      targetHotWaterVolume: 0,
      targetHotWaterDuration: 0,
      targetShotVolume: 0,
      groupTemp: 0,
    );

void main() {
  group('shot-settings debounce race (comms-harden #5)', () {
    test(
      'disconnect during debounce does not leak an unhandled async error',
      () async {
        final uncaughtErrors = <Object>[];

        await runZonedGuarded(
          () async {
            final deviceController =
                DeviceController([MockDeviceDiscoveryService()]);
            await deviceController.initialize();
            final de1Controller = De1Controller(controller: deviceController);
            final testDe1 = TestDe1();

            // Kick off connect: TestDe1.onConnect is a no-op, so
            // connectToDe1 completes quickly. ready is Stream.value(true)
            // so _initializeData fires on the next microtask.
            await de1Controller.connectToDe1(testDe1);

            // Unblock _initializeData's `shotSettings.first` await +
            // trigger the first _shotSettingsUpdate, which schedules the
            // 100ms debounce timer.
            testDe1.emitShotSettings(_emptyShotSettings());
            // Let the microtask chain reach the scheduled Timer.
            await Future<void>.delayed(Duration.zero);

            // Force a disconnect while the debounce timer is still
            // pending. _onDisconnect bumps _connectionGeneration,
            // nulls _de1, cancels _shotSettingsDebounce, and cancels
            // the shotSettings subscription.
            testDe1.setConnectionState(ConnectionState.disconnected);
            await Future<void>.delayed(Duration.zero);

            // Wait past the 100ms debounce window. With the generation
            // fix, the timer body should find a stale generation (or
            // null _de1) and bail without touching connectedDe1().
            await Future<void>.delayed(
                const Duration(milliseconds: 200));

            testDe1.dispose();
          },
          (error, stack) {
            uncaughtErrors.add(error);
          },
        );

        expect(
          uncaughtErrors,
          isEmpty,
          reason:
              'debounce timer closure must bail on disconnect, not leak '
              'DeviceNotConnectedException into the zone',
        );
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );
  });
}
