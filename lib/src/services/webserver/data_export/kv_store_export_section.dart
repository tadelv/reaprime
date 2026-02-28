import 'package:reaprime/src/services/storage/hive_store_service.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class KvStoreExportSection implements DataExportSection {
  final HiveStoreService _store;

  KvStoreExportSection({required HiveStoreService store}) : _store = store;

  @override
  String get filename => 'store.json';

  @override
  Future<dynamic> export() async {
    final result = <String, dynamic>{};
    for (final namespace in _store.namespaces) {
      result[namespace] = await _store.getAll(namespace: namespace);
    }
    return {'namespaces': result};
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    final map = data as Map<String, dynamic>;
    final namespaces = map['namespaces'] as Map<String, dynamic>?;
    if (namespaces == null) {
      return const SectionImportResult(
        errors: ['Expected "namespaces" key in store.json'],
      );
    }

    int imported = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final entry in namespaces.entries) {
      final namespace = entry.key;
      final pairs = entry.value as Map<String, dynamic>;
      for (final kv in pairs.entries) {
        try {
          final existing =
              await _store.get(namespace: namespace, key: kv.key);
          if (existing != null && strategy == ConflictStrategy.skip) {
            skipped++;
          } else {
            await _store.set(
              namespace: namespace,
              key: kv.key,
              value: kv.value,
            );
            imported++;
          }
        } catch (e) {
          errors.add('Failed to import $namespace/${kv.key}: $e');
        }
      }
    }

    return SectionImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }
}
