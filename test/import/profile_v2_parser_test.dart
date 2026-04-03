import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/parsers/profile_v2_parser.dart';

void main() {
  late Map<String, dynamic> londiniumJson;

  setUpAll(() {
    final file = File(
      'test/fixtures/de1app/profiles_v2/best_practice.json',
    );
    londiniumJson = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  group('ProfileV2Parser', () {
    test('parses profile with correct title', () {
      final record = ProfileV2Parser.parse(londiniumJson);
      expect(record.profile.title, 'Londinium');
    });

    test('parses steps correctly (count and names)', () {
      final record = ProfileV2Parser.parse(londiniumJson);
      expect(record.profile.steps.length, 3);
      expect(record.profile.steps[0].name, 'preinfusion');
      expect(record.profile.steps[1].name, 'rise');
      expect(record.profile.steps[2].name, 'decline');
    });

    test('generates content-based hash ID starting with profile:', () {
      final record = ProfileV2Parser.parse(londiniumJson);
      expect(record.id, startsWith('profile:'));
    });

    test('same content produces same ID (deterministic)', () {
      final record1 = ProfileV2Parser.parse(londiniumJson);
      final record2 = ProfileV2Parser.parse(londiniumJson);
      expect(record1.id, record2.id);
    });

    test('parses target weight', () {
      final record = ProfileV2Parser.parse(londiniumJson);
      expect(record.profile.targetWeight, 40.0);
    });
  });
}
