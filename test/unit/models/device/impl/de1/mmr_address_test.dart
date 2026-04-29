import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/mmr_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MmrAddress', () {
    test('every MMRItem implements MmrAddress with a kind', () {
      for (final m in MMRItem.values) {
        expect(m, isA<MmrAddress>(), reason: m.name);
        expect(m.address, greaterThanOrEqualTo(0));
        expect(m.length, greaterThan(0));
        expect(m.kind, isNotNull, reason: '${m.name} kind');
      }
    });

    test('scaled MMRItems have kind == scaledFloat', () {
      expect(MMRItem.flushFlowRate.kind, MmrValueKind.scaledFloat);
      expect(MMRItem.targetSteamFlow.kind, MmrValueKind.scaledFloat);
      expect(MMRItem.calFlowEst.kind, MmrValueKind.scaledFloat);
    });

    test('unscaled int MMRItems have kind == int32', () {
      expect(MMRItem.fanThreshold.kind, MmrValueKind.int32);
      expect(MMRItem.tankTemp.kind, MmrValueKind.int32);
    });

    test('boolean MMRItems have kind == boolean', () {
      expect(MMRItem.allowUSBCharging.kind, MmrValueKind.boolean);
    });
  });
}
