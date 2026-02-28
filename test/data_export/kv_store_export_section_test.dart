import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:reaprime/src/services/storage/hive_store_service.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/kv_store_export_section.dart';

void main() {
  late HiveStoreService store;
  late KvStoreExportSection section;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_kv_export_test_');
    Hive.init(tempDir.path);
    store = HiveStoreService(defaultNamespace: 'testKvExport');
    await store.initialize();
    section = KvStoreExportSection(store: store);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('filename is store.json', () {
    expect(section.filename, equals('store.json'));
  });

  group('export', () {
    test('exports empty store', () async {
      final result = await section.export();
      expect(result, isA<Map<String, dynamic>>());
      final map = result as Map<String, dynamic>;
      expect(map, contains('namespaces'));
      final namespaces = map['namespaces'] as Map<String, dynamic>;
      expect(namespaces, contains('testKvExport'));
      expect(namespaces['testKvExport'], isEmpty);
    });

    test('exports data in default namespace', () async {
      await store.set(key: 'key1', value: 'value1');
      await store.set(key: 'key2', value: 42);

      final result = await section.export();
      final namespaces =
          (result as Map<String, dynamic>)['namespaces'] as Map<String, dynamic>;
      final defaultNs = namespaces['testKvExport'] as Map<String, Object>;
      expect(defaultNs['key1'], equals('value1'));
      expect(defaultNs['key2'], equals(42));
    });

    test('exports data across multiple namespaces', () async {
      await store.set(key: 'k1', value: 'v1');
      await store.set(namespace: 'plugins', key: 'p1', value: 'data1');
      await store.set(namespace: 'plugins', key: 'p2', value: 'data2');

      final result = await section.export();
      final namespaces =
          (result as Map<String, dynamic>)['namespaces'] as Map<String, dynamic>;

      expect(namespaces, contains('testKvExport'));
      expect(namespaces, contains('plugins'));

      final defaultNs = namespaces['testKvExport'] as Map<String, Object>;
      expect(defaultNs['k1'], equals('v1'));

      final pluginsNs = namespaces['plugins'] as Map<String, Object>;
      expect(pluginsNs['p1'], equals('data1'));
      expect(pluginsNs['p2'], equals('data2'));
    });
  });

  group('import with skip strategy', () {
    test('imports new key-value pairs', () async {
      final data = {
        'namespaces': {
          'testKvExport': {'a': 'alpha', 'b': 'beta'},
        },
      };

      final result = await section.import(data, ConflictStrategy.skip);

      expect(result.imported, equals(2));
      expect(result.skipped, equals(0));
      expect(result.errors, isEmpty);

      expect(await store.get(key: 'a'), equals('alpha'));
      expect(await store.get(key: 'b'), equals('beta'));
    });

    test('skips existing keys', () async {
      await store.set(key: 'existing', value: 'original');

      final data = {
        'namespaces': {
          'testKvExport': {'existing': 'new_value'},
        },
      };

      final result = await section.import(data, ConflictStrategy.skip);

      expect(result.imported, equals(0));
      expect(result.skipped, equals(1));

      // Original value preserved
      expect(await store.get(key: 'existing'), equals('original'));
    });

    test('returns error for missing namespaces key', () async {
      final data = <String, dynamic>{'other': 'stuff'};

      final result = await section.import(data, ConflictStrategy.skip);

      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Expected "namespaces" key'));
    });
  });

  group('import with overwrite strategy', () {
    test('imports new key-value pairs', () async {
      final data = {
        'namespaces': {
          'testKvExport': {'x': 'y'},
        },
      };

      final result = await section.import(data, ConflictStrategy.overwrite);

      expect(result.imported, equals(1));
      expect(result.errors, isEmpty);

      expect(await store.get(key: 'x'), equals('y'));
    });

    test('overwrites existing keys', () async {
      await store.set(key: 'existing', value: 'original');

      final data = {
        'namespaces': {
          'testKvExport': {'existing': 'overwritten'},
        },
      };

      final result =
          await section.import(data, ConflictStrategy.overwrite);

      expect(result.imported, equals(1));
      expect(result.skipped, equals(0));

      expect(await store.get(key: 'existing'), equals('overwritten'));
    });

    test('imports into new namespaces', () async {
      final data = {
        'namespaces': {
          'newNamespace': {'key1': 'val1'},
        },
      };

      final result =
          await section.import(data, ConflictStrategy.overwrite);

      expect(result.imported, equals(1));
      expect(result.errors, isEmpty);

      expect(
        await store.get(namespace: 'newNamespace', key: 'key1'),
        equals('val1'),
      );
    });
  });

  group('round-trip', () {
    test('export then import preserves data', () async {
      await store.set(key: 'a', value: 'alpha');
      await store.set(namespace: 'ns2', key: 'b', value: 'beta');

      final exported = await section.export();

      // Clear the store by deleting keys
      await store.delete(key: 'a');
      await store.delete(namespace: 'ns2', key: 'b');

      // Verify cleared
      expect(await store.get(key: 'a'), isNull);
      expect(await store.get(namespace: 'ns2', key: 'b'), isNull);

      // Re-import
      final result =
          await section.import(exported, ConflictStrategy.overwrite);

      expect(result.errors, isEmpty);
      expect(result.imported, equals(2));

      // Verify the specific key-value pairs were restored
      expect(await store.get(key: 'a'), equals('alpha'));
      expect(await store.get(namespace: 'ns2', key: 'b'), equals('beta'));
    });
  });
}
