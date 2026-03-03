import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/shot_annotations.dart';

void main() {
  group('ShotAnnotations', () {
    test('round-trip serialization with all fields', () {
      final ann = ShotAnnotations(
        actualDoseWeight: 18.2,
        actualYield: 37.5,
        drinkTds: 8.5,
        drinkEy: 21.3,
        enjoyment: 8.0,
        espressoNotes: 'Fruity, clean finish',
        extras: {'visualizer': {'score': 92}},
      );

      final json = ann.toJson();
      final restored = ShotAnnotations.fromJson(json);

      expect(restored.actualDoseWeight, 18.2);
      expect(restored.actualYield, 37.5);
      expect(restored.drinkTds, 8.5);
      expect(restored.drinkEy, 21.3);
      expect(restored.enjoyment, 8.0);
      expect(restored.espressoNotes, 'Fruity, clean finish');
      expect(restored.extras, {'visualizer': {'score': 92}});
    });

    test('round-trip with minimal fields (nulls omitted from JSON)', () {
      final ann = ShotAnnotations(enjoyment: 7.5);

      final json = ann.toJson();
      expect(json.containsKey('actualDoseWeight'), false);
      expect(json.containsKey('espressoNotes'), false);
      expect(json['enjoyment'], 7.5);

      final restored = ShotAnnotations.fromJson(json);
      expect(restored.enjoyment, 7.5);
      expect(restored.actualDoseWeight, isNull);
    });

    test('fromLegacyJson maps shotNotes and metadata', () {
      final legacyShotJson = {
        'shotNotes': 'Good shot, slightly bitter',
        'metadata': {'source': 'de1app', 'version': 2},
      };

      final ann = ShotAnnotations.fromLegacyJson(legacyShotJson);

      expect(ann.espressoNotes, 'Good shot, slightly bitter');
      expect(ann.extras, {'source': 'de1app', 'version': 2});
      expect(ann.actualDoseWeight, isNull);
      expect(ann.enjoyment, isNull);
    });

    test('fromLegacyJson handles missing optional fields', () {
      final ann = ShotAnnotations.fromLegacyJson({});

      expect(ann.espressoNotes, isNull);
      expect(ann.extras, isNull);
    });

    test('fromJson handles int values for doubles', () {
      final json = {
        'actualDoseWeight': 18,
        'actualYield': 36,
        'enjoyment': 8,
      };

      final ann = ShotAnnotations.fromJson(json);
      expect(ann.actualDoseWeight, 18.0);
      expect(ann.actualYield, 36.0);
      expect(ann.enjoyment, 8.0);
    });

    test('copyWith preserves unchanged fields', () {
      final ann = ShotAnnotations(
        enjoyment: 7.5,
        espressoNotes: 'Good',
      );

      final updated = ann.copyWith(enjoyment: 9.0);

      expect(updated.enjoyment, 9.0);
      expect(updated.espressoNotes, 'Good');
    });
  });
}
