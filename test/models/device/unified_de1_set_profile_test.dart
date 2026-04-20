import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/transport/serial_port.dart';
import 'package:rxdart/rxdart.dart';

/// Regression coverage for comms-harden #1 — `setProfile` equality guard.
///
/// The guard short-circuits when `_currentProfile == profile`. Before the
/// fix, `_currentProfile` was assigned **before** `_sendProfile` was
/// awaited, so a mid-upload throw (e.g. a BLE timeout after the header
/// frame but before the tail) poisoned the cache: a retry with the same
/// profile hit the guard and silently no-op'd, leaving the DE1 running
/// on a half-loaded profile with the caller seeing success.
///
/// After the fix, `_currentProfile` is assigned only after `_sendProfile`
/// completes successfully, so a retry with the same profile after a
/// failed upload proceeds with a fresh upload.
///
/// Option C verification: integration test over a real `UnifiedDe1` with
/// a recording `SerialTransport`. Counts `writeCommand` invocations as a
/// proxy for "upload happened".
///
/// See: doc/plans/comms-harden.md #1, doc/plans/comms-phase-0-1.md PR 2.
class _RecordingSerialTransport extends SerialTransport {
  final _connState =
      BehaviorSubject<ConnectionState>.seeded(ConnectionState.connected);
  final List<String> writes = [];

  /// If set, the call whose zero-based index matches this value throws
  /// once, then clears itself.
  int? failIndexOnce;

  @override
  String get id => 'test-serial-de1';

  @override
  String get name => 'TestSerialDe1';

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
  Future<void> writeCommand(String command) async {
    final index = writes.length;
    writes.add(command);
    if (failIndexOnce != null && failIndexOnce == index) {
      failIndexOnce = null;
      throw Exception('simulated transport failure at index $index');
    }
  }

  void dispose() {
    _connState.close();
  }
}

void main() {
  group('setProfile retry semantics (comms-harden #1)', () {
    late _RecordingSerialTransport transport;
    late UnifiedDe1 de1;

    const profile = Profile(
      version: '2',
      title: 'Phase 1 Test Profile',
      notes: '',
      author: 'test',
      beverageType: BeverageType.espresso,
      steps: [],
      targetVolumeCountStart: 0,
      tankTemperature: 0,
    );

    setUp(() {
      transport = _RecordingSerialTransport();
      de1 = UnifiedDe1(transport: transport);
    });

    tearDown(() {
      transport.dispose();
    });

    test(
        'retry with the same profile after a failed upload triggers a fresh send',
        () async {
      // Fail the very first write (the header).
      transport.failIndexOnce = 0;
      await expectLater(
        () => de1.setProfile(profile),
        throwsA(isA<Exception>()),
      );
      final writesAfterFailure = transport.writes.length;
      expect(writesAfterFailure, 1,
          reason: 'only the header write reached the transport before the throw');

      // Retry with the same profile. On the pre-fix code this is a silent
      // no-op; on the fixed code it re-runs the full send.
      await de1.setProfile(profile);

      expect(transport.writes.length, greaterThan(writesAfterFailure),
          reason: 'retry must re-upload after a prior failed attempt');
    });

    test('repeated call after a successful upload is a no-op', () async {
      await de1.setProfile(profile);
      final writesAfterSuccess = transport.writes.length;
      expect(writesAfterSuccess, greaterThan(0));

      await de1.setProfile(profile);
      expect(transport.writes.length, writesAfterSuccess,
          reason: 'identical upload on successful cache must short-circuit');
    });

    test('different profile always uploads', () async {
      await de1.setProfile(profile);
      final writesAfterFirst = transport.writes.length;

      final other = profile.copyWith(title: 'Different Profile');
      await de1.setProfile(other);

      expect(transport.writes.length, greaterThan(writesAfterFirst),
          reason: 'different profile must upload even after a prior success');
    });
  });
}
