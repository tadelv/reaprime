import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/forms/hot_water_form.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';

import '../helpers/mock_device_discovery_service.dart';

/// Counts every event that crosses `MockDe1.shotSettings` — the same
/// stream `/ws/v1/machine/shotSettings` delivers to clients. These
/// tests pin the emit-count contract per De1Controller write op so we
/// catch regressions (and drive follow-up reductions) in the number of
/// WS messages per workflow change.
///
/// Context: the original redundant-writes report observed 5 WS emits
/// per single steam-duration PUT. After adding value equality on the
/// workflow data classes and awaiting the individual settings writes
/// in WorkflowHandler, the count drops to 2 per changed field — one
/// from the `setXFlow` "nudge" re-emit and one from the actual
/// `updateShotSettings` write. The nudge is a workaround inside
/// MockDe1/UnifiedDe1 to trigger the De1Controller refresh when flow
/// values change; it's still a redundant WS emit from the client's POV.
void main() {
  late MockDe1 mockDe1;
  late DeviceController deviceController;
  late De1Controller de1Controller;
  late List<De1ShotSettings> observedEmits;
  late StreamSubscription<De1ShotSettings> sub;

  setUp(() async {
    mockDe1 = MockDe1();
    deviceController = DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    de1Controller = De1Controller(controller: deviceController);
    await de1Controller.connectToDe1(mockDe1);

    observedEmits = [];
    sub = mockDe1.shotSettings.listen(observedEmits.add);

    // Let the De1Controller initialization + its internal 100 ms
    // shot-settings debounce settle before the test body runs.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    observedEmits.clear();
  });

  tearDown(() async {
    await sub.cancel();
  });

  group('updateSteamSettings — shotSettings emit count', () {
    test(
      'exactly one emit per steam change (ideal after nudge removal)',
      () async {
        await de1Controller.updateSteamSettings(
          SteamFormSettings(
            steamEnabled: true,
            targetTemp: 150,
            targetDuration: 30,
            targetFlow: 2.5,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          observedEmits.length,
          equals(1),
          reason: 'every setXFlow call in MockDe1/UnifiedDe1 currently '
              're-adds the current shotSettings to the subject as a '
              'workaround to trigger the De1Controller refresh; this '
              'leaks a redundant WS emit. Dropping the nudge (or '
              'replacing it with a dedicated refresh channel) makes '
              'this hit 1.',
        );
      },
      skip: 'pending: drop setXFlow nudge re-emit in '
          'mock_de1.dart/unified_de1.dart — see workflow-updates fix '
          'doc. Remove skip when that lands.',
    );

    test(
      'current behaviour: two emits per steam change (nudge + write)',
      () async {
        await de1Controller.updateSteamSettings(
          SteamFormSettings(
            steamEnabled: true,
            targetTemp: 150,
            targetDuration: 30,
            targetFlow: 2.5,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          observedEmits.length,
          equals(2),
          reason: '1 from MockDe1.setSteamFlow nudge re-emit + 1 from '
              'MockDe1.updateShotSettings. Regression guard: if this '
              'climbs back to 3+ we have reintroduced the '
              'read-modify-write or diff-miss bug.',
        );
        expect(observedEmits.last.targetSteamDuration, equals(30));
      },
    );

    test(
      'multi-field De1Controller sequence: one emit per setXFlow + write',
      () async {
        // Mirrors what WorkflowHandler does for a multi-field PUT that
        // touches steam + hot-water + rinse (which is how the original
        // 5-emit report reproduced). With value equality the handler
        // only enters the branches whose values actually changed; we
        // simulate all three here to pin the per-path count.
        await de1Controller.updateFlushSettings(
          RinseData(targetTemperature: 91, duration: 11, flow: 6.5),
        );
        await de1Controller.updateSteamSettings(
          SteamFormSettings(
            steamEnabled: true,
            targetTemp: 150,
            targetDuration: 44,
            targetFlow: 2.5,
          ),
        );
        await de1Controller.updateHotWaterSettings(
          HotWaterFormSettings(
            targetTemperature: 76,
            flow: 10.0,
            volume: 50,
            duration: 55,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // rinse  : setFlushFlow nudge (1). setFlushTimeout +
        //          setFlushTemperature are no-ops on MockDe1 so no
        //          additional emits.
        // steam  : setSteamFlow nudge (1) + updateShotSettings (1).
        // hw     : setHotWaterFlow nudge (1) + updateShotSettings (1).
        expect(
          observedEmits.length,
          equals(5),
          reason: 'post-fix: 1 rinse-nudge + 2 steam + 2 hot-water. '
              'Reducing this requires dropping the setXFlow nudge '
              're-emits.',
        );
        expect(observedEmits.last.targetSteamDuration, equals(44));
        expect(observedEmits.last.targetHotWaterDuration, equals(55));
      },
    );
  });
}
