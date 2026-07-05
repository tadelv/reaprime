import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/models/data/steam_record.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class SteamExportSection implements DataExportSection {
  final PersistenceController _controller;

  SteamExportSection({required PersistenceController controller})
    : _controller = controller;

  @override
  String get filename => 'steams.json';

  @override
  Future<dynamic> export() async {
    final records = await _controller.storageService.getAllSteams();
    return records.map((r) => r.toJson()).toList();
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    if (data is! List) {
      return const SectionImportResult(
        errors: ['Expected JSON array of steam records'],
      );
    }

    int imported = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final item in data) {
      try {
        final record = SteamRecord.fromJson(item as Map<String, dynamic>);
        final existing = await _controller.storageService.getSteam(record.id);

        if (existing != null) {
          if (strategy == ConflictStrategy.overwrite) {
            await _controller.storageService.updateSteam(record);
            imported++;
          } else {
            skipped++;
          }
        } else {
          await _controller.storageService.storeSteam(record);
          imported++;
        }
      } catch (e) {
        errors.add('Failed to import steam record: $e');
      }
    }

    if (imported > 0) {
      _controller.notifySteamsChanged();
    }

    return SectionImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }
}
