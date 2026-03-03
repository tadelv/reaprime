import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/workflow_context.dart';

void main() {
  group('WorkflowContext', () {
    test('round-trip serialization with all fields', () {
      final ctx = WorkflowContext(
        targetDoseWeight: 18.0,
        targetYield: 36.0,
        grinderId: 'grinder-123',
        grinderModel: 'Niche Zero',
        grinderSetting: '15',
        beanBatchId: 'batch-456',
        coffeeName: 'Gesha Village',
        coffeeRoaster: 'Sey',
        finalBeverageType: 'espresso',
        baristaName: 'Alice',
        drinkerName: 'Bob',
        extras: {'plugin1': {'key': 'value'}},
      );

      final json = ctx.toJson();
      final restored = WorkflowContext.fromJson(json);

      expect(restored.targetDoseWeight, 18.0);
      expect(restored.targetYield, 36.0);
      expect(restored.grinderId, 'grinder-123');
      expect(restored.grinderModel, 'Niche Zero');
      expect(restored.grinderSetting, '15');
      expect(restored.beanBatchId, 'batch-456');
      expect(restored.coffeeName, 'Gesha Village');
      expect(restored.coffeeRoaster, 'Sey');
      expect(restored.finalBeverageType, 'espresso');
      expect(restored.baristaName, 'Alice');
      expect(restored.drinkerName, 'Bob');
      expect(restored.extras, {'plugin1': {'key': 'value'}});
    });

    test('round-trip with minimal fields (nulls omitted from JSON)', () {
      final ctx = WorkflowContext(
        targetDoseWeight: 18.0,
        targetYield: 36.0,
      );

      final json = ctx.toJson();
      expect(json.containsKey('grinderId'), false);
      expect(json.containsKey('extras'), false);

      final restored = WorkflowContext.fromJson(json);
      expect(restored.targetDoseWeight, 18.0);
      expect(restored.targetYield, 36.0);
      expect(restored.grinderId, isNull);
      expect(restored.coffeeName, isNull);
    });

    test('fromLegacyJson maps DoseData/GrinderData/CoffeeData', () {
      final legacyWorkflowJson = {
        'doseData': {'doseIn': 18.0, 'doseOut': 36.0},
        'grinderData': {
          'setting': '15',
          'manufacturer': 'Niche',
          'model': 'Zero',
        },
        'coffeeData': {
          'name': 'Gesha Village',
          'roaster': 'Sey',
        },
      };

      final ctx = WorkflowContext.fromLegacyJson(legacyWorkflowJson);

      expect(ctx.targetDoseWeight, 18.0);
      expect(ctx.targetYield, 36.0);
      expect(ctx.grinderSetting, '15');
      expect(ctx.grinderModel, 'Zero');
      expect(ctx.coffeeName, 'Gesha Village');
      expect(ctx.coffeeRoaster, 'Sey');
    });

    test('fromLegacyJson handles missing optional groups', () {
      final legacyJson = {
        'doseData': {'doseIn': 16, 'doseOut': 32},
      };

      final ctx = WorkflowContext.fromLegacyJson(legacyJson);

      expect(ctx.targetDoseWeight, 16.0);
      expect(ctx.targetYield, 32.0);
      expect(ctx.grinderSetting, isNull);
      expect(ctx.coffeeName, isNull);
    });

    test('fromLegacyJson handles int dose values', () {
      final legacyJson = {
        'doseData': {'doseIn': 18, 'doseOut': 36},
      };

      final ctx = WorkflowContext.fromLegacyJson(legacyJson);
      expect(ctx.targetDoseWeight, 18.0);
      expect(ctx.targetYield, 36.0);
    });

    test('ratio computed correctly', () {
      final ctx = WorkflowContext(targetDoseWeight: 18.0, targetYield: 36.0);
      expect(ctx.ratio, 2.0);
    });

    test('ratio null when dose weight is null or zero', () {
      expect(WorkflowContext(targetYield: 36.0).ratio, isNull);
      expect(
        WorkflowContext(targetDoseWeight: 0, targetYield: 36.0).ratio,
        isNull,
      );
    });

    test('copyWith preserves unchanged fields', () {
      final ctx = WorkflowContext(
        targetDoseWeight: 18.0,
        targetYield: 36.0,
        coffeeName: 'Ethiopian',
      );

      final updated = ctx.copyWith(targetYield: 40.0);

      expect(updated.targetDoseWeight, 18.0);
      expect(updated.targetYield, 40.0);
      expect(updated.coffeeName, 'Ethiopian');
    });
  });
}
