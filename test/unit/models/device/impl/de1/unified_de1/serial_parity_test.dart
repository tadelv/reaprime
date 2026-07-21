import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart';
import 'package:reaprime/src/models/device/transport/serial_port.dart';
import 'package:rxdart/rxdart.dart';

import '../../../../../../helpers/fake_ble_transport.dart';

class _RecordingSerialTransport extends SerialTransport {
  final _connectionState = BehaviorSubject<ConnectionState>.seeded(
    ConnectionState.connected,
  );
  final writes = <String>[];

  @override
  String get id => 'serial-test';

  @override
  String get name => 'Serial test';

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Stream<String> get readStream => const Stream.empty();

  @override
  Stream<Uint8List> get rawStream => const Stream.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() => _connectionState.close();

  @override
  Future<void> writeCommand(String command) async => writes.add(command);

  @override
  Future<void> writeHexCommand(Uint8List command) async {}
}

void main() {
  late _RecordingSerialTransport serial;
  late UnifiedDe1Transport transport;

  setUp(() {
    serial = _RecordingSerialTransport();
    transport = UnifiedDe1Transport(transport: serial);
  });

  tearDown(() => transport.dispose());

  test('serial writeToMMR frames are exactly 20 bytes', () async {
    for (final length in [1, 19, 20]) {
      final input = Uint8List.fromList(List.generate(length, (i) => i + 1));
      final original = Uint8List.fromList(input);

      await transport.write(Endpoint.writeToMMR, input);

      final payload = serial.writes.removeAt(0).substring(3);
      expect(payload.length, 40);
      expect(
        payload.substring(0, length * 2),
        original.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      );
      expect(
        payload.substring(length * 2),
        List.filled((20 - length) * 2, '0').join(),
      );
      expect(input, original);
    }
  });

  test('serial writeToMMR rejects frames longer than 20 bytes', () async {
    await expectLater(
      transport.write(Endpoint.writeToMMR, Uint8List(21)),
      throwsArgumentError,
    );
    expect(serial.writes, isEmpty);
  });

  test('serial non-writeToMMR frames remain unchanged', () async {
    await transport.write(Endpoint.headerWrite, Uint8List.fromList([1]));

    expect(serial.writes, ['<O>01']);
  });

  test('BLE writeToMMR frames remain unchanged', () async {
    final ble = FakeBleTransport();
    final bleTransport = UnifiedDe1Transport(transport: ble);
    addTearDown(bleTransport.dispose);

    await bleTransport.write(Endpoint.writeToMMR, Uint8List.fromList([1]));

    expect(ble.writes.single.data, [1]);
  });
}
