import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/grinder.dart';

void main() {
  final now = DateTime(2026, 1, 15, 10, 0, 0);

  group('GrinderSettingType', () {
    test('fromString parses known values', () {
      expect(GrinderSettingType.fromString('numeric'),
          GrinderSettingType.numeric);
      expect(
          GrinderSettingType.fromString('preset'), GrinderSettingType.preset);
    });

    test('fromString accepts legacy "values" as preset', () {
      expect(
          GrinderSettingType.fromString('values'), GrinderSettingType.preset);
    });

    test('fromString defaults to numeric for unknown', () {
      expect(GrinderSettingType.fromString('unknown'),
          GrinderSettingType.numeric);
    });
  });

  group('Grinder', () {
    test('round-trip serialization with all fields', () {
      final grinder = Grinder(
        id: 'grinder-1',
        model: 'Niche Zero',
        burrs: '63mm Mazzer',
        burrSize: 63.0,
        burrType: 'Conical',
        notes: 'Single dose',
        archived: false,
        settingType: GrinderSettingType.numeric,
        settingValues: null,
        settingSmallStep: 1.0,
        settingBigStep: 5.0,
        rpmSmallStep: null,
        rpmBigStep: null,
        createdAt: now,
        updatedAt: now,
        extras: {'dye2': {'color': '#ff0000'}},
      );

      final json = grinder.toJson();
      final restored = Grinder.fromJson(json);

      expect(restored.id, 'grinder-1');
      expect(restored.model, 'Niche Zero');
      expect(restored.burrs, '63mm Mazzer');
      expect(restored.burrSize, 63.0);
      expect(restored.burrType, 'Conical');
      expect(restored.notes, 'Single dose');
      expect(restored.archived, false);
      expect(restored.settingType, GrinderSettingType.numeric);
      expect(restored.settingSmallStep, 1.0);
      expect(restored.settingBigStep, 5.0);
      expect(restored.extras, {'dye2': {'color': '#ff0000'}});
    });

    test('round-trip with values-based setting type', () {
      final grinder = Grinder(
        id: 'grinder-2',
        model: 'Baratza Encore',
        settingType: GrinderSettingType.preset,
        settingValues: ['1', '2', '3', '4', '5', '10', '15', '20'],
        createdAt: now,
        updatedAt: now,
      );

      final json = grinder.toJson();
      final restored = Grinder.fromJson(json);

      expect(restored.settingType, GrinderSettingType.preset);
      expect(restored.settingValues, ['1', '2', '3', '4', '5', '10', '15', '20']);
    });

    test('nullable fields omitted from JSON', () {
      final grinder = Grinder(
        id: 'grinder-3',
        model: 'Eureka Mignon',
        createdAt: now,
        updatedAt: now,
      );

      final json = grinder.toJson();
      expect(json.containsKey('burrs'), false);
      expect(json.containsKey('burrSize'), false);
      expect(json.containsKey('settingValues'), false);
      expect(json.containsKey('rpmSmallStep'), false);
      expect(json.containsKey('extras'), false);
      expect(json['settingType'], 'numeric');
      expect(json['archived'], false);
    });

    test('create factory generates id and timestamps', () {
      final grinder = Grinder.create(model: 'Lagom P64');

      expect(grinder.id, isNotEmpty);
      expect(grinder.createdAt, isNotNull);
      expect(grinder.updatedAt, isNotNull);
      expect(grinder.archived, false);
      expect(grinder.settingType, GrinderSettingType.numeric);
    });

    test('copyWith preserves unchanged fields', () {
      final grinder = Grinder(
        id: 'grinder-4',
        model: 'Niche Zero',
        burrs: '63mm Mazzer',
        settingSmallStep: 1.0,
        createdAt: now,
        updatedAt: now,
      );

      final updated = grinder.copyWith(settingSmallStep: 0.5);

      expect(updated.id, 'grinder-4');
      expect(updated.model, 'Niche Zero');
      expect(updated.burrs, '63mm Mazzer');
      expect(updated.settingSmallStep, 0.5);
    });

    test('fromJson handles int values for doubles', () {
      final json = {
        'id': 'grinder-5',
        'model': 'Test',
        'burrSize': 64,
        'settingSmallStep': 1,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final grinder = Grinder.fromJson(json);
      expect(grinder.burrSize, 64.0);
      expect(grinder.settingSmallStep, 1.0);
    });
  });
}
