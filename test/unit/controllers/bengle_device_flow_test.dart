import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_virtual_scale.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/machine.dart';

import '../../helpers/fake_ble_transport.dart';

/// A 0xA013 frame carrying an explicit weight and GFlow. GFlow is a big-endian
/// u16 hundredths at offset 10; weight is a big-endian u16 in 1/32 g at offset
/// 20. (Full byte-level breakdown lives in `bengle_shot_sample_test.dart`.)
Uint8List _frame({required double weightG, required double gFlowGps}) {
  final b = ByteData(28);
  b.setUint16(2, 900, Endian.big); // group pressure 9.00 bar
  b.setUint16(10, (gFlowGps * 100).round(), Endian.big);
  b.setUint16(20, (weightG * 32).round(), Endian.big);
  return b.buffer.asUint8List();
}

/// The Bengle computes gravimetric flow on-device, on the load cell it owns,
/// and ships it in every 15 Hz 0xA013 frame. These tests lock the app to that
/// number on the **scale** surface.
///
/// Without the lock, `ScaleController` runs a flow *estimator* over the Bengle's
/// weight — re-deriving a quantity the firmware already computed from the very
/// signal it derived it from. That estimate reads ~0 g/s at shot onset and needs
/// roughly a second to converge, and the shot path consumes it: step-weight
/// exits, the stopping-yield refinement, `ws/v1/scale/snapshot` and the shot
/// record all read `WeightSnapshot.weightFlow`.
///
/// The lock is deliberately asserted **with the Kalman flag ON**, because Kalman
/// is the upstream default and swapping the estimator must never again change
/// what a Bengle reports.
void main() {
  const firmwareGFlow = 1.80; // g/s, as reported in the 0xA013 GFlow field

  group('Bengle device-computed flow (0xA013 GFlow) reaches the scale surface',
      () {
    late FakeBleTransport transport;
    late Bengle bengle;
    late ScaleController controller;

    Future<void> connect({required bool kalman}) async {
      transport = FakeBleTransport();
      // calFlowEst keeps onConnect from eating the MMR read-retry timeout.
      transport.queueMmrResponseInt(MMRItem.calFlowEst, 100);
      transport.queueOnConnectResponses(v13Model: 128); // a real Bengle
      bengle = Bengle(transport: transport);
      await bengle.onConnect();
      controller = ScaleController()..setKalmanFlowEnabled(kalman);
      await controller.connectToScale(BengleVirtualScale(bengle));
    }

    Future<void> shutdown() async {
      controller.dispose();
      transport.dispose();
    }

    for (final kalman in [true, false]) {
      final label = kalman ? 'kalmanFlow ON (upstream default)' : 'kalmanFlow OFF';

      test('$label: the firmware GFlow is emitted verbatim on the FIRST sample',
          () async {
        await connect(kalman: kalman);
        final out = <WeightSnapshot>[];
        final sub = controller.weightSnapshot.listen(out.add);
        final push = transport.subscribers[Endpoint.bengleShotSample.uuid]!;

        push(_frame(weightG: 20.0, gFlowGps: firmwareGFlow));
        await pumpEventQueue();

        expect(out, isNotEmpty);
        expect(
          out.last.weightFlow,
          closeTo(firmwareGFlow, 1e-9),
          reason: 'the app must not re-estimate a flow the firmware computed; '
              'an estimator would read ~0 g/s on the first sample',
        );
        expect(out.last.weight, closeTo(20.0, 1e-6));

        await sub.cancel();
        await shutdown();
      });

      test('$label: no estimator lag — every sample of a steady pour is GFlow',
          () async {
        await connect(kalman: kalman);
        final out = <WeightSnapshot>[];
        final sub = controller.weightSnapshot.listen(out.add);
        final push = transport.subscribers[Endpoint.bengleShotSample.uuid]!;

        // 2 s of a 15 Hz pour: the weight really does climb at `firmwareGFlow`,
        // and the firmware says so in every frame.
        for (var i = 0; i < 30; i++) {
          push(_frame(
            weightG: 20.0 + firmwareGFlow * (i / 15.0),
            gFlowGps: firmwareGFlow,
          ));
          await pumpEventQueue();
        }

        expect(out.length, greaterThanOrEqualTo(30));
        for (final snap in out) {
          expect(
            snap.weightFlow,
            closeTo(firmwareGFlow, 1e-9),
            reason: 'an app-side estimator would ramp up to this value over '
                '~1 s instead of reporting it immediately',
          );
        }

        await sub.cancel();
        await shutdown();
      });
    }

    test('toggling the Kalman flag does not change what a Bengle reports',
        () async {
      final flows = <bool, double>{};
      for (final kalman in [true, false]) {
        await connect(kalman: kalman);
        final out = <WeightSnapshot>[];
        final sub = controller.weightSnapshot.listen(out.add);
        final push = transport.subscribers[Endpoint.bengleShotSample.uuid]!;

        push(_frame(weightG: 20.0, gFlowGps: firmwareGFlow));
        await pumpEventQueue();

        flows[kalman] = out.last.weightFlow;
        await sub.cancel();
        await shutdown();
      }

      expect(
        flows[true],
        closeTo(flows[false]!, 1e-9),
        reason: 'the estimator choice must be inert on a device that computes '
            'its own flow — this is the regression lock against a future '
            'upstream estimator silently taking over the Bengle',
      );
      expect(flows[true], closeTo(firmwareGFlow, 1e-9));
    });

    test(
      'the machine and scale surfaces report the SAME flow (single source)',
      () async {
        await connect(kalman: true);
        final machineSnaps = <MachineSnapshot>[];
        final scaleSnaps = <WeightSnapshot>[];
        final mSub = bengle.currentSnapshot.listen(machineSnaps.add);
        final sSub = controller.weightSnapshot.listen(scaleSnaps.add);
        final push = transport.subscribers[Endpoint.bengleShotSample.uuid]!;

        push(_frame(weightG: 20.0, gFlowGps: firmwareGFlow));
        await pumpEventQueue();

        expect(machineSnaps.last.weightFlow, closeTo(firmwareGFlow, 1e-9));
        expect(scaleSnaps.last.weightFlow, closeTo(firmwareGFlow, 1e-9));
        expect(
          scaleSnaps.last.weightFlow,
          closeTo(machineSnaps.last.weightFlow, 1e-9),
          reason: 'ws/v1/machine/snapshot and ws/v1/scale/snapshot must not '
              'disagree about the flow of the same shot',
        );

        await mSub.cancel();
        await sSub.cancel();
        await shutdown();
      },
    );
  });
}
