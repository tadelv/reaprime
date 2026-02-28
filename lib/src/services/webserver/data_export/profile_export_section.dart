import 'package:reaprime/src/controllers/profile_controller.dart';
import 'package:reaprime/src/models/data/profile_record.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class ProfileExportSection implements DataExportSection {
  final ProfileController _controller;

  ProfileExportSection({required ProfileController controller})
      : _controller = controller;

  @override
  String get filename => 'profiles.json';

  @override
  Future<dynamic> export() async {
    return await _controller.exportProfiles(
      includeHidden: true,
      includeDeleted: true,
    );
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    if (data is! List) {
      return const SectionImportResult(
        errors: ['Expected JSON array of profile records'],
      );
    }

    final profilesJson = data.cast<Map<String, dynamic>>();

    if (strategy == ConflictStrategy.overwrite) {
      int imported = 0;
      final errorMessages = <String>[];

      for (final json in profilesJson) {
        try {
          final record = ProfileRecord.fromJson(json);
          final existing = await _controller.get(record.id);
          if (existing != null) {
            await _controller.update(record.id,
                profile: record.profile, metadata: record.metadata);
          } else {
            await _controller.importProfiles([json]);
          }
          imported++;
        } catch (e) {
          errorMessages.add('Failed to import profile: $e');
        }
      }

      return SectionImportResult(
        imported: imported,
        errors: errorMessages,
      );
    }

    // Default: skip strategy — use existing importProfiles which already skips duplicates
    final result = await _controller.importProfiles(profilesJson);
    return SectionImportResult(
      imported: result['imported'] as int,
      skipped: result['skipped'] as int,
      errors: (result['errors'] as List?)?.cast<String>() ?? [],
    );
  }
}
