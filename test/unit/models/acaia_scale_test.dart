import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_scale.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:rxdart/rxdart.dart';

const _weightFrame = <int>[
  0xEF,
  0xDD,
  0x0C,
  0x06,
  0x05,
  0xE8,
  0x03,
  0x00,
  0x00,
  0x01,
  0x00,
];

class _AcaiaTransport extends BLETransport {
  _AcaiaTransport({required this.services, this.emitWeightDuringInit = true});

  final List<String> services;
  final bool emitWeightDuringInit;
  final BehaviorSubject<ConnectionState> states = BehaviorSubject.seeded(
    ConnectionState.discovered,
  );
  final List<List<int>> writes = [];
  void Function(Uint8List)? notification;
  Future<void> Function(Uint8List)? writeBehavior;
  int disconnectCalls = 0;
  bool _initWeightSent = false;

  @override
  String get id => 'acaia-test';

  @override
  String get name => 'LUNAR-TEST';

  @override
  Stream<ConnectionState> get connectionState => states.stream;

  @override
  Future<ConnectionState> getConnectionState() async => states.value;

  @override
  Future<void> connect() async => states.add(ConnectionState.connected);

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    states.add(ConnectionState.disconnected);
  }

  @override
  Future<List<String>> discoverServices() async => services;

  @override
  Future<Uint8List> read(
    String serviceUUID,
    String characteristicUUID, {
    Duration? timeout,
  }) async => Uint8List(0);

  @override
  Future<void> subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  ) async {
    notification = callback;
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    writes.add(data.toList());
    if (emitWeightDuringInit && !_initWeightSent && data[2] == 0x0C) {
      _initWeightSent = true;
      scheduleMicrotask(() => emit(_weightFrame));
    }
    await writeBehavior?.call(data);
  }

  void emit(List<int> data) => notification!(Uint8List.fromList(data));

  @override
  Future<void> setTransportPriority(bool prioritized) async {}

  @override
  Future<void> dispose() async => states.close();
}

_AcaiaTransport _ips({bool emitWeightDuringInit = true}) => _AcaiaTransport(
  services: const ['00001820-0000-1000-8000-00805f9b34fb'],
  emitWeightDuringInit: emitWeightDuringInit,
);

Future<(AcaiaScale, _AcaiaTransport)> _connected() async {
  final transport = _ips();
  final scale = AcaiaScale(transport: transport);
  await scale.onConnect();
  return (scale, transport);
}

void main() {
  test('detects IPS and Pyxis services', () async {
    for (final services in [
      ['00001820-0000-1000-8000-00805f9b34fb'],
      ['49535343-fe7d-4ae5-8fa9-9fafd205e455'],
    ]) {
      final transport = _AcaiaTransport(services: services);
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();
      expect(await scale.connectionState.first, ConnectionState.connected);
      await scale.disconnect();
      await transport.dispose();
    }
  });

  test('rejects unsupported services', () async {
    final transport = _AcaiaTransport(
      services: const ['0000fff0-0000-1000-8000-00805f9b34fb'],
    );
    final scale = AcaiaScale(transport: transport);
    await scale.onConnect();
    expect(await scale.connectionState.first, ConnectionState.disconnected);
    await transport.dispose();
  });

  test(
    'timer event 11 emits no weight and weight selector emits 100g',
    () async {
      final (scale, transport) = await _connected();
      final snapshots = <ScaleSnapshot>[];
      final subscription = scale.currentSnapshot.listen(snapshots.add);

      transport.emit(const [
        0xEF,
        0xDD,
        0x0C,
        0x09,
        0x0B,
        0x00,
        0x00,
        0x07,
        0x12,
        0x34,
        0x56,
        0x78,
        0x9A,
        0xBC,
      ]);
      transport.emit(const [
        0xEF,
        0xDD,
        0x0C,
        0x09,
        0x0B,
        0x00,
        0x00,
        0x05,
        0xE8,
        0x03,
        0x00,
        0x00,
        0x01,
        0x00,
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(snapshots.map((snapshot) => snapshot.weight), [100.0]);
      await subscription.cancel();
      await scale.disconnect();
      await transport.dispose();
    },
  );

  test(
    'short and bogus frames cannot consume the following weight frame',
    () async {
      for (final prefix in [
        [0xEF, 0xDD, 0x0C, 0x02, 0x05, 0xAA, 0xBB],
        [0xEF, 0xDD, 0x0C, 0xFF, 0x05, 0x00],
      ]) {
        final (scale, transport) = await _connected();
        final snapshots = <ScaleSnapshot>[];
        final subscription = scale.currentSnapshot.listen(snapshots.add);

        transport.emit([...prefix, ..._weightFrame]);
        await Future<void>.delayed(Duration.zero);

        expect(snapshots.map((snapshot) => snapshot.weight), [100.0]);
        await subscription.cancel();
        await scale.disconnect();
        await transport.dispose();
      }
    },
  );

  test('concatenated settings and weight frames are both processed', () async {
    for (final frames in [
      [0xEF, 0xDD, 0x08, 0x03, 72, 0, 0, 0, ..._weightFrame],
      [..._weightFrame, 0xEF, 0xDD, 0x08, 0x03, 72, 0, 0, 0],
    ]) {
      final (scale, transport) = await _connected();
      final snapshots = <ScaleSnapshot>[];
      final subscription = scale.currentSnapshot.listen(snapshots.add);
      transport.emit(frames);
      transport.emit(_weightFrame);
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.last.batteryLevel, 72);
      await subscription.cancel();
      await scale.disconnect();
      await transport.dispose();
    }
  });

  test('split frames and split headers are retained', () async {
    for (final split in [1, 7]) {
      final (scale, transport) = await _connected();
      final snapshots = <ScaleSnapshot>[];
      final subscription = scale.currentSnapshot.listen(snapshots.add);
      transport.emit([0x99, ..._weightFrame.sublist(0, split)]);
      await Future<void>.delayed(Duration.zero);
      expect(snapshots, isEmpty);
      transport.emit(_weightFrame.sublist(split));
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.map((snapshot) => snapshot.weight), [100.0]);
      await subscription.cancel();
      await scale.disconnect();
      await transport.dispose();
    }
  });

  test('battery high bit is masked and invalid battery is retained', () async {
    final (scale, transport) = await _connected();
    var snapshot = scale.currentSnapshot.first;
    transport.emit(const [0xEF, 0xDD, 0x08, 0x03, 0xC8, 0, 0, 0]);
    transport.emit(_weightFrame);
    expect((await snapshot).batteryLevel, 72);

    snapshot = scale.currentSnapshot.first;
    transport.emit(const [0xEF, 0xDD, 0x08, 0x03, 0xE5, 0, 0, 0]);
    transport.emit(_weightFrame);
    expect((await snapshot).batteryLevel, 72);
    await scale.disconnect();
    await transport.dispose();
  });

  test('mute initialization never publishes connected', () {
    fakeAsync((async) {
      final transport = _ips(emitWeightDuringInit: false);
      final scale = AcaiaScale(transport: transport);
      final states = <ConnectionState>[];
      scale.connectionState.listen(states.add);
      scale.onConnect();
      async.flushMicrotasks();
      async.flushTimers();
      async.flushMicrotasks();
      expect(transport.writes, hasLength(20));
      expect(states, isNot(contains(ConnectionState.connected)));
      expect(states.last, ConnectionState.disconnected);
      expect(transport.disconnectCalls, 1);
      transport.dispose();
    });
  });

  test('event 5 and event 11 weight complete initialization', () {
    for (final frame in [
      _weightFrame,
      const [0xEF, 0xDD, 0x0C, 0x09, 0x0B, 0, 0, 0x05, 0xE8, 0x03, 0, 0, 1, 0],
    ]) {
      fakeAsync((async) {
        final transport = _ips(emitWeightDuringInit: false);
        transport.writeBehavior = (data) async {
          if (data[2] == 0x0C) scheduleMicrotask(() => transport.emit(frame));
        };
        final scale = AcaiaScale(transport: transport);
        scale.onConnect();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(scale.connectionState, emits(ConnectionState.connected));
        scale.disconnect();
        async.flushMicrotasks();
        transport.dispose();
      });
    }
  });

  test('maintenance is serialized and stops after disconnect', () {
    fakeAsync((async) {
      final transport = _ips();
      final scale = AcaiaScale(transport: transport);
      scale.onConnect();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      transport.writes.clear();
      final blocked = Completer<void>();
      transport.writeBehavior = (data) => blocked.future;

      async.elapse(const Duration(seconds: 12));
      async.flushMicrotasks();
      expect(transport.writes.where((write) => write[2] == 0), hasLength(1));

      scale.disconnect();
      async.flushMicrotasks();
      blocked.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();
      expect(transport.writes.where((write) => write[2] == 0), hasLength(1));
      transport.dispose();
    });
  });

  test(
    'maintenance errors do not escape and config is initialization-only',
    () {
      for (final error in <Object>[
        TimeoutException('timeout'),
        const DeviceNotConnectedException.scale(),
        StateError('transport'),
      ]) {
        fakeAsync((async) {
          final uncaught = <Object>[];
          runZonedGuarded(() {
            final transport = _ips();
            final scale = AcaiaScale(transport: transport);
            scale.onConnect();
            async.elapse(const Duration(seconds: 1));
            async.flushMicrotasks();
            final configCount = transport.writes
                .where((write) => write[2] == 0x0C)
                .length;
            transport.writeBehavior = (data) async {
              if (data[2] == 0) throw error;
            };
            async.elapse(const Duration(seconds: 3));
            async.flushMicrotasks();
            expect(
              transport.writes.where((write) => write[2] == 0x0C),
              hasLength(configCount),
            );
            scale.disconnect();
            async.flushMicrotasks();
            transport.dispose();
          }, (error, stack) => uncaught.add(error));
          expect(uncaught, isEmpty);
        });
      }
    },
  );

  test('tare sends the command three times', () async {
    final (scale, transport) = await _connected();
    transport.writes.clear();
    await scale.tare();
    expect(transport.writes.where((write) => write[2] == 0x04), hasLength(3));
    await scale.disconnect();
    await transport.dispose();
  });
}
