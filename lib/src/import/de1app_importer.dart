import 'dart:io';

import 'package:logging/logging.dart';
import 'package:reaprime/src/import/entity_extractor.dart';
import 'package:reaprime/src/import/import_result.dart';
import 'package:reaprime/src/import/parsers/grinder_tdb_parser.dart';
import 'package:reaprime/src/import/parsers/profile_v2_parser.dart';
import 'package:reaprime/src/import/parsers/shot_v2_json_parser.dart';
import 'package:reaprime/src/import/parsers/tcl_shot_parser.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'dart:convert';

final _log = Logger('De1appImporter');

/// Orchestrates the full de1app import pipeline:
/// scan → parse shots → extract entities → store everything.
class De1appImporter {
  final StorageService storageService;
  final ProfileStorageService profileStorageService;
  final BeanStorageService beanStorageService;
  final GrinderStorageService grinderStorageService;

  De1appImporter({
    required this.storageService,
    required this.profileStorageService,
    required this.beanStorageService,
    required this.grinderStorageService,
  });

  Future<ImportResult> import(
    ScanResult scanResult, {
    void Function(ImportProgress)? onProgress,
  }) async {
    final errors = <ImportError>[];
    var shotsImported = 0;
    var shotsSkipped = 0;
    var profilesImported = 0;
    var profilesSkipped = 0;
    var beansCreated = 0;
    var grindersCreated = 0;

    // --- Phase 1: Parse shot files ---
    final parsedShots = <ParsedShot>[];
    if (scanResult.shotSource != null) {
      final shotDir = Directory(
        '${scanResult.sourcePath}/${scanResult.shotSource}',
      );

      final isV2 = scanResult.shotSource == 'history_v2';
      final extension = isV2 ? '.json' : '.shot';
      final files = <File>[];

      await for (final entity in shotDir.list()) {
        if (entity is File && entity.path.endsWith(extension)) {
          files.add(entity);
        }
      }

      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final filename = file.uri.pathSegments.last;
        try {
          final content = await file.readAsString();
          ParsedShot parsed;
          if (isV2) {
            final json = jsonDecode(content) as Map<String, dynamic>;
            parsed = ShotV2JsonParser.parse(json);
          } else {
            parsed = TclShotParser.parse(content);
          }
          parsedShots.add(parsed);
        } catch (e, st) {
          _log.warning('Failed to parse shot file $filename', e, st);
          errors.add(
            ImportError(
              filename: filename,
              reason: 'Parse error',
              details: e.toString(),
            ),
          );
        }

        onProgress?.call(
          ImportProgress(
            current: i + 1,
            total: scanResult.shotCount,
            phase: 'shots',
          ),
        );
      }
    }

    // --- Phase 2: Extract and store entities ---
    final extractor = EntityExtractor();
    final extraction = extractor.extract(parsedShots);

    // Store beans
    for (final bean in extraction.beans) {
      try {
        await beanStorageService.insertBean(bean);
        beansCreated++;
      } catch (e, st) {
        _log.warning('Failed to store bean ${bean.name}', e, st);
      }
    }

    // Store batches
    for (final batch in extraction.batches) {
      try {
        await beanStorageService.insertBatch(batch);
      } catch (e, st) {
        _log.warning('Failed to store bean batch ${batch.id}', e, st);
      }
    }

    // Merge DYE grinder specs if available
    var grinders = extraction.grinders;
    if (scanResult.hasDyeGrinders) {
      final tdbFile = File(
        '${scanResult.sourcePath}/plugins/DYE/grinders.tdb',
      );
      try {
        final content = await tdbFile.readAsString();
        final dyeGrinders = GrinderTdbParser.parse(content);
        grinders = extractor.mergeGrinderSpecs(grinders, dyeGrinders);
      } catch (e, st) {
        _log.warning('Failed to parse DYE grinders.tdb', e, st);
      }
    }

    // Store grinders
    for (final grinder in grinders) {
      try {
        await grinderStorageService.insertGrinder(grinder);
        grindersCreated++;
      } catch (e, st) {
        _log.warning('Failed to store grinder ${grinder.model}', e, st);
      }
    }

    // --- Phase 3: Store shots with entity linkage ---
    final existingIds = (await storageService.getShotIds()).toSet();

    for (var i = 0; i < parsedShots.length; i++) {
      final parsed = parsedShots[i];
      final shot = parsed.shot;

      if (existingIds.contains(shot.id)) {
        shotsSkipped++;
        continue;
      }

      final batchId = extraction.shotBeanBatchIds[i];
      final grinderId = extraction.shotGrinderIds[i];

      // Update WorkflowContext with resolved entity IDs
      final updatedShot = (batchId != null || grinderId != null)
          ? _linkShotToEntities(shot, batchId: batchId, grinderId: grinderId)
          : shot;

      try {
        await storageService.storeShot(updatedShot);
        shotsImported++;
      } catch (e, st) {
        _log.warning('Failed to store shot ${shot.id}', e, st);
        errors.add(
          ImportError(
            filename: shot.id,
            reason: 'Storage error',
            details: e.toString(),
          ),
        );
      }
    }

    // --- Phase 4: Import standalone profiles ---
    final profilesDir = Directory('${scanResult.sourcePath}/profiles_v2');
    if (await profilesDir.exists()) {
      final profileFiles = <File>[];
      await for (final entity in profilesDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          profileFiles.add(entity);
        }
      }

      for (var i = 0; i < profileFiles.length; i++) {
        final file = profileFiles[i];
        final filename = file.uri.pathSegments.last;
        try {
          final content = await file.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          final record = ProfileV2Parser.parse(json);

          final existing = await profileStorageService.get(record.id);
          if (existing != null) {
            profilesSkipped++;
          } else {
            await profileStorageService.store(record);
            profilesImported++;
          }
        } catch (e, st) {
          _log.warning('Failed to import profile $filename', e, st);
          errors.add(
            ImportError(
              filename: filename,
              reason: 'Profile import error',
              details: e.toString(),
            ),
          );
        }

        onProgress?.call(
          ImportProgress(
            current: i + 1,
            total: scanResult.profileCount,
            phase: 'profiles',
          ),
        );
      }
    }

    return ImportResult(
      shotsImported: shotsImported,
      shotsSkipped: shotsSkipped,
      profilesImported: profilesImported,
      profilesSkipped: profilesSkipped,
      beansCreated: beansCreated,
      grindersCreated: grindersCreated,
      errors: errors,
    );
  }

  /// Returns a copy of [shot] with [batchId] and/or [grinderId] set in the
  /// workflow's context.
  static ShotRecord _linkShotToEntities(
    ShotRecord shot, {
    String? batchId,
    String? grinderId,
  }) {
    final existingContext = shot.workflow.context;
    final updatedContext = existingContext?.copyWith(
      beanBatchId: batchId,
      grinderId: grinderId,
    );

    if (updatedContext == null) return shot;

    // Workflow.copyWith generates a new UUID — that's intentional for imported shots
    final updatedWorkflow = shot.workflow.copyWith(context: updatedContext);
    return shot.copyWith(workflow: updatedWorkflow);
  }
}
