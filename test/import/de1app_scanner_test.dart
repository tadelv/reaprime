import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/de1app_scanner.dart';
import 'package:reaprime/src/import/import_result.dart';

void main() {
  group('De1appScanner', () {
    group('scan() with full fixture folder', () {
      late ScanResult result;

      setUpAll(() async {
        result = await De1appScanner.scan('test/fixtures/de1app');
      });

      test('finds 1 shot from history_v2', () {
        expect(result.shotCount, equals(1));
      });

      test('shotSource is history_v2', () {
        expect(result.shotSource, equals('history_v2'));
      });

      test('finds 1 profile', () {
        expect(result.profileCount, equals(1));
      });

      test('detects DYE grinders', () {
        expect(result.hasDyeGrinders, isTrue);
      });

      test('sourcePath matches the scanned path', () {
        expect(result.sourcePath, equals('test/fixtures/de1app'));
      });

      test('totalItems is shotCount + profileCount', () {
        expect(result.totalItems, equals(result.shotCount + result.profileCount));
      });

      test('isEmpty is false', () {
        expect(result.isEmpty, isFalse);
      });
    });

    group('fallback to history/ when history_v2/ is absent', () {
      late Directory tempDir;
      late ScanResult result;

      setUpAll(() async {
        tempDir = await Directory.systemTemp.createTemp('de1app_scanner_test_');
        // Create history/ with a .shot file, but no history_v2/
        final historyDir = Directory('${tempDir.path}/history');
        await historyDir.create();
        await File('${tempDir.path}/history/shot1.shot').writeAsString('');

        result = await De1appScanner.scan(tempDir.path);
      });

      tearDownAll(() async {
        await tempDir.delete(recursive: true);
      });

      test('falls back to history/ when history_v2 is absent', () {
        expect(result.shotCount, equals(1));
        expect(result.shotSource, equals('history'));
      });
    });

    group('fallback to history/ when history_v2/ exists but is empty', () {
      late Directory tempDir;
      late ScanResult result;

      setUpAll(() async {
        tempDir = await Directory.systemTemp.createTemp('de1app_scanner_empty_v2_');
        // Create empty history_v2/ and history/ with a .shot file
        await Directory('${tempDir.path}/history_v2').create();
        final historyDir = Directory('${tempDir.path}/history');
        await historyDir.create();
        await File('${tempDir.path}/history/shot1.shot').writeAsString('');

        result = await De1appScanner.scan(tempDir.path);
      });

      tearDownAll(() async {
        await tempDir.delete(recursive: true);
      });

      test('falls back to history/ when history_v2 is empty', () {
        expect(result.shotCount, equals(1));
        expect(result.shotSource, equals('history'));
      });
    });

    group('empty result for non-de1app folder', () {
      late Directory tempDir;
      late ScanResult result;

      setUpAll(() async {
        tempDir = await Directory.systemTemp.createTemp('de1app_scanner_empty_');
        result = await De1appScanner.scan(tempDir.path);
      });

      tearDownAll(() async {
        await tempDir.delete(recursive: true);
      });

      test('shotCount is 0', () {
        expect(result.shotCount, equals(0));
      });

      test('profileCount is 0', () {
        expect(result.profileCount, equals(0));
      });

      test('hasDyeGrinders is false', () {
        expect(result.hasDyeGrinders, isFalse);
      });

      test('shotSource is null', () {
        expect(result.shotSource, isNull);
      });

      test('isEmpty is true', () {
        expect(result.isEmpty, isTrue);
      });
    });
  });
}
