import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:rxdart/rxdart.dart';

/// Minimal BLE transport whose initial connection state is controllable, so
/// we can drive `UnifiedDe1Transport.connect()` down the first-connect path
/// (transport disconnected) vs. the no-op-reconnect path (already connected).
class _Fake extends BLETransport {
  _Fake(ConnectionState initial)
      : _connState = BehaviorSubject<ConnectionState>.seeded(initial);

  final BehaviorSubject<ConnectionState> _connState;

  @override
  String get id => 'fake-id';
  @override
  String get name => 'Fake';
  @override
  Stream<ConnectionState> get connectionState => _connState.stream;
  @override
  Future<void> connect() async => _connState.add(ConnectionState.connected);
  @override
  Future<void> disconnect() async =>
      _connState.add(ConnectionState.disconnected);
  @override
  Future<List<String>> discoverServices() async => [de1ServiceUUID];
  @override
  Future<Uint8List> read(String s, String c, {Duration? timeout}) async =>
      Uint8List(20);
  @override
  Future<void> subscribe(
      String s, String c, void Function(Uint8List) cb) async {}
  @override
  Future<void> setTransportPriority(bool prioritized) async {}
  @override
  Future<void> write(String s, String c, Uint8List data,
      {bool withResponse = true, Duration? timeout}) async {}
}

void main() {
  late StreamSubscription<LogRecord> logSub;
  late List<LogRecord> records;

  setUp(() {
    Logger.root.level = Level.ALL;
    records = [];
    logSub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    await logSub.cancel();
  });

  test('records DuplicateBleSubscription when connect runs on an '
      'already-connected transport', () async {
    final transport = UnifiedDe1Transport(transport: _Fake(
      ConnectionState.connected,
    ));

    await transport.connect();

    final hits =
        records.where((r) => r.error is DuplicateBleSubscription).toList();
    expect(hits.length, 1,
        reason: 'no-op reconnect should record exactly one non-fatal');

    // Privacy: the recorded error is forwarded to Crashlytics unscrubbed, so
    // it must carry an anonymized id, never the raw device id / MAC.
    final err = hits.single.error as DuplicateBleSubscription;
    expect(err.anonymizedDeviceId, startsWith('mac_'));
    expect(err.toString(), isNot(contains('fake-id')));
  });

  test('does not record on a first connect (transport disconnected)',
      () async {
    final transport = UnifiedDe1Transport(transport: _Fake(
      ConnectionState.disconnected,
    ));

    await transport.connect();

    expect(
      records.any((r) => r.error is DuplicateBleSubscription),
      isFalse,
    );
  });
}
