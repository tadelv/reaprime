import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart';

import '../../../../../../helpers/fake_serial_transport.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Golden 0xA013 frame: weight 36.5 g (see `bengle_shot_sample_test.dart`).
const List<int> _golden0xA013 = [
  0x03, 0xE8, 0x03, 0x84, 0x02, 0x58, 0x00, 0xFA, 0x00, 0xC8, 0x00, 0xB4, //
  0x24, 0x22, 0x22, 0x60, 0x24, 0x54, 0x23, 0x28, 0x04, 0x90, 0x07, 0x34, //
  0xBC, 0x00, 0x00, 0x00,
];

void main() {
  group('0xA013 serial dispatch', () {
    late FakeSerialTransport serial;
    late UnifiedDe1Transport transport;

    setUp(() {
      serial = FakeSerialTransport();
      transport = UnifiedDe1Transport(transport: serial);
    });

    tearDown(() => transport.dispose());

    test('connect() enables the 0xA013 stream with <+S>', () async {
      await transport.connect();
      expect(
        serial.writes,
        contains('<+${Endpoint.bengleShotSample.representation}>'),
      );
    });

    test(
      'an inbound [S] frame routes to the bengleShotSample subject',
      () async {
        await transport.connect();

        final frames = <ByteData>[];
        final sub = transport.bengleShotSample.listen(frames.add);
        await pumpEventQueue();
        final baseline = frames.length; // seeded 28-zero frame

        serial.injectSerial('[S]${_hex(_golden0xA013)}\n');
        await pumpEventQueue();

        expect(
          frames.length,
          baseline + 1,
          reason: '[S] must route to _bengleShotSampleNotification',
        );
        final frame = frames.last;
        expect(frame.lengthInBytes, 28);
        // Weight is offset 20, U16P5 (big-endian ÷32).
        expect(frame.getUint16(20, Endian.big) / 32.0, closeTo(36.5, 1e-9));

        await sub.cancel();
      },
    );

    test('a truncated [S] frame is dropped, not routed', () async {
      await transport.connect();

      final frames = <ByteData>[];
      final sub = transport.bengleShotSample.listen(frames.add);
      await pumpEventQueue();
      final baseline = frames.length;

      // 20 bytes (40 hex chars) < 28 — must be dropped.
      serial.injectSerial('[S]${_hex(List<int>.filled(20, 0))}\n');
      await pumpEventQueue();

      expect(frames.length, baseline, reason: 'short [S] frame dropped');

      await sub.cancel();
    });

    test('disconnect() unsubscribes the 0xA013 stream with <-S>', () async {
      await transport.connect();
      serial.writes.clear();
      await transport.disconnect();
      expect(
        serial.writes,
        contains('<-${Endpoint.bengleShotSample.representation}>'),
      );
    });
  });
}
