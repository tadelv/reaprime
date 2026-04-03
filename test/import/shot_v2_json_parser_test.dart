import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/parsers/shot_v2_json_parser.dart';

void main() {
  group('ShotV2JsonParser', () {
    late Map<String, dynamic> fixtureJson;
    late ParsedShot result;

    setUpAll(() {
      final file = File('test/fixtures/de1app/history_v2/20240315T143022.json');
      fixtureJson = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      result = ShotV2JsonParser.parse(fixtureJson);
    });

    group('timestamp', () {
      test('parses correct timestamp from clock', () {
        // clock = 1710510622 = 2024-03-15T13:30:22Z (UTC)
        final expected = DateTime.fromMillisecondsSinceEpoch(
          1710510622 * 1000,
          isUtc: true,
        );
        expect(result.shot.timestamp.isAtSameMomentAs(expected), isTrue);
      });
    });

    group('time-series measurements', () {
      test('produces one snapshot per elapsed entry', () {
        // fixture has 9 elapsed values
        expect(result.shot.measurements.length, equals(9));
      });

      test('first snapshot has correct pressure', () {
        final snap = result.shot.measurements.first;
        expect(snap.machine.pressure, equals(0.0));
      });

      test('snapshot at index 4 has correct pressure', () {
        final snap = result.shot.measurements[4];
        expect(snap.machine.pressure, closeTo(8.8, 0.001));
      });

      test('snapshot at index 4 has correct flow', () {
        final snap = result.shot.measurements[4];
        expect(snap.machine.flow, closeTo(2.8, 0.001));
      });

      test('snapshot at index 4 has correct basket temperature', () {
        final snap = result.shot.measurements[4];
        expect(snap.machine.groupTemperature, closeTo(89.0, 0.001));
      });

      test('snapshot at index 4 has correct mix temperature', () {
        final snap = result.shot.measurements[4];
        expect(snap.machine.mixTemperature, closeTo(85.0, 0.001));
      });

      test('snapshot at index 4 has correct target pressure', () {
        final snap = result.shot.measurements[4];
        expect(snap.machine.targetPressure, closeTo(9.0, 0.001));
      });

      test('snapshot at index 4 has correct weight', () {
        final snap = result.shot.measurements[4];
        expect(snap.scale?.weight, closeTo(2.0, 0.001));
      });

      test('snapshot at index 4 has correct weight flow', () {
        final snap = result.shot.measurements[4];
        expect(snap.scale?.weightFlow, closeTo(2.5, 0.001));
      });

      test('snapshot timestamps are offset from base by elapsed time', () {
        final base = result.shot.timestamp;
        final snap4 = result.shot.measurements[4];
        final expectedOffset = Duration(milliseconds: (1.0 * 1000).round());
        final actualDiff = snap4.machine.timestamp.difference(base);
        expect(actualDiff, equals(expectedOffset));
      });
    });

    group('embedded profile', () {
      test('extracts profile title', () {
        expect(result.shot.workflow.profile.title, equals('Best Practice'));
      });

      test('extracts correct step count', () {
        expect(result.shot.workflow.profile.steps.length, equals(2));
      });

      test('first step name is preinfusion', () {
        expect(result.shot.workflow.profile.steps.first.name, equals('preinfusion'));
      });
    });

    group('bean metadata', () {
      test('extracts bean brand', () {
        expect(result.beanBrand, equals('Banibeans'));
      });

      test('extracts bean type', () {
        expect(result.beanType, equals('Ethiopia Yirgacheffe'));
      });

      test('extracts bean notes', () {
        expect(result.beanNotes, equals('Fruity and floral'));
      });

      test('extracts roast level', () {
        expect(result.roastLevel, equals('Light'));
      });

      test('extracts roast date', () {
        expect(result.roastDate, equals('2024-03-01'));
      });
    });

    group('grinder metadata', () {
      test('extracts grinder model', () {
        expect(result.grinderModel, equals('Niche Zero'));
      });

      test('extracts grinder setting', () {
        expect(result.grinderSetting, equals('15'));
      });
    });

    group('shot annotations', () {
      test('extracts actual dose weight', () {
        expect(result.shot.annotations?.actualDoseWeight, closeTo(18.0, 0.001));
      });

      test('extracts actual yield', () {
        expect(result.shot.annotations?.actualYield, closeTo(36.0, 0.001));
      });

      test('extracts TDS', () {
        expect(result.shot.annotations?.drinkTds, closeTo(8.5, 0.001));
      });

      test('extracts EY', () {
        expect(result.shot.annotations?.drinkEy, closeTo(20.5, 0.001));
      });

      test('extracts enjoyment', () {
        expect(result.shot.annotations?.enjoyment, closeTo(75.0, 0.001));
      });

      test('extracts espresso notes', () {
        expect(
          result.shot.annotations?.espressoNotes,
          equals('Good body, slight sourness'),
        );
      });
    });

    group('workflow context', () {
      test('context is not null', () {
        expect(result.shot.workflow.context, isNotNull);
      });

      test('extracts target dose weight into context', () {
        expect(
          result.shot.workflow.context?.targetDoseWeight,
          closeTo(18.0, 0.001),
        );
      });

      test('extracts target yield into context', () {
        expect(result.shot.workflow.context?.targetYield, closeTo(36.0, 0.001));
      });

      test('extracts grinder model into context', () {
        expect(result.shot.workflow.context?.grinderModel, equals('Niche Zero'));
      });

      test('extracts grinder setting into context', () {
        expect(result.shot.workflow.context?.grinderSetting, equals('15'));
      });

      test('extracts coffee name (beanType) into context', () {
        expect(
          result.shot.workflow.context?.coffeeName,
          equals('Ethiopia Yirgacheffe'),
        );
      });

      test('extracts coffee roaster (beanBrand) into context', () {
        expect(result.shot.workflow.context?.coffeeRoaster, equals('Banibeans'));
      });

      test('extracts barista name from settings', () {
        expect(result.shot.workflow.context?.baristaName, equals('Test User'));
      });

      test('extracts drinker name from settings', () {
        expect(result.shot.workflow.context?.drinkerName, equals('Guest'));
      });
    });

    group('shot ID', () {
      test('shot ID uses de1app-{clock} format', () {
        expect(result.shot.id, equals('de1app-1710510622'));
      });
    });

    group('fallback to settings when meta absent', () {
      test('parses dose from settings when meta is missing', () {
        final noMeta = Map<String, dynamic>.from(fixtureJson)..remove('meta');
        final parsed = ShotV2JsonParser.parse(noMeta);
        expect(parsed.shot.annotations?.actualDoseWeight, closeTo(18.0, 0.001));
      });

      test('parses bean brand from settings when meta is missing', () {
        final noMeta = Map<String, dynamic>.from(fixtureJson)..remove('meta');
        final parsed = ShotV2JsonParser.parse(noMeta);
        expect(parsed.beanBrand, equals('Banibeans'));
      });
    });
  });
}
