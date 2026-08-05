import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

import '../../../../../../helpers/barrier_ble_transport.dart';

void main() {
  late BarrierBleTransport transport;
  late UnifiedDe1 de1;

  setUp(() async {
    transport = BarrierBleTransport();
    addTearDown(transport.dispose);
    transport.queueOnConnectResponses();
    de1 = UnifiedDe1(transport: transport);
    await de1.onConnect();
    transport.writes.clear();
  });

  test(
    'setRefillLevel stays pending until the transport write completes',
    () async {
      final writeArrived = transport.nextWrite(Endpoint.waterLevels.uuid);
      final barrier = Completer<void>();
      transport.pauseNextWrite(Endpoint.waterLevels.uuid, barrier);

      final completed = Completer<void>();
      unawaited(de1.setRefillLevel(50).then(completed.complete));
      await writeArrived;

      // The write reached the transport but is blocked on the barrier, so
      // setRefillLevel must still be in flight.
      expect(completed.isCompleted, isFalse);

      barrier.complete();
      await completed.future;
    },
  );

  test(
    'transport error from setRefillLevel propagates to the caller',
    () async {
      final writeArrived = transport.nextWrite(Endpoint.waterLevels.uuid);
      final barrier = Completer<void>();
      transport.pauseNextWrite(Endpoint.waterLevels.uuid, barrier);

      final write = de1.setRefillLevel(50);
      await writeArrived;

      barrier.completeError(StateError('transport boom'));
      await expectLater(write, throwsA(isA<StateError>()));
    },
  );
}
