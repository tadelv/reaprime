import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/bean.dart';

void main() {
  final now = DateTime(2026, 1, 15, 10, 0, 0);

  group('Bean', () {
    test('round-trip serialization with all fields', () {
      final bean = Bean(
        id: 'bean-1',
        roaster: 'Sey',
        name: 'Gesha Village',
        species: 'Arabica',
        decaf: false,
        decafProcess: null,
        country: 'Ethiopia',
        region: 'Bench Maji',
        producer: 'Gesha Village Estate',
        variety: ['Gesha'],
        altitude: [1900, 2100],
        processing: 'Washed',
        notes: 'Floral, jasmine, bergamot',
        archived: false,
        createdAt: now,
        updatedAt: now,
        extras: {'plugin': {'flag': true}},
      );

      final json = bean.toJson();
      final restored = Bean.fromJson(json);

      expect(restored.id, 'bean-1');
      expect(restored.roaster, 'Sey');
      expect(restored.name, 'Gesha Village');
      expect(restored.species, 'Arabica');
      expect(restored.decaf, false);
      expect(restored.country, 'Ethiopia');
      expect(restored.region, 'Bench Maji');
      expect(restored.producer, 'Gesha Village Estate');
      expect(restored.variety, ['Gesha']);
      expect(restored.altitude, [1900, 2100]);
      expect(restored.processing, 'Washed');
      expect(restored.notes, 'Floral, jasmine, bergamot');
      expect(restored.archived, false);
      expect(restored.extras, {'plugin': {'flag': true}});
    });

    test('nullable fields omitted from JSON', () {
      final bean = Bean(
        id: 'bean-2',
        roaster: 'Square Mile',
        name: 'Red Brick',
        createdAt: now,
        updatedAt: now,
      );

      final json = bean.toJson();
      expect(json.containsKey('species'), false);
      expect(json.containsKey('country'), false);
      expect(json.containsKey('variety'), false);
      expect(json.containsKey('extras'), false);
      expect(json['decaf'], false);
    });

    test('create factory generates id and timestamps', () {
      final bean = Bean.create(roaster: 'Sey', name: 'Worka');

      expect(bean.id, isNotEmpty);
      expect(bean.createdAt, isNotNull);
      expect(bean.updatedAt, isNotNull);
      expect(bean.archived, false);
    });

    test('copyWith updates updatedAt', () {
      final bean = Bean(
        id: 'bean-3',
        roaster: 'Sey',
        name: 'Original',
        createdAt: now,
        updatedAt: now,
      );

      final updated = bean.copyWith(name: 'Updated');

      expect(updated.id, 'bean-3');
      expect(updated.name, 'Updated');
      expect(updated.roaster, 'Sey');
      expect(updated.createdAt, now);
      expect(updated.updatedAt.isAfter(now) || updated.updatedAt == now, true);
    });

    test('altitude parsed from int list', () {
      final json = {
        'id': 'bean-4',
        'roaster': 'Test',
        'name': 'Test',
        'altitude': [1800, 2000],
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final bean = Bean.fromJson(json);
      expect(bean.altitude, [1800, 2000]);
    });
  });

  group('BeanBatch', () {
    test('round-trip serialization with all fields', () {
      final batch = BeanBatch(
        id: 'batch-1',
        beanId: 'bean-1',
        roastDate: DateTime(2026, 1, 10),
        roastLevel: 'Light',
        harvestDate: '2025',
        qualityScore: 87.5,
        price: 24.99,
        currency: 'USD',
        weight: 250.0,
        weightRemaining: 200.0,
        buyDate: DateTime(2026, 1, 12),
        openDate: DateTime(2026, 1, 14),
        bestBeforeDate: DateTime(2026, 7, 10),
        freezeDate: null,
        unfreezeDate: null,
        frozen: false,
        archived: false,
        notes: 'Great value',
        createdAt: now,
        updatedAt: now,
        extras: {'roastProfile': 'city+'},
      );

      final json = batch.toJson();
      final restored = BeanBatch.fromJson(json);

      expect(restored.id, 'batch-1');
      expect(restored.beanId, 'bean-1');
      expect(restored.roastDate, DateTime(2026, 1, 10));
      expect(restored.roastLevel, 'Light');
      expect(restored.harvestDate, '2025');
      expect(restored.qualityScore, 87.5);
      expect(restored.price, 24.99);
      expect(restored.currency, 'USD');
      expect(restored.weight, 250.0);
      expect(restored.weightRemaining, 200.0);
      expect(restored.frozen, false);
      expect(restored.notes, 'Great value');
    });

    test('nullable fields omitted from JSON', () {
      final batch = BeanBatch(
        id: 'batch-2',
        beanId: 'bean-1',
        createdAt: now,
        updatedAt: now,
      );

      final json = batch.toJson();
      expect(json.containsKey('roastDate'), false);
      expect(json.containsKey('price'), false);
      expect(json.containsKey('weight'), false);
      expect(json.containsKey('extras'), false);
      expect(json['frozen'], false);
      expect(json['archived'], false);
    });

    test('create factory sets weightRemaining from weight', () {
      final batch = BeanBatch.create(
        beanId: 'bean-1',
        weight: 250.0,
      );

      expect(batch.weight, 250.0);
      expect(batch.weightRemaining, 250.0);
      expect(batch.id, isNotEmpty);
    });

    test('copyWith preserves unchanged fields', () {
      final batch = BeanBatch(
        id: 'batch-3',
        beanId: 'bean-1',
        weight: 250.0,
        weightRemaining: 200.0,
        createdAt: now,
        updatedAt: now,
      );

      final updated = batch.copyWith(weightRemaining: 180.0);

      expect(updated.weight, 250.0);
      expect(updated.weightRemaining, 180.0);
      expect(updated.beanId, 'bean-1');
    });
  });
}
