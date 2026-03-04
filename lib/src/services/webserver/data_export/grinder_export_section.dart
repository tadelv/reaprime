import 'package:reaprime/src/models/data/grinder.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class GrinderExportSection implements DataExportSection {
  final GrinderStorageService _storage;

  GrinderExportSection({required GrinderStorageService storage})
      : _storage = storage;

  @override
  String get filename => 'grinders.json';

  @override
  Future<dynamic> export() async {
    final grinders = await _storage.getAllGrinders(includeArchived: true);
    return grinders.map((g) => g.toJson()).toList();
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    if (data is! List) {
      return const SectionImportResult(
        errors: ['Expected JSON array of grinder records'],
      );
    }

    int imported = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final item in data) {
      try {
        final grinder = Grinder.fromJson(item as Map<String, dynamic>);
        final existing = await _storage.getGrinderById(grinder.id);

        if (existing != null) {
          if (strategy == ConflictStrategy.overwrite) {
            await _storage.updateGrinder(grinder);
            imported++;
          } else {
            skipped++;
          }
        } else {
          await _storage.insertGrinder(grinder);
          imported++;
        }
      } catch (e) {
        errors.add('Failed to import grinder: $e');
      }
    }

    return SectionImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }
}
