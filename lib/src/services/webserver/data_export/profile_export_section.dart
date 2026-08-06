import 'package:reaprime/src/controllers/profile_controller.dart';
import 'package:reaprime/src/models/data/profile_record.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/data_transfer_limits.dart';
import 'package:reaprime/src/util/incremental_json_parser.dart';

class ProfileExportSection implements DataExportSection {
  final ProfileController _controller;
  final Future<List<ProfileRecord>> Function(int limit, int offset)
  _pageProfiles;
  final int pageSize;

  ProfileExportSection({
    required ProfileController controller,
    required Future<List<ProfileRecord>> Function(int limit, int offset)
    pageProfiles,
    this.pageSize = DataTransferLimits.defaultExportPageSize,
  }) : _controller = controller,
       _pageProfiles = pageProfiles;

  @override
  String get filename => 'profiles.json';

  @override
  Future<void> exportJson(JsonSink output) async {
    final emitter = JsonArrayEmitter(output);
    var offset = 0;
    while (true) {
      final page = await _pageProfiles(pageSize, offset);
      if (page.isEmpty) break;
      for (final record in page) {
        emitter.add(record.toJson());
      }
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    emitter.end();
  }

  @override
  Future<SectionImportResult> importJson(
    SectionJsonInput input,
    ConflictStrategy strategy,
  ) async {
    if (await input.open() != JsonContainerKind.array) {
      return const SectionImportResult(
        errors: ['Expected JSON array of profile records'],
      );
    }

    int imported = 0;
    int skipped = 0;
    final errors = <String>[];

    await for (final event in input.valuesAtDepth(1)) {
      try {
        final json = event.value as Map<String, dynamic>;
        final record = ProfileRecord.fromJson(json);
        final existing = await _controller.get(record.id);
        if (existing != null) {
          if (strategy == ConflictStrategy.overwrite) {
            await _controller.update(
              record.id,
              profile: record.profile,
              metadata: record.metadata,
            );
            imported++;
          } else {
            skipped++;
          }
        } else {
          // Single-record import; importProfiles skips duplicates by hash
          // and updates the profile count.
          final result = await _controller.importProfiles([json]);
          imported += result['imported'] as int;
          skipped += result['skipped'] as int;
          errors.addAll((result['errors'] as List?)?.cast<String>() ?? []);
        }
      } catch (e) {
        errors.add('Failed to import profile: $e');
      }
    }

    return SectionImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }
}
