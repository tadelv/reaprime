import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/parsers/grinder_tdb_parser.dart';
import 'package:reaprime/src/models/data/grinder.dart';

void main() {
  late String tdbContent;
  late List<Grinder> grinders;

  setUpAll(() {
    final file = File(
      'test/fixtures/de1app/plugins/DYE/grinders.tdb',
    );
    tdbContent = file.readAsStringSync();
    grinders = GrinderTdbParser.parse(tdbContent);
  });

  group('GrinderTdbParser', () {
    test('parses all 3 grinder models', () {
      expect(grinders.length, 3);
      final models = grinders.map((g) => g.model).toList();
      expect(models, containsAll(['Niche Zero', 'Eureka Mignon', 'EK43']));
    });

    test('parses burr info correctly', () {
      final nicheZero = grinders.firstWhere((g) => g.model == 'Niche Zero');
      expect(nicheZero.burrs, '63mm conical');

      final eureka = grinders.firstWhere((g) => g.model == 'Eureka Mignon');
      expect(eureka.burrs, '55mm flat');

      final ek43 = grinders.firstWhere((g) => g.model == 'EK43');
      expect(ek43.burrs, '98mm flat');
    });

    test('sets numeric setting type for all grinders', () {
      for (final grinder in grinders) {
        expect(grinder.settingType, GrinderSettingType.numeric);
      }
    });

    test('parses step values correctly', () {
      final nicheZero = grinders.firstWhere((g) => g.model == 'Niche Zero');
      expect(nicheZero.settingSmallStep, 1.0);
      expect(nicheZero.settingBigStep, 5.0);

      final eureka = grinders.firstWhere((g) => g.model == 'Eureka Mignon');
      expect(eureka.settingSmallStep, 0.5);
      expect(eureka.settingBigStep, 2.0);

      final ek43 = grinders.firstWhere((g) => g.model == 'EK43');
      expect(ek43.settingSmallStep, 0.5);
      expect(ek43.settingBigStep, 3.0);
    });
  });
}
