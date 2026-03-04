import 'package:reaprime/src/models/data/bean.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class BeanExportSection implements DataExportSection {
  final BeanStorageService _storage;

  BeanExportSection({required BeanStorageService storage})
      : _storage = storage;

  @override
  String get filename => 'beans.json';

  @override
  Future<dynamic> export() async {
    final beans = await _storage.getAllBeans(includeArchived: true);
    final result = <Map<String, dynamic>>[];

    for (final bean in beans) {
      final batches =
          await _storage.getBatchesForBean(bean.id, includeArchived: true);
      final beanJson = bean.toJson();
      beanJson['batches'] = batches.map((b) => b.toJson()).toList();
      result.add(beanJson);
    }

    return result;
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    if (data is! List) {
      return const SectionImportResult(
        errors: ['Expected JSON array of bean records'],
      );
    }

    int imported = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final item in data) {
      try {
        final json = item as Map<String, dynamic>;
        final batches = (json['batches'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map((b) => BeanBatch.fromJson(b))
                .toList() ??
            [];

        // Remove batches from bean JSON before parsing
        final beanJson = Map<String, dynamic>.from(json)..remove('batches');
        final bean = Bean.fromJson(beanJson);

        final existing = await _storage.getBeanById(bean.id);
        if (existing != null) {
          if (strategy == ConflictStrategy.overwrite) {
            await _storage.updateBean(bean);
            imported++;
          } else {
            skipped++;
          }
        } else {
          await _storage.insertBean(bean);
          imported++;
        }

        // Import batches for this bean
        for (final batch in batches) {
          try {
            final existingBatch = await _storage.getBatchById(batch.id);
            if (existingBatch != null) {
              if (strategy == ConflictStrategy.overwrite) {
                await _storage.updateBatch(batch);
                imported++;
              } else {
                skipped++;
              }
            } else {
              await _storage.insertBatch(batch);
              imported++;
            }
          } catch (e) {
            errors.add('Failed to import batch ${batch.id}: $e');
          }
        }
      } catch (e) {
        errors.add('Failed to import bean: $e');
      }
    }

    return SectionImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }
}
