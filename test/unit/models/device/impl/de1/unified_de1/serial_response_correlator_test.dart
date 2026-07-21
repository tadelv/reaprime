import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/serial_response_correlator.dart';

void main() {
  test('correlates different representations independently', () async {
    final correlator = SerialResponseCorrelator();
    final a = correlator.register('A', const Duration(seconds: 1));
    final j = correlator.register('J', const Duration(seconds: 1));

    expect(correlator.complete('J', ByteData(2)), isTrue);
    expect(correlator.complete('A', ByteData(1)), isTrue);

    expect((await a).lengthInBytes, 1);
    expect((await j).lengthInBytes, 2);
  });

  test('rejects a second pending request for the same representation', () {
    final correlator = SerialResponseCorrelator();
    correlator.register('A', const Duration(seconds: 1));

    expect(
      () => correlator.register('A', const Duration(seconds: 1)),
      throwsStateError,
    );
  });

  test('timeout removes the waiter and late responses are ignored', () async {
    final correlator = SerialResponseCorrelator();

    await expectLater(
      correlator.register('A', Duration.zero),
      throwsA(isA<TimeoutException>()),
    );

    expect(correlator.complete('A', ByteData(1)), isFalse);
    final next = correlator.register('A', const Duration(seconds: 1));
    correlator.complete('A', ByteData(2));
    expect((await next).lengthInBytes, 2);
  });

  test('failAll fails and removes every waiter', () async {
    final correlator = SerialResponseCorrelator();
    final a = correlator.register('A', const Duration(seconds: 1));
    final j = correlator.register('J', const Duration(seconds: 1));

    correlator.failAll(StateError('disconnected'));

    await expectLater(a, throwsStateError);
    await expectLater(j, throwsStateError);
    expect(correlator.hasPending, isFalse);
  });
}
