import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class ShotExportSection implements DataExportSection {
  final PersistenceController _controller;

  ShotExportSection({required PersistenceController controller})
      : _controller = controller;

  @override
  String get filename => 'shots.json';

  @override
  Future<dynamic> export() async {
    final shots = await _controller.shots.first;
    return shots.map((s) => s.toJson()).toList();
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    if (data is! List) {
      return const SectionImportResult(
        errors: ['Expected JSON array of shot records'],
      );
    }

    int imported = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final item in data) {
      try {
        final record = ShotRecord.fromJson(item as Map<String, dynamic>);
        final existing =
            await _controller.storageService.getShot(record.id);

        if (existing != null) {
          if (strategy == ConflictStrategy.overwrite) {
            await _controller.updateShot(record);
            imported++;
          } else {
            skipped++;
          }
        } else {
          await _controller.persistShot(record);
          imported++;
        }
      } catch (e) {
        errors.add('Failed to import shot: $e');
      }
    }

    return SectionImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }
}
