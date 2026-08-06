import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/storage/kv_store_service.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/kv_store_export_section.dart';
import 'package:reaprime/src/util/incremental_json_parser.dart';

import 'streaming_test_helpers.dart';

class MockKvStore implements KeyValueStoreService {
  final Map<String, Map<String, Object>> boxes = {};

  @override
  Future<void> initialize() async {}

  @override
  List<String> get namespaces => boxes.keys.toList();

  @override
  Future<Map<String, Object>> getAll({String namespace = "default"}) async =>
      Map.of(boxes[namespace] ?? {});

  @override
  Future<Object?> get({
    String namespace = "default",
    required String key,
  }) async => boxes[namespace]?[key];

  @override
  Future<List<String>> keys({String namespace = "default"}) async =>
      (boxes[namespace] ?? {}).keys.toList();

  @override
  Future<void> set({
    String namespace = "default",
    required String key,
    required Object value,
  }) async {
    boxes.putIfAbsent(namespace, () => {})[key] = value;
  }

  @override
  Future<bool> delete({
    String namespace = "default",
    required String key,
  }) async {
    boxes[namespace]?.remove(key);
    return true;
  }
}

void main() {
  group('KvStoreExportSection', () {
    test('exports namespaces and key/value pairs incrementally', () async {
      final store = MockKvStore();
      await store.set(namespace: 'default', key: 'a', value: 1);
      await store.set(namespace: 'default', key: 'b', value: {'nested': true});
      await store.set(namespace: 'plugins', key: 'p', value: 'x');
      await store.set(namespace: 'empty', key: 'k', value: 'v');
      await store.delete(namespace: 'empty', key: 'k'); // leave namespace empty

      final pages = <String>[];
      final section = KvStoreExportSection(
        store: store,
        pageKvKeys: (namespace, offset, limit) async {
          pages.add('$namespace@$offset');
          final keys = await store.keys(namespace: namespace);
          return keys.skip(offset).take(limit).toList();
        },
      );

      final sink = CapturingJsonSink();
      await section.exportJson(sink);

      final decoded = jsonDecode(sink.json) as Map<String, dynamic>;
      final namespaces = decoded['namespaces'] as Map<String, dynamic>;
      expect(namespaces.keys.toSet(), {'default', 'plugins', 'empty'});
      expect(namespaces['default'], {
        'a': 1,
        'b': {'nested': true},
      });
      expect(namespaces['plugins'], {'p': 'x'});
    });

    test('imports key/value pairs at depth 3 with skip semantics', () async {
      final store = MockKvStore();
      await store.set(namespace: 'default', key: 'existing', value: 1);
      final section = KvStoreExportSection(
        store: store,
        pageKvKeys: (namespace, offset, limit) async => [],
      );
      final result = await importSectionJson(
        section,
        jsonEncode({
          'namespaces': {
            'default': {'existing': 1, 'new': 2},
            'plugins': {'setting': 'on'},
          },
        }),
        ConflictStrategy.skip,
      );
      expect(result.imported, 2); // new + plugins/setting
      expect(result.skipped, 1); // existing
      expect(store.boxes['default']!['new'], 2);
      expect(store.boxes['plugins']!['setting'], 'on');
    });

    test('rejects malformed payloads without importing', () async {
      final store = MockKvStore();
      final section = KvStoreExportSection(
        store: store,
        pageKvKeys: (namespace, offset, limit) async => [],
      );
      await expectLater(
        importSectionJson(
          section,
          '{"namespaces": {"a": {"k":',
          ConflictStrategy.skip,
        ),
        throwsA(isA<JsonStreamFormatException>()),
      );
      expect(store.boxes, isEmpty);
    });
  });
}
