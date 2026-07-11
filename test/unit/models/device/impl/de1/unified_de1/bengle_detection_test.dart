import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

import '../../../../../../helpers/fake_ble_transport.dart';

/// The authoritative Bengle gate is `v13Model >= 128` read on connect, NOT
/// the BLE advertised name. `DeviceMatcher` stays name-based (that selection
/// is covered by `device_matcher_test.dart`); this proves the runtime
/// capability flag `UnifiedDe1.isBengle` tracks the model the firmware
/// reports over the wire, independent of which class the name happened to
/// pick.
void main() {
  group('UnifiedDe1 Bengle detection', () {
    late FakeBleTransport transport;

    setUp(() {
      transport = FakeBleTransport();
      // `queueOnConnectResponses` doesn't cover `calFlowEst` (the flow-cal
      // warm-up read at the tail of onConnect); queue it so onConnect
      // returns immediately instead of eating the MMR read-retry timeout.
      transport.queueMmrResponseInt(MMRItem.calFlowEst, 100);
    });

    tearDown(() => transport.dispose());

    test('isBengle is false before onConnect has read the model', () {
      final de1 = UnifiedDe1(transport: transport);
      expect(de1.isBengle, isFalse);
    });

    test('v13Model >= 128 gates Bengle on a plain UnifiedDe1', () async {
      final de1 = UnifiedDe1(transport: transport);
      transport.queueOnConnectResponses(v13Model: 128);
      await de1.onConnect();
      expect(de1.isBengle, isTrue);
    });

    test('the boundary value 128 gates Bengle', () async {
      final de1 = UnifiedDe1(transport: transport);
      transport.queueOnConnectResponses(v13Model: 128);
      await de1.onConnect();
      expect(de1.isBengle, isTrue);
    });

    test('v13Model == 1 leaves a plain UnifiedDe1 as DE1', () async {
      final de1 = UnifiedDe1(transport: transport);
      transport.queueOnConnectResponses(v13Model: 1);
      await de1.onConnect();
      expect(de1.isBengle, isFalse);
    });

    test(
      'a name-picked Bengle reading model 128 is authoritatively Bengle',
      () async {
        final bengle = Bengle(transport: transport);
        transport.queueOnConnectResponses(v13Model: 128);
        await bengle.onConnect();
        expect(bengle.isBengle, isTrue);
      },
    );

    test(
      'self-verify: a name-picked Bengle reading a DE1 model is NOT Bengle',
      () async {
        // The incremental self-verify seam: the flag follows the wire, so a
        // mis-named device that reports a DE1-family model (1..7) is flagged
        // DE1 even though its advertised name matched "Bengle".
        final bengle = Bengle(transport: transport);
        transport.queueOnConnectResponses(v13Model: 1);
        await bengle.onConnect();
        expect(bengle.isBengle, isFalse);
      },
    );
  });
}
