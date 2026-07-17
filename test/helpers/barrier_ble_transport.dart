import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'fake_ble_transport.dart';

class BarrierBleTransport extends FakeBleTransport {
  final Map<String, Queue<Completer<FakeBleWrite>>> _writeWaiters = {};
  final Map<String, Queue<Completer<void>>> _writeBarriers = {};

  Future<FakeBleWrite> nextWrite(String characteristicUuid) {
    final completer = Completer<FakeBleWrite>();
    _writeWaiters.putIfAbsent(characteristicUuid, Queue.new).add(completer);
    return completer.future;
  }

  void pauseNextWrite(String characteristicUuid, Completer<void> barrier) {
    _writeBarriers.putIfAbsent(characteristicUuid, Queue.new).add(barrier);
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    await super.write(
      serviceUUID,
      characteristicUUID,
      data,
      withResponse: withResponse,
      timeout: timeout,
    );
    final waiters = _writeWaiters[characteristicUUID];
    if (waiters != null && waiters.isNotEmpty) {
      waiters.removeFirst().complete(writes.last);
    }
    final barriers = _writeBarriers[characteristicUUID];
    if (barriers != null && barriers.isNotEmpty) {
      await barriers.removeFirst().future;
    }
  }
}
