import 'dart:convert';

import 'package:reaprime/src/services/storage/kv_store_service.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/data_transfer_limits.dart';
import 'package:reaprime/src/util/incremental_json_parser.dart';

class KvStoreExportSection implements DataExportSection {
  final KeyValueStoreService _store;
  final Future<List<String>> Function(String namespace, int offset, int limit)
  _pageKvKeys;
  final int pageSize;

  KvStoreExportSection({
    required KeyValueStoreService store,
    required Future<List<String>> Function(
      String namespace,
      int offset,
      int limit,
    )
    pageKvKeys,
    this.pageSize = DataTransferLimits.defaultExportPageSize,
  }) : _store = store,
       _pageKvKeys = pageKvKeys;

  @override
  String get filename => 'store.json';

  @override
  Future<void> exportJson(JsonSink output) async {
    // Shape: {"namespaces": {ns: {k: v}}} written incrementally so only one
    // key/value pair is encoded at a time.
    output.writeRaw('{"namespaces":{');
    var firstNamespace = true;
    for (final namespace in _store.namespaces) {
      output.writeRaw(firstNamespace ? '' : ',');
      output.writeRaw(jsonEncode(namespace));
      output.writeRaw(':{');
      var offset = 0;
      var firstKey = true;
      while (true) {
        final keys = await _pageKvKeys(namespace, offset, pageSize);
        if (keys.isEmpty) break;
        for (final key in keys) {
          final value = await _store.get(namespace: namespace, key: key);
          if (value == null) continue;
          output.writeRaw(firstKey ? '' : ',');
          output.writeRaw(jsonEncode(key));
          output.writeRaw(':');
          output.writeRaw(jsonEncode(value));
          firstKey = false;
        }
        if (keys.length < pageSize) break;
        offset += pageSize;
      }
      output.writeRaw('}');
      firstNamespace = false;
    }
    output.writeRaw('}}');
  }

  @override
  Future<SectionImportResult> importJson(
    SectionJsonInput input,
    ConflictStrategy strategy,
  ) async {
    await validateJson(input);

    int imported = 0;
    int skipped = 0;
    final errors = <String>[];

    // Depth-3 events: keys = [namespaces, <ns>, <key>], value = the KV value.
    await for (final event in input.valuesAtDepth(3)) {
      if (event.keys.length != 3 || event.keys[0] != 'namespaces') {
        errors.add('Unexpected store entry structure in store.json');
        continue;
      }
      final namespace = event.keys[1];
      final key = event.keys[2];
      try {
        final existing = await _store.get(namespace: namespace, key: key);
        if (existing != null && strategy == ConflictStrategy.skip) {
          skipped++;
        } else {
          await _store.set(namespace: namespace, key: key, value: event.value!);
          imported++;
        }
      } catch (e) {
        errors.add('Failed to import $namespace/$key: $e');
      }
    }

    return SectionImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }

  Future<void> validateJson(SectionJsonInput input) async {
    if (await input.open() != JsonContainerKind.object) {
      throw const JsonStreamFormatException(
        'store.json must contain a root object.',
      );
    }

    var sawNamespaces = false;
    String? shapeError;
    await for (final _ in input.valuesAtDepth(
      3,
      onValueStart: (depth, keys, containerKind) {
        if (depth == 1 && keys.length == 1 && keys.first == 'namespaces') {
          sawNamespaces = true;
          if (containerKind != JsonContainerKind.object) {
            shapeError = '"namespaces" must be an object.';
          }
        }
        if (depth == 2 &&
            keys.length == 2 &&
            keys.first == 'namespaces' &&
            containerKind != JsonContainerKind.object) {
          shapeError = 'Every namespace value must be an object.';
        }
      },
    )) {}

    if (!sawNamespaces) {
      throw const JsonStreamFormatException(
        'store.json must contain "namespaces".',
      );
    }
    if (shapeError != null) throw JsonStreamFormatException(shapeError!);
  }
}
