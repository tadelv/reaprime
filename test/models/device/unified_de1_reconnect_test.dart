import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/transport/serial_port.dart';
import 'package:rxdart/rxdart.dart';

/// Regression coverage for comms-harden #3 — `UnifiedDe1.initRawStream`
/// must be idempotent across reconnects.
///
/// Before the fix, `_rawInputController` was a single-subscription
/// `StreamController` and `initRawStream()` called `.listen(...)` once
/// per `onConnect()`. The second reconnect against the same `UnifiedDe1`
/// instance threw `Bad state: Stream has already been listened to.`,
/// wedging the machine at `disconnected` for the rest of the app session.
///
/// Confirmed on real hardware during the Phase 1 smoke test
/// (see doc/plans/comms-harden.md and the Phase 1 smoke report).
///
/// After the fix, `initRawStream()` is guarded with a one-shot flag so
/// the listener is attached only once regardless of how many reconnects
/// cycle through the same instance.

class _QuietSerialTransport extends SerialTransport {
  final _connState =
      BehaviorSubject<ConnectionState>.seeded(ConnectionState.connected);

  @override
  String get id => 'reconnect-test-de1';

  @override
  String get name => 'ReconnectTestDe1';

  @override
  Stream<ConnectionState> get connectionState => _connState.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<String> get readStream => const Stream.empty();

  @override
  Stream<Uint8List> get rawStream => const Stream.empty();

  @override
  Future<void> writeHexCommand(Uint8List command) async {}

  @override
  Future<void> writeCommand(String command) async {}

  void dispose() {
    _connState.close();
  }
}

void main() {
  group('UnifiedDe1 reconnect (comms-harden #3)', () {
    test(
        'initRawStream is idempotent — calling it twice does not throw',
        () {
      final transport = _QuietSerialTransport();
      final de1 = UnifiedDe1(transport: transport);

      expect(() => de1.initRawStream(), returnsNormally);
      expect(
        () => de1.initRawStream(),
        returnsNormally,
        reason:
            'second call simulates a reconnect; must not throw '
            '"Bad state: Stream has already been listened to."',
      );

      transport.dispose();
    });
  });
}
