import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/bookoo/miniscale.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

class _BookooTransport extends BLETransport {
  final BehaviorSubject<ConnectionState> states = BehaviorSubject.seeded(
    ConnectionState.discovered,
  );
  final List<List<int>> writes = [];
  void Function(Uint8List)? notification;

  @override
  String get id => 'bookoo-test';

  @override
  String get name => 'BOOKOO';

  @override
  Stream<ConnectionState> get connectionState => states.stream;

  @override
  Future<ConnectionState> getConnectionState() async => states.value;

  @override
  Future<void> connect() async => states.add(ConnectionState.connected);

  @override
  Future<void> disconnect() async => states.add(ConnectionState.disconnected);

  @override
  Future<List<String>> discoverServices() async => [
    BookooScale.serviceIdentifier.long,
  ];

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
  }

  void emit(List<int> data) => notification!(Uint8List.fromList(data));

  @override
  Future<void> setTransportPriority(bool prioritized) async {}

  @override
  Future<void> dispose() async => states.close();
}

List<int> _packet(double grams, {int? battery = 50, int length = 20}) {
  final magnitude = (grams.abs() * 100).round();
  final packet = List<int>.filled(length, 0);
  if (length > 0) packet[0] = 0x03;
  if (length > 1) packet[1] = 0x0B;
  if (length > 6) packet[6] = grams < 0 ? 0x2D : 0x2B;
  if (length > 7) packet[7] = magnitude >> 16;
  if (length > 8) packet[8] = magnitude >> 8;
  if (length > 9) packet[9] = magnitude;
  if (length > 13 && battery != null) packet[13] = battery;
  return packet;
}

void main() {
  late _BookooTransport transport;
  late BookooScale scale;
  late List<ScaleSnapshot> snapshots;

  setUp(() async {
    transport = _BookooTransport();
    scale = BookooScale(transport: transport);
    snapshots = [];
    await scale.onConnect();
    scale.currentSnapshot.listen(snapshots.add);
  });

  tearDown(() async {
    await scale.disconnect();
    await transport.dispose();
  });

  test('decodes positive and negative three-byte weights', () async {
    transport.emit(_packet(123.45));
    transport.emit(_packet(-12.34));
    await Future<void>.delayed(Duration.zero);
    expect(snapshots.map((snapshot) => snapshot.weight), [123.45, -12.34]);
  });

  test('ten-byte packet emits weight without reading battery', () async {
    transport.emit(_packet(10, length: 10));
    await Future<void>.delayed(Duration.zero);
    expect(snapshots.single.weight, 10);
    expect(snapshots.single.batteryLevel, 0);
  });

  test('short malformed and unrelated packets emit nothing', () async {
    for (final packet in [
      _packet(10, length: 9),
      [0x04, ..._packet(10).sublist(1)],
      [0x03, 0x0A, ..._packet(10).sublist(2)],
      <int>[],
    ]) {
      expect(() => transport.emit(packet), returnsNormally);
    }
    await Future<void>.delayed(Duration.zero);
    expect(snapshots, isEmpty);
  });

  test('invalid battery retains the previous valid level', () async {
    transport.emit(_packet(1, battery: 72));
    transport.emit(_packet(2, battery: 101));
    await Future<void>.delayed(Duration.zero);
    expect(snapshots.map((snapshot) => snapshot.batteryLevel), [72, 72]);
  });

  test('commands remain protocol-compatible', () async {
    await scale.tare();
    await scale.startTimer();
    await scale.stopTimer();
    await scale.resetTimer();
    expect(transport.writes, [
      [0x03, 0x0A, 0x01, 0, 0, 0x08],
      [0x03, 0x0A, 0x04, 0, 0, 0x0A],
      [0x03, 0x0A, 0x05, 0, 0, 0x0D],
      [0x03, 0x0A, 0x06, 0, 0, 0x0C],
    ]);
  });
}
