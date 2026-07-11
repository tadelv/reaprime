import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart';

import '../../../../../../helpers/fake_serial_transport.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A [FakeSerialTransport] whose [writeCommand] throws for one specific
/// command — used to prove a failing `<+X>` request can't leak an
/// unhandled async timeout out of the armed one-shot read future.
class _FailingWriteSerialTransport extends FakeSerialTransport {
  final String failOn;
  _FailingWriteSerialTransport({required this.failOn});

  @override
  Future<void> writeCommand(String command) async {
    if (command == failOn) {
      throw StateError('injected write failure: $command');
    }
    return super.writeCommand(command);
  }
}

void main() {
  group('length-exact <F> (writeToMMR) frames on serial', () {
    late FakeSerialTransport serial;
    late UnifiedDe1Transport transport;

    setUp(() {
      serial = FakeSerialTransport();
      transport = UnifiedDe1Transport(transport: serial);
    });

    tearDown(() => transport.dispose());

    test('a short final DFU chunk is zero-padded to 20 bytes', () async {
      await transport.connect();
      serial.writes.clear();

      // 6-byte final image chunk: Len=6, addr 0x000120, 6 data bytes —
      // exactly what uploadFW emits for a trailing partial chunk.
      final chunk = Uint8List.fromList([
        6,
        0x00,
        0x01,
        0x20,
        0xDE,
        0xAD,
        0xBE,
        0xEF,
        0x01,
        0x02,
      ]);
      await transport.writeWithResponse(Endpoint.writeToMMR, chunk);

      final expected = '<F>${_hex(chunk).padRight(2 * 20, '0')}'; // 40 hex
      expect(
        serial.writes.single,
        expected,
        reason:
            'firmware parser reads exactly sizeof(the MMR write frame)=20 '
            'bytes per <F> frame; a short frame desyncs it',
      );
    });

    test('a full 20-byte frame is passed through unmodified', () async {
      await transport.connect();
      serial.writes.clear();

      final chunk = Uint8List.fromList(List<int>.generate(20, (i) => i + 1));
      await transport.writeWithResponse(Endpoint.writeToMMR, chunk);

      expect(serial.writes.single, '<F>${_hex(chunk)}');
    });

    test('other endpoints are not padded', () async {
      await transport.connect();
      serial.writes.clear();

      final settings = Uint8List.fromList(List<int>.filled(9, 0x42));
      await transport.writeWithResponse(Endpoint.shotSettings, settings);

      expect(serial.writes.single, '<K>${_hex(settings)}');
    });
  });

  group('serial reads', () {
    late FakeSerialTransport serial;
    late UnifiedDe1Transport transport;

    setUp(() {
      serial = FakeSerialTransport();
      transport = UnifiedDe1Transport(transport: serial);
    });

    tearDown(() => transport.dispose());

    test('read(calibration) is a <+R> single-notify round trip', () async {
      await transport.connect();
      serial.writes.clear();

      final pending = transport.read(Endpoint.calibration);
      await pumpEventQueue();
      expect(
        serial.writes,
        contains('<+R>'),
        reason:
            'the serial view has no read verb; a read is an '
            'add-notify that provokes one [R] frame',
      );

      final payload = List<int>.generate(14, (i) => 0xA0 + i);
      serial.injectSerial('[R]${_hex(payload)}\n');

      final result = await pending;
      expect(result.buffer.asUint8List(), payload);
      expect(
        serial.writes.last,
        '<-R>',
        reason: 'the one-shot read must not leave a subscription behind',
      );
    });

    test('read(versions) round-trips via <+A>', () async {
      await transport.connect();
      serial.writes.clear();

      final pending = transport.read(Endpoint.versions);
      await pumpEventQueue();
      expect(serial.writes, contains('<+A>'));

      final payload = List<int>.generate(18, (i) => i);
      serial.injectSerial('[A]${_hex(payload)}\n');

      final result = await pending;
      expect(result.buffer.asUint8List(), payload);
      expect(serial.writes.last, '<-A>');
    });

    test('read(temperatures) round-trips via <+J>', () async {
      await transport.connect();
      serial.writes.clear();

      final pending = transport.read(Endpoint.temperatures);
      await pumpEventQueue();
      expect(serial.writes, contains('<+J>'));

      final payload = List<int>.generate(20, (i) => 0x10 + i);
      serial.injectSerial('[J]${_hex(payload)}\n');

      final result = await pending;
      expect(result.buffer.asUint8List(), payload);
      expect(serial.writes.last, '<-J>');
    });

    test(
      'a single-notify read times out cleanly when firmware never answers',
      () async {
        // Real (shortened) time: fakeAsync stalls on the root-zone
        // `_nullFuture` returned by broadcast-subscription cancels inside
        // `Stream.first`, so the timeout is injected small instead.
        final serial2 = FakeSerialTransport();
        final transport2 = UnifiedDe1Transport(
          transport: serial2,
          serialSingleReadTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(transport2.dispose);
        await transport2.connect();

        await expectLater(
          transport2.read(Endpoint.versions),
          throwsA(isA<TimeoutException>()),
          reason: 'firmware that never emits [A] must not hang the caller',
        );
        expect(
          serial2.writes,
          contains('<-A>'),
          reason: 'the failed read still cleans up its notify',
        );
      },
    );

    test(
      'a failing <+X> request write does not leak an unhandled timeout',
      () async {
        // Locks the `response.ignore()` line in _serialSingleNotifyRead:
        // when the `<+A>` write throws, nothing ever awaits the armed
        // `frames.first.timeout(...)` future — without ignore() its
        // eventual TimeoutException surfaces as an unhandled async error
        // and fails this test when it fires below.
        final serial2 = _FailingWriteSerialTransport(failOn: '<+A>');
        final transport2 = UnifiedDe1Transport(
          transport: serial2,
          serialSingleReadTimeout: const Duration(milliseconds: 40),
        );
        addTearDown(transport2.dispose);
        await transport2.connect();

        await expectLater(
          transport2.read(Endpoint.versions),
          throwsA(isA<StateError>()),
          reason: 'the write failure itself must surface to the caller',
        );
        expect(
          serial2.writes,
          contains('<-A>'),
          reason: 'the failed read still cleans up its notify (finally)',
        );

        // Let the armed timeout fire inside the test body; an unhandled
        // async TimeoutException here fails the test.
        await Future<void>.delayed(const Duration(milliseconds: 120));
      },
    );

    test(
      'endpoints with no serial read path throw UnsupportedError',
      () async {
        await transport.connect();

        for (final e in [
          Endpoint.setTime,
          Endpoint.shotDirectory,
          Endpoint.writeToMMR,
          Endpoint.shotMapRequest,
          Endpoint.deleteShotRange,
          Endpoint.deprecatedShotDesc,
          Endpoint.headerWrite,
          Endpoint.frameWrite,
        ]) {
          await expectLater(
            transport.read(e),
            throwsA(isA<UnsupportedError>()),
            reason: '${e.name} is write-only / never emitted by the firmware',
          );
        }
      },
    );

    test(
      'read(requestedState) serves the stateInfo subject ([N] carries state)',
      () async {
        // There is no [B] notify on the wire; requestedState deliberately
        // aliases the stateInfo subject over serial. Pinned here so a
        // future refactor can't silently break the raw-API read.
        await transport.connect();
        serial.injectSerial('[N]0402\n');
        await pumpEventQueue();

        final viaRequestedState = await transport.read(
          Endpoint.requestedState,
        );
        final viaStateInfo = await transport.read(Endpoint.stateInfo);
        expect(
          viaRequestedState.buffer.asUint8List(),
          viaStateInfo.buffer.asUint8List(),
        );
        expect(viaRequestedState.buffer.asUint8List(), [0x04, 0x02]);
      },
    );
  });

  group('serial RX framing — parser edge cases', () {
    late FakeSerialTransport serial;
    late UnifiedDe1Transport transport;

    setUp(() {
      serial = FakeSerialTransport();
      transport = UnifiedDe1Transport(transport: serial);
    });

    tearDown(() => transport.dispose());

    test('a frame split across chunks reassembles', () async {
      await transport.connect();

      // [E] reply split mid-payload: first chunk has no terminator so it
      // must stay buffered, not be dropped.
      serial.injectSerial('[E]0480');
      await pumpEventQueue();
      serial.injectSerial('000c80000000\n');
      await pumpEventQueue();

      final mmr = await transport.read(Endpoint.readFromMMR);
      expect(mmr.buffer.asUint8List(), [
        0x04,
        0x80,
        0x00,
        0x0C,
        0x80,
        0x00,
        0x00,
        0x00,
      ]);
    });

    test('leading junk before the first [ is discarded', () async {
      await transport.connect();

      serial.injectSerial('OK\r\nboot junk[N]0403\n');
      await pumpEventQueue();

      final state = await transport.read(Endpoint.stateInfo);
      expect(state.buffer.asUint8List(), [0x04, 0x03]);
    });

    test(
      'a >4096-char unterminated buffer is dumped and parsing resyncs',
      () async {
        await transport.connect();

        // A '[M]' start with no terminator ever: grows past the 4096 guard
        // and must be discarded (no checksum/retransmit on this framing —
        // the keepalive's forced [N] resyncs the stream afterwards).
        serial.injectSerial('[M]${'00' * 2500}');
        await pumpEventQueue();

        // The stream recovers: the next complete frame parses normally.
        serial.injectSerial('[N]0405\n');
        await pumpEventQueue();

        final state = await transport.read(Endpoint.stateInfo);
        expect(state.buffer.asUint8List(), [0x04, 0x05]);

        // The dumped garbage never surfaced as a shotSample frame.
        final shot = await transport.read(Endpoint.shotSample);
        expect(
          shot.buffer.asUint8List(),
          List<int>.filled(19, 0),
          reason: 'the overflowed [M] bufferful must be dropped, not parsed',
        );
      },
    );
  });

  group('serial keepalive (actively drive the shared link)', () {
    // Real (shortened) time via the injectable interval: fakeAsync stalls
    // on the root-zone `_nullFuture` that broadcast-subscription cancels
    // return inside disconnect()/dispose().
    const interval = Duration(milliseconds: 40);
    const threePeriods = Duration(milliseconds: 140);

    test('re-asserts the link with <+N> every keepalive period', () async {
      final serial = FakeSerialTransport();
      final transport = UnifiedDe1Transport(
        transport: serial,
        serialKeepaliveInterval: interval,
      );
      addTearDown(transport.dispose);
      await transport.connect();
      serial.writes.clear();

      await Future<void>.delayed(threePeriods);
      expect(
        serial.writes.where((w) => w == '<+N>').length,
        greaterThanOrEqualTo(2),
        reason:
            'a passively-listening USB client silently loses the '
            'notify stream to the BLE source arbitration — the keepalive '
            'must re-assert periodically, not once',
      );
    });

    test('disconnect() stops the keepalive', () async {
      final serial = FakeSerialTransport();
      final transport = UnifiedDe1Transport(
        transport: serial,
        serialKeepaliveInterval: interval,
      );
      addTearDown(transport.dispose);
      await transport.connect();

      await transport.disconnect();
      serial.writes.clear();

      await Future<void>.delayed(threePeriods);
      expect(serial.writes.where((w) => w == '<+N>'), isEmpty);
    });

    test('dispose() stops the keepalive', () async {
      final serial = FakeSerialTransport();
      final transport = UnifiedDe1Transport(
        transport: serial,
        serialKeepaliveInterval: interval,
      );
      await transport.connect();

      await transport.dispose();
      serial.writes.clear();

      await Future<void>.delayed(threePeriods);
      expect(serial.writes.where((w) => w == '<+N>'), isEmpty);
    });

    test('detach() stops the keepalive (re-resolution seam)', () async {
      // A demoted/promoted machine hands its live transport to the
      // replacement wrapper; the discarded wrapper's keepalive must not
      // keep writing on the shared port.
      final serial = FakeSerialTransport();
      final transport = UnifiedDe1Transport(
        transport: serial,
        serialKeepaliveInterval: interval,
      );
      await transport.connect();

      await transport.detach();
      serial.writes.clear();

      await Future<void>.delayed(threePeriods);
      expect(serial.writes.where((w) => w == '<+N>'), isEmpty);
    });
  });
}
